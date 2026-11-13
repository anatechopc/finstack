package triggers_test

import (
	"context"
	"fmt"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"com.loooans.app/triggers"
)

// at is a UTC instant in 2026.
func at(month time.Month, day, hour int) time.Time {
	return time.Date(2026, month, day, hour, 0, 0, 0, time.UTC)
}

func millis(t time.Time) int64 { return t.UnixMilli() }

// recomputeFixture is one company as Firestore holds it: an active loan with
// one payment, a settled loan, a bad debt with an unconfirmed submission, two
// loans that were never released, and one capital addition. Amounts mix
// doubles and integers, and dates mix milliseconds and timestamps, as the
// real collections do.
func recomputeFixture() triggers.RecomputeInput {
	return triggers.RecomputeInput{
		ProductTypes: map[string]string{"L1": "business", "L2": "business", "L3": "personal", "L4": "business", "L5": "business"},
		Capital: []map[string]any{
			{"id": "K1", "provider_id": "C1", "amount": 100000.0, "created_at": millis(at(9, 1, 2))},
		},
		Loans: []map[string]any{
			// Active. After a payment the app sets the loan's status to the schedule's.
			{"id": "L1", "status": "paid_on_time", "amount": 10000.0, "created_at": millis(at(9, 2, 3)), "updated_at": millis(testNow)},
			// Settled on October 5.
			{"id": "L2", "status": "completed", "amount": int64(20000), "additional_charges": 500.0, "deductions": 200.0,
				"additional_charge_upfront_collection": 100.0, "created_at": millis(at(9, 3, 4)), "updated_at": millis(at(10, 5, 5))},
			// Written off on October 6.
			{"id": "L3", "status": "bad_debt", "amount": 8000.0, "created_at": millis(at(9, 4, 6)), "updated_at": at(10, 6, 7)},
			// Never released.
			{"id": "L4", "status": "pending", "amount": 5000.0, "created_at": millis(at(9, 5, 1)), "updated_at": millis(at(9, 5, 1))},
			{"id": "L5", "status": "declined", "amount": 7000.0, "created_at": millis(at(9, 6, 1)), "updated_at": millis(at(9, 7, 1))},
		},
		Schedules: []map[string]any{
			// The planned row the app persists at approval: not a payment.
			{"id": "S1", "loan_id": "L1", "status": "approved", "principal_payment": 10000.0, "interest_payment": 0.0, "created_at": millis(at(9, 2, 3))},
			// Collected on September 9 (testNow), marked paid a day later.
			{"id": "S2", "loan_id": "L1", "status": "paid_on_time", "principal_payment": 3000.0, "interest_payment": 500.0,
				"collected_at": millis(testNow), "paid_at": millis(testNow.Add(24 * time.Hour)), "created_at": millis(at(9, 2, 3))},
			{"id": "S3", "loan_id": "L2", "status": "paid_on_time", "principal_payment": 5000.0, "extra_payment": 1000.0, "interest_payment": 400.0,
				"paid_at": millis(at(9, 20, 8)), "created_at": millis(at(9, 20, 8))},
			{"id": "S4", "loan_id": "L2", "status": "paid_late", "principal_payment": int64(2000), "interest_payment": int64(300),
				"paid_at": at(9, 25, 8), "created_at": millis(at(9, 25, 8))},
			// A borrower submission no teller has confirmed: not counted.
			{"id": "S5", "loan_id": "L3", "status": "payment_submitted", "principal_payment": 1000.0, "interest_payment": 100.0, "created_at": millis(at(9, 15, 9))},
			{"id": "S6", "loan_id": "L3", "status": "not_paid", "principal_payment": 2500.0, "interest_payment": 300.0, "created_at": millis(at(9, 15, 9))},
		},
	}
}

func total(t *testing.T, node map[string]any, path string) float64 {
	t.Helper()
	var current any = node
	for _, part := range strings.Split(path, "/") {
		children, ok := current.(map[string]any)
		if !ok {
			t.Fatalf("%s: no node at %q", path, part)
		}
		current = children[part]
	}
	value, ok := current.(float64)
	if !ok {
		t.Fatalf("%s: got %v (%T), want a number", path, current, current)
	}
	return value
}

