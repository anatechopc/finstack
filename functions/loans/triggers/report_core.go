package triggers

import (
	"fmt"
	"strconv"
	"time"
)

// ReportPlan is everything one event does to a company's report_summary node:
// counter increments keyed by path relative to report_summary, and entries to
// append under report_summary/data. It carries no I/O so the arithmetic is
// table-testable, and the store applies it as ONE atomic multi-path update.
type ReportPlan struct {
	Increments map[string]float64
	Items      []ReportDataItem
}

// ReportDataItem is one entry of the append-only report_summary/data list.
type ReportDataItem struct {
	Key  string
	Item map[string]any
}

// IsEmpty reports whether applying the plan would change nothing.
func (p ReportPlan) IsEmpty() bool {
	return len(p.Increments) == 0 && len(p.Items) == 0
}

func (p *ReportPlan) add(path string, delta float64) {
	if p.Increments == nil {
		p.Increments = map[string]float64{}
	}
	p.Increments[path] += delta
}

// appendItem keeps keys unique within the plan. Two items from one event share
// the same timestamp key; before this the second Set silently overwrote the
// first (the refresh_capital entry vanished under the collection entry).
func (p *ReportPlan) appendItem(item ReportDataItem) {
	base := item.Key
	for n := 2; p.hasKey(item.Key); n++ {
		item.Key = fmt.Sprintf("%s:%d", base, n)
	}
	p.Items = append(p.Items, item)
}

func (p ReportPlan) hasKey(key string) bool {
	for _, it := range p.Items {
		if it.Key == key {
			return true
		}
	}
	return false
}

// addToSummary applies delta to field under every time bucket (year, month,
// week, day), the product node and the sales node.
func (p *ReportPlan) addToSummary(now time.Time, productType, field string, delta float64) {
	for _, tp := range timePaths(now) {
		p.add("total_summary/"+tp+"/"+field, delta)
	}
	p.add("products/"+productType+"/"+field, delta)
	p.add("sales/"+field, delta)
}

// timePaths returns the total_summary buckets for now, coarsest first. The
// week is the ISO week, so the last days of December can sit in week 53 of
// their own year and January 1 can be week 53 of the new year (historical
// behaviour, kept).
func timePaths(now time.Time) []string {
	year, month, day := now.Date()
	_, week := now.ISOWeek()
	yearPath := "year:" + strconv.Itoa(year)
	monthPath := yearPath + ":month:" + strconv.Itoa(int(month))
	weekPath := monthPath + ":week:" + strconv.Itoa(week)
	dayPath := weekPath + ":day:" + strconv.Itoa(day)
	return []string{yearPath, monthPath, weekPath, dayPath}
}

// dataItemKey is the historical key format of report_summary/data entries.
func dataItemKey(now time.Time) string {
	year, month, day := now.Date()
	_, week := now.ISOWeek()
	return fmt.Sprintf("%d:%d:week:%d:%dT%d:%d:%d:%d",
		year, int(month), week, day, now.Hour(), now.Minute(), now.Second(), now.Nanosecond())
}

func dataItem(now time.Time, amount, interest, principal float64, productType, dataType, capitalId, loanId string) ReportDataItem {
	return ReportDataItem{
		Key: dataItemKey(now),
		Item: map[string]any{
			"created_at":   now.UnixMilli(),
			"amount":       amount,
			"interest":     interest,
			"principal":    principal,
			"product_type": productType,
			"data_type":    dataType,
			"capital_id":   capitalId,
			"loan_id":      loanId,
		},
	}
}

// ScheduleAmounts is what the loan-level branches need from one loan_schedule.
// Status matters: the app persists planned rows too (the first schedule at
// approval carries status approved and principal_payment = amount for
// open-term loans), and only rows that are payments have collected anything.
type ScheduleAmounts struct {
	Status    string
	Principal float64 // principal_payment
	Extra     float64 // extra_payment
	Interest  float64 // interest_payment
}

// collectedPrincipal sums the principal (and, when withExtra, the extra
// payments) of the rows that are payments, in the same status set the
// schedule trigger books as collections.
func collectedPrincipal(schedules []ScheduleAmounts, withExtra bool) float64 {
	var total float64
	for _, s := range schedules {
		if !isCollectionStatus(s.Status) {
			continue
		}
		total += s.Principal
		if withExtra {
			total += s.Extra
		}
	}
	return total
}

// LoanReportInput is the parsed loan write.
type LoanReportInput struct {
	Status, OldStatus                                        string
	Amount, AdditionalCharges, Deductions, UpfrontCollection float64
	Schedules                                                []ScheduleAmounts
	ProductType, LoanId                                      string
	Now                                                      time.Time
}

