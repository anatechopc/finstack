package triggers_test

import (
	"sort"
	"strings"
	"testing"
	"time"

	"com.loooans.app/triggers"
)

// Time buckets for testNow (2026-09-09, ISO week 37), derived by hand.
var buckets = []string{
	"year:2026",
	"year:2026:month:9",
	"year:2026:month:9:week:37",
	"year:2026:month:9:week:37:day:9",
}

const itemKey = "2026:9:week:37:9T10:30:0:0"

// summaryPaths lists the six nodes a summary field lives under.
func summaryPaths(field, productType string) []string {
	var paths []string
	for _, b := range buckets {
		paths = append(paths, "total_summary/"+b+"/"+field)
	}
	return append(paths, "products/"+productType+"/"+field, "sales/"+field)
}

func sortedKeys(m map[string]float64) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

func expectIncrements(t *testing.T, plan triggers.ReportPlan, want map[string]float64) {
	t.Helper()
	if len(plan.Increments) != len(want) {
		t.Fatalf("increments: got %d paths %v, want %d", len(plan.Increments), sortedKeys(plan.Increments), len(want))
	}
	for path, delta := range want {
		got, ok := plan.Increments[path]
		if !ok || got != delta {
			t.Errorf("%s: got %v (present %v), want %v", path, got, ok, delta)
		}
	}
}

func expectItem(t *testing.T, item triggers.ReportDataItem, want map[string]any) {
	t.Helper()
	for field, value := range want {
		if item.Item[field] != value {
			t.Errorf("item %s: field %s got %v (%T), want %v (%T)", item.Key, field, item.Item[field], item.Item[field], value, value)
		}
	}
}

// referenceSchedules is what Firestore holds for the spec's reference loan:
// the planned first row the app persists at approval (status approved,
// principal_payment = amount for an open-term loan), two payments, and an
// unpaid planned row. Only the two payments have collected anything.
var referenceSchedules = []triggers.ScheduleAmounts{
	{Status: "approved", Principal: 10000},
	{Status: "paid_on_time", Principal: 3000, Extra: 1000, Interest: 500},
	{Status: "paid_late", Principal: 2000, Interest: 400},
	{Status: "not_paid", Principal: 2500, Interest: 300},
}

func TestPlanLoanReport_Approved_ReleasesAmountAcrossSixNodesAndOneItem(t *testing.T) {
	plan, skip := triggers.PlanLoanReport(triggers.LoanReportInput{
		Status: "approved", OldStatus: "pending", Amount: 10000,
		ProductType: "business", LoanId: "L1", Now: testNow,
	})
	if skip != "" {
		t.Fatalf("skipped: %s", skip)
	}

	want := map[string]float64{}
	for _, p := range summaryPaths("total_amount_released", "business") {
		want[p] = 10000
	}
	expectIncrements(t, plan, want)

	if len(plan.Items) != 1 {
		t.Fatalf("items: got %d, want 1", len(plan.Items))
	}
	if plan.Items[0].Key != itemKey {
		t.Errorf("key: got %q, want %q", plan.Items[0].Key, itemKey)
	}
	expectItem(t, plan.Items[0], map[string]any{
		"data_type": "release", "amount": 10000.0, "interest": 0.0, "principal": 0.0,
		"loan_id": "L1", "product_type": "business", "capital_id": "",
		"created_at": testNow.UnixMilli(),
	})
}

func TestPlanLoanReport_OnlyStatusTransitionsCount(t *testing.T) {
	cases := []struct {
		status, old string
		counted     bool
	}{
		{"approved", "approved", false}, // an edit to an approved loan: D1
		{"approved", "pending", true},
		{"approved", "", true}, // created already approved (teller flow)
		{"completed", "approved", true},
		{"completed", "completed", false},
		{"bad_debt", "approved", true},
		{"bad_debt", "bad_debt", false},
		{"pending", "", false},
		{"declined", "pending", false},
	}
	for _, c := range cases {
		plan, skip := triggers.PlanLoanReport(triggers.LoanReportInput{
			Status: c.status, OldStatus: c.old, Amount: 1, ProductType: "p", Now: testNow,
		})
		if counted := skip == ""; counted != c.counted {
			t.Errorf("%s (was %q): counted=%v, want %v (%s)", c.status, c.old, counted, c.counted, skip)
		}
		if !c.counted && !plan.IsEmpty() {
			t.Errorf("%s (was %q): plan must be empty", c.status, c.old)
		}
	}
}