// Every total, derived by hand from the fixture:
//
//	released    L1 10000 + L2 20000 + L3 8000                          = 38000
//	paid rows   S2 3000+500, S3 5000+400, S4 2000+300 (S5 is unconfirmed)
//	            principal 10000, interest 1200, collections 11200
//	settlement  L2: 20000 + 500 - 200 - 100 - (5000+1000) - 2000        = 12200
//	bad debt    L3: 8000 - 0 (S5 unconfirmed, S6 not paid)              = 8000
//	collections 11200 + 12200 = 23400; principal 10000 + 12200 = 22200
//	capital     100000 + 10000 (principal returned) + 12200 (settled)   = 122200
func TestRecomputeReport_RebuildsEveryTotalFromTheDocuments(t *testing.T) {
	result := triggers.RecomputeReport(recomputeFixture())
	if len(result.Dropped) != 0 {
		t.Fatalf("dropped: %v", result.Dropped)
	}
	if result.Released != 3 || result.Paid != 3 || result.Capital != 1 {
		t.Fatalf("booked %d loans, %d rows, %d capital; want 3, 3, 1", result.Released, result.Paid, result.Capital)
	}
	if want := []string{"schedule S5 of loan L3: principal 1000.00, interest 100.00"}; !reflect.DeepEqual(result.Pending, want) {
		t.Errorf("pending submissions: got %q, want %q", result.Pending, want)
	}

	node := result.Plan.SummaryNode()
	want := map[string]float64{
		"sales/total_amount_released":    38000,
		"sales/total_collections":        23400,
		"sales/total_interest_payments":  1200,
		"sales/total_principal_payments": 22200,

		"products/business/total_amount_released":    30000,
		"products/business/total_collections":        23400, // 3500 + 5400 + 2300 + 12200
		"products/business/total_interest_payments":  1200,
		"products/business/total_principal_payments": 22200, // 3000 + 5000 + 2000 + 12200
		"products/personal/total_amount_released":    8000,
		"products/personal/total_bad_debts":          8000,

		"capital_usage/total_capital":   122200,
		"capital_usage/total_bad_debts": 8000,

		"total_summary/year:2026/total_amount_released":    38000,
		"total_summary/year:2026/total_collections":        23400,
		"total_summary/year:2026/total_interest_payments":  1200,
		"total_summary/year:2026/total_principal_payments": 22200,
		"total_summary/year:2026/total_bad_debts":          8000,
		// Releases bucket on the loan's created_at, paid rows on their own date.
		"total_summary/year:2026:month:9/total_amount_released":    38000,
		"total_summary/year:2026:month:9/total_collections":        11200,
		"total_summary/year:2026:month:9/total_interest_payments":  1200,
		"total_summary/year:2026:month:9/total_principal_payments": 10000,
		// Settlement and bad debt bucket on the loan's updated_at.
		"total_summary/year:2026:month:10/total_collections":        12200,
		"total_summary/year:2026:month:10/total_principal_payments": 12200,
		"total_summary/year:2026:month:10/total_bad_debts":          8000,
		// S2 buckets on collected_at (September 9), not on paid_at (the 10th).
		"total_summary/year:2026:month:9:week:37:day:9/total_collections":        3500,
		"total_summary/year:2026:month:9:week:37:day:9/total_interest_payments":  500,
		"total_summary/year:2026:month:9:week:37:day:9/total_principal_payments": 3000,
	}
	for path, value := range want {
		if got := total(t, node, path); got != value {
			t.Errorf("%s: got %v, want %v", path, got, value)
		}
	}
	for _, absent := range []string{
		"sales/total_bad_debts",
		"total_summary/year:2026:month:9/total_bad_debts",
		"total_summary/year:2026:month:9:week:37:day:10/total_collections",
		"products/personal/total_collections", // the only personal row is unconfirmed
	} {
		if _, ok := result.Plan.Increments[absent]; ok {
			t.Errorf("%s must not exist", absent)
		}
	}

	// One release per released loan, one add_capital, a refresh_capital and a
	// collection per confirmed row and per settlement, one bad_debt.
	types := map[string]int{}
	for _, item := range result.Plan.Items {
		types[item.Item["data_type"].(string)]++
	}
	wantTypes := map[string]int{"release": 3, "add_capital": 1, "refresh_capital": 4, "collection": 4, "bad_debt": 1}
	if !reflect.DeepEqual(types, wantTypes) {
		t.Errorf("data items by type: got %v, want %v", types, wantTypes)
	}
	if got := len(node["data"].(map[string]any)); got != 13 {
		t.Errorf("data node holds %d items, want 13", got)
	}

	// One line per loan, by id: what was booked for it.
	wantLoans := []triggers.LoanLine{
		{Id: "L1", Status: "paid_on_time", Amount: 10000, Released: 10000, PaidPrincipal: 3000, Interest: 500},
		{Id: "L2", Status: "completed", Amount: 20000, Released: 20000, PaidPrincipal: 7000, Interest: 700, Remainder: 12200},
		{Id: "L3", Status: "bad_debt", Amount: 8000, Released: 8000, BadDebt: 8000},
		{Id: "L4", Status: "pending", Amount: 5000, Note: "not released"},
		{Id: "L5", Status: "declined", Amount: 7000, Note: "not released"},
	}
	if !reflect.DeepEqual(result.Loans, wantLoans) {
		t.Errorf("loan lines:\n got %+v\nwant %+v", result.Loans, wantLoans)
	}
}

