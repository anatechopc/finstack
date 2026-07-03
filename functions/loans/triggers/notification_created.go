package triggers

import (
	"com.loooans.app/utils"
	"context"
	"errors"
	"fmt"
	"github.com/cloudevents/sdk-go/v2/event"
	"github.com/golang/protobuf/proto"
	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
)

// NotificationCreated
//
//	function to run firestore trigger for collection
//		collection: notifications/
//	Once a new notification document is created, this trigger
//	will send a notification request to the FCM server that will
//	send push notifications to the devices stored in the devices
//	collection under user
//
// /**
func NotificationCreated(ctx context.Context, event event.Event) error {
	log, logErr := utils.InitializeLogger("notification_created")

	if logErr != nil {
		return logErr
	}

	var data firestoredata.DocumentEventData

	if err := proto.Unmarshal(event.Data(), &data); err != nil {
		return fmt.Errorf("proto.Unmarshal: %w", err)
	}

	log.Debug(fmt.Sprintf("Function triggered by change to: %v\n", event.Source()))
	log.Debug(fmt.Sprintf("Old value: %+v\n", data.GetOldValue()))
	log.Debug(fmt.Sprintf("New value: %+v\n", data.GetValue()))

	if data.GetValue() == nil {
		log.Error("No value for newly created doc")
		return errors.New("no value for newly created doc")
	}

	var title string
	var message string
	var recipientId string
	var notificationData map[string]*firestoredata.Value
	var priority string

	if value, ok := data.GetValue().GetFields()["title"]; ok {
		title = value.GetStringValue()
	} else {
		return fmt.Errorf("No title for notification: %s", data.GetValue().GetName())
	}

	if value, ok := data.GetValue().GetFields()["message"]; ok {
		message = value.GetStringValue()
	} else {
		return fmt.Errorf("No message for notification: %s", data.GetValue().GetName())
	}

	if value, ok := data.GetValue().GetFields()["recipient_id"]; ok {
		recipientId = value.GetStringValue()
	} else {
		return fmt.Errorf("No recipient for notification: %s", data.GetValue().GetName())
	}

	if value, ok := data.GetValue().GetFields()["priority"]; ok {
		priority = value.GetStringValue()
	} else {
		return fmt.Errorf("No priority for notification: %s", data.GetValue().GetName())
	}

	if value, ok := data.GetValue().GetFields()["data"]; ok {
		notificationData = value.GetMapValue().GetFields()
	} else {
		return fmt.Errorf("No data for notification: %s", data.GetValue().GetName())
	}

	app, errFirebaseAdmin := utils.InitializeFirebase(ctx)

	if errFirebaseAdmin != nil {
		return errFirebaseAdmin
	}

	// get environment for path
	collectionPrefix := utils.GetCollectionPrefix()
	firestoreClient, errFirestoreClient := app.Firestore(ctx)

	if errFirestoreClient != nil {
		return fmt.Errorf("failed to instantiate firestore client: %v", errFirestoreClient)
	}

	// Deliver the push via the shared multicast helper (token gather + FCM payload
	// with Android priority + APNS alert/default sound). The notification document
	// is already persisted, so the push is best-effort at the token layer; a send
	// error is still returned so the platform retries.
	if err := sendPushToUsers(ctx, app, firestoreClient, collectionPrefix, log, []string{recipientId}, pushOptions{
		title:    title,
		body:     message,
		data:     parseNotificationData(notificationData),
		priority: priority,
	}); err != nil {
		return fmt.Errorf("failed to send FCM message: %w", err)
	}

	return nil
}

func parseNotificationData(data map[string]*firestoredata.Value) map[string]string {
	notificationType := data["notification_type"].GetStringValue()
	productId := data["product_id"].GetStringValue()
	loanId := data["loan_id"].GetStringValue()
	paymentId := data["payment_id"].GetStringValue()
	capitalId := data["capital_id"].GetStringValue()
	companyId := data["company_id"].GetStringValue()
	reviewId := data["review_id"].GetStringValue()
	userId := data["user_id"].GetStringValue()
	karmaId := data["karma_id"].GetStringValue()

	return map[string]string{
		"type":       notificationType,
		"product_id": productId,
		"loan_id":    loanId,
		"payment_id": paymentId,
		"capital_id": capitalId,
		"company_id": companyId,
		"review_id":  reviewId,
		"user_id":    userId,
		"karma_id":   karmaId,
	}
}
