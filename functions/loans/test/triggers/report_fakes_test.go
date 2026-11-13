package triggers_test

import (
	"context"
	"errors"
	"sync"
	"time"

	"com.loooans.app/triggers"
)

// fakeClock is a settable clock so lease behaviour can be tested.
type fakeClock struct {
	mu  sync.Mutex
	now time.Time
}

func (c *fakeClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.now
}

func (c *fakeClock) Advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.now = c.now.Add(d)
}

// fakeReportStore is an in-memory ReportStore that records every call and
// follows the same claim rule (DecideClaim) as the RTDB store.
type fakeReportStore struct {
	mu             sync.Mutex
	Nodes          map[string]float64
	Items          map[string]map[string]any
	Claims         map[string]triggers.ClaimRecord
	Applies        []triggers.ReportPlan
	ProductTypes   map[string]string
	ClaimErr       error
	ApplyErr       error
	ProductTypeErr error
	// ApplyCommitsDespiteErr simulates a write that reached the server while
	// the client saw an error (timeout): the plan and the applied marker land,
	// then ApplyErr is returned.
	ApplyCommitsDespiteErr bool
}

func newFakeReportStore() *fakeReportStore {
	return &fakeReportStore{
		Nodes:        map[string]float64{},
		Items:        map[string]map[string]any{},
		Claims:       map[string]triggers.ClaimRecord{},
		ProductTypes: map[string]string{"L1": "business"},
	}
}

func (f *fakeReportStore) ClaimEvent(_ context.Context, basePath, eventId string, now time.Time) (triggers.ClaimResult, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.ClaimErr != nil {
		return triggers.ClaimInProgress, f.ClaimErr
	}
	key := basePath + "/" + eventId
	var current *triggers.ClaimRecord
	if record, ok := f.Claims[key]; ok {
		current = &record
	}
	result, next := triggers.DecideClaim(current, now)
	f.Claims[key] = next
	return result, nil
}

func (f *fakeReportStore) ProductType(_ context.Context, _ string, loanId string) (string, error) {
	if f.ProductTypeErr != nil {
		return "", f.ProductTypeErr
	}
	productType, ok := f.ProductTypes[loanId]
	if !ok {
		return "", errors.New("product type not found")
	}
	return productType, nil
}

func (f *fakeReportStore) Apply(_ context.Context, basePath, eventId string, now time.Time, plan triggers.ReportPlan) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.ApplyErr != nil && !f.ApplyCommitsDespiteErr {
		return f.ApplyErr
	}
	f.Applies = append(f.Applies, plan)
	for path, delta := range plan.Increments {
		f.Nodes[basePath+"/report_summary/"+path] += delta
	}
	for _, item := range plan.Items {
		f.Items[basePath+"/report_summary/data/"+item.Key] = item.Item
	}
	f.Claims[basePath+"/"+eventId] = triggers.ClaimRecord{Applied: true, AppliedAt: now.UnixMilli()}
	return f.ApplyErr
}

// pendingClaims counts claims that were won but not applied.
func (f *fakeReportStore) pendingClaims() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	pending := 0
	for _, record := range f.Claims {
		if !record.Applied {
			pending++
		}
	}
	return pending
}

// testNow is 2026-09-09 10:30 UTC: ISO week 37 (derived by hand).
var testNow = time.Date(2026, 9, 9, 10, 30, 0, 0, time.UTC)

func newDeps(store *fakeReportStore, schedules []triggers.ScheduleAmounts) (triggers.ReportDeps, *fakeClock) {
	clock := &fakeClock{now: testNow}
	return triggers.ReportDeps{
		Store: store,
		LoadSchedules: func(context.Context, string) ([]triggers.ScheduleAmounts, error) {
			return schedules, nil
		},
		Now: clock.Now,
	}, clock
}
