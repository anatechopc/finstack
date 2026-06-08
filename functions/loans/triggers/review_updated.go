package triggers

import (
	"context"
	"errors"
	"fmt"

	"com.loooans.app/utils"
	"github.com/cloudevents/sdk-go/v2/event"
	"github.com/golang/protobuf/proto"
	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
)

// fallbackCompanyName is used in the borrower notification message when the
// company name cannot be read (the name is cosmetic — we still notify).
const fallbackCompanyName = "The loan provider"

// ReviewUpdatedDeps holds the collaborator functions used by the core so the
// business logic can be unit-tested without Firestore.
type ReviewUpdatedDeps struct {
	// GetCompanyName resolves a company's display name. Best-effort: a non-nil
	// error makes the core fall back to a generic name rather than aborting
	// the notification.
	GetCompanyName func(ctx context.Context, companyId string) (string, error)
	// Notify writes a notification document for the recipient. The existing
	// notificationCreated trigger handles FCM delivery.
	Notify func(ctx context.Context, recipientId, title, message string, data map[string]string) error
	// IsAuthorizedResponder reports whether responderId is an admin or review
	// moderator of companyId — i.e. someone actually permitted to respond.
	// Gates the notification so a response written by an unauthorized user
	// (e.g. one that slipped past the Firestore security rules) never notifies
	// the borrower. Defence in depth; a non-nil error aborts (retry) rather
	// than notifying on an unverified responder.
	IsAuthorizedResponder func(ctx context.Context, responderId, companyId string) (bool, error)
}

// HandleReviewUpdatedCore notifies the borrower when a company first posts a
// response to their review.
//
// It fires on every empty/nil -> non-empty transition of the `response` field.
// Edits (non-empty -> non-empty) and clears (non-empty -> empty) are no-ops, so
// editing a response does not re-notify. Note: deleting a response and then
// posting a new one IS a fresh empty -> non-empty transition and notifies again
// — by design, since the borrower has a genuinely new response to read. The
// transition is derived purely from the before/after snapshots (no per-review
// "already notified" history is persisted). Unrelated field changes are ignored.
func HandleReviewUpdatedCore(
	ctx context.Context,
	reviewId string,
	before, after map[string]any,
	deps ReviewUpdatedDeps,
) error {
	if before == nil || after == nil {
		return nil
	}

	beforeResponse, _ := before["response"].(string)
	afterResponse, _ := after["response"].(string)

	// First set only: response went from absent/empty to present.
	if !(beforeResponse == "" && afterResponse != "") {
		return nil
	}

	userId, _ := after["user_id"].(string)
	if userId == "" {
		// No borrower to notify — nothing actionable.
		return nil
	}

	providerId, _ := after["provider_id"].(string)
	productId, _ := after["product_id"].(string)

	// Authorization gate: only notify when the response was written by an
	// admin / review moderator of the review's company. This prevents a
	// spoofed or unauthorized response (e.g. one that bypassed the Firestore
	// security rules) from sending the borrower a trusted-looking notification.
	if deps.IsAuthorizedResponder != nil {
		respondedById, _ := after["responded_by_id"].(string)
		authorized, err := deps.IsAuthorizedResponder(ctx, respondedById, providerId)
		if err != nil {
			return fmt.Errorf("verify responder %q: %w", respondedById, err)
		}
		if !authorized {
			return nil
		}
	}

	// Company name is cosmetic: degrade gracefully rather than dropping the
	// notification if the read fails or the field is empty.
	companyName := fallbackCompanyName
	if deps.GetCompanyName != nil && providerId != "" {
		if name, err := deps.GetCompanyName(ctx, providerId); err == nil && name != "" {
			companyName = name
		}
	}

	title := "Your review got a response"
	message := fmt.Sprintf(
		"%s responded to your review. Tap to see what they said about your experience.",
		companyName,
	)

	data := makeNotificationData("review",
		withReviewId(reviewId),
		withProductId(productId),
		withCompanyId(providerId),
		withUserId(userId),
	)

	return deps.Notify(ctx, userId, title, message, data)
}

// ReviewUpdated is the CloudEvent adapter. It wires real Firestore into the
// core. Triggered by document.v1.updated on reviews/{id}.
func ReviewUpdated(ctx context.Context, ev event.Event) error {
	log, logErr := utils.InitializeLogger("review_updated")
	if logErr != nil {
		return logErr
	}

	var data firestoredata.DocumentEventData
	if err := proto.Unmarshal(ev.Data(), &data); err != nil {
		return fmt.Errorf("proto.Unmarshal: %w", err)
	}

	reviewId, before, after, err := extractReviewChange(&data)
	if err != nil {
		log.Sugar().Warnf("review_updated: skipping event: %v", err)
		return nil
	}

	app, fbErr := utils.InitializeFirebase(ctx)
	if fbErr != nil {
		return fbErr
	}
	fs, fsErr := app.Firestore(ctx)
	if fsErr != nil {
		return fmt.Errorf("failed to instantiate firestore client: %w", fsErr)
	}
	defer fs.Close()

	collectionPrefix := utils.GetCollectionPrefix()

	deps := ReviewUpdatedDeps{
		GetCompanyName: func(ctx context.Context, companyId string) (string, error) {
			doc, dErr := fs.Collection(collectionPrefix + "companies").Doc(companyId).Get(ctx)
			if dErr != nil {
				return "", fmt.Errorf("failed to get company %s: %w", companyId, dErr)
			}
			name, _ := doc.Data()["name"].(string)
			return name, nil
		},
		Notify: func(ctx context.Context, recipientId, title, message string, data map[string]string) error {
			return createNotification(ctx, fs, collectionPrefix, recipientId, title, message, "normal", data)
		},
		IsAuthorizedResponder: func(ctx context.Context, responderId, companyId string) (bool, error) {
			if responderId == "" || companyId == "" {
				return false, nil
			}
			// Authorized responders are exactly the users reviewCreated fans
			// out to: admins and review moderators of the company.
			ids, idErr := getCompanyUserIdsByRole(
				ctx, fs, collectionPrefix, companyId, []string{"admin", "reviewModerator"},
			)
			if idErr != nil {
				return false, idErr
			}
			for _, id := range ids {
				if id == responderId {
					return true, nil
				}
			}
			return false, nil
		},
	}

	return HandleReviewUpdatedCore(ctx, reviewId, before, after, deps)
}

// extractReviewChange pulls the review id + before/after maps (limited to the
// fields this trigger cares about) from the proto event.
func extractReviewChange(data *firestoredata.DocumentEventData) (string, map[string]any, map[string]any, error) {
	if data.GetValue() == nil || data.GetOldValue() == nil {
		return "", nil, nil, errors.New("missing value or old value")
	}

	var reviewId string
	if idVal, ok := data.GetValue().GetFields()["id"]; ok {
		reviewId = idVal.GetStringValue()
	}
	if reviewId == "" {
		return "", nil, nil, errors.New("missing review id")
	}

	before := flattenReviewFields(data.GetOldValue().GetFields())
	after := flattenReviewFields(data.GetValue().GetFields())
	return reviewId, before, after, nil
}

// flattenReviewFields converts the firestoredata.Value map into a plain Go map
// covering only the fields this trigger reads.
func flattenReviewFields(fields map[string]*firestoredata.Value) map[string]any {
	out := map[string]any{}
	for k, v := range fields {
		switch k {
		case "response", "user_id", "provider_id", "product_id", "id",
			"responded_by_id":
			out[k] = v.GetStringValue()
		}
	}
	return out
}
