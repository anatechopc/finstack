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
	Loans     []map[string]any // {prefix}loans where company_id == company
	Schedules []map[string]any // {prefix}loan_schedules where company_id == company
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
	// documents are logged and dropped).
	Dropped []string
}

// RecomputeReport rebuilds the summary from the final documents by feeding
// them to the same planning functions the triggers use (PlanLoanReport,
// PlanScheduleReport, PlanCapitalReport), so the two agree by construction.
// What the triggers take from the event time, recompute takes from a document
// date: see docs/superpowers/specs/2026-11-13-report-recompute-tool.md.
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
	drop := func(format string, args ...any) {
		res.Dropped = append(res.Dropped, fmt.Sprintf(format, args...))
	}

	// Every row of a loan, read the way the trigger's schedule loader reads
	// it: the bad_debt and completed branches sum the paid ones.
	rowsByLoan := map[string][]ScheduleAmounts{}
	for _, fields := range in.Schedules {
		if fields["deleted_at"] != nil {
			continue
		}
		loanId, _ := fields["loan_id"].(string)
		amounts := scheduleAmountsOf(fields)
		rowsByLoan[loanId] = append(rowsByLoan[loanId], amounts)
		if !isCollectionStatus(amounts.Status) {
			continue
		}
		id := docId(fields)
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
		// when it was created (a submission not yet confirmed).
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
	}
	// A loan's rows are summed in a fixed order so the sum does not depend on
	// the order Firestore returned them in.
	for _, rows := range rowsByLoan {
		sort.Slice(rows, func(i, j int) bool {
			a, b := rows[i], rows[j]
			if a.Principal != b.Principal {
				return a.Principal < b.Principal
			}
			if a.Extra != b.Extra {
				return a.Extra < b.Extra
			}
			return a.Status < b.Status
		})
	}

	for _, fields := range in.Loans {
		if fields["deleted_at"] != nil {
			continue
		}
		id, _ := fields["id"].(string)
		status, _ := fields["status"].(string)
		amount, hasAmount := numberValue(fields["amount"])
		// The same fields the loan trigger requires.
		if id == "" || status == "" || !hasAmount {
			drop("loan %s: no id, status or amount", docId(fields))
			continue
		}
		released, known := loanWasReleased(status)
		if !known {
			drop("loan %s: unknown status %q", id, status)
			continue
		}
		if !released {
			continue
		}
		productType := in.ProductTypes[id]
		if productType == "" {
			drop("loan %s: no product type", id)
			continue
		}
		created, hasCreated := firstTime(fields, "created_at")
		updated, hasUpdated := firstTime(fields, "updated_at")
		terminal := status == "bad_debt" || status == "completed"
		if !hasCreated || (terminal && !hasUpdated) {
			drop("loan %s: no created_at or updated_at", id)
			continue
		}

		input := LoanReportInput{
			Status: "approved", OldStatus: "pending", Amount: amount,
			ProductType: productType, LoanId: id, Now: created,
		}
		plan, _ := PlanLoanReport(input)
		bookings = append(bookings, booking{created, "loan/" + id + "/release", plan})
		res.Released++

		if terminal {
			input.Status, input.OldStatus, input.Now = status, "approved", updated
			input.AdditionalCharges = numberOf(fields["additional_charges"])
			input.Deductions = numberOf(fields["deductions"])
			input.UpfrontCollection = numberOf(fields["additional_charge_upfront_collection"])
			input.Schedules = rowsByLoan[id]
			plan, _ = PlanLoanReport(input)
			bookings = append(bookings, booking{updated, "loan/" + id + "/" + status, plan})
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
