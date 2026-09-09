package triggers_test

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

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
	deps, _ := newDeps(store, nil)

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
	deps, _ := newDeps(store, nil)

	var wg sync.WaitGroup
	var mu sync.Mutex
	applied, waiting := 0, 0
	for range 20 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			outcome, err := triggers.HandleLoanChangeCore(context.Background(), "dev", approvedEvent("e1"), deps)
			mu.Lock()
			defer mu.Unlock()
			switch {
			case err == nil && outcome == triggers.ReportApplied:
				applied++
			case errors.Is(err, triggers.ErrReportInProgress):
				waiting++ // told to retry later; the winner is still writing
			case err == nil && outcome == triggers.ReportAlreadyApplied:
			default:
				t.Errorf("unexpected outcome %v err %v", outcome, err)
			}
		}()
	}
	wg.Wait()

	if applied != 1 || len(store.Applies) != 1 || store.Nodes[reportBase+"sales/total_amount_released"] != 10000 {
		t.Errorf("applied %d (waiting %d), applies %d, total %v; want exactly one apply of 10000",
			applied, waiting, len(store.Applies), store.Nodes[reportBase+"sales/total_amount_released"])
	}
}

func TestHandleLoanChange_DifferentEventsBothCount(t *testing.T) {
	store := newFakeReportStore()
	deps, _ := newDeps(store, nil)

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
	deps, _ := newDeps(store, nil)
	ev := approvedEvent("e1")
	ev.OldStatus = "approved"

	outcome, err := triggers.HandleLoanChangeCore(context.Background(), "dev", ev, deps)
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
	deps, _ := newDeps(store, nil)

	outcome, err := triggers.HandleLoanChangeCore(context.Background(), "dev", triggers.LoanChangeEvent{EventId: "e1", IsDelete: true}, deps)
	if err != nil || outcome != triggers.ReportSkipped {
		t.Fatalf("outcome %v, err %v", outcome, err)
	}
}

func TestHandleLoanChange_MissingProductType_ErrorsBeforeClaiming(t *testing.T) {
	store := newFakeReportStore()
	store.ProductTypes = map[string]string{}
	deps, _ := newDeps(store, nil)

	outcome, err := triggers.HandleLoanChangeCore(context.Background(), "dev", approvedEvent("e1"), deps)
	if err == nil || outcome != triggers.ReportFailed {
		t.Fatalf("expected a failure, got outcome %v err %v", outcome, err)
	}
	if len(store.Claims) != 0 {
		t.Errorf("the event must not be claimed when nothing was applied: %v", store.Claims)
	}
}

func TestHandleLoanChange_ApplyFailure_RetryWaitsForTheLeaseThenApplies(t *testing.T) {
	store := newFakeReportStore()
	deps, clock := newDeps(store, nil)
	boom := errors.New("rtdb unavailable")
	store.ApplyErr = boom

	outcome, err := triggers.HandleLoanChangeCore(context.Background(), "dev", approvedEvent("e1"), deps)
	if !errors.Is(err, boom) || outcome != triggers.ReportFailed {
		t.Fatalf("error must wrap the apply failure, got outcome %v err %v", outcome, err)
	}
	if store.pendingClaims() != 1 {
		t.Fatalf("the claim must stay pending (never released): %v", store.Claims)
	}

	// An immediate retry sees a fresh lease and is told to come back later.
	store.ApplyErr = nil
	_, err = triggers.HandleLoanChangeCore(context.Background(), "dev", approvedEvent("e1"), deps)
	if !errors.Is(err, triggers.ErrReportInProgress) {
		t.Fatalf("retry within the lease must be deferred, got %v", err)
	}
	if len(store.Applies) != 0 {
		t.Fatalf("nothing may be applied during the lease")
	}

	// After the lease expires the retry takes over and applies exactly once.
	clock.Advance(11 * time.Minute)
	outcome, err = triggers.HandleLoanChangeCore(context.Background(), "dev", approvedEvent("e1"), deps)
	if err != nil || outcome != triggers.ReportApplied {
		t.Fatalf("retry after the lease: outcome %v, err %v", outcome, err)
	}
	if got := store.Nodes[reportBase+"sales/total_amount_released"]; got != 10000 {
		t.Errorf("after retry: got %v, want 10000", got)
	}
}

