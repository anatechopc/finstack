package triggers_test

import (
	"context"
	"sort"
	"testing"

	"com.loooans.app/test/fakes"
	"com.loooans.app/triggers"
)

// paymentCreatedDeps builds PaymentCreatedDeps wired to the given fakes. ProductName
// is left nil (the core defaults the message to "loan") to keep cases focused.
func paymentCreatedDeps(
	schedules *fakes.ScheduleLoanResolver,
	loans *fakes.LoanInfoReader,
	subs *fakes.SubmissionFirstPayment,
	users *fakes.CompanyUsersReader,
	notifier *fakes.Notifier,
) triggers.PaymentCreatedDeps {
	return triggers.PaymentCreatedDeps{
		LoanIdForSchedule:           schedules.LoanIdForSchedule,
		LoanInfo:                    loans.LoanInfo,
		FirstPaymentIdForSubmission: subs.FirstPaymentIdForSubmission,
		CompanyUserIds:              users.CompanyUserIds,
		Notify:                      notifier.Notify,
	}
}

func recipientIds(notifier *fakes.Notifier) []string {
	ids := make([]string, 0, len(notifier.Notifications))
	for _, n := range notifier.Notifications {
		ids = append(ids, n.RecipientId)
	}
	sort.Strings(ids)
	return ids
}

// --- De-dup -----------------------------------------------------------------

func TestHandlePaymentCreatedCore_EmptySubmission_Notifies(t *testing.T) {
	notifier := &fakes.Notifier{}
	schedules := &fakes.ScheduleLoanResolver{}
	loans := &fakes.LoanInfoReader{Loans: map[string]fakes.LoanInfo{
		"loan-1": {CompanyId: "company-1", ProductId: "product-1"},
	}}
	subs := &fakes.SubmissionFirstPayment{}
	users := &fakes.CompanyUsersReader{Users: map[string][]string{
		"company-1": {"admin-1", "officer-1"},
	}}

	fields := map[string]any{
		"id":      "payment-1",
		"loan_id": "loan-1",
	}

	if err := triggers.HandlePaymentCreatedCore(
		context.Background(), "payment-1", fields,
		paymentCreatedDeps(schedules, loans, subs, users, notifier),
	); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}

	if got, want := recipientIds(notifier), []string{"admin-1", "officer-1"}; !equal(got, want) {
		t.Fatalf("recipients: got %v, want %v", got, want)
	}
	if len(subs.Calls) != 0 {
		t.Errorf("empty submission_id should not query FirstPaymentIdForSubmission, got calls %v", subs.Calls)
	}
	// notification content
	n := notifier.Notifications[0]
	if n.Title != "Payment submitted" {
		t.Errorf("title: got %q", n.Title)
	}
	if n.Data["loan_id"] != "loan-1" || n.Data["company_id"] != "company-1" ||
		n.Data["payment_id"] != "payment-1" || n.Data["product_id"] != "product-1" {
		t.Errorf("notification data mismatch: %+v", n.Data)
	}
	if n.Data["notification_type"] != "payment" {
		t.Errorf("notification_type: got %q", n.Data["notification_type"])
	}
}

func TestHandlePaymentCreatedCore_FirstOfSubmission_Notifies(t *testing.T) {
	notifier := &fakes.Notifier{}
	schedules := &fakes.ScheduleLoanResolver{}
	loans := &fakes.LoanInfoReader{Loans: map[string]fakes.LoanInfo{
		"loan-1": {CompanyId: "company-1", ProductId: "product-1"},
	}}
	subs := &fakes.SubmissionFirstPayment{FirstIds: map[string]string{
		"submission-1": "payment-1", // the created payment is the first
	}}
	users := &fakes.CompanyUsersReader{Users: map[string][]string{
		"company-1": {"admin-1"},
	}}

	fields := map[string]any{
		"id":            "payment-1",
		"loan_id":       "loan-1",
		"submission_id": "submission-1",
	}

	if err := triggers.HandlePaymentCreatedCore(
		context.Background(), "payment-1", fields,
		paymentCreatedDeps(schedules, loans, subs, users, notifier),
	); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}

	if got, want := recipientIds(notifier), []string{"admin-1"}; !equal(got, want) {
		t.Fatalf("recipients: got %v, want %v", got, want)
	}
}

func TestHandlePaymentCreatedCore_SecondOfSubmission_NoOp(t *testing.T) {
	notifier := &fakes.Notifier{}
	schedules := &fakes.ScheduleLoanResolver{}
	loans := &fakes.LoanInfoReader{Loans: map[string]fakes.LoanInfo{
		"loan-1": {CompanyId: "company-1", ProductId: "product-1"},
	}}
	subs := &fakes.SubmissionFirstPayment{FirstIds: map[string]string{
		"submission-1": "payment-1", // a sibling, not this one, is first
	}}
	users := &fakes.CompanyUsersReader{Users: map[string][]string{
		"company-1": {"admin-1"},
	}}

	fields := map[string]any{
		"id":            "payment-2",
		"loan_id":       "loan-1",
		"submission_id": "submission-1",
	}

	if err := triggers.HandlePaymentCreatedCore(
		context.Background(), "payment-2", fields,
		paymentCreatedDeps(schedules, loans, subs, users, notifier),
	); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}

	if len(notifier.Notifications) != 0 {
		t.Fatalf("sibling payment should not notify, got %d", len(notifier.Notifications))
	}
	// De-dup gate runs before any loan/company lookup work.
	if len(loans.Calls) != 0 {
		t.Errorf("loan info should not be looked up for a sibling, got %v", loans.Calls)
	}
	if len(users.Calls) != 0 {
		t.Errorf("company users should not be looked up for a sibling, got %v", users.Calls)
	}
}

