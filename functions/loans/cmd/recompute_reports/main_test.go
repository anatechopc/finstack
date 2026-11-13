package main

import (
	"bytes"
	"context"
	"reflect"
	"strconv"
	"strings"
	"testing"
	"time"

	"com.loooans.app/triggers"
)

var fixedNow = time.Date(2026, 11, 13, 4, 5, 6, 0, time.UTC)

// fakeBackend stands in for Firestore and the Realtime Database. Its ETag is
// a version counter, so a write between the tool's read and its write is
// refused the way the database refuses a stale ETag.
type fakeBackend struct {
	input    triggers.RecomputeInput
	summary  map[string]any
	version  int
	claims   map[string]triggers.ClaimRecord
	replaced int
	markers  map[string]map[string]any
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
			if etag != strconv.Itoa(f.version) {
				return false, nil
			}
			f.summary, f.version, f.replaced = summary, f.version+1, f.replaced+1
			return true, nil
		},
		mark: func(_ context.Context, runId string, marker map[string]any) error {
			if f.markers == nil {
				f.markers = map[string]map[string]any{}
			}
			f.markers[runId] = marker
			return nil
		},
		now: func() time.Time { return fixedNow },
	}
}

// oneLoanAndCapital: one approved loan of 10000 and 50000 of capital.
func oneLoanAndCapital() triggers.RecomputeInput {
	created := time.Date(2026, 9, 9, 10, 30, 0, 0, time.UTC).UnixMilli()
	return triggers.RecomputeInput{
		Loans:        []map[string]any{{"id": "L1", "status": "approved", "amount": 10000.0, "created_at": created, "updated_at": created}},
		Capital:      []map[string]any{{"id": "K1", "amount": 50000.0, "created_at": created}},
		ProductTypes: map[string]string{"L1": "business"},
	}
}

// pollutedSummary is the live node after campaign D1: the release booked
// three times, with three data items, and the capital item missing.
func pollutedSummary() map[string]any {
	return map[string]any{
		"sales":         map[string]any{"total_amount_released": 30000.0},
		"products":      map[string]any{"business": map[string]any{"total_amount_released": 30000.0}},
		"capital_usage": map[string]any{"total_capital": 50000.0},
		"data":          map[string]any{"a": map[string]any{"amount": 10000.0}, "b": map[string]any{"amount": 10000.0}, "c": map[string]any{"amount": 10000.0}},
	}
}

