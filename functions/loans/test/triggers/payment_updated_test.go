package triggers_test

import (
	"context"
	"strings"
	"testing"

	"com.loooans.app/test/fakes"
	"com.loooans.app/triggers"
)

// paymentDepsWith builds PaymentUpdatedDeps wired to the given notifier fake.
func paymentDepsWith(notifier *fakes.Notifier) triggers.PaymentUpdatedDeps {
	return triggers.PaymentUpdatedDeps{
		Notify: notifier.Notify,
	}
}

func TestHandlePaymentUpdatedCore_PendingToConfirmed_NotifiesBorrower(t *testing.T) {
	notifier := &fakes.Notifier{}

	before := map[string]any{
		"id":      "payment-1",
		"status":  "pending",
		"user_id": "borrower-1",
		"loan_id": "loan-1",
	}
	after := map[string]any{
		"id":      "payment-1",
		"status":  "confirmed",
		"user_id": "borrower-1",
		"loan_id": "loan-1",
	}

	if err := triggers.HandlePaymentUpdatedCore(
		context.Background(), "payment-1", before, after, paymentDepsWith(notifier),
	); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}

	if len(notifier.Notifications) != 1 {
		t.Fatalf("expected 1 notification, got %d", len(notifier.Notifications))
	}
	n := notifier.Notifications[0]
	if n.RecipientId != "borrower-1" {
		t.Errorf("recipient: got %s, want borrower-1", n.RecipientId)
	}
	if !strings.Contains(strings.ToLower(n.Message), "confirmed") {
		t.Errorf("message should mention confirmed, got %q", n.Message)
	}
	if n.Data["payment_id"] != "payment-1" {
		t.Errorf("payment_id: got %q, want payment-1", n.Data["payment_id"])
	}
	if n.Data["user_id"] != "borrower-1" {
		t.Errorf("user_id: got %q, want borrower-1", n.Data["user_id"])
	}
	if n.Data["loan_id"] != "loan-1" {
		t.Errorf("loan_id: got %q, want loan-1", n.Data["loan_id"])
	}
	if n.Data["notification_type"] != "payment" {
		t.Errorf("notification_type: got %q, want payment", n.Data["notification_type"])
	}
}

func TestHandlePaymentUpdatedCore_PendingToRejected_NotifiesWithReason(t *testing.T) {
	notifier := &fakes.Notifier{}

	before := map[string]any{
		"id":      "payment-2",
		"status":  "pending",
		"user_id": "borrower-2",
	}
	after := map[string]any{
		"id":               "payment-2",
		"status":           "rejected",
		"user_id":          "borrower-2",
		"rejection_reason": "blurry photo",
	}

	if err := triggers.HandlePaymentUpdatedCore(
		context.Background(), "payment-2", before, after, paymentDepsWith(notifier),
	); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}

	if len(notifier.Notifications) != 1 {
		t.Fatalf("expected 1 notification, got %d", len(notifier.Notifications))
	}
	n := notifier.Notifications[0]
	if n.RecipientId != "borrower-2" {
		t.Errorf("recipient: got %s, want borrower-2", n.RecipientId)
	}
	if !strings.Contains(strings.ToLower(n.Message), "rejected") {
		t.Errorf("message should mention rejected, got %q", n.Message)
	}
	if !strings.Contains(n.Message, "blurry photo") {
		t.Errorf("message should include the rejection reason, got %q", n.Message)
	}
}

func TestHandlePaymentUpdatedCore_ConfirmedToConfirmed_NoOp(t *testing.T) {
	notifier := &fakes.Notifier{}

	before := map[string]any{"id": "payment-3", "status": "confirmed", "user_id": "borrower-3"}
	after := map[string]any{"id": "payment-3", "status": "confirmed", "user_id": "borrower-3"}

	if err := triggers.HandlePaymentUpdatedCore(
		context.Background(), "payment-3", before, after, paymentDepsWith(notifier),
	); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(notifier.Notifications) != 0 {
		t.Fatalf("confirmed->confirmed should not notify, got %d", len(notifier.Notifications))
	}
}

func TestHandlePaymentUpdatedCore_PendingToPending_NoOp(t *testing.T) {
	notifier := &fakes.Notifier{}

	// status stays pending — e.g. an unrelated field edit.
	before := map[string]any{"id": "payment-4", "status": "pending", "user_id": "borrower-4"}
	after := map[string]any{"id": "payment-4", "status": "pending", "user_id": "borrower-4"}

	if err := triggers.HandlePaymentUpdatedCore(
		context.Background(), "payment-4", before, after, paymentDepsWith(notifier),
	); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(notifier.Notifications) != 0 {
		t.Fatalf("pending->pending should not notify, got %d", len(notifier.Notifications))
	}
}

func TestHandlePaymentUpdatedCore_NilSnapshots_NoOp(t *testing.T) {
	notifier := &fakes.Notifier{}

	if err := triggers.HandlePaymentUpdatedCore(
		context.Background(), "payment-5", nil, nil, paymentDepsWith(notifier),
	); err != nil {
		t.Fatalf("unexpected err on nil snapshots: %v", err)
	}
	if len(notifier.Notifications) != 0 {
		t.Fatalf("nil snapshots should not notify, got %d", len(notifier.Notifications))
	}
}

func TestHandlePaymentUpdatedCore_MissingUserId_NoOp(t *testing.T) {
	notifier := &fakes.Notifier{}

	before := map[string]any{"id": "payment-6", "status": "pending"}
	after := map[string]any{"id": "payment-6", "status": "confirmed"}

	if err := triggers.HandlePaymentUpdatedCore(
		context.Background(), "payment-6", before, after, paymentDepsWith(notifier),
	); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(notifier.Notifications) != 0 {
		t.Fatalf("missing user_id should not notify, got %d", len(notifier.Notifications))
	}
}