// --- Loan resolution --------------------------------------------------------

func TestHandlePaymentCreatedCore_ResolvesLoanFromSchedule_Notifies(t *testing.T) {
	notifier := &fakes.Notifier{}
	schedules := &fakes.ScheduleLoanResolver{LoanIds: map[string]string{
		"schedule-9": "loan-9",
	}}
	loans := &fakes.LoanInfoReader{Loans: map[string]fakes.LoanInfo{
		"loan-9": {CompanyId: "company-9", ProductId: "product-9"},
	}}
	subs := &fakes.SubmissionFirstPayment{}
	users := &fakes.CompanyUsersReader{Users: map[string][]string{
		"company-9": {"admin-9", "officer-9"},
	}}

	// No loan_id on the doc — only loan_schedule_id (the real PaymentEntity shape).
	fields := map[string]any{
		"id":               "payment-9",
		"loan_schedule_id": "schedule-9",
	}

	if err := triggers.HandlePaymentCreatedCore(
		context.Background(), "payment-9", fields,
		paymentCreatedDeps(schedules, loans, subs, users, notifier),
	); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}

	if got, want := recipientIds(notifier), []string{"admin-9", "officer-9"}; !equal(got, want) {
		t.Fatalf("recipients: got %v, want %v", got, want)
	}
	// LoanInfo must be called with the resolved loan id.
	if len(loans.Calls) != 1 || loans.Calls[0] != "loan-9" {
		t.Errorf("LoanInfo calls: got %v, want [loan-9]", loans.Calls)
	}
	if n := notifier.Notifications[0]; n.Data["loan_id"] != "loan-9" || n.Data["company_id"] != "company-9" {
		t.Errorf("notification data mismatch: %+v", n.Data)
	}
}

func TestHandlePaymentCreatedCore_NoLoanNoSchedule_NoOp(t *testing.T) {
	notifier := &fakes.Notifier{}
	schedules := &fakes.ScheduleLoanResolver{}
	loans := &fakes.LoanInfoReader{}
	subs := &fakes.SubmissionFirstPayment{}
	users := &fakes.CompanyUsersReader{}

	fields := map[string]any{
		"id": "payment-x",
	}

	if err := triggers.HandlePaymentCreatedCore(
		context.Background(), "payment-x", fields,
		paymentCreatedDeps(schedules, loans, subs, users, notifier),
	); err != nil {
		t.Fatalf("expected graceful no-op, got err: %v", err)
	}
	if len(notifier.Notifications) != 0 {
		t.Fatalf("no loan/schedule should not notify, got %d", len(notifier.Notifications))
	}
	if len(loans.Calls) != 0 {
		t.Errorf("LoanInfo should not be called, got %v", loans.Calls)
	}
}

func TestHandlePaymentCreatedCore_ScheduleUnresolved_NoOp(t *testing.T) {
	notifier := &fakes.Notifier{}
	// Schedule resolver returns "" for an unknown schedule.
	schedules := &fakes.ScheduleLoanResolver{LoanIds: map[string]string{}}
	loans := &fakes.LoanInfoReader{}
	subs := &fakes.SubmissionFirstPayment{}
	users := &fakes.CompanyUsersReader{}

	fields := map[string]any{
		"id":               "payment-y",
		"loan_schedule_id": "schedule-missing",
	}

	if err := triggers.HandlePaymentCreatedCore(
		context.Background(), "payment-y", fields,
		paymentCreatedDeps(schedules, loans, subs, users, notifier),
	); err != nil {
		t.Fatalf("expected graceful no-op, got err: %v", err)
	}
	if len(notifier.Notifications) != 0 {
		t.Fatalf("unresolved schedule should not notify, got %d", len(notifier.Notifications))
	}
	if len(loans.Calls) != 0 {
		t.Errorf("LoanInfo should not be called for unresolved schedule, got %v", loans.Calls)
	}
}

func TestHandlePaymentCreatedCore_NilFields_NoOp(t *testing.T) {
	notifier := &fakes.Notifier{}
	deps := paymentCreatedDeps(
		&fakes.ScheduleLoanResolver{}, &fakes.LoanInfoReader{},
		&fakes.SubmissionFirstPayment{}, &fakes.CompanyUsersReader{}, notifier,
	)
	if err := triggers.HandlePaymentCreatedCore(context.Background(), "p", nil, deps); err != nil {
		t.Fatalf("nil fields should be a no-op, got err: %v", err)
	}
	if len(notifier.Notifications) != 0 {
		t.Fatalf("nil fields should not notify, got %d", len(notifier.Notifications))
	}
}

func equal(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
