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

// PaymentCreated
//
//	function to run firestore trigger for collection
//		collection: payments/
//	When a new payment document is created, this trigger
//	creates notification documents for company admins and
//	loan officers. The existing notificationCreated trigger
//	handles FCM push delivery.
//
// /**
func PaymentCreated(ctx context.Context, event event.Event) error {
	log, logErr := utils.InitializeLogger("payment_created")

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

	var paymentId string
	var loanId string

	if value, ok := data.GetValue().GetFields()["id"]; ok {
		paymentId = value.GetStringValue()
	}

	if value, ok := data.GetValue().GetFields()["loan_id"]; ok {
		loanId = value.GetStringValue()
	} else {
		return errors.New(fmt.Sprintf("No loan_id for payment: %s", data.GetValue().GetName()))
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

	// Read the associated loan document to get product_id and company_id
	loanDoc, loanErr := firestoreClient.Collection(collectionPrefix + "loans").Doc(loanId).Get(ctx)
	if loanErr != nil {
		return fmt.Errorf("failed to get loan %s for payment notification: %w", loanId, loanErr)
	}

	var companyId string
	var productId string

	if cId, ok := loanDoc.Data()["company_id"].(string); ok {
		companyId = cId
	}
	if pId, ok := loanDoc.Data()["product_id"].(string); ok {
		productId = pId
	}

	// Get product name for notification message
	productName := "loan"
	if productId != "" {
		if name, err := getProductName(ctx, firestoreClient, collectionPrefix, productId); err == nil && name != "" {
			productName = name
			if len(productName) < 4 || productName[len(productName)-4:] != "loan" {
				productName = productName + " loan"
			}
		}
	}

	notifData := makeNotificationData("payment",
		withLoanId(loanId),
		withProductId(productId),
		withCompanyId(companyId),
		withPaymentId(paymentId),
	)

	// Notify company admins and loan officers
	adminIds, err := getCompanyUserIdsByRole(ctx, firestoreClient, collectionPrefix, companyId, []string{"admin", "loanOfficer"})
	if err != nil {
		return fmt.Errorf("failed to get company users: %w", err)
	}

	for _, adminId := range adminIds {
		notifyErr := createNotification(ctx, firestoreClient, collectionPrefix, adminId,
			"Payment submitted",
			fmt.Sprintf("A user has submitted a payment for their %s. Click here review.", productName),
			"normal", notifData,
		)
		if notifyErr != nil {
			log.Error(fmt.Sprintf("failed to create notification for admin %s: %v", adminId, notifyErr))
		}
	}

	log.Debug(fmt.Sprintf("Created %d payment notifications for company %s", len(adminIds), companyId))

	return nil
}