// A loan leaves approved for the status of its latest schedule, so every
// LoanStatus value (packages/loans/loan_repository/.../loan_status.dart)
// except pending and declined belongs to a loan that was released.
func TestRecomputeReport_ALoanIsReleasedInEveryStatusButPendingAndDeclined(t *testing.T) {
	released := map[string]bool{
		"pending": false, "declined": false,
		"approved": true, "payment_submitted": true, "paid_on_time": true, "paid_late": true,
		"not_paid": true, "not_paid_overdue": true, "completed": true, "bad_debt": true,
	}
	for status, want := range released {
		t.Run(status, func(t *testing.T) {
			result := triggers.RecomputeReport(triggers.RecomputeInput{
				Loans: []map[string]any{{"id": "L1", "status": status, "amount": 1000.0,
					"created_at": millis(testNow), "updated_at": millis(testNow)}},
				ProductTypes: map[string]string{"L1": "business"},
			})
			if len(result.Dropped) != 0 {
				t.Fatalf("dropped: %v", result.Dropped)
			}
			got, booked := result.Plan.Increments["sales/total_amount_released"]
			if booked != want || (want && got != 1000) || (result.Released == 1) != want {
				t.Fatalf("released %v (booked %v, count %d); want released=%v", got, booked, result.Released, want)
			}
		})
	}
}

func TestRecomputeReport_CollectionDate_IsCollectedThenPaidThenCreated(t *testing.T) {
	row := func(dates map[string]any) triggers.RecomputeInput {
		fields := map[string]any{"id": "S1", "loan_id": "L1", "status": "paid_on_time", "principal_payment": 100.0, "interest_payment": 10.0}
		for name, value := range dates {
			fields[name] = value
		}
		return triggers.RecomputeInput{Schedules: []map[string]any{fields}, ProductTypes: map[string]string{"L1": "business"}}
	}
	cases := []struct {
		name    string
		dates   map[string]any
		wantDay string
	}{
		{"collected_at wins", map[string]any{"collected_at": millis(at(9, 9, 1)), "paid_at": millis(at(9, 10, 1)), "created_at": millis(at(9, 11, 1))}, "week:37:day:9"},
		{"then paid_at", map[string]any{"collected_at": nil, "paid_at": millis(at(9, 10, 1)), "created_at": millis(at(9, 11, 1))}, "week:37:day:10"},
		{"then created_at", map[string]any{"created_at": float64(millis(at(9, 11, 1)))}, "week:37:day:11"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			result := triggers.RecomputeReport(row(tc.dates))
			path := "total_summary/year:2026:month:9:" + tc.wantDay + "/total_collections"
			if got := result.Plan.Increments[path]; got != 110 {
				t.Fatalf("%s: got %v, want 110 (paths: %v)", path, got, sortedKeys(result.Plan.Increments))
			}
		})
	}
}

// Owner rule: malformed documents are logged and dropped. Soft-deleted
// documents and loans never released are left out without a note.
func TestRecomputeReport_DropsMalformedDocumentsAndSkipsDeletedOnes(t *testing.T) {
	created := millis(testNow)
	result := triggers.RecomputeReport(triggers.RecomputeInput{
		ProductTypes: map[string]string{"L1": "business"},
		Loans: []map[string]any{
			{"id": "L-no-amount", "status": "approved", "created_at": created},
			{"id": "L-no-type", "status": "approved", "amount": 1.0, "created_at": created},
			{"id": "L-odd", "status": "frozen", "amount": 1.0, "created_at": created},
			{"status": "approved", "amount": 1.0, "created_at": created},
			{"id": "L1", "status": "completed", "amount": 1.0, "created_at": created}, // no updated_at
			{"id": "L1", "status": "approved", "amount": 1.0, "created_at": created, "deleted_at": created},
		},
		Schedules: []map[string]any{
			{"id": "S-no-loan", "status": "paid_on_time", "principal_payment": 1.0, "interest_payment": 1.0, "created_at": created},
			{"id": "S-no-interest", "loan_id": "L1", "status": "paid_on_time", "principal_payment": 1.0, "created_at": created},
			{"id": "S-no-type", "loan_id": "L9", "status": "paid_late", "principal_payment": 1.0, "interest_payment": 1.0, "created_at": created},
			{"id": "S-no-date", "loan_id": "L1", "status": "paid_late", "principal_payment": 1.0, "interest_payment": 1.0},
			{"id": "S-deleted", "loan_id": "L1", "status": "paid_late", "principal_payment": 1.0, "interest_payment": 1.0, "created_at": created, "deleted_at": created},
			{"id": "S-planned", "status": "not_paid"}, // not a payment: nothing to book, nothing to report
		},
		Capital: []map[string]any{
			{"id": "K-no-amount", "created_at": created},
			{"id": "K-deleted", "amount": 1.0, "created_at": created, "deleted_at": testNow},
		},
	})

	want := []string{
		"capital K-no-amount: no id, amount or created_at",
		"loan (no id field): no id, status or amount",
		"loan L-no-amount: no id, status or amount",
		"loan L-no-type: no product type",
		`loan L-odd: unknown status "frozen"`,
		"loan L1: no created_at or updated_at",
		"schedule S-no-date: no collected_at, paid_at or created_at",
		"schedule S-no-interest: no loan_id, interest_payment or principal_payment",
		"schedule S-no-loan: no loan_id, interest_payment or principal_payment",
		"schedule S-no-type: no product type for loan L9",
	}
	if !reflect.DeepEqual(result.Dropped, want) {
		t.Errorf("dropped:\n got %q\nwant %q", result.Dropped, want)
	}
	if !result.Plan.IsEmpty() {
		t.Errorf("nothing may be booked, got %v and %d items", result.Plan.Increments, len(result.Plan.Items))
	}
	// Every loan document that is not soft-deleted has a line saying why.
	notes := map[string]string{}
	for _, loan := range result.Loans {
		notes[loan.Id] = loan.Note
	}
	if len(result.Loans) != 5 || notes["L-no-type"] != "dropped: loan L-no-type: no product type" {
		t.Errorf("loan lines: %+v", result.Loans)
	}
}

