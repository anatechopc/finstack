package triggers_test

import (
	"context"
	"errors"
	"sync"
	"testing"

	"com.loooans.app/triggers"
)

const reportBase = "dev/companies/C1/report_summary/"

func approvedEvent(id string) triggers.LoanChangeEvent {
	return triggers.LoanChangeEvent{
		EventId: id, CompanyId: "C1", LoanId: "L1",
		Status: "approved", OldStatus: "pending", Amount: 10000,
	}
}

func TestHandleLoanChange_DoubleDelivery_AppliesOnce(t *testing.T) {
	store := newFakeReportStore()
	deps := reportDeps(store, nil)

	first, err := triggers.HandleLoanChangeCore(context.Background(), "dev", approvedEvent("e1"), deps)
	if err != nil || first != triggers.ReportApplied {
		t.Fatalf("first delivery: outcome %v, err %v", first, err)
	}
	second, err := triggers.HandleLoanChangeCore(context.Background(), "dev", approvedEvent("e1"), deps)
	if err != nil || second != triggers.ReportAlreadyApplied {
		t.Fatalf("redelivery: outcome %v, err %v", second, err)
	}

	if len(store.Applies) != 1 {
		t.Errorf("applies: got %d, want 1", len(store.Applies))
	}
	if got := store.Nodes[reportBase+"sales/total_amount_released"]; got != 10000 {
		t.Errorf("total_amount_released after redelivery: got %v, want 10000", got)
	}
}

func TestHandleLoanChange_ConcurrentSameEvent_AppliesOnce(t *testing.T) {
	store := newFakeReportStore()
	deps := reportDeps(store, nil)

	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := triggers.HandleLoanChangeCore(context.Background(), "dev", approvedEvent("e1"), deps); err != nil {
				t.Errorf("unexpected err: %v", err)
			}
		}()
	}
	wg.Wait()

	if len(store.Applies) != 1 || store.Nodes[reportBase+"sales/total_amount_released"] != 10000 {
		t.Errorf("applies %d, total %v; want 1 and 10000", len(store.Applies), store.Nodes[reportBase+"sales/total_amount_released"])
	}
}

func TestHandleLoanChange_DifferentEventsBothCount(t *testing.T) {
	store := newFakeReportStore()
	deps := reportDeps(store, nil)

	for _, id := range []string{"e1", "e2"} {
		if _, err := triggers.HandleLoanChangeCore(context.Background(), "dev", approvedEvent(id), deps); err != nil {
			t.Fatalf("%s: %v", id, err)
		}
	}
	if got := store.Nodes[reportBase+"total_summary/year:2026/total_amount_released"]; got != 20000 {
		t.Errorf("two releases: got %v, want 20000", got)
	}
}

func TestHandleLoanChange_SameStatusRewrite_TouchesNothing(t *testing.T) {
	store := newFakeReportStore()
	store.ProductTypeErr = errors.New("must not be consulted")
	ev := approvedEvent("e1")
	ev.OldStatus = "approved"

	outcome, err := triggers.HandleLoanChangeCore(context.Background(), "dev", ev, reportDeps(store, nil))
	if err != nil || outcome != triggers.ReportSkipped {
		t.Fatalf("outcome %v, err %v", outcome, err)
	}
	if len(store.Claims) != 0 || len(store.Applies) != 0 {
		t.Errorf("claims %d, applies %d; want none", len(store.Claims), len(store.Applies))
	}
}

func TestHandleLoanChange_Delete_IsNoop(t *testing.T) {
	store := newFakeReportStore()
	store.ProductTypeErr = errors.New("must not be consulted")

	outcome, err := triggers.HandleLoanChangeCore(context.Background(), "dev", triggers.LoanChangeEvent{EventId: "e1", IsDelete: true}, reportDeps(store, nil))
	if err != nil || outcome != triggers.ReportSkipped {
		t.Fatalf("outcome %v, err %v", outcome, err)
	}
}

func TestHandleLoanChange_MissingProductType_ErrorsBeforeClaiming(t *testing.T) {
	store := newFakeReportStore()
	store.ProductTypes = map[string]string{}

	_, err := triggers.HandleLoanChangeCore(context.Background(), "dev", approvedEvent("e1"), reportDeps(store, nil))
	if err == nil {
		t.Fatal("expected an error")
	}
	if len(store.Claims) != 0 {
		t.Errorf("the event must not be claimed when nothing was applied: %v", store.Claims)
	}
}

func TestHandleLoanChange_ApplyFailureReleasesClaim_SoARetryApplies(t *testing.T) {
	store := newFakeReportStore()
	deps := reportDeps(store, nil)
	boom := errors.New("rtdb unavailable")
	store.ApplyErr = boom

	_, err := triggers.HandleLoanChangeCore(context.Background(), "dev", approvedEvent("e1"), deps)
	if !errors.Is(err, boom) {
		t.Fatalf("error must wrap the apply failure, got %v", err)
	}
	if len(store.Claims) != 0 {
		t.Fatalf("claim must be released after a failed apply: %v", store.Claims)
	}

	store.ApplyErr = nil
	outcome, err := triggers.HandleLoanChangeCore(context.Background(), "dev", approvedEvent("e1"), deps)
	if err != nil || outcome != triggers.ReportApplied {
		t.Fatalf("retry: outcome %v, err %v", outcome, err)
	}
	if got := store.Nodes[reportBase+"sales/total_amount_released"]; got != 10000 {
		t.Errorf("after retry: got %v, want 10000", got)
	}
}

