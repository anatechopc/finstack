package main

import (
	"bytes"
	"context"
	"errors"
	"reflect"
	"strconv"
	"strings"
	"testing"
	"time"

	"com.loooans.app/triggers"
)

var fixedNow = time.Date(2026, 11, 13, 4, 5, 6, 0, time.UTC)

const firstRunId = "20261113T040506Z"

// fakeBackend stands in for Firestore and the Realtime Database. Its ETag is
// a version counter, so a write between the tool's read and its write is
// refused the way the database refuses a stale ETag.
type fakeBackend struct {
	input   triggers.RecomputeInput
	summary map[string]any
	version int
	claims  map[string]triggers.ClaimRecord
	records map[string]map[string]any // report_recomputes
	calls   []string                  // writes, in order: "mark" and "replace"
	markErr error
	runs    int // each run is a minute after the previous one
	// duringSource runs while the tool reads the documents: a trigger firing
	// in the middle of a run.
	duringSource func()
}

func (f *fakeBackend) deps() deps {
	return deps{
		live: func(context.Context) (map[string]any, string, map[string]triggers.ClaimRecord, error) {
			return f.summary, strconv.Itoa(f.version), f.claims, nil
		},
		source: func(context.Context) (triggers.RecomputeInput, error) {
			if f.duringSource != nil {
				f.duringSource()
			}
			return f.input, nil
		},
		replace: func(_ context.Context, etag string, summary map[string]any) (bool, error) {
			f.calls = append(f.calls, "replace")
			if etag != strconv.Itoa(f.version) {
				return false, nil
			}
			f.summary, f.version = summary, f.version+1
			return true, nil
		},
		mark: func(_ context.Context, runId string, fields map[string]any) error {
			if f.markErr != nil {
				return f.markErr
			}
			f.calls = append(f.calls, "mark")
			if f.records == nil {
				f.records = map[string]map[string]any{}
			}
			if f.records[runId] == nil {
				f.records[runId] = map[string]any{}
			}
			for key, value := range fields {
				f.records[runId][key] = value
			}
			return nil
		},
		record: func(_ context.Context, runId string) (map[string]any, error) {
			return f.records[runId], nil
		},
		now: func() time.Time {
			f.runs++
			return fixedNow.Add(time.Duration(f.runs-1) * time.Minute)
		},
	}
}

// oneLoanAndCapital: one approved loan of 10000 and 50000 of capital.
func oneLoanAndCapital() triggers.RecomputeInput {
	created := time.Date(2026, 9, 9, 10, 30, 0, 0, time.UTC).UnixMilli()
	return triggers.RecomputeInput{
		Company:      "C1",
		Loans:        []map[string]any{{"id": "L1", "status": "approved", "amount": 10000.0, "created_at": created, "updated_at": created}},
		Capital:      []map[string]any{{"id": "K1", "amount": 50000.0, "created_at": created}},
		ProductTypes: map[string]string{"L1": "business"},
	}
}

// pollutedSummary is the live node after campaign D1: the release booked
// three times, with three data items, and the capital item missing. One more
// release belongs to a loan Firestore no longer has.
func pollutedSummary() map[string]any {
	release := func(loanId string, amount float64) map[string]any {
		return map[string]any{"data_type": "release", "loan_id": loanId, "amount": amount}
	}
	return map[string]any{
		"sales":         map[string]any{"total_amount_released": 30500.0},
		"products":      map[string]any{"business": map[string]any{"total_amount_released": 30500.0}},
		"capital_usage": map[string]any{"total_capital": 50000.0},
		"data":          map[string]any{"a": release("L1", 10000), "b": release("L1", 10000), "c": release("L1", 10000), "d": release("GONE", 500)},
	}
}

func runOnce(t *testing.T, backend *fakeBackend, opts options) (string, error) {
	t.Helper()
	var out bytes.Buffer
	err := run(context.Background(), opts, backend.deps(), &out)
	return out.String(), err
}

// columns collapses the padding of the printed tables.
func columns(out string) string { return strings.Join(strings.Fields(out), " ") }

