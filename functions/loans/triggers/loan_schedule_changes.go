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

// LoanScheduleChanges books a collection when a loan_schedule document is
// created in a paid or submitted state.
//
// Deployed on google.cloud.firestore.document.v1.created for
// {prefix}loan_schedules/{uid}: it fires once per document. Each event id is
// still claimed before the atomic write so a redelivery cannot double count
// (see docs/superpowers/specs/2026-09-09-report-triggers-rebuild.md).
func LoanScheduleChanges(ctx context.Context, ev event.Event) error {
	log, logErr := utils.InitializeLogger("loan_schedule_changes")
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

	scheduleEvent := ScheduleCreatedEvent{EventId: ev.ID()}
	var ok bool
	if scheduleEvent.CompanyId, ok = stringField(fields, "company_id"); !ok {
		return fmt.Errorf("no company_id for loan schedule: %s", name)
	}
	if scheduleEvent.Status, ok = stringField(fields, "status"); !ok {
		return fmt.Errorf("no status for loan schedule: %s", name)
	}
	if scheduleEvent.LoanId, ok = stringField(fields, "loan_id"); !ok {
		return fmt.Errorf("no loan_id for loan schedule: %s", name)
	}
	if scheduleEvent.Interest, ok = numberField(fields, "interest_payment"); !ok {
		return fmt.Errorf("no interest_payment for loan schedule: %s", name)
	}
	if scheduleEvent.Principal, ok = numberField(fields, "principal_payment"); !ok {
		return fmt.Errorf("no principal_payment for loan schedule: %s", name)
	}

	if !isCollectionStatus(scheduleEvent.Status) {
		// Nothing to book; skip the Firebase setup entirely.
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

	_, err = HandleScheduleCreatedCore(ctx, utils.GetMinifiedEnv(), scheduleEvent, ReportDeps{
		Store:   NewRTDBReportStore(dbClient),
		Now:     time.Now,
		LogInfo: func(format string, args ...any) { log.Info(fmt.Sprintf(format, args...)) },
	})
	if err != nil {
		log.Error("report: " + err.Error())
	}
	return err
}