func TestPlanLoanReport_BadDebt_IsAmountMinusPrincipalOfPaidRows(t *testing.T) {
	// 10000 released; principal of the PAID rows 3000 + 2000 -> bad debt 5000.
	// The planned rows (approved first row, unpaid row), extra and interest
	// payments do not reduce it.
	plan, skip := triggers.PlanLoanReport(triggers.LoanReportInput{
		Status: "bad_debt", OldStatus: "approved", Amount: 10000,
		ProductType: "business", LoanId: "L1", Now: testNow, Schedules: referenceSchedules,
	})
	if skip != "" {
		t.Fatalf("skipped: %s", skip)
	}

	want := map[string]float64{}
	for _, b := range buckets {
		want["total_summary/"+b+"/total_bad_debts"] = 5000
	}
	want["products/business/total_bad_debts"] = 5000
	want["capital_usage/total_bad_debts"] = 5000
	expectIncrements(t, plan, want)

	if len(plan.Items) != 1 {
		t.Fatalf("items: got %d, want 1", len(plan.Items))
	}
	expectItem(t, plan.Items[0], map[string]any{"data_type": "bad_debt", "amount": 5000.0, "loan_id": "L1"})
}

func TestPlanLoanReport_Completed_BooksRemainingPrincipalOfPaidRows(t *testing.T) {
	// released  = 10000 + 500 charges - 200 deductions - 100 upfront = 10200
	// returned  = paid rows only: 3000 + 1000 extra + 2000            = 6000
	// remaining = 4200 (owner decision 2026-09-09)
	// Summing every row would count the planned first row (10000) and the
	// unpaid row (2500) and book -8300. Before this PR: charges subtracted
	// twice (D5) and interest subtracted from principal (D6).
	plan, skip := triggers.PlanLoanReport(triggers.LoanReportInput{
		Status: "completed", OldStatus: "approved",
		Amount: 10000, AdditionalCharges: 500, Deductions: 200, UpfrontCollection: 100,
		ProductType: "business", LoanId: "L1", Now: testNow, Schedules: referenceSchedules,
	})
	if skip != "" {
		t.Fatalf("skipped: %s", skip)
	}

	want := map[string]float64{"capital_usage/total_capital": 4200}
	for _, p := range summaryPaths("total_collections", "business") {
		want[p] = 4200
	}
	for _, p := range summaryPaths("total_principal_payments", "business") {
		want[p] = 4200
	}
	expectIncrements(t, plan, want)
	for path := range plan.Increments {
		if strings.Contains(path, "interest") {
			t.Errorf("interest must not be booked at completion, got %s", path)
		}
	}

	if len(plan.Items) != 2 {
		t.Fatalf("items: got %d, want 2", len(plan.Items))
	}
	refresh, collection := plan.Items[0], plan.Items[1]
	expectItem(t, refresh, map[string]any{"data_type": "refresh_capital", "amount": 4200.0, "product_type": "", "loan_id": ""})
	expectItem(t, collection, map[string]any{
		"data_type": "collection", "amount": 4200.0, "principal": 4200.0, "interest": 0.0,
		"product_type": "business", "loan_id": "L1",
	})
	if refresh.Key != itemKey || collection.Key != itemKey+":2" {
		t.Errorf("keys must be unique within the plan: %q, %q", refresh.Key, collection.Key)
	}
}

func TestPlanLoanReport_Completed_WithoutPaidRowsBooksTheWholeRelease(t *testing.T) {
	// Settled before any payment: remaining = released = 10200.
	plan, _ := triggers.PlanLoanReport(triggers.LoanReportInput{
		Status: "completed", OldStatus: "approved",
		Amount: 10000, AdditionalCharges: 500, Deductions: 200, UpfrontCollection: 100,
		ProductType: "business", LoanId: "L1", Now: testNow,
		Schedules: []triggers.ScheduleAmounts{{Status: "approved", Principal: 10000}},
	})
	if got := plan.Increments["sales/total_collections"]; got != 10200 {
		t.Errorf("collections: got %v, want 10200", got)
	}
}