// loanTransition reports whether this write is the transition the report
// counts. Writes that keep the status (edits to an approved loan) are no-ops:
// campaign D1. Leaving and re-entering a status counts again (a new release).
func loanTransition(status, oldStatus string) bool {
	switch status {
	case "approved", "bad_debt", "completed":
		return status != oldStatus
	}
	return false
}

// PlanLoanReport returns the plan for a loan write, or an empty plan with the
// reason it is skipped.
func PlanLoanReport(in LoanReportInput) (ReportPlan, string) {
	var p ReportPlan
	if !loanTransition(in.Status, in.OldStatus) {
		return p, fmt.Sprintf("status %q (was %q) is not a report transition", in.Status, in.OldStatus)
	}

	switch in.Status {
	case "approved":
		p.addToSummary(in.Now, in.ProductType, "total_amount_released", in.Amount)
		p.appendItem(dataItem(in.Now, in.Amount, 0, 0, in.ProductType, "release", "", in.LoanId))

	case "bad_debt":
		// Bad debt is the principal never collected: amount minus principal
		// paid, floored at zero (an overpaid loan is not a negative debt).
		badDebt := max(in.Amount-collectedPrincipal(in.Schedules, false), 0)
		for _, tp := range timePaths(in.Now) {
			p.add("total_summary/"+tp+"/total_bad_debts", badDebt)
		}
		p.add("products/"+in.ProductType+"/total_bad_debts", badDebt)
		p.add("capital_usage/total_bad_debts", badDebt)
		p.appendItem(dataItem(in.Now, badDebt, 0, 0, in.ProductType, "bad_debt", "", in.LoanId))

	case "completed":
		// Early settlement books the remaining principal (owner decision
		// 2026-09-09): released amount minus the principal the paid rows
		// already returned, floored at zero. Interest is not booked here;
		// every paid row booked its own interest when it was created
		// (loanScheduleChanges).
		loanAmount := in.Amount + in.AdditionalCharges - in.Deductions - in.UpfrontCollection
		remaining := max(loanAmount-collectedPrincipal(in.Schedules, true), 0)
		p.add("capital_usage/total_capital", remaining)
		p.appendItem(dataItem(in.Now, remaining, 0, 0, "", "refresh_capital", "", ""))
		p.addToSummary(in.Now, in.ProductType, "total_collections", remaining)
		p.addToSummary(in.Now, in.ProductType, "total_principal_payments", remaining)
		p.appendItem(dataItem(in.Now, remaining, 0, remaining, in.ProductType, "collection", "", in.LoanId))
	}

	return p, ""
}

// isCollectionStatus reports whether a schedule row in this status is a
// payment. A borrower submission counts before confirmation: kept as-is.
func isCollectionStatus(status string) bool {
	switch status {
	case "payment_submitted", "paid_on_time", "paid_late":
		return true
	}
	return false
}

// ScheduleReportInput is the parsed loan_schedule create.
type ScheduleReportInput struct {
	Status              string
	Interest, Principal float64
	ProductType, LoanId string
	Now                 time.Time
}

// PlanScheduleReport books a collection for a schedule created in a paid or
// submitted state, or returns an empty plan with the reason it is skipped.
func PlanScheduleReport(in ScheduleReportInput) (ReportPlan, string) {
	var p ReportPlan
	if !isCollectionStatus(in.Status) {
		return p, fmt.Sprintf("status %q is not a collection", in.Status)
	}
	p.add("capital_usage/total_capital", in.Principal)
	p.appendItem(dataItem(in.Now, in.Principal, 0, 0, "", "refresh_capital", "", ""))
	collected := in.Principal + in.Interest
	p.addToSummary(in.Now, in.ProductType, "total_collections", collected)
	p.addToSummary(in.Now, in.ProductType, "total_interest_payments", in.Interest)
	p.addToSummary(in.Now, in.ProductType, "total_principal_payments", in.Principal)
	p.appendItem(dataItem(in.Now, collected, in.Interest, in.Principal, in.ProductType, "collection", "", in.LoanId))
	return p, ""
}

// CapitalReportInput is the parsed capital create.
type CapitalReportInput struct {
	Amount    float64
	CapitalId string
	Now       time.Time
}

// PlanCapitalReport books added capital.
func PlanCapitalReport(in CapitalReportInput) ReportPlan {
	var p ReportPlan
	p.add("capital_usage/total_capital", in.Amount)
	p.appendItem(dataItem(in.Now, in.Amount, 0, 0, "", "add_capital", in.CapitalId, ""))
	return p
}
