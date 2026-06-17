package triggers

import (
	"context"
	"errors"
	"fmt"

	"cloud.google.com/go/firestore"
	"com.loooans.app/utils"
	"github.com/cloudevents/sdk-go/v2/event"
	"github.com/golang/protobuf/proto"
	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
	"google.golang.org/api/iterator"
)

// PaymentCreatedDeps holds the collaborator functions used by the core so the
// notification fan-out can be unit-tested without Firestore.
type PaymentCreatedDeps struct {
	// LoanIdForSchedule resolves the loan id for a given loan_schedule_id by
	// reading the loan_schedules document. Returns ("", nil) when the schedule
	// cannot be resolved to a loan (the core treats this as a graceful no-op).
	LoanIdForSchedule func(ctx context.Context, scheduleId string) (string, error)
	// LoanInfo returns the company id and product id for a loan.
	LoanInfo func(ctx context.Context, loanId string) (companyId, productId string, err error)
	// FirstPaymentIdForSubmission returns the id of the earliest-created payment
	// sharing the given submission_id. Used to de-dup notifications for a
	// multi-payment "pay in full" submission.
	FirstPaymentIdForSubmission func(ctx context.Context, submissionId string) (string, error)
	// CompanyUserIds returns the user ids of company members holding one of the
	// given roles.
	CompanyUserIds func(ctx context.Context, companyId string, roles []string) ([]string, error)
	// ProductName returns the product's display loan_type for the message.
	ProductName func(ctx context.Context, productId string) (string, error)
	// Notify writes a notification document for the recipient. The existing
	// notificationCreated trigger handles FCM delivery.
	Notify func(ctx context.Context, recipientId, title, message string, data map[string]string) error
}

