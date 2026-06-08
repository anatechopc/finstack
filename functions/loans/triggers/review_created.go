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

// ReviewCreatedDeps holds the collaborator functions used by the core so the
// fan-out logic can be unit-tested without Firestore.
type ReviewCreatedDeps struct {
	// GetResponderIds returns the user ids that should be notified of a new
	// review for the company — its admins and review moderators.
	GetResponderIds func(ctx context.Context, companyId string) ([]string, error)
	// Notify writes a notification document for the recipient. The existing
	// notificationCreated trigger handles FCM delivery.
	Notify func(ctx context.Context, recipientId, title, message string, data map[string]string) error
}

const (
	reviewCreatedTitle   = "A review has been posted"
	reviewCreatedMessage = "A user has posted a review on their recent loan " +
		"experience. Click here to see what they say about their experience."
)

// HandleReviewCreatedCore notifies a company's admins and review moderators that
// a borrower posted a new review.
//
// It returns (notifyFailures, lookupErr):
//   - lookupErr is set when the responder lookup fails; nobody was notified, so
//     the caller should retry.
//   - notifyFailures lists per-recipient Notify errors. Delivery is best-effort:
//     a failure for one recipient does not abort the others and does not trigger
//     a retry (which would re-notify recipients that already succeeded). The
//     caller logs these for visibility.
//
// A review with no provider_id is a no-op (nothing to notify).
func HandleReviewCreatedCore(
	ctx context.Context,
	reviewId string,
	review map[string]any,
	deps ReviewCreatedDeps,
) (notifyFailures []error, lookupErr error) {
	providerId, _ := review["provider_id"].(string)
	if providerId == "" {
		return nil, nil
	}
	productId, _ := review["product_id"].(string)

	responderIds, err := deps.GetResponderIds(ctx, providerId)
	if err != nil {
		return nil, fmt.Errorf("get company responders for %s: %w", providerId, err)
	}

	data := makeNotificationData("review",
		withReviewId(reviewId),
		withProductId(productId),
		withCompanyId(providerId),
	)

	for _, id := range responderIds {
		if e := deps.Notify(ctx, id, reviewCreatedTitle, reviewCreatedMessage, data); e != nil {
			notifyFailures = append(notifyFailures, fmt.Errorf("notify %s: %w", id, e))
		}
	}
	return notifyFailures, nil
}

// ReviewCreated is the CloudEvent adapter. It wires real Firestore into the
// core. Triggered by document.v1.created on reviews/{id}.
func ReviewCreated(ctx context.Context, ev event.Event) error {
	log, logErr := utils.InitializeLogger("review_created")
	if logErr != nil {
		return logErr
	}

	var data firestoredata.DocumentEventData
	if err := proto.Unmarshal(ev.Data(), &data); err != nil {
		return fmt.Errorf("proto.Unmarshal: %w", err)
	}

	reviewId, review, err := extractReviewCreate(&data)
	if err != nil {
		log.Sugar().Warnf("review_created: skipping event: %v", err)
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

	deps := ReviewCreatedDeps{
		GetResponderIds: func(ctx context.Context, companyId string) ([]string, error) {
			return getCompanyUserIdsByRole(
				ctx, fs, collectionPrefix, companyId, []string{"admin", "reviewModerator"},
			)
		},
		Notify: func(ctx context.Context, recipientId, title, message string, data map[string]string) error {
			return createNotification(ctx, fs, collectionPrefix, recipientId, title, message, "normal", data)
		},
	}

	notifyFailures, lookupErr := HandleReviewCreatedCore(ctx, reviewId, review, deps)
	if lookupErr != nil {
		// Nobody was notified — let Cloud Functions retry.
		return lookupErr
	}
	for _, e := range notifyFailures {
		log.Sugar().Errorf("review_created: %v", e)
	}
	return nil
}

// extractReviewCreate pulls the review id + the fields the trigger cares about
// from the created-document proto event.
func extractReviewCreate(data *firestoredata.DocumentEventData) (string, map[string]any, error) {
	if data.GetValue() == nil {
		return "", nil, errors.New("missing value")
	}

	review := map[string]any{}
	for k, v := range data.GetValue().GetFields() {
		switch k {
		case "id", "provider_id", "product_id":
			review[k] = v.GetStringValue()
		}
	}

	reviewId, _ := review["id"].(string)
	if reviewId == "" {
		return "", nil, errors.New("missing review id")
	}
	return reviewId, review, nil
}
