package triggers

import (
	"fmt"
	"sort"
	"strings"
	"time"
)

// RecomputeInput is what Firestore and the product-type nodes hold for one
// company: raw documents, exactly as read. Every rule (required fields,
// statuses, dates) lives in RecomputeReport so it is testable without I/O.
type RecomputeInput struct {
	// Company is the company id. A row whose company_id is empty or another
	// company's still belongs to this company's loan: it is counted and
	// reported in Mismatched. Empty skips that check.
	Company string
	Loans   []map[string]any // {prefix}loans where company_id == company
	// Schedules are the rows of those loans, read by loan_id as the trigger's
	// schedule loader reads them.
	Schedules []map[string]any
	Capital   []map[string]any // {prefix}capital where provider_id == company
	// ProductTypes maps a loan id to its product type, from the Realtime
	// Database nodes {company}/loans/{loanId}:product_type the triggers read.
	ProductTypes map[string]string
}

// RecomputeResult is a company's report_summary rebuilt from its documents.
type RecomputeResult struct {
	// Plan applied to an empty node is the summary: Increments are the totals,
	// Items the data list. See SummaryNode.
	Plan ReportPlan
	// Released, Paid and Capital count the documents that were booked.
	Released, Paid, Capital int
	// Dropped names every document left out and why (owner rule: malformed
	// documents are logged and dropped). The summary is incomplete while any
	// exists, so the tool refuses to apply it.
	Dropped []string
	// Pending names the payment_submitted rows: unconfirmed, not counted.
	Pending []string
	// Mismatched names the rows whose company_id is empty or another
	// company's. They are counted.
	Mismatched []string
	// OpenTermPlanned names the confirmed open-term rows whose
	// principal_payment is at or above the loan's amount: the planned row the
	// app persists at approval with the whole amount as principal, confirmed
	// without its amounts being written (#138). They are counted as returned
	// principal, so the tool refuses to apply while any exists.
	OpenTermPlanned []string
	// Loans is one line per loan document: what was booked for it.
	Loans []LoanLine
}

// LoanLine is what recompute booked for one loan. Ids and amounts only.
type LoanLine struct {
	Id, Status string
	Amount     float64 // the loan's amount field
	Released   float64 // booked as total_amount_released
	// PaidPrincipal and Interest sum the loan's confirmed rows that were
	// booked as collections.
	PaidPrincipal, Interest float64
	Remainder               float64 // booked at settlement (completed)
	BadDebt                 float64 // booked as bad debt
	Note                    string  // why nothing was released, or why the loan was dropped
}

