package triggers

import (
	"context"
	"errors"
	"fmt"
	"time"

	"com.loooans.app/utils"
	"github.com/cloudevents/sdk-go/v2/event"
	"github.com/golang/protobuf/proto"
	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
)

// LoanScheduleChanges
//
//	function to run firestore trigger for collection
//		collection: loan_schedules/
//	this trigger will create a Realtime DB data for reports
//
//	NOTE:
//		the trigger event for loan schedule changes will be `google.cloud.firestore.document.v1.created`
//		meaning, this trigger will only execute when the loan_schedule document is first created. This is
//		to prevent double records in our report data and will mess up with the reporting.
//	/**
func LoanScheduleChanges(ctx context.Context, event event.Event) error {
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
	// start for loan
	var status string
	// start for loan_schedule
	var interest float64
	var principal float64

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

	if value, ok := data.GetValue().GetFields()["loan_id"]; ok {
		loanId = value.GetStringValue()
	} else {
		return errors.New(fmt.Sprintf("No loan_id for loan: %s", data.GetValue().GetName()))
	}

	if value, ok := data.GetValue().GetFields()["interest_payment"]; ok {
		if iValue, isInt := value.GetValueType().(*firestoredata.Value_IntegerValue); isInt {
			interest = float64(iValue.IntegerValue)
		} else {
			interest = value.GetDoubleValue()
		}
	} else {
		return errors.New(fmt.Sprintf("No interest_payment for loan: %s", data.GetValue().GetName()))
	}

	if value, ok := data.GetValue().GetFields()["principal_payment"]; ok {
		if iValue, isInt := value.GetValueType().(*firestoredata.Value_IntegerValue); isInt {
			principal = float64(iValue.IntegerValue)
		} else {
			principal = value.GetDoubleValue()
		}
	} else {
		return errors.New(fmt.Sprintf("No principal_payment for loan: %s", data.GetValue().GetName()))
	}

	var dataErrors error = nil

	if status == "payment_submitted" || status == "paid_on_time" || status == "paid_late" {
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

		timeNow := time.Now().UTC()

		productType, prodTypeErr := getProductType(ctx, *dbClient, basePath+"/loans/"+loanId+":product_type")

		if prodTypeErr != nil {
			return fmt.Errorf("cannot get product type: %w", prodTypeErr)
		}

		// time paths
		yearPath, monthPath, weekPath, dayPath := getTimePaths(timeNow)

		// update capital usage to reflect used capital
		dataErrors = applyToNodeValue(ctx, *dbClient, capitalUsagePath+"/total_capital", principal)

		dataErrors = addReportDataItem(ctx, *dbClient, basePath, timeNow, principal, 0, 0, "", "refresh_capital", "", "")
		// collection
		collectedAmount := principal + interest
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+yearPath+"/total_collections", collectedAmount)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+monthPath+"/total_collections", collectedAmount)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+weekPath+"/total_collections", collectedAmount)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+dayPath+"/total_collections", collectedAmount)

		dataErrors = applyToNodeValue(ctx, *dbClient, productsPath+"/"+productType+"/total_collections", collectedAmount)
		dataErrors = applyToNodeValue(ctx, *dbClient, salesPath+"/total_collections", collectedAmount)

		// interest
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+yearPath+"/total_interest_payments", interest)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+monthPath+"/total_interest_payments", interest)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+weekPath+"/total_interest_payments", interest)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+dayPath+"/total_interest_payments", interest)

		dataErrors = applyToNodeValue(ctx, *dbClient, productsPath+"/"+productType+"/total_interest_payments", interest)
		dataErrors = applyToNodeValue(ctx, *dbClient, salesPath+"/total_interest_payments", interest)

		// principal
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+yearPath+"/total_principal_payments", principal)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+monthPath+"/total_principal_payments", principal)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+weekPath+"/total_principal_payments", principal)
		dataErrors = applyToNodeValue(ctx, *dbClient, totalSummaryPath+"/"+dayPath+"/total_principal_payments", principal)

		dataErrors = applyToNodeValue(ctx, *dbClient, productsPath+"/"+productType+"/total_principal_payments", principal)
		dataErrors = applyToNodeValue(ctx, *dbClient, salesPath+"/total_principal_payments", principal)

		dataErrors = addReportDataItem(ctx, *dbClient, basePath, timeNow, collectedAmount, interest, principal, productType, "collection", "", loanId)
	}

	return dataErrors
}
