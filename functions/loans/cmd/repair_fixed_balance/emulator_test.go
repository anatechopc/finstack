//go:build emulator

// Integration proofs for the repair tool against the Firestore emulator,
// through the real adapters:
//
//	cd apps/loans && firebase emulators:start --only firestore --project demo-finstack
//	cd functions/loans && FIRESTORE_EMULATOR_HOST=localhost:8081 \
//	  go test -tags emulator ./cmd/repair_fixed_balance/ -run Emulator -v
//
// They skip without FIRESTORE_EMULATOR_HOST (never-touch-prod). CI does not
// start emulators, so CI does not run them.
package main

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"regexp"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
)

// seed writes one G1 loan (10,000 at 5% for 3 months) with its first row
// stored as before the fix (3,655.82) under prefix.
func seed(t *testing.T, store *firestore.Client, prefix, id string) {
	t.Helper()
	ctx := context.Background()
	if _, err := store.Collection(prefix+"loans").Doc(id).Set(ctx, map[string]any{
		"amount": 10000, "additional_charges": 0, "deductions": 0, "period": 3, "deleted_at": nil,
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Collection(prefix+"loan_schedules").Doc(id+"-r1").Set(ctx, map[string]any{
		"loan_id": id, "status": "paid_on_time", "due_at": int64(1797120000000), "is_open_term": false,
		"principal_payment": 3172.09, "extra_payment": 0.004353687551429175,
		"outstanding_balance": 3655.824353687551, "updated_at": int64(1797120000000), "deleted_at": nil,
	}); err != nil {
		t.Fatal(err)
	}
}

func newEmulator(t *testing.T) *firestore.Client {
	t.Helper()
	if os.Getenv("FIRESTORE_EMULATOR_HOST") == "" {
		t.Skip("set FIRESTORE_EMULATOR_HOST=localhost:8081 to run the emulator proofs")
	}
	t.Setenv("ENVIRONMENT", "") // connect() sets it from -env; restored after
	store, err := firestore.NewClient(context.Background(), emulatorProject)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.Close() })
	return store
}

func balance(t *testing.T, store *firestore.Client, collection, id string) float64 {
	t.Helper()
	snap, err := store.Collection(collection).Doc(id).Get(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	return num(snap.Data()["outstanding_balance"])
}

func runTool(t *testing.T, opts options, wrap func(deps) deps) (string, error) {
	t.Helper()
	var out bytes.Buffer
	d, closeClient, err := connect(context.Background(), opts, &out)
	if err != nil {
		t.Fatal(err)
	}
	defer closeClient()
	if wrap != nil {
		d = wrap(d)
	}
	err = run(context.Background(), opts, d, &out)
	return out.String(), err
}

func TestEmulatorDryRunThenApplyOnDevOnly(t *testing.T) {
	store := newEmulator(t)
	id := fmt.Sprintf("it%d", time.Now().UnixNano())
	seed(t, store, "dev_", id)
	seed(t, store, "stg_", id)

	out, err := runTool(t, options{env: "dev", by: "emulator-test"}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out, "affected: loan "+id+" row "+id+"-r1 due 2026-12-13 principal 3172.09: stored 3655.82, correct 6827.91") {
		t.Fatalf("dry run output:\n%s", out)
	}
	if got := balance(t, store, "dev_loan_schedules", id+"-r1"); !near(got, 3655.82) {
		t.Fatalf("the dry run wrote %v", got)
	}

	out, err = runTool(t, options{env: "dev", apply: true, by: "emulator-test"}, nil)
	if err != nil {
		t.Fatalf("%v\n%s", err, out)
	}
	if got := balance(t, store, "dev_loan_schedules", id+"-r1"); !near(got, 6827.91) {
		t.Errorf("dev balance after apply = %v, want 6,827.91", got)
	}
	if got := balance(t, store, "stg_loan_schedules", id+"-r1"); !near(got, 3655.82) {
		t.Errorf("stg balance = %v; -env dev must not touch stg_", got)
	}
	runId := regexp.MustCompile(`run (\S+): wrote`).FindStringSubmatch(out)
	if runId == nil {
		t.Fatalf("no run id in:\n%s", out)
	}
	marker, err := store.Collection("dev_repair_runs").Doc(runId[1]).Get(context.Background())
	if err != nil {
		t.Fatalf("run marker: %v\n%s", err, out)
	}
	if marker.Data()["applied"] != true || marker.Data()["issue"] != "finstack#140" {
		t.Errorf("marker = %v", marker.Data())
	}
	row, _ := store.Collection("dev_loan_schedules").Doc(id + "-r1").Get(context.Background())
	if row.Data()["updated_at"] != int64(1797120000000) {
		t.Errorf("updated_at = %v, want it left as it was", row.Data()["updated_at"])
	}

	// A second apply finds nothing left on this loan.
	out, err = runTool(t, options{env: "dev", by: "emulator-test"}, nil)
	if err != nil || strings.Contains(out, "loan "+id+" ") {
		t.Errorf("after the apply: %v\n%s", err, out)
	}
}

func TestEmulatorARowChangedAfterTheReadIsNotWritten(t *testing.T) {
	store := newEmulator(t)
	id := fmt.Sprintf("it%d", time.Now().UnixNano())
	seed(t, store, "stg_", id)

	out, err := runTool(t, options{env: "stg", apply: true, by: "emulator-test"}, func(d deps) deps {
		rewrite := d.rewrite
		d.rewrite = func(ctx context.Context, f fix) error {
			if f.rowId == id+"-r1" {
				// A payment lands between the read and the write.
				if _, err := store.Collection("stg_loan_schedules").Doc(f.rowId).Update(ctx,
					[]firestore.Update{{Path: "status", Value: "paid_late"}}); err != nil {
					t.Fatal(err)
				}
			}
			return rewrite(ctx, f)
		}
		return d
	})

	if err == nil || !strings.Contains(out, "not written: row "+id+"-r1") {
		t.Fatalf("err %v, output:\n%s", err, out)
	}
	if got := balance(t, store, "stg_loan_schedules", id+"-r1"); !near(got, 3655.82) {
		t.Errorf("balance = %v, want the row left as it was", got)
	}
}
