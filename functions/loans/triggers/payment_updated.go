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

// Payment status values as serialised by the Dart PaymentStatus enum (the
// app writes the enum .name): see payment_repository PaymentStatusEnumMap.
const (
	paymentStatusPending   = "pending"
	paymentStatusConfirmed = "confirmed"
	paymentStatusRejected  = "rejected"
)

// PaymentUpdatedDeps holds the collaborator functions used by the core so the
// business logic can be unit-tested without Firestore.
type PaymentUpdatedDeps struct {
	// Notify writes a notification document for the recipient. The existing
	// notificationCreated trigger handles FCM delivery.
	Notify func(ctx context.Context, recipientId, title, message string, data map[string]string) error
}

// HandlePaymentUpdatedCore notifies the borrower when a lender confirms or
// rejects their submitted payment.
//
// It fires ONLY on the status transition pending -> confirmed or
// pending -> rejected and notifies payment.user_id (the borrower who submitted
// the payment). Every other change — confirmed -> confirmed, pending -> pending,
// or an unrelated field edit — is a no-op. The transition is derived purely
// from the before/after snapshots.
func HandlePaymentUpdatedCore(
	ctx context.Context,
	paymentId string,
	before, after map[string]any,
	deps PaymentUpdatedDeps,
) error {
	if before == nil || after == nil {
		return nil
	}

	beforeStatus, _ := before["status"].(string)
	afterStatus, _ := after["status"].(string)

	// Fire only when a pending payment is resolved to confirmed or rejected.
	if beforeStatus != paymentStatusPending {
		return nil
	}
	if afterStatus != paymentStatusConfirmed && afterStatus != paymentStatusRejected {
		return nil
	}

	userId, _ := after["user_id"].(string)
	if userId == "" {
		// No borrower to notify — nothing actionable.
		return nil
	}

	loanId, _ := after["loan_id"].(string)

	var title, message string
	if afterStatus == paymentStatusConfirmed {
		title = "Payment confirmed"
		message = "Your payment was confirmed."
	} else {
		title = "Payment rejected"
		message = "Your payment was rejected"
		if reason, _ := after["rejection_reason"].(string); reason != "" {
			message = fmt.Sprintf("Your payment was rejected: %s", reason)
		}
	}

	data := makeNotificationData("payment",
		withPaymentId(paymentId),
		withLoanId(loanId),
		withUserId(userId),
	)

	return deps.Notify(ctx, userId, title, message, data)
}

// PaymentUpdated is the CloudEvent adapter. It wires real Firestore into the
// core. Triggered by document.v1.updated on payments/{id}.
func PaymentUpdated(ctx context.Context, ev event.Event) error {
	log, logErr := utils.InitializeLogger("payment_updated")
	if logErr != nil {
		return logErr
	}

	var data firestoredata.DocumentEventData
	if err := proto.Unmarshal(ev.Data(), &data); err != nil {
		return fmt.Errorf("proto.Unmarshal: %w", err)
	}

	paymentId, before, after, err := extractPaymentChange(&data)
	if err != nil {
		log.Sugar().Warnf("payment_updated: skipping event: %v", err)
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

	deps := PaymentUpdatedDeps{
		Notify: func(ctx context.Context, recipientId, title, message string, data map[string]string) error {
			return createNotification(ctx, fs, collectionPrefix, recipientId, title, message, "normal", data)
		},
	}

	return HandlePaymentUpdatedCore(ctx, paymentId, before, after, deps)
}

// extractPaymentChange pulls the payment id + before/after maps (limited to the
// fields this trigger cares about) from the proto event.
func extractPaymentChange(data *firestoredata.DocumentEventData) (string, map[string]any, map[string]any, error) {
	if data.GetValue() == nil || data.GetOldValue() == nil {
		return "", nil, nil, errors.New("missing value or old value")
	}

	var paymentId string
	if idVal, ok := data.GetValue().GetFields()["id"]; ok {
		paymentId = idVal.GetStringValue()
	}
	if paymentId == "" {
		return "", nil, nil, errors.New("missing payment id")
	}

	before := flattenPaymentFields(data.GetOldValue().GetFields())
	after := flattenPaymentFields(data.GetValue().GetFields())
	return paymentId, before, after, nil
}

// flattenPaymentFields converts the firestoredata.Value map into a plain Go map
// covering only the fields this trigger reads.
func flattenPaymentFields(fields map[string]*firestoredata.Value) map[string]any {
	out := map[string]any{}
	for k, v := range fields {
		switch k {
		case "status", "user_id", "loan_id", "rejection_reason", "id":
			out[k] = v.GetStringValue()
		}
	}
	return out
}
