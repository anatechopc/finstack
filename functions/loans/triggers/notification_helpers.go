package triggers

import (
	"context"
	"fmt"
	"time"

	"cloud.google.com/go/firestore"
	"com.loooans.app/utils"
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

	now := time.Now().UTC()

	notificationDoc := map[string]interface{}{
		"recipient_id": recipientId,
		"title":        title,
		"message":      message,
		"read":         false,
		"priority":     priority,
		"data":         data,
		"created_at":   now,
		"updated_at":   now,
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

// getProductName reads a product document and returns its loan_type field.
func getProductName(
	ctx context.Context,
	firestoreClient *firestore.Client,
	collectionPrefix string,
	productId string,
) (string, error) {
	doc, err := firestoreClient.Collection(collectionPrefix+"products").Doc(productId).Get(ctx)
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