// RecomputeReport rebuilds the summary from the final documents by feeding
// them to the planning functions the triggers use (PlanLoanReport,
// PlanScheduleReport, PlanCapitalReport), so a formula has one implementation.
// What the triggers take from the event time, recompute takes from a document
// date, and a document's final state stands in for its history: the cases
// where that gives another number than the triggers booked are listed in
// docs/superpowers/specs/2026-11-13-report-recompute-tool.md §4.
//
// One deliberate difference from the trigger planner: a payment_submitted row
// is a borrower's claim that no teller has confirmed. The triggers book it
// when it is created and count it as returned principal; recompute counts
// neither until the row is paid_on_time or paid_late.
//
// The result depends only on the set of documents, not on their order.
func RecomputeReport(in RecomputeInput) RecomputeResult {
	var res RecomputeResult
	type booking struct {
		at   time.Time
		id   string
		plan ReportPlan
	}
	var bookings []booking
	drop := func(format string, args ...any) string {
		note := fmt.Sprintf(format, args...)
		res.Dropped = append(res.Dropped, note)
		return note
	}

	// The confirmed rows of each loan, read the way the trigger's schedule
	// loader reads them: the bad_debt and completed branches sum them.
	rowsByLoan := map[string][]ScheduleAmounts{}
	bookedByLoan := map[string][]ScheduleAmounts{} // the rows booked as collections
	loanAmounts := map[string]float64{}
	for _, fields := range in.Loans {
		id, _ := fields["id"].(string)
		if amount, ok := numberValue(fields["amount"]); ok && id != "" {
			loanAmounts[id] = amount
		}
	}
	openTermByLoan := map[string][]string{} // row ids, for the loan lines
	for _, fields := range in.Schedules {
		if fields["deleted_at"] != nil {
			continue
		}
		id := docId(fields)
		loanId, _ := fields["loan_id"].(string)
		amounts := scheduleAmountsOf(fields)
		if owner, _ := fields["company_id"].(string); in.Company != "" && owner != in.Company {
			res.Mismatched = append(res.Mismatched, fmt.Sprintf("schedule %s of loan %s: company_id %q", id, loanId, owner))
		}
		if amounts.Status == "payment_submitted" {
			res.Pending = append(res.Pending, fmt.Sprintf("schedule %s of loan %s: principal %.2f, interest %.2f", id, loanId, amounts.Principal, amounts.Interest))
			continue
		}
		if !isConfirmedPayment(amounts.Status) {
			continue
		}
		rowsByLoan[loanId] = append(rowsByLoan[loanId], amounts)
		if loanAmount, ok := loanAmounts[loanId]; ok && fields["is_open_term"] == true && amounts.Principal >= loanAmount {
			res.OpenTermPlanned = append(res.OpenTermPlanned, fmt.Sprintf("schedule %s of loan %s: principal_payment %.2f, loan amount %.2f", id, loanId, amounts.Principal, loanAmount))
			openTermByLoan[loanId] = append(openTermByLoan[loanId], id)
		}
		// The same fields the schedule trigger requires.
		_, hasInterest := numberValue(fields["interest_payment"])
		_, hasPrincipal := numberValue(fields["principal_payment"])
		if loanId == "" || !hasInterest || !hasPrincipal {
			drop("schedule %s: no loan_id, interest_payment or principal_payment", id)
			continue
		}
		productType := in.ProductTypes[loanId]
		if productType == "" {
			drop("schedule %s: no product type for loan %s", id, loanId)
			continue
		}
		// When the money was received, else when the row was marked paid, else
		// when it was created.
		at, ok := firstTime(fields, "collected_at", "paid_at", "created_at")
		if !ok {
			drop("schedule %s: no collected_at, paid_at or created_at", id)
			continue
		}
		plan, _ := PlanScheduleReport(ScheduleReportInput{
			Status: amounts.Status, Interest: amounts.Interest, Principal: amounts.Principal,
			ProductType: productType, LoanId: loanId, Now: at,
		})
		bookings = append(bookings, booking{at, "schedule/" + id, plan})
		res.Paid++
		bookedByLoan[loanId] = append(bookedByLoan[loanId], amounts)
	}
	// A loan's rows are summed in a fixed order so the sums do not depend on
	// the order Firestore returned them in.
	for _, byLoan := range []map[string][]ScheduleAmounts{rowsByLoan, bookedByLoan} {
		for _, rows := range byLoan {
			sort.Slice(rows, func(i, j int) bool {
				a, b := rows[i], rows[j]
				if a.Principal != b.Principal {
					return a.Principal < b.Principal
				}
				if a.Extra != b.Extra {
					return a.Extra < b.Extra
				}
				if a.Interest != b.Interest {
					return a.Interest < b.Interest
				}
				return a.Status < b.Status
			})
		}
	}

	bookLoan := func(fields map[string]any) LoanLine {
		id, _ := fields["id"].(string)
		status, _ := fields["status"].(string)
		amount, hasAmount := numberValue(fields["amount"])
		line := LoanLine{Id: docId(fields), Status: status, Amount: amount}
		for _, row := range bookedByLoan[id] {
			line.PaidPrincipal += row.Principal
			line.Interest += row.Interest
		}
		// The same fields the loan trigger requires.
		if id == "" || status == "" || !hasAmount {
			line.Note = "dropped: " + drop("loan %s: no id, status or amount", line.Id)
			return line
		}
		released, known := loanWasReleased(status)
		if !known {
			line.Note = "dropped: " + drop("loan %s: unknown status %q", id, status)
			return line
		}
		if !released {
			line.Note = "not released"
			return line
		}
		productType := in.ProductTypes[id]
		if productType == "" {
			line.Note = "dropped: " + drop("loan %s: no product type", id)
			return line
		}
		created, hasCreated := firstTime(fields, "created_at")
		updated, hasUpdated := firstTime(fields, "updated_at")
		terminal := status == "bad_debt" || status == "completed"
		if !hasCreated || (terminal && !hasUpdated) {
			line.Note = "dropped: " + drop("loan %s: no created_at or updated_at", id)
			return line
		}

		input := LoanReportInput{
			Status: "approved", OldStatus: "pending", Amount: amount,
			ProductType: productType, LoanId: id, Now: created,
		}
		plan, _ := PlanLoanReport(input)
		bookings = append(bookings, booking{created, "loan/" + id + "/release", plan})
		res.Released++
		line.Released = amount

		if terminal {
			input.Status, input.OldStatus, input.Now = status, "approved", updated
			input.AdditionalCharges = numberOf(fields["additional_charges"])
			input.Deductions = numberOf(fields["deductions"])
			input.UpfrontCollection = numberOf(fields["additional_charge_upfront_collection"])
			input.Schedules = rowsByLoan[id]
			plan, _ = PlanLoanReport(input)
			bookings = append(bookings, booking{updated, "loan/" + id + "/" + status, plan})
			// The plan's own numbers: completed returns the remainder to
			// capital, bad_debt books the debt under capital_usage.
			line.Remainder = plan.Increments["capital_usage/total_capital"]
			line.BadDebt = plan.Increments["capital_usage/total_bad_debts"]
		}
		return line
	}
	for _, fields := range in.Loans {
		if fields["deleted_at"] == nil {
			line := bookLoan(fields)
			if rows := openTermByLoan[line.Id]; len(rows) > 0 {
				sort.Strings(rows)
				flag := "open-term planned row(s) " + strings.Join(rows, ", ") + " counted as returned principal (#138)"
				if line.Note != "" {
					flag = line.Note + "; " + flag
				}
				line.Note = flag
			}
			res.Loans = append(res.Loans, line)
		}
	}

	for _, fields := range in.Capital {
		if fields["deleted_at"] != nil {
			continue
		}
		id, _ := fields["id"].(string)
		amount, hasAmount := numberValue(fields["amount"])
		created, hasCreated := firstTime(fields, "created_at")
		if id == "" || !hasAmount || !hasCreated {
			drop("capital %s: no id, amount or created_at", docId(fields))
			continue
		}
		plan := PlanCapitalReport(CapitalReportInput{Amount: amount, CapitalId: id, Now: created})
		bookings = append(bookings, booking{created, "capital/" + id, plan})
		res.Capital++
	}

	// One fixed order: floating-point sums and the :n suffixes of colliding
	// data-item keys then come out the same on every run.
	sort.Slice(bookings, func(i, j int) bool {
		if !bookings[i].at.Equal(bookings[j].at) {
			return bookings[i].at.Before(bookings[j].at)
		}
		return bookings[i].id < bookings[j].id
	})
	sort.Strings(res.Dropped)
	sort.Strings(res.Pending)
	sort.Strings(res.Mismatched)
	sort.Strings(res.OpenTermPlanned)
	sort.Slice(res.Loans, func(i, j int) bool { return res.Loans[i].Id < res.Loans[j].Id })
	usedKeys := map[string]bool{}
	for _, b := range bookings {
		for _, path := range sortedPaths(b.plan.Increments) {
			res.Plan.add(path, b.plan.Increments[path])
		}
		for _, item := range b.plan.Items {
			// Documents that share a millisecond share a key. The triggers let
			// the later event overwrite the earlier item; recompute keeps both.
			base := item.Key
			for n := 2; usedKeys[item.Key]; n++ {
				item.Key = fmt.Sprintf("%s:%d", base, n)
			}
			usedKeys[item.Key] = true
			res.Plan.Items = append(res.Plan.Items, item)
		}
	}
	return res
}

