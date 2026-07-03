package triggers

import (
	"context"
	"fmt"
	"time"

	"cloud.google.com/go/firestore"
	"com.loooans.app/utils"
	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"go.uber.org/zap"
	"google.golang.org/api/iterator"
)

// createNotification writes a notification document to the notifications
// collection. The existing notificationCreated trigger picks it up and
// delivers the FCM push.
func createNotification(
	ctx context.Context,
	firestoreClient *firestore.Client,
	collectionPrefix string,
	recipientId string,
	title string,
	message string,
	priority string,
	data map[string]string,
) error {
	log, logErr := utils.InitializeLogger("notification_helpers")
	if logErr != nil {
		return logErr
	}

	// Store timestamps as int64 millis since epoch to match the codebase
	// convention. Writing a raw Go time.Time would be auto-serialised by
	// the Firebase Admin SDK as a Firestore Timestamp protocol object,
	// which breaks Flutter's json_serializable `as num?` deserialisation.
	// See root MEMORY.md > Date/Timestamp Convention.
	nowMillis := time.Now().UTC().UnixMilli()

	notificationDoc := map[string]interface{}{
		"recipient_id": recipientId,
		"title":        title,
		"message":      message,
		"read":         false,
		"priority":     priority,
		"data":         data,
		"created_at":   nowMillis,
		"updated_at":   nowMillis,
		"deleted_at":   nil,
	}

	collectionRef := firestoreClient.Collection(collectionPrefix + "notifications")
	docRef, _, err := collectionRef.Add(ctx, notificationDoc)
	if err != nil {
		return fmt.Errorf("failed to create notification for %s: %w", recipientId, err)
	}

	// Update the document with its own ID (matching Flutter's BaseRepository pattern)
	_, updateErr := docRef.Update(ctx, []firestore.Update{
		{Path: "id", Value: docRef.ID},
	})
	if updateErr != nil {
		return fmt.Errorf("failed to update notification id for %s: %w", recipientId, updateErr)
	}

	log.Debug(fmt.Sprintf("Created notification %s for recipient %s: %s", docRef.ID, recipientId, title))
	return nil
}

// getCompanyUserIdsByRole queries the users collection for users belonging
// to the given company with one of the specified roles. Returns their user IDs.
func getCompanyUserIdsByRole(
	ctx context.Context,
	firestoreClient *firestore.Client,
	collectionPrefix string,
	companyId string,
	roles []string,
) ([]string, error) {
	query := firestoreClient.Collection(collectionPrefix+"users").
		Where("company_id", "==", companyId).
		Where("user_role", "in", roles)

	iter := query.Documents(ctx)
	defer iter.Stop()

	var userIds []string
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("failed to iterate company users: %w", err)
		}

		if id, ok := doc.Data()["id"].(string); ok && id != "" {
			userIds = append(userIds, id)
		}
	}

	return userIds, nil
}

// pushOptions is the per-message FCM payload shared by the notificationCreated
// and chat messageWritten triggers.
type pushOptions struct {
	title    string
	body     string
	data     map[string]string
	priority string // "high" or "normal"; defaults to "high" when empty
	imageURL string
}

// deviceTokensForUsers collects the FCM tokens registered under each user's
// devices subcollection. A per-user read failure is logged and skipped (rather
// than aborting the whole fan-out or vanishing without a trace).
func deviceTokensForUsers(
	ctx context.Context, fs *firestore.Client, prefix string, log *zap.Logger, userIds []string,
) []string {
	var tokens []string
	for _, uid := range userIds {
		docs, err := fs.Collection(prefix + "users/" + uid + "/devices").Documents(ctx).GetAll()
		if err != nil {
			if log != nil {
				log.Sugar().Warnf("push: skipping recipient %q — devices read failed: %v", uid, err)
			}
			continue
		}
		for _, d := range docs {
			if t, ok := d.Data()["token"].(string); ok && t != "" {
				tokens = append(tokens, t)
			}
		}
	}
	return tokens
}

// sendPushToUsers gathers device tokens for the given users and sends one FCM
// multicast with a consistent cross-platform payload (Notification + Data +
// Android priority + APNS alert with default sound). Delivery is best-effort at
// the token layer (per-user read failures are logged and skipped); it returns
// nil when no tokens are found and only returns an error for FCM client-init or
// send failure. Callers decide whether to propagate that error (retry) or treat
// the push as best-effort.
func sendPushToUsers(
	ctx context.Context, app *firebase.App, fs *firestore.Client, prefix string,
	log *zap.Logger, userIds []string, opts pushOptions,
) error {
	tokens := deviceTokensForUsers(ctx, fs, prefix, log, userIds)
	if len(tokens) == 0 {
		return nil
	}
	fcm, err := app.Messaging(ctx)
	if err != nil {
		return fmt.Errorf("cannot initialize FCM client: %w", err)
	}
	priority := opts.priority
	if priority == "" {
		priority = "high"
	}
	_, err = fcm.SendEachForMulticast(ctx, &messaging.MulticastMessage{
		Tokens:       tokens,
		Data:         opts.data,
		Notification: &messaging.Notification{Title: opts.title, Body: opts.body, ImageURL: opts.imageURL},
		Android:      &messaging.AndroidConfig{Priority: priority},
		APNS: &messaging.APNSConfig{
			Payload: &messaging.APNSPayload{
				Aps: &messaging.Aps{
					Alert: &messaging.ApsAlert{Title: opts.title, Body: opts.body},
					Sound: "default",
				},
			},
		},
	})
	return err
}

// getProductName reads a product document and returns its loan_type field.
func getProductName(
	ctx context.Context,
	firestoreClient *firestore.Client,
	collectionPrefix string,
	productId string,
) (string, error) {
	doc, err := firestoreClient.Collection(collectionPrefix + "products").Doc(productId).Get(ctx)
	if err != nil {
		return "", fmt.Errorf("failed to get product %s: %w", productId, err)
	}

	if loanType, ok := doc.Data()["loan_type"].(string); ok {
		return loanType, nil
	}

	return "", fmt.Errorf("product %s has no loan_type field", productId)
}

// makeNotificationData builds the data map for a notification document.
func makeNotificationData(notificationType string, opts ...notificationDataOption) map[string]string {
	data := map[string]string{
		"notification_type": notificationType,
		"product_id":        "",
		"loan_id":           "",
		"payment_id":        "",
		"capital_id":        "",
		"company_id":        "",
		"review_id":         "",
		"user_id":           "",
		"karma_id":          "",
	}

	for _, opt := range opts {
		opt(data)
	}

	return data
}

type notificationDataOption func(map[string]string)

func withProductId(id string) notificationDataOption {
	return func(data map[string]string) { data["product_id"] = id }
}

func withLoanId(id string) notificationDataOption {
	return func(data map[string]string) { data["loan_id"] = id }
}

func withPaymentId(id string) notificationDataOption {
	return func(data map[string]string) { data["payment_id"] = id }
}

func withCompanyId(id string) notificationDataOption {
	return func(data map[string]string) { data["company_id"] = id }
}

func withReviewId(id string) notificationDataOption {
	return func(data map[string]string) { data["review_id"] = id }
}

func withUserId(id string) notificationDataOption {
	return func(data map[string]string) { data["user_id"] = id }
}