func expectOutput(t *testing.T, out string, wants ...string) {
	t.Helper()
	for _, want := range wants {
		if !strings.Contains(columns(out), want) {
			t.Errorf("output lacks %q:\n%s", want, out)
		}
	}
}

func TestCheckOptions(t *testing.T) {
	cases := []struct {
		name    string
		opts    options
		wantErr string
	}{
		{"dry run on dev", options{company: "C1", env: "dev"}, ""},
		{"dry run on prod needs no confirmation", options{company: "C1", env: "prod"}, ""},
		{"apply on dev", options{company: "C1", env: "dev", apply: true, by: "me"}, ""},
		{"apply on prod, confirmed", options{company: "C1", env: "prod", apply: true, confirmProd: "C1", by: "me"}, ""},
		{"apply on prod without confirmation", options{company: "C1", env: "prod", apply: true, by: "me"}, "-confirm-prod C1"},
		{"apply on prod confirming another company", options{company: "C1", env: "prod", apply: true, confirmProd: "C2", by: "me"}, "-confirm-prod C1"},
		{"restore on prod without confirmation", options{company: "C1", env: "prod", apply: true, restore: firstRunId, by: "me"}, "-confirm-prod C1"},
		{"no company", options{env: "dev"}, "-company is required"},
		{"company that is a path", options{company: "C1/report_summary", env: "dev"}, "-company is required"},
		{"no env", options{company: "C1"}, "-env must be"},
		{"unknown env", options{company: "C1", env: "production"}, "-env must be"},
		{"restore that is a path", options{company: "C1", env: "dev", restore: "../report_summary"}, "-restore must be a run id"},
		{"apply without an operator", options{company: "C1", env: "dev", apply: true}, "-by must name"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := checkOptions(tc.opts)
			switch {
			case tc.wantErr == "" && err != nil:
				t.Fatalf("refused: %v", err)
			case tc.wantErr != "" && (err == nil || !strings.Contains(err.Error(), tc.wantErr)):
				t.Fatalf("got %v, want an error containing %q", err, tc.wantErr)
			}
		})
	}
}

// connect refuses, before creating any client, the two setups that would read
// one place and write another.
func TestConnect_RefusesAMismatchedEnvironmentAndMixingLocalWithRealDatabases(t *testing.T) {
	opts := options{company: "C1", env: "dev"}

	t.Setenv("ENVIRONMENT", "production") // left over from another shell
	if _, _, err := connect(context.Background(), opts, &bytes.Buffer{}); err == nil || !strings.Contains(err.Error(), "ENVIRONMENT=production is set but -env dev") {
		t.Fatalf("mismatched ENVIRONMENT: got %v", err)
	}

	t.Setenv("ENVIRONMENT", "development")
	t.Setenv("FIRESTORE_EMULATOR_HOST", "localhost:8081")
	t.Setenv("FIREBASE_DATABASE_EMULATOR_HOST", "")
	if _, _, err := connect(context.Background(), opts, &bytes.Buffer{}); err == nil || !strings.Contains(err.Error(), "set both") {
		t.Fatalf("Firestore emulator with the real database: got %v", err)
	}
	t.Setenv("FIRESTORE_EMULATOR_HOST", "")
	t.Setenv("FIREBASE_DATABASE_EMULATOR_HOST", "localhost:9000?ns=demo-finstack")
	if _, _, err := connect(context.Background(), opts, &bytes.Buffer{}); err == nil || !strings.Contains(err.Error(), "set both") {
		t.Fatalf("database emulator with the real Firestore: got %v", err)
	}
}

