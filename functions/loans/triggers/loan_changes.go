package triggers

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strconv"
	"time"

	"cloud.google.com/go/firestore"
	"com.loooans.app/utils"
	"firebase.google.com/go/v4/db"
	"github.com/cloudevents/sdk-go/v2/event"
	"github.com/golang/protobuf/proto"
	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
)

// LoanChanges
//
//	function to run firestore trigger for collection
//		collection: loans/
//	this trigger will create a Realtime DB data for reports
//
// /**
func LoanChanges(ctx context.Context, event event.Event) error {
	log, logErr := utils.InitializeLogger("loan_changes")

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

	var companyId string
	var loanId string
	var status string
	var amount float64

	if cId, ok := data.GetValue().GetFields()["company_id"]; ok {
		companyId = cId.GetStringValue()
	} else {
		return errors.New(fmt.Sprintf("No company_id for loan: %s", data.GetValue().GetName()))
	}

	if value, ok := data.GetValue().GetFields()["status"]; ok {
		status = value.GetStringValue()
	} else {
		return errors.New(fmt.Sprintf("No status for loan: %s", data.GetValue().GetName()))
	}

	if value, ok := data.GetValue().GetFields()["amount"]; ok {
		if integerValue, isInteger := value.GetValueType().(*firestoredata.Value_IntegerValue); isInteger {
			amount = float64(integerValue.IntegerValue)
		} else {
			amount = value.GetDoubleValue()
		}
	} else {
		return errors.New(fmt.Sprintf("No amount for loan: %s", data.GetValue().GetName()))
	}

	if value, ok := data.GetValue().GetFields()["id"]; ok {
		loanId = value.GetStringValue()
	} else {
		return errors.New(fmt.Sprintf("No id for loan: %s", data.GetValue().GetName()))
	}

	app, errFirebaseAdmin := utils.InitializeFirebase(ctx)

	if errFirebaseAdmin != nil {
		return errFirebaseAdmin
	}

	dbClient, errDbClient := app.Database(ctx)

	if errDbClient != nil {
		return errDbClient
	}

	pathEnv := getPathEnv()

	basePath := pathEnv + "/companies/" + companyId
	salesPath, productsPath, totalSummaryPath, capitalUsagePath := getReportPaths(basePath)

	productType, prodTypeErr := getProductType(ctx, *dbClient, basePath+"/loans/"+loanId+":product_type")

	timeNow := time.Now().UTC()
	if prodTypeErr != nil {
		return fmt.Errorf("cannot get product type: %w", prodTypeErr)
	}

	// time paths
	yearPath, monthPath, weekPath, dayPath := getTimePaths(timeNow)

	var dataErrors error = nil

	if status == "approved" {
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+yearPath+"/total_amount_released", amount)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+monthPath+"/total_amount_released", amount)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+weekPath+"/total_amount_released", amount)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+dayPath+"/total_amount_released", amount)

		dataErrors = applyToNodeValue(ctx, *dbClient, productsPath+"/"+productType+"/total_amount_released", amount)

		dataErrors = applyToNodeValue(ctx, *dbClient, salesPath+"/total_amount_released", amount)

		dataErrors = addReportDataItem(ctx, *dbClient, basePath, timeNow, amount, 0, 0, productType, "release", "", loanId)

	} else if status == "bad_debt" {
		// bad debt here
		// update total_bad_debts field
		// update capital_usage,product, total_summary and data

		// bad debt is the remaining principal that cannot be collected.
		// one of the reasons is that the borrower is unable to pay.
		//
		// To compute for bad debt, get every loan_schedule payment:
		// 		bad_debt = principal - total_principal_amount_paid
		// Then, uncomment the lines below to apply the bad_debt in the report

		firestoreClient, errFirestoreClient := app.Firestore(ctx)

		if errFirestoreClient != nil {
			log.Error("error firestore client: " + errFirestoreClient.Error())
			return fmt.Errorf("error firestore client: %w", errFirestoreClient)
		}

		loanSchedules, collectionErr := firestoreClient.Collection(pathEnv+"_loan_schedules").Where("loan_id", "==", loanId).Documents(ctx).GetAll()

		if collectionErr != nil {
			return fmt.Errorf("cannot get loan schedules for loanId %s: %$w", loanId, collectionErr)
		}

		var totalPrincipalPaid float64

		for _, schedule := range loanSchedules {
			if rawValue, ok := schedule.Data()["principal_payment"]; ok {
				if value, ok2 := rawValue.(float64); ok2 {
					totalPrincipalPaid += value
				}
			}
		}

		totalBadDebt := amount - totalPrincipalPaid
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+yearPath+"/total_bad_debts", totalBadDebt)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+monthPath+"/total_bad_debts", totalBadDebt)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+weekPath+"/total_bad_debts", totalBadDebt)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+dayPath+"/total_bad_debts", totalBadDebt)

		dataErrors = applyToNodeValue(ctx, *dbClient, productsPath+"/"+productType+"/total_bad_debts", totalBadDebt)

		dataErrors = applyToNodeValue(ctx, *dbClient, capitalUsagePath+"/total_bad_debts", totalBadDebt)

		dataErrors = addReportDataItem(ctx, *dbClient, basePath, timeNow, totalBadDebt, 0, 0, productType, "bad_debt", "", loanId)
	} else if status == "completed" {
		// completed status is just like paid statuses. The difference is that, we get the remaining balance
		// and then, the remaining balance we tag them as collection in the reports.
		// TODO(deibeeed) complete this for report

		firestoreClient, errFirestoreClient := app.Firestore(ctx)

		if errFirestoreClient != nil {
			log.Error("error firestore client: " + errFirestoreClient.Error())
			return fmt.Errorf("error firestore client: %w", errFirestoreClient)
		}

		loanSchedules, collectionErr := firestoreClient.Collection(pathEnv+"_loan_schedules").Where("loan_id", "==", loanId).Documents(ctx).GetAll()

		if collectionErr != nil {
			return fmt.Errorf("cannot get loan schedules for loanId %s: %$w", loanId, collectionErr)
		}

		var totalLoanAmount = amount
		var totalInterestPaymentAmount float64
		var totalPrincipalPaymentAmount float64

		if value, ok := data.GetValue().GetFields()["additional_charges"]; ok {
			if integerValue, isInteger := value.GetValueType().(*firestoredata.Value_IntegerValue); isInteger {
				totalLoanAmount += float64(integerValue.IntegerValue)
			} else {
				totalLoanAmount += value.GetDoubleValue()
			}
		}

		if value, ok := data.GetValue().GetFields()["deductions"]; ok {
			if integerValue, isInteger := value.GetValueType().(*firestoredata.Value_IntegerValue); isInteger {
				totalLoanAmount -= float64(integerValue.IntegerValue)
			} else {
				totalLoanAmount -= value.GetDoubleValue()
			}
		}

		if value, ok := data.GetValue().GetFields()["additional_charges"]; ok {
			if integerValue, isInteger := value.GetValueType().(*firestoredata.Value_IntegerValue); isInteger {
				totalLoanAmount -= float64(integerValue.IntegerValue)
			} else {
				totalLoanAmount -= value.GetDoubleValue()
			}
		}

		if value, ok := data.GetValue().GetFields()["additional_charge_upfront_collection"]; ok {
			if integerValue, isInteger := value.GetValueType().(*firestoredata.Value_IntegerValue); isInteger {
				totalLoanAmount -= float64(integerValue.IntegerValue)
			} else {
				totalLoanAmount -= value.GetDoubleValue()
			}
		}

		for _, schedule := range loanSchedules {
			if rawValue, ok := schedule.Data()["principal_payment"]; ok {
				if value, ok2 := rawValue.(float64); ok2 {
					totalPrincipalPaymentAmount += value
				} else if value, ok2 := rawValue.(int64); ok2 {
					totalPrincipalPaymentAmount += float64(value)
				}
			}

			if rawValue, ok := schedule.Data()["extra_payment"]; ok {
				if value, ok2 := rawValue.(float64); ok2 {
					totalPrincipalPaymentAmount += value
				} else if value, ok2 := rawValue.(int64); ok2 {
					totalPrincipalPaymentAmount += float64(value)
				}
			}

			if rawValue2, ok3 := schedule.Data()["interest_payment"]; ok3 {
				if value, ok3 := rawValue2.(float64); ok3 {
					totalInterestPaymentAmount += value
				} else if value, ok3 := rawValue2.(int64); ok3 {
					totalInterestPaymentAmount += float64(value)
				}
			}
		}

		log.Debug(fmt.Sprintf("totalLoanAmount: %f", totalLoanAmount))
		log.Debug(fmt.Sprintf("totalPrincipalPaymentAmount: %f", totalPrincipalPaymentAmount))
		log.Debug(fmt.Sprintf("totalInterestPaymentAmount: %f", totalInterestPaymentAmount))

		totalPaidAmount := totalPrincipalPaymentAmount + totalInterestPaymentAmount
		totalRemainingBalance := totalLoanAmount - totalPaidAmount

		var usedCapital float64

		if len(loanSchedules) > 0 {
			usedCapital = totalRemainingBalance + totalPrincipalPaymentAmount
		} else {
			usedCapital = totalRemainingBalance
		}

		// update capital usage to reflect used capital
		dataErrors = applyToNodeValue(ctx, *dbClient, capitalUsagePath+"/total_capital", usedCapital)

		dataErrors = addReportDataItem(ctx, *dbClient, basePath, timeNow, amount, 0, 0, "", "refresh_capital", "", "")

		// collection
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+yearPath+"/total_collections", totalRemainingBalance)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+monthPath+"/total_collections", totalRemainingBalance)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+weekPath+"/total_collections", totalRemainingBalance)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+dayPath+"/total_collections", totalRemainingBalance)

		dataErrors = applyToNodeValue(ctx, *dbClient, productsPath+"/"+productType+"/total_collections", totalRemainingBalance)
		dataErrors = applyToNodeValue(ctx, *dbClient, salesPath+"/total_collections", totalRemainingBalance)

		// interest
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+yearPath+"/total_interest_payments", totalInterestPaymentAmount)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+monthPath+"/total_interest_payments", totalInterestPaymentAmount)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+weekPath+"/total_interest_payments", totalInterestPaymentAmount)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+dayPath+"/total_interest_payments", totalInterestPaymentAmount)

		dataErrors = applyToNodeValue(ctx, *dbClient, productsPath+"/"+productType+"/total_interest_payments", totalInterestPaymentAmount)
		dataErrors = applyToNodeValue(ctx, *dbClient, salesPath+"/total_interest_payments", totalInterestPaymentAmount)

		// principal
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+yearPath+"/total_principal_payments", totalPrincipalPaymentAmount)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+monthPath+"/total_principal_payments", totalPrincipalPaymentAmount)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+weekPath+"/total_principal_payments", totalPrincipalPaymentAmount)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+dayPath+"/total_principal_payments", totalPrincipalPaymentAmount)

		dataErrors = applyToNodeValue(ctx, *dbClient, productsPath+"/"+productType+"/total_principal_payments", totalPrincipalPaymentAmount)
		dataErrors = applyToNodeValue(ctx, *dbClient, salesPath+"/total_principal_payments", totalPrincipalPaymentAmount)

		dataErrors = addReportDataItem(ctx, *dbClient, basePath, timeNow, totalRemainingBalance, totalInterestPaymentAmount, totalPrincipalPaymentAmount, productType, "collection", "", loanId)
	}

	// --- Notification creation ---
	// Create notifications based on loan status changes.
	// We detect transitions by comparing old vs new status.
	var oldStatus string
	if data.GetOldValue() != nil {
		if value, ok := data.GetOldValue().GetFields()["status"]; ok {
			oldStatus = value.GetStringValue()
		}
	}

	// Only create notifications when the status actually changed
	if status != oldStatus {
		collectionPrefix := utils.GetCollectionPrefix()
		firestoreClient, errFirestoreClient := app.Firestore(ctx)

		if errFirestoreClient != nil {
			log.Error("error creating firestore client for notifications: " + errFirestoreClient.Error())
			// Don't fail the entire trigger for notification errors — report data is more critical
		} else {
			notifyErr := createLoanStatusNotifications(ctx, firestoreClient, collectionPrefix, data, status, loanId, companyId)
			if notifyErr != nil {
				log.Error("error creating loan status notifications: " + notifyErr.Error())
			}
		}
	}

	return dataErrors
}