// Rows are read by loan, as the trigger's loader reads them, so a row can
// carry no company_id or another company's. It is counted (the loan is this
// company's) and reported.
func TestRecomputeReport_ReportsRowsWhoseCompanyIsNotTheLoans(t *testing.T) {
	row := func(id string, company any) map[string]any {
		fields := map[string]any{"id": id, "loan_id": "L1", "status": "paid_on_time", "principal_payment": 100.0,
			"interest_payment": 10.0, "paid_at": millis(testNow)}
		if company != nil {
			fields["company_id"] = company
		}
		return fields
	}
	result := triggers.RecomputeReport(triggers.RecomputeInput{
		Company:      "C1",
		Schedules:    []map[string]any{row("S-own", "C1"), row("S-none", nil), row("S-other", "C2")},
		ProductTypes: map[string]string{"L1": "business"},
	})
	want := []string{`schedule S-none of loan L1: company_id ""`, `schedule S-other of loan L1: company_id "C2"`}
	if !reflect.DeepEqual(result.Mismatched, want) {
		t.Errorf("mismatched: got %q, want %q", result.Mismatched, want)
	}
	if result.Paid != 3 || result.Plan.Increments["sales/total_collections"] != 330 || len(result.Dropped) != 0 {
		t.Errorf("all three rows count: paid %d, collections %v, dropped %v", result.Paid, result.Plan.Increments["sales/total_collections"], result.Dropped)
	}
}

// Idempotency of the core: the summary is a function of the set of documents.
// Recomputing again, or from the same documents in another order, gives the
// same node bit for bit, including the keys of items that share a millisecond
// and sums of amounts that are not exact in binary.
func TestRecomputeReport_SameDocumentsInAnyOrderGiveTheSameSummary(t *testing.T) {
	build := func() triggers.RecomputeInput {
		in := recomputeFixture()
		in.ProductTypes["L6"] = "personal"
		in.Loans = append(in.Loans, map[string]any{"id": "L6", "status": "completed", "amount": 1.0,
			"created_at": millis(at(9, 8, 1)), "updated_at": millis(at(9, 30, 1))})
		for i, amount := range []float64{0.1, 0.2, 0.3} {
			in.Schedules = append(in.Schedules, map[string]any{"id": fmt.Sprintf("F%d", i), "loan_id": "L6", "status": "paid_on_time",
				"principal_payment": amount, "interest_payment": amount, "paid_at": millis(at(9, 12, 1))})
		}
		// Two capital additions in the same millisecond share a data-item key.
		in.Capital = append(in.Capital,
			map[string]any{"id": "K2", "amount": 1.5, "created_at": millis(at(9, 1, 2))},
			map[string]any{"id": "K3", "amount": 2.5, "created_at": millis(at(9, 1, 2))})
		return in
	}
	forward, reversed := build(), build()
	slices.Reverse(reversed.Loans)
	slices.Reverse(reversed.Schedules)
	slices.Reverse(reversed.Capital)

	first, again, other := triggers.RecomputeReport(forward), triggers.RecomputeReport(forward), triggers.RecomputeReport(reversed)
	if !reflect.DeepEqual(first.Plan.SummaryNode(), again.Plan.SummaryNode()) {
		t.Fatal("recomputing the same input twice gave two summaries")
	}
	if !reflect.DeepEqual(first.Plan.SummaryNode(), other.Plan.SummaryNode()) {
		t.Fatal("the summary depends on the order of the documents")
	}
	if !reflect.DeepEqual(first.Loans, other.Loans) || !reflect.DeepEqual(first.Pending, other.Pending) {
		t.Fatal("the loan lines or the pending list depend on the order of the documents")
	}

	// K1, K2 and K3 share 2026-09-01 02:00:00.000: three items, three keys.
	data := first.Plan.SummaryNode()["data"].(map[string]any)
	for _, key := range []string{"2026:9:week:36:1T2:0:0:0", "2026:9:week:36:1T2:0:0:0:2", "2026:9:week:36:1T2:0:0:0:3"} {
		if _, ok := data[key]; !ok {
			t.Errorf("no data item under %q", key)
		}
	}
}

