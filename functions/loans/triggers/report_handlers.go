package triggers

import (
	"context"
	"errors"
	"fmt"
	"time"
)

// ClaimResult is the store's answer to "may this delivery apply the event?".
type ClaimResult int

const (
	// ClaimWon: this delivery applies the event.
	ClaimWon ClaimResult = iota
	// ClaimApplied: the event was already applied; nothing to do.
	ClaimApplied
	// ClaimInProgress: another delivery holds a fresh lease; retry later.
	ClaimInProgress
)

// ClaimRecord is what the store keeps per event under report_events/{id}.
type ClaimRecord struct {
	ClaimedAt int64 `json:"claimed_at"`
	Applied   bool  `json:"applied"`
	AppliedAt int64 `json:"applied_at,omitempty"`
}

// claimLease bounds how long a claim without an apply blocks a retry. It must
// exceed the trigger's timeout so an in-flight delivery is never overtaken.
const claimLease = 10 * time.Minute

// DecideClaim is the one claim rule, shared by the RTDB transaction and the
// test fake: nothing recorded → win; applied → done; a stale lease → win
// again (the previous delivery died between claim and apply); otherwise
// someone is applying it right now.
func DecideClaim(current *ClaimRecord, now time.Time) (ClaimResult, ClaimRecord) {
	if current == nil {
		return ClaimWon, ClaimRecord{ClaimedAt: now.UnixMilli()}
	}
	if current.Applied {
		return ClaimApplied, *current
	}
	if now.Sub(time.UnixMilli(current.ClaimedAt)) > claimLease {
		return ClaimWon, ClaimRecord{ClaimedAt: now.UnixMilli()}
	}
	return ClaimInProgress, *current
}

// ErrReportInProgress is returned when another delivery of the same event
// holds a fresh lease; returning it makes the platform retry later.
var ErrReportInProgress = errors.New("report event is being applied by another delivery; retry later")

// ReportStore is the Realtime Database side of the report writers.
// NewRTDBReportStore is the production adapter; the tests use an in-memory one.
type ReportStore interface {
	// ClaimEvent records the delivery under report_events/{eventId} following
	// DecideClaim, inside a transaction.
	ClaimEvent(ctx context.Context, basePath, eventId string, now time.Time) (ClaimResult, error)
	// ProductType reads {basePath}/loans/{loanId}:product_type.
	ProductType(ctx context.Context, basePath, loanId string) (string, error)
	// Apply performs the plan AND marks the event applied in ONE atomic write,
	// so a write that committed while the client saw an error is still
	// recognised as applied by the retry.
	Apply(ctx context.Context, basePath, eventId string, now time.Time, plan ReportPlan) error
}

// ReportDeps injects every side effect of the report handlers.
type ReportDeps struct {
	Store ReportStore
	// LoadSchedules returns status and amounts of every loan_schedule of a
	// loan; the bad_debt and completed branches need them. May be nil for the
	// schedule and capital handlers.
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
	// ReportFailed: returned together with an error.
	ReportFailed
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
		return ReportFailed, fmt.Errorf("cannot get product type for loan %s: %w", ev.LoanId, err)
	}

	var schedules []ScheduleAmounts
	if ev.Status == "bad_debt" || ev.Status == "completed" {
		if deps.LoadSchedules == nil {
			return ReportFailed, fmt.Errorf("loan %s: status %q needs schedules but no loader is wired", ev.LoanId, ev.Status)
		}
		schedules, err = deps.LoadSchedules(ctx, ev.LoanId)
		if err != nil {
			return ReportFailed, fmt.Errorf("cannot get loan schedules for loan %s: %w", ev.LoanId, err)
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
		return ReportFailed, fmt.Errorf("cannot get product type for loan %s: %w", ev.LoanId, err)
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

// applyReport claims the event and applies the plan together with the
// event's applied marker in one atomic write. The claim is never released:
// if the write committed while the client saw an error, the marker went with
// it and the retry is a no-op; if it did not commit, the lease expires and
// the retry re-applies. Either way an event is never counted twice.
func applyReport(ctx context.Context, deps ReportDeps, basePath, eventId string, plan ReportPlan) (ReportOutcome, error) {
	now := deps.Now().UTC()
	result, err := deps.Store.ClaimEvent(ctx, basePath, eventId, now)
	if err != nil {
		return ReportFailed, fmt.Errorf("cannot claim event %s: %w", eventId, err)
	}
	switch result {
	case ClaimApplied:
		deps.info("event %s already applied to %s, skipping", eventId, basePath)
		return ReportAlreadyApplied, nil
	case ClaimInProgress:
		return ReportFailed, fmt.Errorf("event %s on %s: %w", eventId, basePath, ErrReportInProgress)
	}
	if err := deps.Store.Apply(ctx, basePath, eventId, now, plan); err != nil {
		return ReportFailed, fmt.Errorf("cannot apply report for event %s: %w", eventId, err)
	}
	return ReportApplied, nil
}
