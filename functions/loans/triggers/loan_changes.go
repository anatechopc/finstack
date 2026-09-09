package triggers

import (
	"context"
	"fmt"
	"time"

	"cloud.google.com/go/firestore"
	"com.loooans.app/utils"
	"github.com/cloudevents/sdk-go/v2/event"
	"github.com/golang/protobuf/proto"
	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
)

// LoanChanges books report totals for loan status transitions (release, bad
// debt, settlement) and creates status notifications.
//
// Deployed on google.cloud.firestore.document.v1.written for
// {prefix}loans/{uid}: it fires on every create AND update, so the core only
// acts on a status transition and claims each event id once before one
// atomic write (campaign D1/D2; see
// docs/superpowers/specs/2026-09-09-report-triggers-rebuild.md).
func LoanChanges(ctx context.Context, ev event.Event) error {
	log, logErr := utils.InitializeLogger("loan_changes")
	if logErr != nil {
		return logErr
	}

	var data firestoredata.DocumentEventData
	if err := proto.Unmarshal(ev.Data(), &data); err != nil {
		return fmt.Errorf("proto.Unmarshal: %w", err)
	}
	log.Debug(fmt.Sprintf("Function triggered by change to: %v", ev.Source()))

	loanEvent, err := parseLoanChange(ev.ID(), &data)
	if err != nil {
		return err
	}
	if loanEvent.IsDelete {
		// A hard delete: nothing to report or notify, and an error would only
		// be retried forever.
		return nil
	}

	app, err := utils.InitializeFirebase(ctx)
	if err != nil {
		return err
	}
	dbClient, err := app.Database(ctx)
	if err != nil {
		return err
	}
	firestoreClient, err := app.Firestore(ctx)
	if err != nil {
		return fmt.Errorf("error firestore client: %w", err)
	}
	collectionPrefix := utils.GetCollectionPrefix()

	outcome, reportErr := HandleLoanChangeCore(ctx, utils.GetMinifiedEnv(), loanEvent, ReportDeps{
		Store:         NewRTDBReportStore(dbClient),
		LoadSchedules: firestoreScheduleLoader(firestoreClient, collectionPrefix),
		Now:           time.Now,
		LogInfo:       func(format string, args ...any) { log.Info(fmt.Sprintf(format, args...)) },
	})
	if reportErr != nil {
		// Returned so the event is retried; the claim was released.
		log.Error("report: " + reportErr.Error())
		return reportErr
	}
	if outcome == ReportAlreadyApplied {
		// A redelivered event already sent its notifications.
		return nil
	}

	// --- Notification creation ---
	// Only create notifications when the status actually changed.
	if loanEvent.Status != loanEvent.OldStatus {
		if notifyErr := createLoanStatusNotifications(ctx, firestoreClient, collectionPrefix, &data, loanEvent.Status, loanEvent.LoanId, loanEvent.CompanyId); notifyErr != nil {
			// Don't fail the trigger for notification errors — report data is more critical
			log.Error("error creating loan status notifications: " + notifyErr.Error())
		}
	}

	return nil
}

// parseLoanChange extracts what the report and notification paths need.
func parseLoanChange(eventId string, data *firestoredata.DocumentEventData) (LoanChangeEvent, error) {
	loanEvent := LoanChangeEvent{EventId: eventId}
	if data.GetValue() == nil {
		loanEvent.IsDelete = true
		return loanEvent, nil
	}
	fields := data.GetValue().GetFields()
	name := data.GetValue().GetName()

	var ok bool
	if loanEvent.CompanyId, ok = stringField(fields, "company_id"); !ok {
		return loanEvent, fmt.Errorf("no company_id for loan: %s", name)
	}
	if loanEvent.Status, ok = stringField(fields, "status"); !ok {
		return loanEvent, fmt.Errorf("no status for loan: %s", name)
	}
	if loanEvent.LoanId, ok = stringField(fields, "id"); !ok {
		return loanEvent, fmt.Errorf("no id for loan: %s", name)
	}
	if loanEvent.Amount, ok = numberField(fields, "amount"); !ok {
		return loanEvent, fmt.Errorf("no amount for loan: %s", name)
	}
	loanEvent.AdditionalCharges, _ = numberField(fields, "additional_charges")
	loanEvent.Deductions, _ = numberField(fields, "deductions")
	loanEvent.UpfrontCollection, _ = numberField(fields, "additional_charge_upfront_collection")
	if data.GetOldValue() != nil {
		loanEvent.OldStatus, _ = stringField(data.GetOldValue().GetFields(), "status")
	}
	return loanEvent, nil
}

func stringField(fields map[string]*firestoredata.Value, name string) (string, bool) {
	value, ok := fields[name]
	if !ok {
		return "", false
	}
	return value.GetStringValue(), true
}