// history replays document writes through the trigger cores, with the fake
// store and the clock set to each write's time, and keeps the documents
// Firestore would hold afterwards.
type history struct {
	t         *testing.T
	store     *fakeReportStore
	clock     *fakeClock
	events    int
	loans     map[string]map[string]any
	schedules map[string]map[string]any
	capital   []map[string]any
}

const historyBase = "dev/companies/C1/report_summary/"

func newHistory(t *testing.T) *history {
	store := newFakeReportStore()
	store.ProductTypes = map[string]string{"L1": "business", "L2": "business", "L3": "personal"}
	return &history{t: t, store: store, clock: &fakeClock{now: testNow},
		loans: map[string]map[string]any{}, schedules: map[string]map[string]any{}}
}

func (h *history) deps() triggers.ReportDeps {
	return triggers.ReportDeps{
		Store: h.store,
		Now:   h.clock.Now,
		LoadSchedules: func(_ context.Context, loanId string) ([]triggers.ScheduleAmounts, error) {
			var rows []triggers.ScheduleAmounts
			for _, doc := range h.schedules {
				if doc["loan_id"] == loanId {
					rows = append(rows, triggers.ScheduleAmounts{Status: doc["status"].(string),
						Principal: doc["principal_payment"].(float64), Extra: doc["extra_payment"].(float64), Interest: doc["interest_payment"].(float64)})
				}
			}
			return rows, nil
		},
	}
}

func (h *history) eventAt(when time.Time) string {
	h.clock.now = when
	h.events++
	return fmt.Sprintf("e%d", h.events)
}

// writeLoan creates or updates a loan and delivers the write to loanChanges.
// charges are additional_charges, deductions and upfront collection.
func (h *history) writeLoan(when time.Time, id, status string, amount float64, charges ...float64) {
	h.t.Helper()
	charges = append(charges, 0, 0, 0)
	doc, exists := h.loans[id]
	oldStatus := ""
	if exists {
		oldStatus = doc["status"].(string)
	} else {
		doc = map[string]any{"id": id, "company_id": "C1", "created_at": millis(when)}
		h.loans[id] = doc
	}
	doc["status"], doc["amount"], doc["updated_at"] = status, amount, millis(when)
	doc["additional_charges"], doc["deductions"], doc["additional_charge_upfront_collection"] = charges[0], charges[1], charges[2]
	_, err := triggers.HandleLoanChangeCore(context.Background(), "dev", triggers.LoanChangeEvent{
		EventId: h.eventAt(when), CompanyId: "C1", LoanId: id, Status: status, OldStatus: oldStatus,
		Amount: amount, AdditionalCharges: charges[0], Deductions: charges[1], UpfrontCollection: charges[2],
	}, h.deps())
	if err != nil {
		h.t.Fatalf("loan %s -> %s: %v", id, status, err)
	}
}

// approveLoan creates a loan and approves it in the same instant, so the
// approval time equals created_at, the date recompute buckets a release on.
func (h *history) approveLoan(when time.Time, id string, amount float64, charges ...float64) {
	h.t.Helper()
	h.writeLoan(when, id, "pending", amount, charges...)
	h.writeLoan(when, id, "approved", amount, charges...)
}

// createSchedule creates a loan_schedule and delivers the create to
// loanScheduleChanges.
func (h *history) createSchedule(when time.Time, id, loanId, status string, principal, extra, interest float64) {
	h.t.Helper()
	h.schedules[id] = map[string]any{"id": id, "company_id": "C1", "loan_id": loanId, "status": status,
		"principal_payment": principal, "extra_payment": extra, "interest_payment": interest, "created_at": millis(when)}
	_, err := triggers.HandleScheduleCreatedCore(context.Background(), "dev", triggers.ScheduleCreatedEvent{
		EventId: h.eventAt(when), CompanyId: "C1", LoanId: loanId, Status: status, Interest: interest, Principal: principal,
	}, h.deps())
	if err != nil {
		h.t.Fatalf("schedule %s: %v", id, err)
	}
}

// updateSchedule changes a row's status. loanScheduleChanges is deployed on
// document creation only, so no trigger runs.
func (h *history) updateSchedule(when time.Time, id, status string) {
	doc := h.schedules[id]
	doc["status"], doc["updated_at"] = status, millis(when)
	if status == "paid_on_time" || status == "paid_late" {
		doc["paid_at"] = millis(when)
	}
}