func TestHandleLoanChange_ApplyCommittedButClientErrored_RetryIsNoop(t *testing.T) {
	// The write reached the server, the client saw a timeout: the applied
	// marker landed with the increments, so the retry must not count again.
	store := newFakeReportStore()
	deps, clock := newDeps(store, nil)
	store.ApplyErr = errors.New("timeout")
	store.ApplyCommitsDespiteErr = true

	if _, err := triggers.HandleLoanChangeCore(context.Background(), "dev", approvedEvent("e1"), deps); err == nil {
		t.Fatal("expected the client-side error")
	}
	store.ApplyErr = nil
	clock.Advance(time.Minute)

	outcome, err := triggers.HandleLoanChangeCore(context.Background(), "dev", approvedEvent("e1"), deps)
	if err != nil || outcome != triggers.ReportAlreadyApplied {
		t.Fatalf("retry: outcome %v, err %v", outcome, err)
	}
	if got := store.Nodes[reportBase+"sales/total_amount_released"]; got != 10000 || len(store.Applies) != 1 {
		t.Errorf("must be counted once: total %v, applies %d", got, len(store.Applies))
	}
}

func TestHandleLoanChange_Completed_LoadsSchedulesAndBooksRemainingPrincipal(t *testing.T) {
	store := newFakeReportStore()
	deps, _ := newDeps(store, []triggers.ScheduleAmounts{
		{Status: "approved", Principal: 10000}, // the planned first row the app persists at approval
		{Status: "paid_on_time", Principal: 3000, Extra: 1000, Interest: 500},
		{Status: "paid_late", Principal: 2000, Interest: 400},
		{Status: "not_paid", Principal: 2500},
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
		t.Errorf("capital returned: got %v, want 4200 (planned and unpaid rows ignored)", got)
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
	deps, _ := newDeps(store, nil)
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
	deps, _ := newDeps(store, nil)

	outcome, err := triggers.HandleScheduleCreatedCore(context.Background(), "dev", triggers.ScheduleCreatedEvent{
		EventId: "s1", CompanyId: "C1", LoanId: "L1", Status: "not_paid", Principal: 2000,
	}, deps)
	if err != nil || outcome != triggers.ReportSkipped {
		t.Fatalf("outcome %v, err %v", outcome, err)
	}
}

func TestHandleScheduleCreated_PaidRow_BooksCollectionOnce(t *testing.T) {
	store := newFakeReportStore()
	deps, _ := newDeps(store, nil)
	ev := triggers.ScheduleCreatedEvent{
		EventId: "s1", CompanyId: "C1", LoanId: "L1", Status: "paid_late", Interest: 500, Principal: 2000,
	}

	for i := range 2 {
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
	deps, _ := newDeps(store, nil)
	ev := triggers.CapitalCreatedEvent{EventId: "c1", CompanyId: "C1", CapitalId: "K1", Amount: 50000}

	for i := range 2 {
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

func TestDecideClaim_Rule(t *testing.T) {
	now := testNow
	if result, record := triggers.DecideClaim(nil, now); result != triggers.ClaimWon || record.ClaimedAt != now.UnixMilli() {
		t.Errorf("first claim: %v %+v", result, record)
	}
	applied := triggers.ClaimRecord{Applied: true}
	if result, _ := triggers.DecideClaim(&applied, now); result != triggers.ClaimApplied {
		t.Errorf("applied event: %v", result)
	}
	fresh := triggers.ClaimRecord{ClaimedAt: now.Add(-time.Minute).UnixMilli()}
	if result, _ := triggers.DecideClaim(&fresh, now); result != triggers.ClaimInProgress {
		t.Errorf("fresh lease: %v", result)
	}
	stale := triggers.ClaimRecord{ClaimedAt: now.Add(-11 * time.Minute).UnixMilli()}
	if result, record := triggers.DecideClaim(&stale, now); result != triggers.ClaimWon || record.ClaimedAt != now.UnixMilli() {
		t.Errorf("stale lease must be taken over: %v %+v", result, record)
	}
}