func TestHandleLoanChange_ReleaseFailure_ReportsBothErrors(t *testing.T) {
	store := newFakeReportStore()
	applyErr := errors.New("apply failed")
	releaseErr := errors.New("release failed")
	store.ApplyErr, store.ReleaseErr = applyErr, releaseErr

	_, err := triggers.HandleLoanChangeCore(context.Background(), "dev", approvedEvent("e1"), reportDeps(store, nil))
	if !errors.Is(err, applyErr) || !errors.Is(err, releaseErr) {
		t.Fatalf("both failures must be reported (D3), got %v", err)
	}
}

func TestHandleLoanChange_Completed_LoadsSchedulesAndBooksRemainingPrincipal(t *testing.T) {
	store := newFakeReportStore()
	deps := reportDeps(store, []triggers.ScheduleAmounts{
		{Principal: 3000, Extra: 1000, Interest: 500},
		{Principal: 2000, Interest: 400},
	})
	ev := triggers.LoanChangeEvent{
		EventId: "e9", CompanyId: "C1", LoanId: "L1", Status: "completed", OldStatus: "approved",
		Amount: 10000, AdditionalCharges: 500, Deductions: 200, UpfrontCollection: 100,
	}

	outcome, err := triggers.HandleLoanChangeCore(context.Background(), "dev", ev, deps)
	if err != nil || outcome != triggers.ReportApplied {
		t.Fatalf("outcome %v, err %v", outcome, err)
	}
	if got := store.Nodes[reportBase+"capital_usage/total_capital"]; got != 4200 {
		t.Errorf("capital returned: got %v, want 4200", got)
	}
	if got := store.Nodes[reportBase+"sales/total_collections"]; got != 4200 {
		t.Errorf("collections: got %v, want 4200", got)
	}
	if _, booked := store.Nodes[reportBase+"sales/total_interest_payments"]; booked {
		t.Errorf("interest must not be booked at completion")
	}
	if len(store.Items) != 2 {
		t.Errorf("items: got %d, want 2 (refresh_capital + collection)", len(store.Items))
	}
}

func TestHandleLoanChange_CompletedWithoutLoader_Errors(t *testing.T) {
	store := newFakeReportStore()
	deps := reportDeps(store, nil)
	deps.LoadSchedules = nil
	ev := approvedEvent("e1")
	ev.Status, ev.OldStatus = "completed", "approved"

	if _, err := triggers.HandleLoanChangeCore(context.Background(), "dev", ev, deps); err == nil {
		t.Fatal("expected an error when schedules cannot be loaded")
	}
	if len(store.Claims) != 0 {
		t.Errorf("nothing must be claimed: %v", store.Claims)
	}
}

func TestHandleScheduleCreated_NotPaid_SkipsWithoutLookups(t *testing.T) {
	store := newFakeReportStore()
	store.ProductTypeErr = errors.New("must not be consulted")

	outcome, err := triggers.HandleScheduleCreatedCore(context.Background(), "dev", triggers.ScheduleCreatedEvent{
		EventId: "s1", CompanyId: "C1", LoanId: "L1", Status: "not_paid", Principal: 2000,
	}, reportDeps(store, nil))
	if err != nil || outcome != triggers.ReportSkipped {
		t.Fatalf("outcome %v, err %v", outcome, err)
	}
}

func TestHandleScheduleCreated_PaidRow_BooksCollectionOnce(t *testing.T) {
	store := newFakeReportStore()
	deps := reportDeps(store, nil)
	ev := triggers.ScheduleCreatedEvent{
		EventId: "s1", CompanyId: "C1", LoanId: "L1", Status: "paid_late", Interest: 500, Principal: 2000,
	}

	for i := 0; i < 2; i++ {
		if _, err := triggers.HandleScheduleCreatedCore(context.Background(), "dev", ev, deps); err != nil {
			t.Fatalf("delivery %d: %v", i+1, err)
		}
	}
	if got := store.Nodes[reportBase+"sales/total_collections"]; got != 2500 {
		t.Errorf("collections: got %v, want 2500", got)
	}
	if got := store.Nodes[reportBase+"capital_usage/total_capital"]; got != 2000 {
		t.Errorf("capital: got %v, want 2000", got)
	}
}

func TestHandleCapitalCreated_BooksCapitalOnce(t *testing.T) {
	store := newFakeReportStore()
	deps := reportDeps(store, nil)
	ev := triggers.CapitalCreatedEvent{EventId: "c1", CompanyId: "C1", CapitalId: "K1", Amount: 50000}

	for i := 0; i < 2; i++ {
		if _, err := triggers.HandleCapitalCreatedCore(context.Background(), "dev", ev, deps); err != nil {
			t.Fatalf("delivery %d: %v", i+1, err)
		}
	}
	if got := store.Nodes[reportBase+"capital_usage/total_capital"]; got != 50000 {
		t.Errorf("capital: got %v, want 50000", got)
	}
	if len(store.Items) != 1 {
		t.Errorf("items: got %d, want 1", len(store.Items))
	}
}
