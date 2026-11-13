package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"com.loooans.app/triggers"
	"com.loooans.app/utils"
	"firebase.google.com/go/v4/db"
)

// targets maps -env to the ENVIRONMENT value the deployed functions run with
// and to the Firebase project that hosts it. ENVIRONMENT selects the
// Firestore collection prefix, the Realtime Database root and the database
// URL through utils, exactly as it does for the triggers.
var targets = map[string]struct{ environment, project string }{
	"dev":  {"development", "loooans-dev-stg"},
	"stg":  {"staging", "loooans-dev-stg"},
	"prod": {"production", "loooans-prod"},
}

// emulatorProject is the project id the repo's emulator commands use.
const emulatorProject = "demo-finstack"

// connect wires the real Firestore and Realtime Database (or both emulators)
// for one company and prints what it is pointed at.
func connect(ctx context.Context, opts options, out io.Writer) (deps, func(), error) {
	target := targets[opts.env]
	if current := os.Getenv("ENVIRONMENT"); current != "" && current != target.environment {
		return deps{}, nil, fmt.Errorf("ENVIRONMENT=%s is set but -env %s means %s; unset it or make them agree", current, opts.env, target.environment)
	}
	if err := os.Setenv("ENVIRONMENT", target.environment); err != nil {
		return deps{}, nil, err
	}

	// One emulator without the other would compare, or overwrite, a real
	// database with emulator data.
	firestoreEmulator := os.Getenv("FIRESTORE_EMULATOR_HOST") != ""
	databaseEmulator := os.Getenv("FIREBASE_DATABASE_EMULATOR_HOST") != ""
	if firestoreEmulator != databaseEmulator {
		return deps{}, nil, errors.New("set both FIRESTORE_EMULATOR_HOST and FIREBASE_DATABASE_EMULATOR_HOST, or neither")
	}
	project, where := target.project, "project "+target.project
	if firestoreEmulator {
		project, where = emulatorProject, "EMULATORS (project "+emulatorProject+")"
	}

	app, err := utils.InitializeFirebase(ctx)
	if err != nil {
		return deps{}, nil, err
	}
	database, err := app.Database(ctx)
	if err != nil {
		return deps{}, nil, fmt.Errorf("realtime database client: %w", err)
	}
	store, err := firestore.NewClient(ctx, project)
	if err != nil {
		return deps{}, nil, fmt.Errorf("firestore client for %s: %w", project, err)
	}

	prefix := utils.GetCollectionPrefix()
	base := utils.GetMinifiedEnv() + "/companies/" + opts.company
	mode := "DRY RUN (no writes)"
	if opts.apply {
		mode = "APPLY"
	}
	fmt.Fprintf(out, "report recompute, %s: %s, Firestore %sloans / %sloan_schedules / %scapital, Realtime Database %s\n",
		mode, where, prefix, prefix, prefix, base)

	return deps{
		live:    databaseLive(database, base),
		source:  firestoreSource(store, database, prefix, base, opts.company),
		replace: databaseReplace(database, base),
		mark:    databaseMark(database, base),
		record:  databaseRecord(database, base),
		now:     time.Now,
	}, func() { store.Close() }, nil
}

// firestoreSource reads the company's loans and capital, each loan's rows,
// and the product-type nodes the triggers read.
func firestoreSource(store *firestore.Client, database *db.Client, prefix, base, company string) func(context.Context) (triggers.RecomputeInput, error) {
	// ponytail: one unpaged stream per query; page by document id (see
	// cmd/backfill_search_tokens eachDocument) when a company outgrows it.
	all := func(ctx context.Context, collection, field, value string) ([]map[string]any, error) {
		docs, err := store.Collection(prefix+collection).Where(field, "==", value).Documents(ctx).GetAll()
		if err != nil {
			return nil, fmt.Errorf("%s%s where %s == %s: %w", prefix, collection, field, value, err)
		}
		out := make([]map[string]any, 0, len(docs))
		for _, doc := range docs {
			out = append(out, doc.Data())
		}
		return out, nil
	}
	return func(ctx context.Context) (triggers.RecomputeInput, error) {
		in := triggers.RecomputeInput{Company: company}
		var err error
		if in.Loans, err = all(ctx, "loans", "company_id", company); err != nil {
			return in, err
		}
		// Rows by loan_id, the query of the trigger's schedule loader
		// (firestoreScheduleLoader), not by the row's own company_id.
		// ponytail: one query per loan; batch with an `in` filter (30 ids per
		// query) when a company has thousands of loans.
		for _, loan := range in.Loans {
			loanId, _ := loan["id"].(string)
			if loanId == "" {
				continue
			}
			rows, err := all(ctx, "loan_schedules", "loan_id", loanId)
			if err != nil {
				return in, err
			}
			in.Schedules = append(in.Schedules, rows...)
		}
		if in.Capital, err = all(ctx, "capital", "provider_id", company); err != nil {
			return in, err
		}
		var nodes map[string]any
		if err := database.NewRef(base+"/loans").Get(ctx, &nodes); err != nil {
			return in, fmt.Errorf("read %s/loans: %w", base, err)
		}
		in.ProductTypes = map[string]string{}
		for key, value := range nodes {
			loanId, isPair := strings.CutSuffix(key, ":product_type")
			if productType, ok := value.(string); isPair && ok {
				in.ProductTypes[loanId] = productType
			}
		}
		return in, nil
	}
}

func databaseLive(database *db.Client, base string) func(context.Context) (map[string]any, string, map[string]triggers.ClaimRecord, error) {
	return func(ctx context.Context) (map[string]any, string, map[string]triggers.ClaimRecord, error) {
		var summary map[string]any
		etag, err := database.NewRef(base+"/report_summary").GetWithETag(ctx, &summary)
		if err != nil {
			return nil, "", nil, fmt.Errorf("read %s/report_summary: %w", base, err)
		}
		// ponytail: reads every claim ever recorded; query by claimed_at (needs
		// an .indexOn rule) when report_events grows large.
		var claims map[string]triggers.ClaimRecord
		if err := database.NewRef(base+"/report_events").Get(ctx, &claims); err != nil {
			return nil, "", nil, fmt.Errorf("read %s/report_events: %w", base, err)
		}
		return summary, etag, claims, nil
	}
}

// databaseReplace replaces the whole report_summary node in one conditional
// write: all of it lands or none of it, and none of it if the node changed
// since it was read.
func databaseReplace(database *db.Client, base string) func(context.Context, string, map[string]any) (bool, error) {
	return func(ctx context.Context, etag string, summary map[string]any) (bool, error) {
		return database.NewRef(base+"/report_summary").SetIfUnchanged(ctx, etag, summary)
	}
}

// databaseMark merges fields into a run record. Records live beside
// report_summary, like report_events, so the app, which streams
// report_summary in full, never downloads them.
func databaseMark(database *db.Client, base string) func(context.Context, string, map[string]any) error {
	return func(ctx context.Context, runId string, fields map[string]any) error {
		return database.NewRef(base+"/report_recomputes/"+runId).Update(ctx, fields)
	}
}

func databaseRecord(database *db.Client, base string) func(context.Context, string) (map[string]any, error) {
	return func(ctx context.Context, runId string) (map[string]any, error) {
		var record map[string]any
		err := database.NewRef(base+"/report_recomputes/"+runId).Get(ctx, &record)
		return record, err
	}
}