func runOnce(t *testing.T, backend *fakeBackend, opts options) (string, error) {
	t.Helper()
	var out bytes.Buffer
	err := run(context.Background(), opts, backend.deps(), &out)
	return out.String(), err
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
		{"no company", options{env: "dev"}, "-company is required"},
		{"company that is a path", options{company: "C1/report_summary", env: "dev"}, "-company is required"},
		{"no env", options{company: "C1"}, "-env must be"},
		{"unknown env", options{company: "C1", env: "production"}, "-env must be"},
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

func TestRun_DryRun_PrintsTheDifferenceAndWritesNothing(t *testing.T) {
	backend := &fakeBackend{input: oneLoanAndCapital(), summary: pollutedSummary()}
	out, err := runOnce(t, backend, options{company: "C1", env: "dev"})
	if err != nil {
		t.Fatal(err)
	}
	if backend.replaced != 0 || len(backend.markers) != 0 || !reflect.DeepEqual(backend.summary, pollutedSummary()) {
		t.Fatalf("a dry run wrote: %d replaces, %d markers", backend.replaced, len(backend.markers))
	}
	columns := strings.Join(strings.Fields(out), " ") // column padding collapsed
	for _, want := range []string{
		"source: 1 loans (1 released), 0 schedules (0 paid), 1 capital (1 counted), 0 dropped",
		// recomputed, live, live minus recomputed
		"sales/total_amount_released 10000.00 30000.00 20000.00",
		"capital_usage/total_capital 50000.00 50000.00 0.00",
		"all-time totals: 2 of 3 differ by 0.005 or more",
		// The period buckets exist only in the recompute: all four differ.
		"total_summary/year:2026:month:9:week:37:day:9/total_amount_released 10000.00 0.00 -10000.00",
		"period totals (total_summary): 4 of 4 differ by 0.005 or more",
		"data items: recomputed 2, live 3",
		"live differs from the recomputed summary",
		"dry run: nothing written",
	} {
		if !strings.Contains(columns, want) {
			t.Errorf("output lacks %q:\n%s", want, out)
		}
	}
}

// Tool-level idempotency: after an apply the live node IS the recompute, so a
// second dry run reports zero difference and a second apply writes nothing.
func TestRun_Apply_WritesTheRecomputedSummaryOnce(t *testing.T) {
	backend := &fakeBackend{input: oneLoanAndCapital(), summary: pollutedSummary()}
	opts := options{company: "C1", env: "dev", apply: true, by: "tester@host"}
	out, err := runOnce(t, backend, opts)
	if err != nil {
		t.Fatal(err)
	}

	want := normalize(triggers.RecomputeReport(oneLoanAndCapital()).Plan.SummaryNode())
	if !reflect.DeepEqual(backend.summary, want) || backend.replaced != 1 {
		t.Fatalf("live after apply (%d replaces):\n got %v\nwant %v", backend.replaced, backend.summary, want)
	}
	marker := backend.markers["20261113T040506Z"]
	if marker == nil {
		t.Fatalf("no run marker under the run id; markers: %v\n%s", backend.markers, out)
	}
	before, after := marker["before"].(map[string]any), marker["after"].(map[string]any)
	if marker["by"] != "tester@host" || marker["at"] != fixedNow.UnixMilli() ||
		before["sales"].(map[string]any)["total_amount_released"] != 30000.0 ||
		after["sales"].(map[string]any)["total_amount_released"] != 10000.0 {
		t.Errorf("marker: %v", marker)
	}
	if _, ok := before["data"]; ok {
		t.Error("the marker must not copy the data list")
	}

	out, err = runOnce(t, backend, options{company: "C1", env: "dev"})
	if err != nil || !strings.Contains(out, "live equals the recomputed summary: zero difference") ||
		!strings.Contains(out, "all-time totals: 0 of 3 differ") || !strings.Contains(out, "period totals (total_summary): 0 of 4 differ") {
		t.Fatalf("second dry run must show zero difference (err %v):\n%s", err, out)
	}
	out, err = runOnce(t, backend, opts)
	if err != nil || backend.replaced != 1 || len(backend.markers) != 1 || !strings.Contains(out, "apply: nothing to write") {
		t.Fatalf("second apply must write nothing (err %v, %d replaces, %d markers):\n%s", err, backend.replaced, len(backend.markers), out)
	}
}

func TestRun_Apply_Refuses(t *testing.T) {
	opts := options{company: "C1", env: "dev", apply: true, by: "tester@host"}
	untouched := func(t *testing.T, backend *fakeBackend, err error, want string) {
		t.Helper()
		if err == nil || !strings.Contains(err.Error(), want) {
			t.Fatalf("got %v, want an error containing %q", err, want)
		}
		if backend.replaced != 0 || len(backend.markers) != 0 {
			t.Fatalf("a refused apply wrote: %d replaces, %d markers", backend.replaced, len(backend.markers))
		}
	}

	t.Run("no documents: a wrong company id must not delete the live summary", func(t *testing.T) {
		backend := &fakeBackend{summary: pollutedSummary()}
		_, err := runOnce(t, backend, opts)
		untouched(t, backend, err, "no documents found for company C1")
	})

	t.Run("an event claimed and not applied within the retry window", func(t *testing.T) {
		backend := &fakeBackend{input: oneLoanAndCapital(), summary: pollutedSummary(), claims: map[string]triggers.ClaimRecord{
			"done":  {Applied: true},
			"fresh": {ClaimedAt: fixedNow.Add(-time.Hour).UnixMilli()},
		}}
		out, err := runOnce(t, backend, opts)
		untouched(t, backend, err, "1 event(s) were claimed by a trigger and not applied")
		if !strings.Contains(out, "claims: 2 recorded, 1 not applied (1 of them younger than 7 days)") {
			t.Errorf("output:\n%s", out)
		}
	})

	t.Run("a trigger writes during the run: the conditional write is refused", func(t *testing.T) {
		backend := &fakeBackend{input: oneLoanAndCapital(), summary: pollutedSummary()}
		backend.duringSource = func() { backend.version++ }
		_, err := runOnce(t, backend, opts)
		untouched(t, backend, err, "a trigger changed the live summary during this run")
	})
}

// A claim older than the retry window is a delivery the platform gave up on:
// recompute covers its document, so it does not block.
func TestRun_Apply_AllowsClaimsThePlatformNoLongerRetries(t *testing.T) {
	backend := &fakeBackend{input: oneLoanAndCapital(), summary: pollutedSummary(), claims: map[string]triggers.ClaimRecord{
		"abandoned": {ClaimedAt: fixedNow.Add(-8 * 24 * time.Hour).UnixMilli()},
	}}
	if _, err := runOnce(t, backend, options{company: "C1", env: "dev", apply: true, by: "tester@host"}); err != nil || backend.replaced != 1 {
		t.Fatalf("err %v, %d replaces; want the apply to go through", err, backend.replaced)
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