// createLoanStatusNotifications creates notification documents based on the
// loan status transition. The existing notificationCreated trigger handles
// FCM push delivery.
func createLoanStatusNotifications(
	ctx context.Context,
	firestoreClient *firestore.Client,
	collectionPrefix string,
	data firestoredata.DocumentEventData,
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

func addReportDataItem(ctx context.Context, dbClient db.Client, basePath string, timeNow time.Time, amount float64, interest float64, principal float64, productType string, dataType string, capitalId string, loanId string) error {
	reportSummaryPath := basePath + "/report_summary"
	dataPath := reportSummaryPath + "/data/"
	year, month, day := timeNow.Date()
	_, week := timeNow.ISOWeek()
	dataItemPath := fmt.Sprintf("%d:%d:week:%d:%dT%d:%d:%d:%d", year, int(month), week, day, timeNow.Hour(), timeNow.Minute(), timeNow.Second(), timeNow.Nanosecond())
	reportDataItem := map[string]any{
		"created_at":   timeNow.UnixMilli(),
		"amount":       amount,
		"interest":     interest,
		"principal":    principal,
		"product_type": productType,
		"data_type":    dataType,
		"capital_id":   capitalId,
		"loan_id":      loanId,
	}

	dataItemRef := dbClient.NewRef(dataPath + dataItemPath)
	if err := dataItemRef.Set(ctx, reportDataItem); err != nil {
		return fmt.Errorf("cannot set data to %s: %w", dataItemPath, err)
	}

	return nil
}

// applyToNodeValue
//
// updates the value of pathToNodeValue with applyValue
//
// If no error is returned, the update is successful.
// /**
func applyToNodeValue(ctx context.Context, dbClient db.Client, pathToNodeValue string, applyValue float64) error {
	ref := dbClient.NewRef(pathToNodeValue)
	var value float64
	err := ref.Get(ctx, &value)

	if err != nil {
		return fmt.Errorf("cannot get value of path %s: %w", pathToNodeValue, err)
	} else {
		// pathToValue does not exist, no data or has data, the value is still 0.0 based on ChatGPT convo
		// https://chatgpt.com/share/67624222-3f68-8007-8d97-fad75fe9e370
		setErr := ref.Set(ctx, value+applyValue)

		if setErr != nil {
			return fmt.Errorf("cannot apply to %s: %w", pathToNodeValue, err)
		}
	}

	return nil
}

// getProductType
//
// # Gets the product type from the realtime database
//
// The path should have the following:
//
//	path = basePath + "/companies/<companyId>/loans/<loanId>:product_type"
//	/**
func getProductType(ctx context.Context, dbClient db.Client, path string) (string, error) {
	ref := dbClient.NewRef(path)
	var productType string
	err := ref.Get(ctx, &productType)

	if err != nil {
		return "", err
	} else if len(productType) == 0 {
		return "", errors.New("product type not found")
	}

	return productType, nil
}

func getPathEnv() string {
	env := os.Getenv("ENVIRONMENT")
	pathEnv := ""

	switch env {
	case "development":
		pathEnv = "dev"
		break
	case "staging":
		pathEnv = "stg"
		break
	}

	return pathEnv
}

func getTimePaths(timeNow time.Time) (string, string, string, string) {
	year, month, day := timeNow.Date()
	_, week := timeNow.ISOWeek()
	yearPath := "year:" + strconv.Itoa(year)
	monthPath := yearPath + ":month:" + strconv.Itoa(int(month))
	weekPath := monthPath + ":week:" + strconv.Itoa(week)
	dayPath := weekPath + ":day:" + strconv.Itoa(day)

	return yearPath, monthPath, weekPath, dayPath
}

func getReportPaths(basePath string) (string, string, string, string) {
	reportSummaryPath := basePath + "/report_summary"
	salesPath := reportSummaryPath + "/sales"
	productsPath := reportSummaryPath + "/products"
	totalSummaryPath := reportSummaryPath + "/total_summary"
	capitalUsagePath := reportSummaryPath + "/capital_usage"

	return salesPath, productsPath, totalSummaryPath, capitalUsagePath
}