func TestPlanLoanReport_OverpaidPrincipalFloorsAtZero(t *testing.T) {
	// Paid rows returned more than was released (extra payments): the
	// settlement and the bad debt book 0, never a negative amount.
	overpaid := []triggers.ScheduleAmounts{{Status: "paid_on_time", Principal: 9000, Extra: 3000}}
	completed, _ := triggers.PlanLoanReport(triggers.LoanReportInput{
		Status: "completed", OldStatus: "approved", Amount: 10000,
		ProductType: "business", LoanId: "L1", Now: testNow, Schedules: overpaid,
	})
	if got := completed.Increments["sales/total_collections"]; got != 0 {
		t.Errorf("completed collections: got %v, want 0", got)
	}
	badDebt, _ := triggers.PlanLoanReport(triggers.LoanReportInput{
		Status: "bad_debt", OldStatus: "approved", Amount: 10000,
		ProductType: "business", LoanId: "L1", Now: testNow,
		Schedules: []triggers.ScheduleAmounts{{Status: "paid_on_time", Principal: 12000}},
	})
	if got := badDebt.Increments["capital_usage/total_bad_debts"]; got != 0 {
		t.Errorf("bad debt: got %v, want 0", got)
	}
}

func TestPlanScheduleReport_PaidRowBooksCollectionInterestPrincipalAndCapital(t *testing.T) {
	// principal 2000 + interest 500 -> collection 2500; capital back 2000.
	plan, skip := triggers.PlanScheduleReport(triggers.ScheduleReportInput{
		Status: "paid_on_time", Interest: 500, Principal: 2000,
		ProductType: "business", LoanId: "L1", Now: testNow,
	})
	if skip != "" {
		t.Fatalf("skipped: %s", skip)
	}

	want := map[string]float64{"capital_usage/total_capital": 2000}
	for _, p := range summaryPaths("total_collections", "business") {
		want[p] = 2500
	}
	for _, p := range summaryPaths("total_interest_payments", "business") {
		want[p] = 500
	}
	for _, p := range summaryPaths("total_principal_payments", "business") {
		want[p] = 2000
	}
	expectIncrements(t, plan, want)

	if len(plan.Items) != 2 {
		t.Fatalf("items: got %d, want 2", len(plan.Items))
	}
	expectItem(t, plan.Items[0], map[string]any{"data_type": "refresh_capital", "amount": 2000.0})
	expectItem(t, plan.Items[1], map[string]any{
		"data_type": "collection", "amount": 2500.0, "interest": 500.0, "principal": 2000.0, "loan_id": "L1",
	})
}

func TestPlanScheduleReport_OnlyPaidOrSubmittedRowsCount(t *testing.T) {
	for status, counted := range map[string]bool{
		"payment_submitted": true, "paid_on_time": true, "paid_late": true,
		"not_paid": false, "not_paid_overdue": false, "pending": false, "approved": false,
	} {
		plan, skip := triggers.PlanScheduleReport(triggers.ScheduleReportInput{Status: status, Principal: 1, ProductType: "p", Now: testNow})
		if got := skip == ""; got != counted {
			t.Errorf("%s: counted=%v, want %v", status, got, counted)
		}
		if !counted && !plan.IsEmpty() {
			t.Errorf("%s: plan must be empty", status)
		}
	}
}

func TestPlanCapitalReport_AddsCapitalAndItem(t *testing.T) {
	plan := triggers.PlanCapitalReport(triggers.CapitalReportInput{Amount: 50000, CapitalId: "C1", Now: testNow})

	expectIncrements(t, plan, map[string]float64{"capital_usage/total_capital": 50000})
	if len(plan.Items) != 1 {
		t.Fatalf("items: got %d, want 1", len(plan.Items))
	}
	expectItem(t, plan.Items[0], map[string]any{"data_type": "add_capital", "amount": 50000.0, "capital_id": "C1", "loan_id": ""})
}

func TestTimeBuckets_UseTheISOWeekAcrossTheYearBoundary(t *testing.T) {
	// Historical behaviour, pinned: the ISO week is combined with the calendar
	// year and month, so Dec 31 2026 sits in week 53 of 2026 and Jan 1 2027 in
	// week 53 of 2027 (derived by hand: 2026-12-31 is a Thursday of ISO week 53).
	cases := map[time.Time]string{
		time.Date(2026, 12, 31, 0, 0, 0, 0, time.UTC): "total_summary/year:2026:month:12:week:53:day:31/total_amount_released",
		time.Date(2027, 1, 1, 0, 0, 0, 0, time.UTC):   "total_summary/year:2027:month:1:week:53:day:1/total_amount_released",
	}
	for now, path := range cases {
		loanPlan, _ := triggers.PlanLoanReport(triggers.LoanReportInput{
			Status: "approved", OldStatus: "pending", Amount: 1, ProductType: "p", Now: now,
		})
		if _, ok := loanPlan.Increments[path]; !ok {
			t.Errorf("%s: missing bucket %s in %v", now.Format("2006-01-02"), path, sortedKeys(loanPlan.Increments))
		}
	}
}
