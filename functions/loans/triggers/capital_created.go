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

// CapitalCreated books added capital when a capital document is created.
//
// Deployed on google.cloud.firestore.document.v1.created for
// {prefix}capital/{uid}. Each event id is claimed before the atomic write so a
// redelivery cannot double count
// (see docs/superpowers/specs/2026-09-09-report-triggers-rebuild.md).
func CapitalCreated(ctx context.Context, ev event.Event) error {
	log, logErr := utils.InitializeLogger("capital_created")
	if logErr != nil {
		return logErr
	}

	var data firestoredata.DocumentEventData
	if err := proto.Unmarshal(ev.Data(), &data); err != nil {
		return fmt.Errorf("proto.Unmarshal: %w", err)
	}
	log.Debug(fmt.Sprintf("Function triggered by change to: %v", ev.Source()))

	if data.GetValue() == nil {
		return errors.New("no value for newly created doc")
	}
	fields := data.GetValue().GetFields()
	name := data.GetValue().GetName()

	capitalEvent := CapitalCreatedEvent{EventId: ev.ID()}
	var ok bool
	if capitalEvent.CompanyId, ok = stringField(fields, "provider_id"); !ok {
		return fmt.Errorf("no provider_id for capital: %s", name)
	}
	if capitalEvent.CapitalId, ok = stringField(fields, "id"); !ok {
		return fmt.Errorf("no id for capital: %s", name)
	}
	if capitalEvent.Amount, ok = numberField(fields, "amount"); !ok {
		return fmt.Errorf("no amount for capital: %s", name)
	}

	app, err := utils.InitializeFirebase(ctx)
	if err != nil {
		return err
	}
	dbClient, err := app.Database(ctx)
	if err != nil {
		return err
	}

	_, err = HandleCapitalCreatedCore(ctx, utils.GetMinifiedEnv(), capitalEvent, ReportDeps{
		Store:   NewRTDBReportStore(dbClient),
		Now:     time.Now,
		LogInfo: func(format string, args ...any) { log.Info(fmt.Sprintf(format, args...)) },
	})
	if err != nil {
		log.Error("report: " + err.Error())
	}
	return err
}