func (h *history) createCapital(when time.Time, id string, amount float64) {
	h.t.Helper()
	h.capital = append(h.capital, map[string]any{"id": id, "provider_id": "C1", "amount": amount, "created_at": millis(when)})
	_, err := triggers.HandleCapitalCreatedCore(context.Background(), "dev", triggers.CapitalCreatedEvent{
		EventId: h.eventAt(when), CompanyId: "C1", CapitalId: id, Amount: amount,
	}, h.deps())
	if err != nil {
		h.t.Fatalf("capital %s: %v", id, err)
	}
}

// live is what the triggers wrote: totals and data items by relative path.
func (h *history) live() (map[string]float64, map[string]map[string]any) {
	totals, items := map[string]float64{}, map[string]map[string]any{}
	for path, value := range h.store.Nodes {
		totals[strings.TrimPrefix(path, historyBase)] = value
	}
	for path, item := range h.store.Items {
		items[strings.TrimPrefix(path, historyBase+"data/")] = item
	}
	return totals, items
}

// result is the recompute of the documents the history left.
func (h *history) result() triggers.RecomputeResult {
	h.t.Helper()
	in := triggers.RecomputeInput{Company: "C1", Capital: h.capital, ProductTypes: h.store.ProductTypes}
	for _, doc := range h.loans {
		in.Loans = append(in.Loans, doc)
	}
	for _, doc := range h.schedules {
		in.Schedules = append(in.Schedules, doc)
	}
	result := triggers.RecomputeReport(in)
	if len(result.Dropped) != 0 || len(result.Mismatched) != 0 {
		h.t.Fatalf("dropped %v, mismatched %v", result.Dropped, result.Mismatched)
	}
	return result
}

// recomputed is that recompute as totals and data items by relative path.
func (h *history) recomputed() (map[string]float64, map[string]map[string]any) {
	h.t.Helper()
	result := h.result()
	items := map[string]map[string]any{}
	for _, item := range result.Plan.Items {
		items[item.Key] = item.Item
	}
	return result.Plan.Increments, items
}

// Equivalence: a history replayed event by event through the trigger cores
// leaves the same totals and the same data items as recomputing from the
// documents that history leaves behind. The script covers the three writers
// and every branch: capital, release, planned row, paid rows, the loan
// following its schedule's status (no report transition), settlement, bad
// debt, and a loan never approved. Each loan is approved in the instant it is
// created, each row is created as a confirmed payment, and no loan leaves a
// final status; the tests below name what happens when a history does not
// have that shape.
func TestRecompute_EqualsReplayingTheHistoryThroughTheTriggers(t *testing.T) {
	h := newHistory(t)
	h.createCapital(at(9, 1, 2), "K1", 50000)

	h.approveLoan(at(9, 2, 3), "L1", 10000)
	h.createSchedule(at(9, 2, 4), "S1", "L1", "approved", 10000, 0, 0) // the planned row
	h.createSchedule(at(9, 9, 10), "S2", "L1", "paid_on_time", 3000, 0, 500)
	h.writeLoan(at(9, 9, 11), "L1", "paid_on_time", 10000)

	h.approveLoan(at(9, 3, 4), "L2", 20000, 500, 200, 100)
	h.createSchedule(at(9, 20, 8), "S3", "L2", "paid_late", 5000, 1000, 400)
	h.writeLoan(at(9, 20, 9), "L2", "paid_late", 20000, 500, 200, 100)
	h.writeLoan(at(10, 5, 5), "L2", "completed", 20000, 500, 200, 100) // 20200 - 6000 = 14200

	h.approveLoan(at(9, 4, 6), "L3", 8000)
	h.createSchedule(at(9, 15, 9), "S4", "L3", "paid_on_time", 1000, 0, 100)
	h.writeLoan(at(9, 15, 10), "L3", "paid_on_time", 8000)
	h.writeLoan(at(10, 6, 7), "L3", "bad_debt", 8000) // 8000 - 1000 = 7000

	h.writeLoan(at(9, 5, 1), "L4", "pending", 5000) // never approved

	liveTotals, liveItems := h.live()
	totals, items := h.recomputed()
	if !reflect.DeepEqual(totals, liveTotals) {
		for _, path := range sortedKeys(liveTotals) {
			if totals[path] != liveTotals[path] {
				t.Errorf("%s: triggers %v, recompute %v", path, liveTotals[path], totals[path])
			}
		}
		t.Fatalf("totals differ: triggers wrote %d paths, recompute %d", len(liveTotals), len(totals))
	}
	if !reflect.DeepEqual(items, liveItems) {
		t.Fatalf("data items differ: triggers wrote %d, recompute %d", len(liveItems), len(items))
	}

	// Hand-checked anchors, so the comparison is not two wrong numbers agreeing.
	anchors := map[string]float64{
		"sales/total_amount_released":                               38000,
		"capital_usage/total_capital":                               73200, // 50000 + 3000 + 5000 + 1000 + 14200
		"capital_usage/total_bad_debts":                             7000,
		"sales/total_collections":                                   24200, // 3500 + 5400 + 1100 + 14200
		"total_summary/year:2026:month:10/total_principal_payments": 14200,
	}
	for path, want := range anchors {
		if totals[path] != want {
			t.Errorf("%s: got %v, want %v", path, totals[path], want)
		}
	}
	if len(items) != 13 { // 3 releases, 1 capital, 3 paid rows x 2, settlement x 2, 1 bad debt
		t.Errorf("%d data items, want 13", len(items))
	}
}

