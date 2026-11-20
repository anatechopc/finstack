package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"time"

	"cloud.google.com/go/firestore"
	"com.loooans.app/utils"
	"google.golang.org/api/option"
)

// targets maps -env to the ENVIRONMENT value the deployed functions run with
// and to the Firebase project that hosts it. ENVIRONMENT selects the
// Firestore collection prefix through utils, as it does for the triggers.
var targets = map[string]struct{ environment, project string }{
	"dev":  {"development", "loooans-dev-stg"},
	"stg":  {"staging", "loooans-dev-stg"},
	"prod": {"production", "loooans-prod"},
}

// emulatorProject is the project id the repo's emulator commands use.
const emulatorProject = "demo-finstack"

// connect wires Firestore (or its emulator) and prints what it is pointed at.
func connect(ctx context.Context, opts options, out io.Writer) (deps, func(), error) {
	target := targets[opts.env]
	if current := os.Getenv("ENVIRONMENT"); current != "" && current != target.environment {
		return deps{}, nil, fmt.Errorf("ENVIRONMENT=%s is set but -env %s means %s; unset it or make them agree", current, opts.env, target.environment)
	}
	if err := os.Setenv("ENVIRONMENT", target.environment); err != nil {
		return deps{}, nil, err
	}

	project, where := target.project, "project "+target.project
	var clientOpts []option.ClientOption
	if os.Getenv("FIRESTORE_EMULATOR_HOST") != "" {
		project, where = emulatorProject, "EMULATOR (project "+emulatorProject+")"
	} else {
		// User credentials carry a quota project of their own; pin it.
		clientOpts = append(clientOpts, option.WithQuotaProject(project))
	}
	store, err := firestore.NewClient(ctx, project, clientOpts...)
	if err != nil {
		return deps{}, nil, fmt.Errorf("firestore client for %s: %w", project, err)
	}

	prefix := utils.GetCollectionPrefix()
	mode := "DRY RUN (no writes)"
	if opts.apply {
		mode = "APPLY"
	}
	fmt.Fprintf(out, "fixed-term balance repair (#140), %s: %s, Firestore %sloans / %sloan_schedules, marker %srepair_runs\n",
		mode, where, prefix, prefix, prefix)

	return deps{
		load: func(ctx context.Context) ([]doc, []doc, error) {
			loans, err := all(ctx, store, prefix+"loans")
			if err != nil {
				return nil, nil, err
			}
			rows, err := all(ctx, store, prefix+"loan_schedules")
			return loans, rows, err
		},
		rewrite: func(ctx context.Context, f fix) error {
			_, err := store.Collection(prefix+"loan_schedules").Doc(f.rowId).Update(ctx,
				[]firestore.Update{{Path: "outstanding_balance", Value: f.correct}},
				firestore.LastUpdateTime(f.updated))
			return err
		},
		mark: func(ctx context.Context, runId string, fields map[string]any) error {
			_, err := store.Collection(prefix+"repair_runs").Doc(runId).Set(ctx, fields, firestore.MergeAll)
			return err
		},
		now: time.Now,
	}, func() { store.Close() }, nil
}

// all reads every document of a collection.
// ponytail: one unpaged read per collection; page by document id (see
// cmd/backfill_search_tokens eachDocument) when a collection outgrows memory.
func all(ctx context.Context, store *firestore.Client, collection string) ([]doc, error) {
	snaps, err := store.Collection(collection).Documents(ctx).GetAll()
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", collection, err)
	}
	docs := make([]doc, 0, len(snaps))
	for _, s := range snaps {
		docs = append(docs, doc{id: s.Ref.ID, data: s.Data(), updated: s.UpdateTime})
	}
	return docs, nil
}
