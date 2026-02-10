package triggers

import (
	"com.loooans.app/utils"
	"context"
	"errors"
	"fmt"
	"github.com/cloudevents/sdk-go/v2/event"
	"github.com/golang/protobuf/proto"
	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
	"time"
)

// CapitalCreated
//
//	function to run firestore trigger for collection
//		collection: capital/
//	this trigger will create a Realtime DB data for reports
//
// /**
func CapitalCreated(ctx context.Context, event event.Event) error {
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
	var amount float64
	var id string

	if cId, ok := data.GetValue().GetFields()["provider_id"]; ok {
		companyId = cId.GetStringValue()
	} else {
		return errors.New(fmt.Sprintf("No provider_id for capital: %s", data.GetValue().GetName()))
	}

	if value, ok := data.GetValue().GetFields()["id"]; ok {
		id = value.GetStringValue()
	} else {
		return errors.New(fmt.Sprintf("No id for capital: %s", data.GetValue().GetName()))
	}

	if value, ok := data.GetValue().GetFields()["amount"]; ok {
		if integerValue, isInteger := value.GetValueType().(*firestoredata.Value_IntegerValue); isInteger {
			amount = float64(integerValue.IntegerValue)
		} else {
			amount = value.GetDoubleValue()
		}
	} else {
		return errors.New(fmt.Sprintf("No amount for capital: %s", data.GetValue().GetName()))
	}

	app, errFirebaseAdmin := utils.InitializeFirebase(ctx)

	if errFirebaseAdmin != nil {
		return errFirebaseAdmin
	}

	dbClient, errDbClient := app.Database(ctx)

	if errDbClient != nil {
		return errDbClient
	}

	pathEnv := utils.GetMinifiedEnv()

	timeNow := time.Now().UTC()

	basePath := pathEnv + "/companies/" + companyId

	_, _, _, capitalUsagePath := getReportPaths(basePath)

	var dataErrors error = nil

	dataErrors = applyToNodeValue(ctx, *dbClient, capitalUsagePath+"/total_capital", amount)

	dataErrors = addReportDataItem(ctx, *dbClient, basePath, timeNow, amount, 0, 0, "", "add_capital", id, "")

	return dataErrors
}