// Every history in which the triggers and recompute give different numbers,
// each named. Spec §4 says which side is right for each.
func TestRecompute_DiffersFromTheTriggers_OnlyInTheNamedWays(t *testing.T) {
	const released, collections, badDebts = "sales/total_amount_released", "sales/total_collections", "capital_usage/total_bad_debts"

	t.Run("approval after application: the release moves to the day the loan was created", func(t *testing.T) {
		h := newHistory(t)
		h.writeLoan(at(9, 2, 3), "L1", "pending", 10000)
		h.writeLoan(at(9, 4, 3), "L1", "approved", 10000) // the trigger books at the event time
		live, _ := h.live()
		totals, _ := h.recomputed()

		const approvalDay = "total_summary/year:2026:month:9:week:36:day:4/total_amount_released"
		const createdDay = "total_summary/year:2026:month:9:week:36:day:2/total_amount_released"
		if live[approvalDay] != 10000 || totals[createdDay] != 10000 {
			t.Fatalf("triggers %v on the approval day, recompute %v on the creation day; want 10000 each", live[approvalDay], totals[createdDay])
		}
		if _, ok := totals[approvalDay]; ok {
			t.Fatal("recompute cannot know the approval day: the loan document does not record it")
		}
		for _, same := range []string{released, "products/business/total_amount_released", "total_summary/year:2026:month:9:week:36/total_amount_released"} {
			if live[same] != totals[same] {
				t.Errorf("%s: triggers %v, recompute %v; only the day may differ here", same, live[same], totals[same])
			}
		}
	})

	t.Run("a payment_submitted row: the trigger books it at creation and as returned principal, recompute waits for the confirmation", func(t *testing.T) {
		h := newHistory(t)
		h.approveLoan(at(9, 2, 3), "L1", 10000)
		h.createSchedule(at(9, 9, 10), "S2", "L1", "payment_submitted", 3000, 0, 500)
		h.writeLoan(at(9, 20, 3), "L1", "completed", 10000)
		live, _ := h.live()
		result := h.result()
		// Triggers: 3500 for the submission, then a remainder of 10000 - 3000.
		if live[collections] != 10500 || live["capital_usage/total_capital"] != 10000 {
			t.Fatalf("triggers: collections %v, capital %v; want 10500 and 10000", live[collections], live["capital_usage/total_capital"])
		}
		// Recompute: no confirmed cash, so the whole 10000 is the remainder.
		if got := result.Plan.Increments[collections]; got != 10000 {
			t.Fatalf("recompute: collections %v, want 10000", got)
		}
		if want := []string{"schedule S2 of loan L1: principal 3000.00, interest 500.00"}; !reflect.DeepEqual(result.Pending, want) {
			t.Fatalf("pending: got %q, want %q", result.Pending, want)
		}
	})

	t.Run("Pay now on the planned row: it carries the whole principal and is unconfirmed, so neither side counts it", func(t *testing.T) {
		h := newHistory(t)
		h.approveLoan(at(9, 2, 3), "L1", 10000)
		h.createSchedule(at(9, 2, 4), "S1", "L1", "approved", 10000, 0, 0) // open-term: principal_payment = amount
		h.updateSchedule(at(9, 9, 10), "S1", "payment_submitted")          // the borrower's update changes the status only
		live, _ := h.live()
		result := h.result()
		_, liveBooked := live[collections]
		_, booked := result.Plan.Increments[collections]
		if liveBooked || booked || result.Paid != 0 {
			t.Fatalf("triggers booked %v, recompute booked %v (%d rows); want nothing on either side", live[collections], result.Plan.Increments[collections], result.Paid)
		}
		if want := []string{"schedule S1 of loan L1: principal 10000.00, interest 0.00"}; !reflect.DeepEqual(result.Pending, want) {
			t.Fatalf("pending: got %q, want %q", result.Pending, want)
		}
	})

	t.Run("a planned row confirmed later by update: the create-only trigger never books it, recompute does", func(t *testing.T) {
		h := newHistory(t)
		h.approveLoan(at(9, 2, 3), "L1", 10000)
		h.createSchedule(at(9, 2, 4), "S1", "L1", "approved", 3000, 0, 500) // planned row persisted at approval
		h.updateSchedule(at(9, 8, 10), "S1", "payment_submitted")           // Pay now
		h.updateSchedule(at(9, 9, 10), "S1", "paid_on_time")                // confirmed
		live, _ := h.live()
		totals, _ := h.recomputed()
		if _, booked := live[collections]; booked {
			t.Fatalf("the trigger booked %v for an update", live[collections])
		}
		if totals[collections] != 3500 || totals["total_summary/year:2026:month:9:week:37:day:9/total_collections"] != 3500 {
			t.Fatalf("recompute: got %v, want 3500 on the day it was paid", totals[collections])
		}
	})

	t.Run("a submission rejected later: the trigger keeps the collection, recompute does not count it", func(t *testing.T) {
		h := newHistory(t)
		h.approveLoan(at(9, 2, 3), "L1", 10000)
		h.createSchedule(at(9, 9, 10), "S2", "L1", "payment_submitted", 3000, 0, 500)
		h.updateSchedule(at(9, 10, 10), "S2", "not_paid") // rejected: the row is not a payment any more
		live, _ := h.live()
		result := h.result()
		if live[collections] != 3500 {
			t.Fatalf("triggers: got %v, want 3500", live[collections])
		}
		if _, booked := result.Plan.Increments[collections]; booked || len(result.Pending) != 0 {
			t.Fatalf("recompute counted or listed a rejected submission: %v, %v", result.Plan.Increments[collections], result.Pending)
		}
	})

	t.Run("a loan that leaves approved and comes back: the trigger releases it twice, recompute once", func(t *testing.T) {
		h := newHistory(t)
		h.approveLoan(at(9, 2, 3), "L1", 10000)
		h.writeLoan(at(9, 3, 3), "L1", "not_paid", 10000)
		h.writeLoan(at(9, 4, 3), "L1", "approved", 10000)
		live, _ := h.live()
		totals, _ := h.recomputed()
		if live[released] != 20000 || totals[released] != 10000 {
			t.Fatalf("triggers %v, recompute %v; want 20000 and 10000", live[released], totals[released])
		}
	})

	t.Run("a bad debt followed by a payment: the trigger keeps the write-off, recompute sees a loan that is not a bad debt", func(t *testing.T) {
		h := newHistory(t)
		h.approveLoan(at(9, 2, 3), "L1", 10000)
		h.writeLoan(at(9, 10, 3), "L1", "bad_debt", 10000)
		h.createSchedule(at(9, 20, 3), "S2", "L1", "paid_on_time", 2000, 0, 100)
		h.writeLoan(at(9, 20, 4), "L1", "paid_on_time", 10000) // the app moves the loan to its schedule's status
		live, _ := h.live()
		totals, _ := h.recomputed()
		if _, booked := totals[badDebts]; live[badDebts] != 10000 || booked {
			t.Fatalf("triggers %v, recompute %v; want 10000 and nothing", live[badDebts], totals[badDebts])
		}
	})

	t.Run("a loan completed twice: the trigger books the remainder twice, recompute once", func(t *testing.T) {
		h := newHistory(t)
		h.approveLoan(at(9, 2, 3), "L1", 10000)
		h.writeLoan(at(9, 10, 3), "L1", "completed", 10000)
		h.writeLoan(at(9, 11, 3), "L1", "not_paid", 10000)
		h.writeLoan(at(9, 12, 3), "L1", "completed", 10000)
		live, _ := h.live()
		totals, _ := h.recomputed()
		if live[collections] != 20000 || totals[collections] != 10000 {
			t.Fatalf("triggers %v, recompute %v; want 20000 and 10000", live[collections], totals[collections])
		}
	})

	t.Run("a row paid after settlement: the trigger adds it to a remainder already booked in full, recompute does not exceed the loan", func(t *testing.T) {
		h := newHistory(t)
		h.approveLoan(at(9, 2, 3), "L1", 10000)
		h.writeLoan(at(9, 10, 3), "L1", "completed", 10000) // nothing paid yet: remainder 10000
		h.createSchedule(at(9, 20, 3), "S2", "L1", "paid_on_time", 4000, 0, 0)
		live, _ := h.live()
		totals, _ := h.recomputed()
		if live[collections] != 14000 || totals[collections] != 10000 {
			t.Fatalf("triggers %v, recompute %v; want 14000 and 10000 (remainder 6000 + row 4000)", live[collections], totals[collections])
		}
	})

	t.Run("two events in the same millisecond: the later data item overwrites the earlier, recompute keeps both", func(t *testing.T) {
		h := newHistory(t)
		h.createCapital(at(9, 1, 2), "K1", 100)
		h.createCapital(at(9, 1, 2), "K2", 200)
		live, liveItems := h.live()
		totals, items := h.recomputed()
		if live["capital_usage/total_capital"] != 300 || totals["capital_usage/total_capital"] != 300 {
			t.Fatalf("totals must agree at 300: triggers %v, recompute %v", live["capital_usage/total_capital"], totals["capital_usage/total_capital"])
		}
		if len(liveItems) != 1 || len(items) != 2 {
			t.Fatalf("data items: triggers %d, recompute %d; want 1 and 2", len(liveItems), len(items))
		}
	})
}