// Each -env has its own collection prefix and database root; none is
// hardcoded. No request is sent: the clients connect on first use.
func TestConnect_NamesTheCollectionsAndTheRootOfEachEnvironment(t *testing.T) {
	t.Setenv("FIRESTORE_EMULATOR_HOST", "localhost:1")
	t.Setenv("FIREBASE_DATABASE_EMULATOR_HOST", "localhost:1?ns=demo-finstack")
	cases := []struct{ env, environment, want string }{
		{"dev", "development", "Firestore dev_loans / dev_loan_schedules / dev_capital, Realtime Database dev/companies/C1\n"},
		{"stg", "staging", "Firestore stg_loans / stg_loan_schedules / stg_capital, Realtime Database stg/companies/C1\n"},
		{"prod", "production", "Firestore loans / loan_schedules / capital, Realtime Database /companies/C1\n"},
	}
	for _, tc := range cases {
		t.Run(tc.env, func(t *testing.T) {
			t.Setenv("ENVIRONMENT", tc.environment)
			var out bytes.Buffer
			_, closeClients, err := connect(context.Background(), options{company: "C1", env: tc.env}, &out)
			if err != nil {
				t.Fatal(err)
			}
			closeClients()
			if !strings.HasSuffix(out.String(), tc.want) {
				t.Fatalf("got %q, want it to end with %q", out.String(), tc.want)
			}
		})
	}
}

func TestRun_DryRun_PrintsTheDifferenceAndWritesNothing(t *testing.T) {
	backend := &fakeBackend{input: oneLoanAndCapital(), summary: pollutedSummary()}
	out, err := runOnce(t, backend, options{company: "C1", env: "dev"})
	if err != nil {
		t.Fatal(err)
	}
	if len(backend.calls) != 0 || len(backend.records) != 0 || !reflect.DeepEqual(backend.summary, pollutedSummary()) {
		t.Fatalf("a dry run wrote: %v", backend.calls)
	}
	expectOutput(t, out,
		"source: 1 loans (1 released), 0 schedules (0 paid, 0 pending submissions), 1 capital (1 counted), 0 dropped",
		// recomputed, live, live minus recomputed
		"sales/total_amount_released 10000.00 30500.00 20500.00",
		"capital_usage/total_capital 50000.00 50000.00 0.00",
		"all-time totals: 2 of 3 differ by 0.005 or more",
		// The period buckets exist only in the recompute: all four differ.
		"total_summary/year:2026:month:9:week:37:day:9/total_amount_released 10000.00 0.00 -10000.00",
		"period totals (total_summary): 4 of 4 differ by 0.005 or more",
		"data items: recomputed 2, live 4",
		"live differs from the recomputed summary",
		"dry run: nothing written",
	)
	if strings.Contains(out, "live_released") {
		t.Errorf("the per-loan table is printed only with -loans:\n%s", out)
	}
}

// -loans: one line per loan with what was booked and what the live data list
// released for it, and one line per live release whose loan is gone.
func TestRun_Loans_PrintsOneLinePerLoanBesideTheLiveReleases(t *testing.T) {
	input := oneLoanAndCapital()
	input.Loans = append(input.Loans, map[string]any{"id": "L2", "status": "pending", "amount": 700.0})
	backend := &fakeBackend{input: input, summary: pollutedSummary()}
	out, err := runOnce(t, backend, options{company: "C1", env: "dev", loans: true})
	if err != nil {
		t.Fatal(err)
	}
	expectOutput(t, out,
		"loan status amount released live_released paid_principal interest remainder bad_debt note",
		"L1 approved 10000.00 10000.00 30000.00 0.00 0.00 0.00 0.00",
		"L2 pending 700.00 0.00 0.00 0.00 0.00 0.00 0.00 not released",
		"GONE (no document) 0.00 500.00 released in the live data list only",
	)
}

