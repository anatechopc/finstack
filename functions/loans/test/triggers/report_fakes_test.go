package triggers_test

import (
	"context"
	"errors"
	"sync"
	"time"

	"com.loooans.app/triggers"
)

// fakeReportStore is an in-memory ReportStore that records every call.
type fakeReportStore struct {
	mu             sync.Mutex
	Nodes          map[string]float64
	Items          map[string]map[string]any
	Claims         map[string]bool
	Applies        []triggers.ReportPlan
	ProductTypes   map[string]string
	ClaimErr       error
	ReleaseErr     error
	ApplyErr       error
	ProductTypeErr error
}

func newFakeReportStore() *fakeReportStore {
	return &fakeReportStore{
		Nodes:        map[string]float64{},
		Items:        map[string]map[string]any{},
		Claims:       map[string]bool{},
		ProductTypes: map[string]string{"L1": "business"},
	}
}

func (f *fakeReportStore) ClaimEvent(_ context.Context, basePath, eventId string) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.ClaimErr != nil {
		return false, f.ClaimErr
	}
	key := basePath + "/" + eventId
	if f.Claims[key] {
		return false, nil
	}
	f.Claims[key] = true
	return true, nil
}

func (f *fakeReportStore) ReleaseEvent(_ context.Context, basePath, eventId string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.ReleaseErr != nil {
		return f.ReleaseErr
	}
	delete(f.Claims, basePath+"/"+eventId)
	return nil
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

func (f *fakeReportStore) Apply(_ context.Context, basePath string, plan triggers.ReportPlan) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.ApplyErr != nil {
		return f.ApplyErr
	}
	f.Applies = append(f.Applies, plan)
	for path, delta := range plan.Increments {
		f.Nodes[basePath+"/report_summary/"+path] += delta
	}
	for _, item := range plan.Items {
		f.Items[basePath+"/report_summary/data/"+item.Key] = item.Item
	}
	return nil
}

// testNow is 2026-09-09 10:30 UTC: ISO week 37 (derived by hand).
var testNow = time.Date(2026, 9, 9, 10, 30, 0, 0, time.UTC)

func reportDeps(store *fakeReportStore, schedules []triggers.ScheduleAmounts) triggers.ReportDeps {
	return triggers.ReportDeps{
		Store: store,
		LoadSchedules: func(context.Context, string) ([]triggers.ScheduleAmounts, error) {
			return schedules, nil
		},
		Now: func() time.Time { return testNow },
	}
}