// HandlePaymentCreatedCore notifies a company's admins and loan officers that a
// borrower submitted a payment.
//
// De-duplication: a borrower paying "in full" creates N payments sharing one
// submission_id, which would otherwise fire N lender notifications. When a
// submission_id is present, only the FIRST payment of that submission notifies;
// siblings are a no-op. Legacy and teller payments carry no submission_id and
// always notify.
//
// Loan resolution: payment docs carry loan_schedule_id (not loan_id). The core
// uses fields["loan_id"] when present (backward-compat) and otherwise resolves
// it from the schedule via deps.LoanIdForSchedule. If neither yields a loan id,
// it is a graceful no-op (returns nil) so a malformed doc does not crash the
// function.
func HandlePaymentCreatedCore(
	ctx context.Context,
	paymentId string,
	fields map[string]any,
	deps PaymentCreatedDeps,
) error {
	if fields == nil {
		return nil
	}

	// De-dup gate first — avoid any lookup work for sibling payments.
	submissionId, _ := fields["submission_id"].(string)
	if submissionId != "" {
		firstId, err := deps.FirstPaymentIdForSubmission(ctx, submissionId)
		if err != nil {
			return fmt.Errorf("first payment for submission %s: %w", submissionId, err)
		}
		if firstId != "" && firstId != paymentId {
			// A sibling payment already notified — nothing to do.
			return nil
		}
	}

	// Resolve the loan id. Prefer an explicit loan_id (legacy/teller docs),
	// otherwise resolve it from the loan schedule.
	loanId, _ := fields["loan_id"].(string)
	if loanId == "" {
		scheduleId, _ := fields["loan_schedule_id"].(string)
		if scheduleId != "" {
			resolved, err := deps.LoanIdForSchedule(ctx, scheduleId)
			if err != nil {
				return fmt.Errorf("resolve loan for schedule %s: %w", scheduleId, err)
			}
			loanId = resolved
		}
	}
	if loanId == "" {
		// No loan to attribute this payment to — nothing actionable.
		return nil
	}

	companyId, productId, err := deps.LoanInfo(ctx, loanId)
	if err != nil {
		return fmt.Errorf("loan info for %s: %w", loanId, err)
	}

	// Product name for the message body (best-effort, defaults to "loan").
	productName := "loan"
	if productId != "" && deps.ProductName != nil {
		if name, nameErr := deps.ProductName(ctx, productId); nameErr == nil && name != "" {
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

	recipientIds, err := deps.CompanyUserIds(ctx, companyId, []string{"admin", "loanOfficer"})
	if err != nil {
		return fmt.Errorf("company users for %s: %w", companyId, err)
	}

	title := "Payment submitted"
	message := fmt.Sprintf("A user has submitted a payment for their %s. Click here review.", productName)

	for _, recipientId := range recipientIds {
		if notifyErr := deps.Notify(ctx, recipientId, title, message, notifData); notifyErr != nil {
			// Best-effort: log via wrapped error string; the adapter logs these.
			// Returning would re-notify already-notified recipients on retry.
			fmt.Printf("payment_created: failed to notify %s: %v\n", recipientId, notifyErr)
		}
	}

	return nil
}

// PaymentCreated is the CloudEvent adapter. It wires real Firestore into the
// core. Triggered by document.v1.created on payments/{id}.
//
// When a new payment document is created, this trigger creates notification
// documents for company admins and loan officers. The existing
// notificationCreated trigger handles FCM push delivery.
func PaymentCreated(ctx context.Context, ev event.Event) error {
	log, logErr := utils.InitializeLogger("payment_created")
	if logErr != nil {
		return logErr
	}

	var data firestoredata.DocumentEventData
	if err := proto.Unmarshal(ev.Data(), &data); err != nil {
		return fmt.Errorf("proto.Unmarshal: %w", err)
	}

	log.Debug(fmt.Sprintf("Function triggered by change to: %v\n", ev.Source()))

	if data.GetValue() == nil {
		log.Error("No value for newly created doc")
		return errors.New("no value for newly created doc")
	}

	paymentId, fields := extractPaymentCreate(&data)
	if paymentId == "" {
		log.Sugar().Warnf("payment_created: skipping event: missing payment id")
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

	deps := PaymentCreatedDeps{
		LoanIdForSchedule: func(ctx context.Context, scheduleId string) (string, error) {
			doc, err := fs.Collection(collectionPrefix+"loan_schedules").Doc(scheduleId).Get(ctx)
			if err != nil {
				return "", fmt.Errorf("failed to get loan_schedule %s: %w", scheduleId, err)
			}
			if loanId, ok := doc.Data()["loan_id"].(string); ok {
				return loanId, nil
			}
			return "", nil
		},
		LoanInfo: func(ctx context.Context, loanId string) (string, string, error) {
			doc, err := fs.Collection(collectionPrefix+"loans").Doc(loanId).Get(ctx)
			if err != nil {
				return "", "", fmt.Errorf("failed to get loan %s: %w", loanId, err)
			}
			companyId, _ := doc.Data()["company_id"].(string)
			productId, _ := doc.Data()["product_id"].(string)
			return companyId, productId, nil
		},
		FirstPaymentIdForSubmission: func(ctx context.Context, submissionId string) (string, error) {
			iter := fs.Collection(collectionPrefix+"payments").
				Where("submission_id", "==", submissionId).
				OrderBy("created_at", firestore.Asc).
				Limit(1).
				Documents(ctx)
			defer iter.Stop()

			doc, err := iter.Next()
			if err == iterator.Done {
				return "", nil
			}
			if err != nil {
				return "", fmt.Errorf("failed to query submission %s: %w", submissionId, err)
			}
			if id, ok := doc.Data()["id"].(string); ok {
				return id, nil
			}
			return "", nil
		},
		CompanyUserIds: func(ctx context.Context, companyId string, roles []string) ([]string, error) {
			return getCompanyUserIdsByRole(ctx, fs, collectionPrefix, companyId, roles)
		},
		ProductName: func(ctx context.Context, productId string) (string, error) {
			return getProductName(ctx, fs, collectionPrefix, productId)
		},
		Notify: func(ctx context.Context, recipientId, title, message string, data map[string]string) error {
			return createNotification(ctx, fs, collectionPrefix, recipientId, title, message, "normal", data)
		},
	}

	return HandlePaymentCreatedCore(ctx, paymentId, fields, deps)
}

// extractPaymentCreate pulls the payment id + the fields the trigger cares about
// from the created-document proto event.
func extractPaymentCreate(data *firestoredata.DocumentEventData) (string, map[string]any) {
	fields := map[string]any{}
	for k, v := range data.GetValue().GetFields() {
		switch k {
		case "id", "loan_id", "loan_schedule_id", "submission_id":
			fields[k] = v.GetStringValue()
		}
	}
	paymentId, _ := fields["id"].(string)
	return paymentId, fields
}