func TestRun_ListsPendingSubmissionsAndRowsOfAnotherCompany(t *testing.T) {
	input := oneLoanAndCapital()
	paid := time.Date(2026, 9, 20, 0, 0, 0, 0, time.UTC).UnixMilli()
	input.Schedules = []map[string]any{
		{"id": "S1", "loan_id": "L1", "company_id": "C1", "status": "payment_submitted", "principal_payment": 10000.0, "interest_payment": 300.0},
		{"id": "S2", "loan_id": "L1", "company_id": "C2", "status": "paid_on_time", "principal_payment": 100.0, "interest_payment": 10.0, "paid_at": paid},
	}
	out, err := runOnce(t, &fakeBackend{input: input}, options{company: "C1", env: "dev"})
	if err != nil {
		t.Fatal(err)
	}
	expectOutput(t, out,
		"source: 1 loans (1 released), 2 schedules (1 paid, 1 pending submissions), 1 capital (1 counted), 0 dropped",
		"pending submission, not counted: schedule S1 of loan L1: principal 10000.00, interest 300.00",
		`counted, but its company_id is not this company: schedule S2 of loan L1: company_id "C2"`,
		"sales/total_collections 110.00 0.00 -110.00",
	)
}

// An apply saves the complete previous node before it writes, and tool-level
// idempotency: after it the live node IS the recompute, so a second dry run
// reports zero difference and a second apply writes nothing.
func TestRun_Apply_SavesThePreviousNodeThenWritesTheRecomputedSummaryOnce(t *testing.T) {
	backend := &fakeBackend{input: oneLoanAndCapital(), summary: pollutedSummary()}
	opts := options{company: "C1", env: "dev", apply: true, by: "tester@host"}
	out, err := runOnce(t, backend, opts)
	if err != nil {
		t.Fatal(err)
	}

	want := normalize(triggers.RecomputeReport(oneLoanAndCapital()).Plan.SummaryNode())
	if !reflect.DeepEqual(backend.summary, want) {
		t.Fatalf("live after apply:\n got %v\nwant %v", backend.summary, want)
	}
	// The copy is saved first; the record is marked applied only afterwards.
	if !reflect.DeepEqual(backend.calls, []string{"mark", "replace", "mark"}) {
		t.Fatalf("writes in order: %v", backend.calls)
	}
	record := backend.records[firstRunId]
	if record == nil {
		t.Fatalf("no record under the run id; records: %v\n%s", backend.records, out)
	}
	if !reflect.DeepEqual(record["previous"], pollutedSummary()) {
		t.Errorf("the saved copy is not the node as it was, data list included:\n got %v\nwant %v", record["previous"], pollutedSummary())
	}
	after := record["after"].(map[string]any)
	if record["by"] != "tester@host" || record["at"] != fixedNow.UnixMilli() || record["applied"] != true ||
		after["sales"].(map[string]any)["total_amount_released"] != 10000.0 || after["data"] != nil {
		t.Errorf("record: %v", record)
	}
	expectOutput(t, out, "the previous node is saved at report_recomputes/"+firstRunId, "undo: -restore "+firstRunId)

	out, err = runOnce(t, backend, options{company: "C1", env: "dev"})
	if err != nil {
		t.Fatal(err)
	}
	expectOutput(t, out, "live equals the recomputed summary: zero difference", "all-time totals: 0 of 3 differ", "period totals (total_summary): 0 of 4 differ")

	out, err = runOnce(t, backend, opts)
	if err != nil || len(backend.calls) != 3 || len(backend.records) != 1 {
		t.Fatalf("second apply must write nothing (err %v, writes %v)", err, backend.calls)
	}
	expectOutput(t, out, "apply: nothing to write")
}

