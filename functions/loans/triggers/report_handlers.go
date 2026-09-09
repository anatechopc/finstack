package triggers

import (
	"context"
	"errors"
	"fmt"
	"time"
)

// ReportStore is the Realtime Database side of the report writers.
// NewRTDBReportStore is the production adapter; the tests use an in-memory one.
type ReportStore interface {
	// ClaimEvent records eventId under report_summary/applied_events and
	// reports false when it was already recorded (a redelivered event).
	ClaimEvent(ctx context.Context, basePath, eventId string) (bool, error)
	// ReleaseEvent forgets a claim so a retry can re-apply the event.
	ReleaseEvent(ctx context.Context, basePath, eventId string) error
	// ProductType reads {basePath}/loans/{loanId}:product_type.
	ProductType(ctx context.Context, basePath, loanId string) (string, error)
	// Apply performs the plan as one atomic write.
	Apply(ctx context.Context, basePath string, plan ReportPlan) error
}

// ReportDeps injects every side effect of the report handlers.
type ReportDeps struct {
	Store ReportStore
	// LoadSchedules returns the amounts of every loan_schedule of a loan; the
	// bad_debt and completed branches need them. May be nil for the schedule
	// and capital handlers.
	LoadSchedules func(ctx context.Context, loanId string) ([]ScheduleAmounts, error)
	Now           func() time.Time
	LogInfo       func(format string, args ...any)
}

func (d ReportDeps) info(format string, args ...any) {
	if d.LogInfo != nil {
		d.LogInfo(format, args...)
	}
}

// ReportOutcome says what a handler did with an event.
type ReportOutcome int

const (
	// ReportApplied: the plan was written.
	ReportApplied ReportOutcome = iota
	// ReportSkipped: nothing to report for this event (no transition, delete).
	ReportSkipped
	// ReportAlreadyApplied: a redelivery of an event that was already written.
	ReportAlreadyApplied
)

// LoanChangeEvent is the parsed, storage-agnostic view of a loan write.
type LoanChangeEvent struct {
	EventId                                                  string
	IsDelete                                                 bool
	CompanyId, LoanId                                        string
	Status, OldStatus                                        string
	Amount, AdditionalCharges, Deductions, UpfrontCollection float64
}

// ScheduleCreatedEvent is the parsed loan_schedule create.
type ScheduleCreatedEvent struct {
	EventId             string
	CompanyId, LoanId   string
	Status              string
	Interest, Principal float64
}

// CapitalCreatedEvent is the parsed capital create.
type CapitalCreatedEvent struct {
	EventId   string
	CompanyId string
	CapitalId string
	Amount    float64
}

func companyBasePath(pathEnv, companyId string) string {
	return pathEnv + "/companies/" + companyId
}

// HandleLoanChangeCore books a release, a bad debt or a settlement for a loan
// write, exactly once per status transition and once per event.
func HandleLoanChangeCore(ctx context.Context, pathEnv string, ev LoanChangeEvent, deps ReportDeps) (ReportOutcome, error) {
	if ev.IsDelete {
		// A hard delete on a `written` trigger: nothing to report, and an
		// error here would only be retried forever.
		return ReportSkipped, nil
	}
	if !loanTransition(ev.Status, ev.OldStatus) {
		deps.info("loan %s: status %q (was %q) is not a report transition, skipping", ev.LoanId, ev.Status, ev.OldStatus)
		return ReportSkipped, nil
	}
	base := companyBasePath(pathEnv, ev.CompanyId)

	productType, err := deps.Store.ProductType(ctx, base, ev.LoanId)
	if err != nil {
		return ReportSkipped, fmt.Errorf("cannot get product type for loan %s: %w", ev.LoanId, err)
	}

	var schedules []ScheduleAmounts
	if ev.Status == "bad_debt" || ev.Status == "completed" {
		if deps.LoadSchedules == nil {
			return ReportSkipped, fmt.Errorf("loan %s: status %q needs schedules but no loader is wired", ev.LoanId, ev.Status)
		}
		schedules, err = deps.LoadSchedules(ctx, ev.LoanId)
		if err != nil {
			return ReportSkipped, fmt.Errorf("cannot get loan schedules for loan %s: %w", ev.LoanId, err)
		}
	}

	plan, skip := PlanLoanReport(LoanReportInput{
		Status: ev.Status, OldStatus: ev.OldStatus,
		Amount: ev.Amount, AdditionalCharges: ev.AdditionalCharges,
		Deductions: ev.Deductions, UpfrontCollection: ev.UpfrontCollection,
		Schedules: schedules, ProductType: productType, LoanId: ev.LoanId,
		Now: deps.Now().UTC(),
	})
	if skip != "" {
		deps.info("loan %s: %s", ev.LoanId, skip)
		return ReportSkipped, nil
	}
	return applyReport(ctx, deps, base, ev.EventId, plan)
}

// HandleScheduleCreatedCore books a collection for a paid or submitted
// schedule row.
func HandleScheduleCreatedCore(ctx context.Context, pathEnv string, ev ScheduleCreatedEvent, deps ReportDeps) (ReportOutcome, error) {
	if !isCollectionStatus(ev.Status) {
		deps.info("schedule of loan %s: status %q is not a collection, skipping", ev.LoanId, ev.Status)
		return ReportSkipped, nil
	}
	base := companyBasePath(pathEnv, ev.CompanyId)
	productType, err := deps.Store.ProductType(ctx, base, ev.LoanId)
	if err != nil {
		return ReportSkipped, fmt.Errorf("cannot get product type for loan %s: %w", ev.LoanId, err)
	}
	plan, _ := PlanScheduleReport(ScheduleReportInput{
		Status: ev.Status, Interest: ev.Interest, Principal: ev.Principal,
		ProductType: productType, LoanId: ev.LoanId, Now: deps.Now().UTC(),
	})
	return applyReport(ctx, deps, base, ev.EventId, plan)
}

// HandleCapitalCreatedCore books added capital.
func HandleCapitalCreatedCore(ctx context.Context, pathEnv string, ev CapitalCreatedEvent, deps ReportDeps) (ReportOutcome, error) {
	base := companyBasePath(pathEnv, ev.CompanyId)
	plan := PlanCapitalReport(CapitalReportInput{Amount: ev.Amount, CapitalId: ev.CapitalId, Now: deps.Now().UTC()})
	return applyReport(ctx, deps, base, ev.EventId, plan)
}

// applyReport claims the event, applies the plan atomically and releases the
// claim if the apply failed so a retry can redo it. A redelivered event that
// was already claimed is a no-op (campaign D1 / the idempotency proof).
func applyReport(ctx context.Context, deps ReportDeps, basePath, eventId string, plan ReportPlan) (ReportOutcome, error) {
	claimed, err := deps.Store.ClaimEvent(ctx, basePath, eventId)
	if err != nil {
		return ReportSkipped, fmt.Errorf("cannot claim event %s: %w", eventId, err)
	}
	if !claimed {
		deps.info("event %s already applied to %s, skipping", eventId, basePath)
		return ReportAlreadyApplied, nil
	}
	if err := deps.Store.Apply(ctx, basePath, plan); err != nil {
		applyErr := fmt.Errorf("cannot apply report for event %s: %w", eventId, err)
		if relErr := deps.Store.ReleaseEvent(ctx, basePath, eventId); relErr != nil {
			return ReportSkipped, errors.Join(applyErr, fmt.Errorf("cannot release claim for event %s: %w", eventId, relErr))
		}
		return ReportSkipped, applyErr
	}
	return ReportApplied, nil
}
