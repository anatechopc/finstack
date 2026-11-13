// dev_reset empties the DEVELOPMENT environment so that fresh data can be
// created through the app. It works in two steps, so that what is deleted is
// always an explicit list a person can read first:
//
//	cd functions/loans
//	go run ./cmd/dev_reset -plan <new dir>      # read-only: writes plan.jsonl and summary.txt
//
//	# Back up what the plan covers. summary.txt ends with the collection ids.
//	# Use a bucket that Firebase Storage does not serve to app users.
//	gcloud firestore export gs://<bucket>/backups/<name> --collection-ids=<ids> --project loooans-dev-stg
//	firebase database:get /dev --project loooans-dev-stg --output <dir>/rtdb-dev.json
//
//	# Write <dir>/backup.txt with these four lines (restore commands may follow):
//	#   firestore_export: gs://<bucket>/backups/<name>
//	#   firestore_operation: projects/loooans-dev-stg/databases/(default)/operations/<id>
//	#   firestore_export_state: SUCCESSFUL
//	#   rtdb_backup: <dir>/rtdb-dev.json
//
//	go run ./cmd/dev_reset -apply <dir> -confirm dev    # deletes the listed paths, prints what remains
//
// A plan is valid for two hours and a plan directory is used once.
//
// It can only reach project loooans-dev-stg, root collections whose id starts
// with dev_, and Realtime Database paths under dev/. Those three are constants
// (rules.go); nothing on the command line or in the environment changes them.
// Staging shares the project, the Firestore database and the Auth user pool
// with dev, so the prefix is the only thing between this tool and staging data.
// Firebase Auth users and Cloud Storage files are never deleted.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"strings"
	"time"

	firebase "firebase.google.com/go/v4"
	"google.golang.org/api/iterator"
	"google.golang.org/api/option"
	"google.golang.org/api/transport"
)

func main() {
	planDir := flag.String("plan", "", "read dev and write plan.jsonl and summary.txt into this new `directory` (deletes nothing)")
	applyDir := flag.String("apply", "", "delete exactly the paths marked delete in this `directory`'s plan.jsonl")
	confirm := flag.String("confirm", "", "with -apply: must be the literal word dev")
	flag.Parse()
	if (*planDir == "") == (*applyDir == "") || flag.NArg() > 0 {
		fmt.Fprintln(os.Stderr, "usage: dev_reset -plan <new dir>   |   dev_reset -apply <dir> -confirm dev")
		os.Exit(2)
	}

	ctx := context.Background()
	t, err := realTarget(ctx)
	if err == nil && *planDir != "" {
		err = runPlan(ctx, t, *planDir, time.Now(), os.Stdout)
	} else if err == nil {
		err = runApply(ctx, t, *applyDir, *confirm, time.Now(), os.Stdout)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

// realTarget connects to the dev project with Application Default Credentials.
func realTarget(ctx context.Context) (target, error) {
	// A half-emulated run is dangerous: with only the Auth emulator set, the
	// uid list would be empty and every user document would be planned for
	// deletion.
	for _, name := range []string{"FIRESTORE_EMULATOR_HOST", "FIREBASE_DATABASE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST"} {
		if os.Getenv(name) != "" {
			return target{}, fmt.Errorf("refusing to run: %s is set; this tool only works on the real %s", name, projectID)
		}
	}
	// User credentials carry a quota project of their own; pin that too.
	quota := option.WithQuotaProject(projectID)
	creds, err := transport.Creds(ctx, quota, option.WithScopes("https://www.googleapis.com/auth/cloud-platform"))
	if err != nil {
		return target{}, fmt.Errorf("no Application Default Credentials (gcloud auth application-default login): %w", err)
	}
	if err := checkADCProject(creds.ProjectID, os.Getenv); err != nil {
		return target{}, err
	}

	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: projectID, DatabaseURL: databaseURL}, quota)
	if err != nil {
		return target{}, err
	}
	fs, err := app.Firestore(ctx)
	if err != nil {
		return target{}, err
	}
	rtdb, err := app.Database(ctx)
	if err != nil {
		return target{}, err
	}
	authClient, err := app.Auth(ctx)
	if err != nil {
		return target{}, err
	}
	return target{
		project: projectID,
		fs:      fs,
		rtdb:    rtdb,
		authUsers: func(ctx context.Context) (map[string]string, error) {
			users := map[string]string{}
			it := authClient.Users(ctx, "")
			for {
				u, err := it.Next()
				if err == iterator.Done {
					return users, nil
				}
				if err != nil {
					return nil, err
				}
				users[u.UID] = strings.ToLower(u.Email)
			}
		},
	}, nil
}