// Rollback: -restore writes the node a run saved back, itself recorded and
// itself undoable.
func TestRun_Restore_WritesTheSavedNodeBack(t *testing.T) {
	backend := &fakeBackend{input: oneLoanAndCapital(), summary: pollutedSummary()}
	apply := options{company: "C1", env: "dev", apply: true, by: "tester@host"}
	if _, err := runOnce(t, backend, apply); err != nil {
		t.Fatal(err)
	}
	recomputed := backend.summary

	restore := options{company: "C1", env: "dev", restore: firstRunId, by: "tester@host"}
	out, err := runOnce(t, backend, restore)
	if err != nil || !reflect.DeepEqual(backend.summary, recomputed) {
		t.Fatalf("a restore without -apply is a dry run (err %v)", err)
	}
	expectOutput(t, out,
		"restore: the summary as it was before run "+firstRunId,
		"sales/total_amount_released 30500.00 10000.00 -20500.00", // saved, live
		"live differs from the saved summary",
		"dry run: nothing written",
	)

	restore.apply = true
	if _, err = runOnce(t, backend, restore); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(backend.summary, pollutedSummary()) {
		t.Fatalf("live after the restore is not the node the first run saved:\n got %v", backend.summary)
	}
	const restoreRunId = "20261113T040706Z" // the third run, two minutes later
	record := backend.records[restoreRunId]
	if record == nil || record["restores"] != firstRunId || record["applied"] != true || !reflect.DeepEqual(record["previous"], recomputed) {
		t.Errorf("restore record: %v (records %d)", record, len(backend.records))
	}

	restore.restore = "20200101T000000Z"
	if _, err = runOnce(t, backend, restore); err == nil || !strings.Contains(err.Error(), "no run 20200101T000000Z is recorded") {
		t.Fatalf("unknown run: got %v", err)
	}
}

func TestRun_Apply_Refuses(t *testing.T) {
	opts := options{company: "C1", env: "dev", apply: true, by: "tester@host"}
	refused := func(t *testing.T, backend *fakeBackend, err error, wants ...string) {
		t.Helper()
		for _, want := range wants {
			if err == nil || !strings.Contains(err.Error(), want) {
				t.Fatalf("got %v, want an error containing %q", err, want)
			}
		}
		if len(backend.calls) != 0 || len(backend.records) != 0 || !reflect.DeepEqual(backend.summary, pollutedSummary()) {
			t.Fatalf("a refused apply wrote: %v", backend.calls)
		}
	}

	// The review's probe: the only loan has no product-type node, so it is
	// dropped and the recompute is empty. Applying it would delete the node.
	t.Run("one approved loan without a product type, live summary present", func(t *testing.T) {
		input := oneLoanAndCapital()
		input.Capital, input.ProductTypes = nil, nil
		backend := &fakeBackend{input: input, summary: pollutedSummary()}
		out, err := runOnce(t, backend, opts)
		refused(t, backend, err, "the recompute is empty, so an apply would delete the live summary", "1 document(s) were dropped")
		expectOutput(t, out, "dropped: loan L1: no product type")
	})

	t.Run("any dropped document, even when the rest recomputes", func(t *testing.T) {
		input := oneLoanAndCapital()
		input.Loans = append(input.Loans, map[string]any{"id": "L2", "status": "approved", "created_at": int64(1)}) // no amount
		backend := &fakeBackend{input: input, summary: pollutedSummary()}
		out, err := runOnce(t, backend, opts)
		refused(t, backend, err, "1 document(s) were dropped (listed above), so the recompute is incomplete")
		expectOutput(t, out, "dropped: loan L2: no id, status or amount")

		opts := opts
		opts.apply = false
		out, err = runOnce(t, backend, opts)
		if err != nil {
			t.Fatal(err)
		}
		expectOutput(t, out, "an apply would be refused: 1 document(s) were dropped")
	})

	t.Run("no documents: a wrong company id must not delete the live summary", func(t *testing.T) {
		backend := &fakeBackend{summary: pollutedSummary()}
		_, err := runOnce(t, backend, opts)
		refused(t, backend, err, "the recompute is empty")
	})

	// The platform redelivers for up to 7 days: a claim one hour old and one
	// almost seven days old both block.
	for name, age := range map[string]time.Duration{"an hour ago": time.Hour, "almost seven days ago": 7*24*time.Hour - time.Minute} {
		t.Run("an event claimed "+name+" and not applied", func(t *testing.T) {
			backend := &fakeBackend{input: oneLoanAndCapital(), summary: pollutedSummary(), claims: map[string]triggers.ClaimRecord{
				"done":    {Applied: true},
				"pending": {ClaimedAt: fixedNow.Add(-age).UnixMilli()},
			}}
			out, err := runOnce(t, backend, opts)
			refused(t, backend, err, "1 event(s) were claimed by a trigger and not applied in the last 7 days")
			expectOutput(t, out, "claims: 2 recorded, 1 not applied (1 of them younger than 7 days)")
		})
	}

	t.Run("a run with the same id exists: its saved node must not be overwritten", func(t *testing.T) {
		saved := map[string]any{"previous": map[string]any{"kept": true}}
		backend := &fakeBackend{input: oneLoanAndCapital(), summary: pollutedSummary(), records: map[string]map[string]any{firstRunId: saved}}
		_, err := runOnce(t, backend, opts)
		if err == nil || !strings.Contains(err.Error(), "a run "+firstRunId+" is already recorded") {
			t.Fatalf("got %v", err)
		}
		if len(backend.calls) != 0 || !reflect.DeepEqual(backend.records[firstRunId], saved) || !reflect.DeepEqual(backend.summary, pollutedSummary()) {
			t.Fatalf("the existing record or the summary was touched: %v", backend.calls)
		}
	})

	t.Run("the previous node cannot be saved: nothing is replaced", func(t *testing.T) {
		backend := &fakeBackend{input: oneLoanAndCapital(), summary: pollutedSummary(), markErr: errors.New("permission denied")}
		_, err := runOnce(t, backend, opts)
		refused(t, backend, err, "nothing written: the previous summary could not be saved", "permission denied")
	})

	t.Run("a trigger writes during the run: the conditional write is refused", func(t *testing.T) {
		backend := &fakeBackend{input: oneLoanAndCapital(), summary: pollutedSummary()}
		backend.duringSource = func() { backend.version++ }
		_, err := runOnce(t, backend, opts)
		if err == nil || !strings.Contains(err.Error(), "a trigger changed the live summary during this run") {
			t.Fatalf("got %v", err)
		}
		record := backend.records[firstRunId]
		if !reflect.DeepEqual(backend.summary, pollutedSummary()) || record["applied"] != false ||
			record["outcome"] != "not applied: the live summary changed during the run" {
			t.Fatalf("the summary must be untouched and the record must say it was not applied: %v", record)
		}
	})
}