// numberField reads an integer or double Firestore value as float64.
func numberField(fields map[string]*firestoredata.Value, name string) (float64, bool) {
	value, ok := fields[name]
	if !ok {
		return 0, false
	}
	if integer, isInteger := value.GetValueType().(*firestoredata.Value_IntegerValue); isInteger {
		return float64(integer.IntegerValue), true
	}
	return value.GetDoubleValue(), true
}

// firestoreScheduleLoader reads the payment amounts of every loan_schedule of
// a loan. Before this the collection was built as `{env}_loan_schedules`,
// which in production (empty env) named a collection that does not exist.
func firestoreScheduleLoader(client *firestore.Client, collectionPrefix string) func(context.Context, string) ([]ScheduleAmounts, error) {
	return func(ctx context.Context, loanId string) ([]ScheduleAmounts, error) {
		docs, err := client.Collection(collectionPrefix+"loan_schedules").Where("loan_id", "==", loanId).Documents(ctx).GetAll()
		if err != nil {
			return nil, err
		}
		schedules := make([]ScheduleAmounts, 0, len(docs))
		for _, doc := range docs {
			fields := doc.Data()
			schedules = append(schedules, ScheduleAmounts{
				Principal: numberOf(fields["principal_payment"]),
				Extra:     numberOf(fields["extra_payment"]),
				Interest:  numberOf(fields["interest_payment"]),
			})
		}
		return schedules, nil
	}
}

func numberOf(value any) float64 {
	switch number := value.(type) {
	case float64:
		return number
	case int64:
		return float64(number)
	case int:
		return float64(number)
	}
	return 0
}

// createLoanStatusNotifications creates notification documents based on the
// loan status transition. The existing notificationCreated trigger handles
// FCM push delivery.
func createLoanStatusNotifications(
	ctx context.Context,
	firestoreClient *firestore.Client,
	collectionPrefix string,
	data *firestoredata.DocumentEventData,
	status string,
	loanId string,
	companyId string,
) error {
	// Extract additional fields from the loan document
	var userId string
	var productId string

	if value, ok := data.GetValue().GetFields()["user_id"]; ok {
		userId = value.GetStringValue()
	}
	if value, ok := data.GetValue().GetFields()["product_id"]; ok {
		productId = value.GetStringValue()
	}

	// Get product name for notification messages
	productName := "loan"
	if productId != "" {
		if name, err := getProductName(ctx, firestoreClient, collectionPrefix, productId); err == nil && name != "" {
			productName = name
			// Ensure it ends with "loan" for readability
			if len(productName) < 4 || productName[len(productName)-4:] != "loan" {
				productName = productName + " loan"
			}
		}
	}

	notifData := makeNotificationData("loan",
		withLoanId(loanId),
		withProductId(productId),
		withCompanyId(companyId),
	)

	switch status {
	case "pending":
		// Loan was just created — notify borrower and company admins
		if userId != "" {
			_ = createNotification(ctx, firestoreClient, collectionPrefix, userId,
				"Loan application submitted",
				fmt.Sprintf("Your %s application has been submitted.\nA loan application officer will review your loan application.\nTo check for the progress, please go to \"My loans\" then select your loan application.\n\nWe will notify you for further progress.", productName),
				"normal", notifData,
			)
		}

		// Notify company admins and loan officers
		adminIds, err := getCompanyUserIdsByRole(ctx, firestoreClient, collectionPrefix, companyId, []string{"admin", "loanOfficer"})
		if err == nil {
			for _, adminId := range adminIds {
				_ = createNotification(ctx, firestoreClient, collectionPrefix, adminId,
					"Loan application submitted and is ready for review",
					"A user has submitted a loan application. Click here review.",
					"normal", notifData,
				)
			}
		}

		// Notify co-makers if present
		if coMakerValues, ok := data.GetValue().GetFields()["co_maker_user_ids"]; ok {
			if arrayValue := coMakerValues.GetArrayValue(); arrayValue != nil {
				for _, coMakerValue := range arrayValue.GetValues() {
					coMakerId := coMakerValue.GetStringValue()
					if coMakerId != "" {
						_ = createNotification(ctx, firestoreClient, collectionPrefix, coMakerId,
							"You have been added as a co-maker",
							fmt.Sprintf("You have been added as a co-maker for a %s application.\nClick here for more details about the loan.", productName),
							"high", notifData,
						)
					}
				}
			}
		}

	case "approved":
		// Notify the borrower that their loan was approved
		if userId != "" {
			_ = createNotification(ctx, firestoreClient, collectionPrefix, userId,
				"Your loan application is approved!",
				fmt.Sprintf("Congratulations! Your %s application is approved.\nClick here for more details.", productName),
				"high", notifData,
			)
		}

	case "declined":
		// Notify the borrower that their loan was declined
		if userId != "" {
			_ = createNotification(ctx, firestoreClient, collectionPrefix, userId,
				"Your loan application was declined.",
				fmt.Sprintf("Your %s application was declined.\nClick here for more details", productName),
				"normal", notifData,
			)
		}
	}

	return nil
}
