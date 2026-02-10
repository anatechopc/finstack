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

// ReviewCreated
//
//	function to run firestore trigger for collection
//		collection: reviews/
//	When a new review document is created, this trigger
//	creates notification documents for company admins and
//	review moderators. The existing notificationCreated trigger
//	handles FCM push delivery.
//
// /**
func ReviewCreated(ctx context.Context, event event.Event) error {
	log, logErr := utils.InitializeLogger("review_created")

	if logErr != nil {
		return logErr
	}

	var data firestoredata.DocumentEventData

	if err := proto.Unmarshal(event.Data(), &data); err != nil {
		return fmt.Errorf("proto.Unmarshal: %w", err)
	}

	log.Debug(fmt.Sprintf("Function triggered by change to: %v\n", event.Source()))
	log.Debug(fmt.Sprintf("New value: %+v\n", data.GetValue()))

	if data.GetValue() == nil {
		log.Error("No value for newly created doc")
		return errors.New("no value for newly created doc")
	}

	var providerId string
	var productId string
	var reviewId string

	if value, ok := data.GetValue().GetFields()["provider_id"]; ok {
		providerId = value.GetStringValue()
	} else {
		return errors.New(fmt.Sprintf("No provider_id for review: %s", data.GetValue().GetName()))
	}

	if value, ok := data.GetValue().GetFields()["product_id"]; ok {
		productId = value.GetStringValue()
	}

	if value, ok := data.GetValue().GetFields()["id"]; ok {
		reviewId = value.GetStringValue()
	}

	app, errFirebaseAdmin := utils.InitializeFirebase(ctx)

	if errFirebaseAdmin != nil {
		return errFirebaseAdmin
	}

	collectionPrefix := utils.GetCollectionPrefix()
	firestoreClient, errFirestoreClient := app.Firestore(ctx)

	if errFirestoreClient != nil {
		return fmt.Errorf("failed to instantiate firestore client: %v", errFirestoreClient)
	}

	notifData := makeNotificationData("loan",
		withReviewId(reviewId),
		withProductId(productId),
		withCompanyId(providerId),
	)

	// Notify company admins and review moderators
	adminIds, err := getCompanyUserIdsByRole(ctx, firestoreClient, collectionPrefix, providerId, []string{"admin", "reviewModerator"})
	if err != nil {
		return fmt.Errorf("failed to get company users: %w", err)
	}

	for _, adminId := range adminIds {
		notifyErr := createNotification(ctx, firestoreClient, collectionPrefix, adminId,
			"A review has been posted",
			"A user has posted a review on their recent loan experience. Click here to see what they say about their experience.",
			"normal", notifData,
		)
		if notifyErr != nil {
			log.Error(fmt.Sprintf("failed to create notification for admin %s: %v", adminId, notifyErr))
		}
	}

	log.Debug(fmt.Sprintf("Created %d review notifications for company %s", len(adminIds), providerId))

	return nil
}
