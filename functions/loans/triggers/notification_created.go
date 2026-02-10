package triggers

import (
	"com.loooans.app/utils"
	"context"
	"errors"
	"firebase.google.com/go/v4/messaging"
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
		return errors.New(fmt.Sprintf("No title for notification: %s", data.GetValue().GetName()))
	}

	if value, ok := data.GetValue().GetFields()["message"]; ok {
		message = value.GetStringValue()
	} else {
		return errors.New(fmt.Sprintf("No message for notification: %s", data.GetValue().GetName()))
	}

	if value, ok := data.GetValue().GetFields()["recipient_id"]; ok {
		recipientId = value.GetStringValue()
	} else {
		return errors.New(fmt.Sprintf("No recipient for notification: %s", data.GetValue().GetName()))
	}

	if value, ok := data.GetValue().GetFields()["priority"]; ok {
		priority = value.GetStringValue()
	} else {
		return errors.New(fmt.Sprintf("No priority for notification: %s", data.GetValue().GetName()))
	}

	if value, ok := data.GetValue().GetFields()["data"]; ok {
		notificationData = value.GetMapValue().GetFields()
	} else {
		return errors.New(fmt.Sprintf("No data for notification: %s", data.GetValue().GetName()))
	}

	app, errFirebaseAdmin := utils.InitializeFirebase(ctx)

	if errFirebaseAdmin != nil {
		return errFirebaseAdmin
	}

	// get environment for apth
	collectionPrefix := utils.GetCollectionPrefix()
	firestoreClient, errFirestoreClient := app.Firestore(ctx)

	if errFirestoreClient != nil {
		//log.Error("error firestore client: " + errFirestoreClient.Error())
		//http.Error(w, "error firestore client: "+errFirestoreClient.Error(), http.StatusInternalServerError)
		return fmt.Errorf("failed to instantiate firestore client: %v", errFirestoreClient)
	}

	devicesCollection := firestoreClient.
		Collection(collectionPrefix + "users/" + recipientId + "/devices").
		Documents(ctx)
	devicesSnapshots, snapshotsErr := devicesCollection.GetAll()

	if snapshotsErr != nil {
		return fmt.Errorf("failed to get devices for user %s: %v", recipientId, snapshotsErr)
	}

	var tokens []string

	for _, snapshot := range devicesSnapshots {
		tokenTemp := snapshot.Data()["token"]

		if value, ok := tokenTemp.(string); ok {
			tokens = append(tokens, value)
		}
	}

	fcmClient, fcmClientErr := app.Messaging(ctx)

	if fcmClientErr != nil {
		return fmt.Errorf("cannot initialize FCM client, %v", fcmClientErr)
	}

	/// create message here:
	/// NOTES:
	///		Token = device fcm token
	/// 	Data = additional data on top of the notification
	///		Notification = the object that they can see when opening the status bar / notification bar of the device (android/ios)
	/// 	Android = Android specific configurations for push notification
	///			Priority = Values are either 'normal' or "high"
	///			Data = the same data as above, overrides the data outside of this notification message object once this is supplied
	///		APNS = apple push notification config for push notification
	///			Payload = APNS payload of the notification
	///				Aps = contains the payload
	///
	///	For MulticastMessage, token is a list of tokens
	///
	fcmMulticastMessage := &messaging.MulticastMessage{
		Data: parseNotificationData(notificationData),
		Notification: &messaging.Notification{
			Title:    title,
			Body:     message,
			ImageURL: "",
		},
		Android: &messaging.AndroidConfig{
			CollapseKey:           "",
			Priority:              priority,
			TTL:                   nil,
			RestrictedPackageName: "",
			Data:                  nil,
			Notification:          nil,
			FCMOptions:            nil,
		},
		Webpush: nil,
		APNS: &messaging.APNSConfig{
			Headers: nil,
			Payload: &messaging.APNSPayload{
				Aps: &messaging.Aps{
					Alert: &messaging.ApsAlert{
						Title:           title,
						SubTitle:        "",
						Body:            message,
						LocKey:          "",
						LocArgs:         nil,
						TitleLocKey:     "",
						TitleLocArgs:    nil,
						SubTitleLocKey:  "",
						SubTitleLocArgs: nil,
						ActionLocKey:    "",
						LaunchImage:     "",
					},
					Sound: "default",
				},
				CustomData: nil,
			},
			FCMOptions: nil,
		},
		//FCMOptions:   nil,
		Tokens: tokens,
		//Topic:     "",
		//Condition: "",
	}

	//fcmResponse, fcmResponseErr := fcmClient.Send(ctx, fcmMessage)
	fcmBatchResponse, fcmResponseErr := fcmClient.SendEachForMulticast(ctx, fcmMulticastMessage)
	//fcmResponse, fcmResponseErr := fcmClient.SendEach(ctx, messages)

	if fcmResponseErr != nil {
		return fmt.Errorf("failed to send FCM message: %v", fcmResponseErr)
	}

	log.Debug(fmt.Sprintf("Successfully sent FCM message: %v", fcmBatchResponse))

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