// SummaryNode is the report_summary node the plan produces when applied to
// an empty node: every increment as a value, every item under data.
func (p ReportPlan) SummaryNode() map[string]any {
	node := map[string]any{}
	set := func(path string, value any) {
		parts := strings.Split(path, "/")
		at := node
		for _, part := range parts[:len(parts)-1] {
			child, ok := at[part].(map[string]any)
			if !ok {
				child = map[string]any{}
				at[part] = child
			}
			at = child
		}
		at[parts[len(parts)-1]] = value
	}
	for path, value := range p.Increments {
		set(path, value)
	}
	for _, item := range p.Items {
		set("data/"+item.Key, item.Item)
	}
	return node
}

// loanWasReleased reports whether a loan in this status was approved at some
// point. After approval the app sets a loan's status to that of its latest
// schedule (payment_confirmation_service.dart), so every status but pending
// and declined is reached through approval.
func loanWasReleased(status string) (released, known bool) {
	switch status {
	case "pending", "declined":
		return false, true
	case "approved", "payment_submitted", "paid_on_time", "paid_late",
		"not_paid", "not_paid_overdue", "completed", "bad_debt":
		return true, true
	}
	return false, false
}

// isConfirmedPayment reports whether a row's money was confirmed received.
// Narrower than the trigger's isCollectionStatus, which also takes
// payment_submitted.
func isConfirmedPayment(status string) bool {
	return status == "paid_on_time" || status == "paid_late"
}

// scheduleAmountsOf reads what the loan-level branches need from a
// loan_schedule document. Shared by the trigger's loader and by recompute.
func scheduleAmountsOf(fields map[string]any) ScheduleAmounts {
	status, _ := fields["status"].(string)
	return ScheduleAmounts{
		Status:    status,
		Principal: numberOf(fields["principal_payment"]),
		Extra:     numberOf(fields["extra_payment"]),
		Interest:  numberOf(fields["interest_payment"]),
	}
}

func numberValue(value any) (float64, bool) {
	switch value.(type) {
	case float64, int64, int:
		return numberOf(value), true
	}
	return 0, false
}

// firstTime returns the first of the named fields that holds a date, in UTC
// (the triggers bucket in UTC). The app stores milliseconds since the epoch;
// Go writers store Firestore timestamps.
func firstTime(fields map[string]any, names ...string) (time.Time, bool) {
	for _, name := range names {
		switch value := fields[name].(type) {
		case time.Time:
			if !value.IsZero() {
				return value.UTC(), true
			}
		case float64, int64, int:
			if millis := int64(numberOf(value)); millis > 0 {
				return time.UnixMilli(millis).UTC(), true
			}
		}
	}
	return time.Time{}, false
}

func docId(fields map[string]any) string {
	if id, _ := fields["id"].(string); id != "" {
		return id
	}
	return "(no id field)"
}

func sortedPaths(increments map[string]float64) []string {
	paths := make([]string, 0, len(increments))
	for path := range increments {
		paths = append(paths, path)
	}
	sort.Strings(paths)
	return paths
}
