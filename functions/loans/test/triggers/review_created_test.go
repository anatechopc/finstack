package triggers_test

import (
	"context"
	"errors"
	"testing"

	"com.loooans.app/test/fakes"
	"com.loooans.app/triggers"
)

// responderLister is a fake GetResponderIds dep: it returns a fixed id list (or
// an error) and records the company ids it was asked about.
type responderLister struct {
	ids   []string
	err   error
	calls []string
}

func (r *responderLister) list(_ context.Context, companyId string) ([]string, error) {
	r.calls = append(r.calls, companyId)
	if r.err != nil {
		return nil, r.err
	}
	return r.ids, nil
}

func createDeps(notifier *fakes.Notifier, lister *responderLister) triggers.ReviewCreatedDeps {
	return triggers.ReviewCreatedDeps{
		GetResponderIds: lister.list,
		Notify:          notifier.Notify,
	}
}

func TestHandleReviewCreatedCore_NotifiesAdminsAndModerators(t *testing.T) {
	notifier := &fakes.Notifier{}
	lister := &responderLister{ids: []string{"admin-1", "moderator-2"}}

	review := map[string]any{
		"id":          "review-1",
		"provider_id": "company-1",
		"product_id":  "product-1",
	}

	failures, err := triggers.HandleReviewCreatedCore(
		context.Background(), "review-1", review, createDeps(notifier, lister),
	)
	if err != nil {
		t.Fatalf("unexpected lookup err: %v", err)
	}
	if len(failures) != 0 {
		t.Fatalf("expected no notify failures, got %v", failures)
	}
	if len(notifier.Notifications) != 2 {
		t.Fatalf("expected 2 notifications, got %d", len(notifier.Notifications))
	}
	if lister.calls[0] != "company-1" {
		t.Errorf("responder lookup company: got %q, want company-1", lister.calls[0])
	}

	recipients := map[string]bool{}
	for _, n := range notifier.Notifications {
		recipients[n.RecipientId] = true
		if n.Data["notification_type"] != "review" {
			t.Errorf("notification_type: got %q, want review", n.Data["notification_type"])
		}
		if n.Data["review_id"] != "review-1" {
			t.Errorf("review_id: got %q, want review-1", n.Data["review_id"])
		}
		if n.Data["company_id"] != "company-1" {
			t.Errorf("company_id: got %q, want company-1", n.Data["company_id"])
		}
		if n.Data["product_id"] != "product-1" {
			t.Errorf("product_id: got %q, want product-1", n.Data["product_id"])
		}
	}
	if !recipients["admin-1"] || !recipients["moderator-2"] {
		t.Errorf("expected both admin-1 and moderator-2 notified, got %v", recipients)
	}
}

func TestHandleReviewCreatedCore_MissingProvider_NoOp(t *testing.T) {
	notifier := &fakes.Notifier{}
	lister := &responderLister{ids: []string{"admin-1"}}

	review := map[string]any{"id": "review-1", "product_id": "product-1"}

	failures, err := triggers.HandleReviewCreatedCore(
		context.Background(), "review-1", review, createDeps(notifier, lister),
	)
	if err != nil {
		t.Fatalf("missing provider should be a no-op, got err: %v", err)
	}
	if len(failures) != 0 {
		t.Fatalf("expected no notify failures, got %v", failures)
	}
	if len(notifier.Notifications) != 0 {
		t.Fatalf("missing provider_id should notify nobody, got %d", len(notifier.Notifications))
	}
	if len(lister.calls) != 0 {
		t.Errorf("responder lookup should be skipped when provider is empty, got %v", lister.calls)
	}
}

func TestHandleReviewCreatedCore_NoResponders_NoOp(t *testing.T) {
	notifier := &fakes.Notifier{}
	lister := &responderLister{ids: []string{}}

	review := map[string]any{"id": "review-1", "provider_id": "company-1"}

	failures, err := triggers.HandleReviewCreatedCore(
		context.Background(), "review-1", review, createDeps(notifier, lister),
	)
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(failures) != 0 {
		t.Fatalf("expected no notify failures, got %v", failures)
	}
	if len(notifier.Notifications) != 0 {
		t.Fatalf("no responders should notify nobody, got %d", len(notifier.Notifications))
	}
}

func TestHandleReviewCreatedCore_ResponderLookupError_Propagates(t *testing.T) {
	notifier := &fakes.Notifier{}
	lister := &responderLister{err: errors.New("firestore: unavailable")}

	review := map[string]any{"id": "review-1", "provider_id": "company-1"}

	failures, err := triggers.HandleReviewCreatedCore(
		context.Background(), "review-1", review, createDeps(notifier, lister),
	)
	if err == nil {
		t.Fatal("expected the responder-lookup error to propagate (retry)")
	}
	if len(failures) != 0 {
		t.Errorf("no notify failures expected when lookup fails, got %v", failures)
	}
	if len(notifier.Notifications) != 0 {
		t.Errorf("must not notify when responder lookup fails, got %d", len(notifier.Notifications))
	}
}

func TestHandleReviewCreatedCore_NotifyError_IsBestEffort(t *testing.T) {
	// Notify fails for every recipient; the core must still attempt all of them
	// and report each failure rather than aborting after the first.
	notifier := &fakes.Notifier{Err: errors.New("firestore: write failed")}
	lister := &responderLister{ids: []string{"admin-1", "moderator-2"}}

	review := map[string]any{"id": "review-1", "provider_id": "company-1"}

	failures, err := triggers.HandleReviewCreatedCore(
		context.Background(), "review-1", review, createDeps(notifier, lister),
	)
	if err != nil {
		t.Fatalf("notify failures should not surface as the lookup error: %v", err)
	}
	if len(failures) != 2 {
		t.Fatalf("expected 2 reported notify failures, got %d", len(failures))
	}
	// Both recipients were attempted despite the first failing.
	if len(notifier.Notifications) != 2 {
		t.Errorf("expected both recipients attempted, got %d", len(notifier.Notifications))
	}
}