// A claim older than the retry window is a delivery the platform gave up on:
// recompute covers its document, so it does not block.
func TestRun_Apply_AllowsClaimsThePlatformNoLongerRetries(t *testing.T) {
	backend := &fakeBackend{input: oneLoanAndCapital(), summary: pollutedSummary(), claims: map[string]triggers.ClaimRecord{
		"abandoned": {ClaimedAt: fixedNow.Add(-7*24*time.Hour - time.Minute).UnixMilli()},
	}}
	if _, err := runOnce(t, backend, options{company: "C1", env: "dev", apply: true, by: "tester@host"}); err != nil || backend.records[firstRunId]["applied"] != true {
		t.Fatalf("err %v, record %v; want the apply to go through", err, backend.records[firstRunId])
	}
}

func TestCompare_ListsTotalsOfBothSidesAndLeavesTheDataListOut(t *testing.T) {
	recomputed := map[string]any{
		"sales": map[string]any{"total_collections": 100.0},
		"data":  map[string]any{"k": map[string]any{"amount": 100.0}},
	}
	live := map[string]any{
		"sales":      map[string]any{"total_collections": 100.004, "total_amount_released": 5.0},
		"data":       map[string]any{"k": map[string]any{"amount": 999.0}},
		"updated_at": "yesterday",
	}
	rows, strays := compare(recomputed, live)
	want := []totalRow{{"sales/total_amount_released", 0, 5}, {"sales/total_collections", 100, 100.004}}
	if !reflect.DeepEqual(rows, want) {
		t.Fatalf("rows: got %v, want %v", rows, want)
	}
	if rows[0].differs() == false || rows[1].differs() {
		t.Errorf("5 differs, 0.004 is below the tolerance: got %v and %v", rows[0].differs(), rows[1].differs())
	}
	if !reflect.DeepEqual(strays, []string{"updated_at"}) {
		t.Errorf("strays: %v", strays)
	}
}
