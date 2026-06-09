package triggers_test

import (
	"context"
	"errors"
	"strings"
	"testing"

	"com.loooans.app/test/fakes"
	"com.loooans.app/triggers"
)

// depsWith builds ReviewUpdatedDeps wired to the given fakes, authorizing every
// responder (the gate is exercised separately by depsWithAuth).
func depsWith(notifier *fakes.Notifier, companyNames *fakes.CompanyNameReader) triggers.ReviewUpdatedDeps {
	return depsWithAuth(notifier, companyNames, &fakes.ResponderAuthorizer{})
}

// depsWithAuth builds ReviewUpdatedDeps with an explicit responder authorizer.
func depsWithAuth(
	notifier *fakes.Notifier,
	companyNames *fakes.CompanyNameReader,
	authorizer *fakes.ResponderAuthorizer,
) triggers.ReviewUpdatedDeps {
	return triggers.ReviewUpdatedDeps{
		GetCompanyName:        companyNames.Read,
		Notify:                notifier.Notify,
		IsAuthorizedResponder: authorizer.IsAuthorized,
	}
}

func TestHandleReviewUpdatedCore_ResponseFirstSet_NotifiesBorrower(t *testing.T) {
	notifier := &fakes.Notifier{}
	companyNames := &fakes.CompanyNameReader{Names: map[string]string{"company-1": "IzzyLoans"}}

	before := map[string]any{
		"id":          "review-1",
		"response":    "",
		"user_id":     "borrower-1",
		"provider_id": "company-1",
		"product_id":  "product-1",
	}
	after := map[string]any{
		"id":          "review-1",
		"response":    "Thanks for the kind words!",
		"user_id":     "borrower-1",
		"provider_id": "company-1",
		"product_id":  "product-1",
	}

	if err := triggers.HandleReviewUpdatedCore(
		context.Background(), "review-1", before, after, depsWith(notifier, companyNames),
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
	if !strings.Contains(n.Message, "IzzyLoans") {
		t.Errorf("message should mention company name, got %q", n.Message)
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
	if n.Data["user_id"] != "borrower-1" {
		t.Errorf("user_id: got %q, want borrower-1", n.Data["user_id"])
	}
	if n.Data["notification_type"] != "review" {
		t.Errorf("notification_type: got %q, want review", n.Data["notification_type"])
	}
}

func TestHandleReviewUpdatedCore_ResponseEdited_NoOp(t *testing.T) {
	notifier := &fakes.Notifier{}
	companyNames := &fakes.CompanyNameReader{}

	before := map[string]any{"id": "review-1", "response": "Thanks!", "user_id": "borrower-1"}
	after := map[string]any{"id": "review-1", "response": "Thanks a lot!", "user_id": "borrower-1"}

	if err := triggers.HandleReviewUpdatedCore(
		context.Background(), "review-1", before, after, depsWith(notifier, companyNames),
	); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(notifier.Notifications) != 0 {
		t.Fatalf("editing an existing response should not notify, got %d", len(notifier.Notifications))
	}
}

func TestHandleReviewUpdatedCore_ResponseCleared_NoOp(t *testing.T) {
	notifier := &fakes.Notifier{}
	companyNames := &fakes.CompanyNameReader{}

	before := map[string]any{"id": "review-1", "response": "Thanks!", "user_id": "borrower-1"}
	after := map[string]any{"id": "review-1", "response": "", "user_id": "borrower-1"}

	if err := triggers.HandleReviewUpdatedCore(
		context.Background(), "review-1", before, after, depsWith(notifier, companyNames),
	); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(notifier.Notifications) != 0 {
		t.Fatalf("clearing a response should not notify, got %d", len(notifier.Notifications))
	}
}

func TestHandleReviewUpdatedCore_UnrelatedChange_NoOp(t *testing.T) {
	notifier := &fakes.Notifier{}
	companyNames := &fakes.CompanyNameReader{}

	// response stays empty on both sides — e.g. a rating/message edit.
	before := map[string]any{"id": "review-1", "response": "", "user_id": "borrower-1"}
	after := map[string]any{"id": "review-1", "response": "", "user_id": "borrower-1"}

	if err := triggers.HandleReviewUpdatedCore(
		context.Background(), "review-1", before, after, depsWith(notifier, companyNames),
	); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(notifier.Notifications) != 0 {
		t.Fatalf("unrelated change should not notify, got %d", len(notifier.Notifications))
	}
}

func TestHandleReviewUpdatedCore_NilSnapshots_NoOp(t *testing.T) {
	notifier := &fakes.Notifier{}
	companyNames := &fakes.CompanyNameReader{}

	if err := triggers.HandleReviewUpdatedCore(
		context.Background(), "review-1", nil, nil, depsWith(notifier, companyNames),
	); err != nil {
		t.Fatalf("unexpected err on nil snapshots: %v", err)
	}
	if len(notifier.Notifications) != 0 {
		t.Fatalf("nil snapshots should not notify, got %d", len(notifier.Notifications))
	}
}

func TestHandleReviewUpdatedCore_MissingUserId_NoOp(t *testing.T) {
	notifier := &fakes.Notifier{}
	companyNames := &fakes.CompanyNameReader{Names: map[string]string{"company-1": "IzzyLoans"}}

	before := map[string]any{"id": "review-1", "response": ""}
	after := map[string]any{"id": "review-1", "response": "Thanks!", "provider_id": "company-1"}

	if err := triggers.HandleReviewUpdatedCore(
		context.Background(), "review-1", before, after, depsWith(notifier, companyNames),
	); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(notifier.Notifications) != 0 {
		t.Fatalf("missing user_id should not notify, got %d", len(notifier.Notifications))
	}
}

func TestHandleReviewUpdatedCore_CompanyNameError_FallsBackAndStillNotifies(t *testing.T) {
	notifier := &fakes.Notifier{}
	companyNames := &fakes.CompanyNameReader{Err: errors.New("firestore: unavailable")}

	before := map[string]any{"id": "review-1", "response": "", "user_id": "borrower-1", "provider_id": "company-1"}
	after := map[string]any{"id": "review-1", "response": "Thanks!", "user_id": "borrower-1", "provider_id": "company-1"}

	if err := triggers.HandleReviewUpdatedCore(
		context.Background(), "review-1", before, after, depsWith(notifier, companyNames),
	); err != nil {
		t.Fatalf("company-name read failure should not abort the notification: %v", err)
	}
	if len(notifier.Notifications) != 1 {
		t.Fatalf("expected 1 notification despite name read failure, got %d", len(notifier.Notifications))
	}
	// Message still goes out, just without a real company name.
	if notifier.Notifications[0].Message == "" {
		t.Errorf("expected a non-empty fallback message")
	}
}

func TestHandleReviewUpdatedCore_NotifyError_Propagates(t *testing.T) {
	notifier := &fakes.Notifier{Err: errors.New("firestore: write failed")}
	companyNames := &fakes.CompanyNameReader{Names: map[string]string{"company-1": "IzzyLoans"}}

	before := map[string]any{"id": "review-1", "response": "", "user_id": "borrower-1", "provider_id": "company-1"}
	after := map[string]any{"id": "review-1", "response": "Thanks!", "user_id": "borrower-1", "provider_id": "company-1"}

	err := triggers.HandleReviewUpdatedCore(
		context.Background(), "review-1", before, after, depsWith(notifier, companyNames),
	)
	if err == nil {
		t.Fatal("expected the Notify error to propagate")
	}
}

func TestHandleReviewUpdatedCore_UnauthorizedResponder_NoOp(t *testing.T) {
	notifier := &fakes.Notifier{}
	companyNames := &fakes.CompanyNameReader{Names: map[string]string{"company-1": "IzzyLoans"}}
	// Only admin-1 is authorized; the response was written by stranger-9.
	authorizer := &fakes.ResponderAuthorizer{Authorized: map[string]bool{"admin-1": true}}

	before := map[string]any{"id": "review-1", "response": "", "user_id": "borrower-1", "provider_id": "company-1"}
	after := map[string]any{
		"id":              "review-1",
		"response":        "Totally legit response",
		"user_id":         "borrower-1",
		"provider_id":     "company-1",
		"responded_by_id": "stranger-9",
	}

	if err := triggers.HandleReviewUpdatedCore(
		context.Background(), "review-1", before, after, depsWithAuth(notifier, companyNames, authorizer),
	); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(notifier.Notifications) != 0 {
		t.Fatalf("an unauthorized responder must not notify the borrower, got %d", len(notifier.Notifications))
	}
	if len(authorizer.Calls) != 1 || authorizer.Calls[0].ResponderId != "stranger-9" ||
		authorizer.Calls[0].CompanyId != "company-1" {
		t.Errorf("expected one authorize call for stranger-9/company-1, got %+v", authorizer.Calls)
	}
}

func TestHandleReviewUpdatedCore_AuthorizedResponder_Notifies(t *testing.T) {
	notifier := &fakes.Notifier{}
	companyNames := &fakes.CompanyNameReader{Names: map[string]string{"company-1": "IzzyLoans"}}
	authorizer := &fakes.ResponderAuthorizer{Authorized: map[string]bool{"admin-1": true}}

	before := map[string]any{"id": "review-1", "response": "", "user_id": "borrower-1", "provider_id": "company-1"}
	after := map[string]any{
		"id":              "review-1",
		"response":        "Thank you!",
		"user_id":         "borrower-1",
		"provider_id":     "company-1",
		"responded_by_id": "admin-1",
	}

	if err := triggers.HandleReviewUpdatedCore(
		context.Background(), "review-1", before, after, depsWithAuth(notifier, companyNames, authorizer),
	); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(notifier.Notifications) != 1 {
		t.Fatalf("an authorized responder should notify the borrower, got %d", len(notifier.Notifications))
	}
}

func TestHandleReviewUpdatedCore_ResponderVerifyError_Propagates(t *testing.T) {
	notifier := &fakes.Notifier{}
	companyNames := &fakes.CompanyNameReader{Names: map[string]string{"company-1": "IzzyLoans"}}
	authorizer := &fakes.ResponderAuthorizer{Err: errors.New("firestore: unavailable")}

	before := map[string]any{"id": "review-1", "response": "", "user_id": "borrower-1", "provider_id": "company-1"}
	after := map[string]any{
		"id":              "review-1",
		"response":        "Thank you!",
		"user_id":         "borrower-1",
		"provider_id":     "company-1",
		"responded_by_id": "admin-1",
	}

	err := triggers.HandleReviewUpdatedCore(
		context.Background(), "review-1", before, after, depsWithAuth(notifier, companyNames, authorizer),
	)
	if err == nil {
		t.Fatal("expected the responder-verification error to propagate (retry), not a silent notify")
	}
	if len(notifier.Notifications) != 0 {
		t.Fatalf("must not notify when authorization can't be verified, got %d", len(notifier.Notifications))
	}
}
