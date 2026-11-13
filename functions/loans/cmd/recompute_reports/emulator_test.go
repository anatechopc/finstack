//go:build emulator

// Integration proofs for the recompute tool against the Firestore and
// Realtime Database emulators, through the real adapters:
//
//	cd apps/loans && firebase emulators:start --only database,firestore --project demo-finstack
//	cd functions/loans && FIRESTORE_EMULATOR_HOST=localhost:8081 \
//	  FIREBASE_DATABASE_EMULATOR_HOST='localhost:9000?ns=demo-finstack' \
//	  go test -tags emulator ./cmd/recompute_reports/ -run Emulator -v
//
// They skip without both emulator variables (never-touch-prod).
package main

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"os"
	"reflect"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/db"

	"com.loooans.app/triggers"
)

// emulatorCompany is one seeded company: documents in the Firestore emulator
// (dev_ collections), product types, a polluted live summary and one applied
// event claim in the Realtime Database emulator.
type emulatorCompany struct {
	id       string
	base     string // dev/companies/{id}
	database *db.Client
	input    triggers.RecomputeInput // the documents as seeded
}

func seedEmulatorCompany(t *testing.T) *emulatorCompany {
	t.Helper()
	if os.Getenv("FIRESTORE_EMULATOR_HOST") == "" || os.Getenv("FIREBASE_DATABASE_EMULATOR_HOST") == "" {
		t.Skip("set FIRESTORE_EMULATOR_HOST=localhost:8081 and FIREBASE_DATABASE_EMULATOR_HOST='localhost:9000?ns=demo-finstack' to run the emulator proofs")
	}
	// connect() derives prefixes from ENVIRONMENT; registering it here restores
	// the caller's value after the test.
	t.Setenv("ENVIRONMENT", "development")
	ctx := context.Background()

	app, err := firebase.NewApp(ctx, &firebase.Config{DatabaseURL: "https://demo-finstack.firebaseio.com"})
	if err != nil {
		t.Fatal(err)
	}
	database, err := app.Database(ctx)
	if err != nil {
		t.Fatal(err)
	}
	store, err := firestore.NewClient(ctx, emulatorProject)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.Close() })

	id := fmt.Sprintf("it%d", time.Now().UnixNano())
	company := &emulatorCompany{id: id, base: "dev/companies/" + id, database: database}
	day := func(month time.Month, d int) int64 {
		return time.Date(2026, month, d, 10, 30, 0, 0, time.UTC).UnixMilli()
	}
	l1, l2 := id+"-L1", id+"-L2"

	company.input = triggers.RecomputeInput{
		ProductTypes: map[string]string{l1: "business", l2: "personal"},
		Loans: []map[string]any{
			{"id": l1, "company_id": id, "status": "paid_on_time", "amount": 10000.0, "created_at": day(9, 2), "updated_at": day(9, 9)},
			{"id": l2, "company_id": id, "status": "completed", "amount": int64(20000), "additional_charges": 500.5, "deductions": 200.0,
				"additional_charge_upfront_collection": 100.0, "created_at": day(9, 3), "updated_at": day(10, 5)},
		},
		Schedules: []map[string]any{
			{"id": id + "-S1", "company_id": id, "loan_id": l1, "status": "approved", "principal_payment": 10000.0, "interest_payment": 0.0, "created_at": day(9, 2)},
			{"id": id + "-S2", "company_id": id, "loan_id": l1, "status": "paid_on_time", "principal_payment": 1234.56, "interest_payment": 78.9,
				"collected_at": day(9, 9), "paid_at": day(9, 9), "created_at": day(9, 9)},
			{"id": id + "-S3", "company_id": id, "loan_id": l2, "status": "paid_late", "principal_payment": 0.1, "extra_payment": 0.2, "interest_payment": 0.3,
				"paid_at": day(9, 20), "created_at": day(9, 20)},
		},
		Capital: []map[string]any{
			{"id": id + "-K1", "provider_id": id, "amount": 50000.0, "created_at": day(9, 1)},
		},
	}
	write := func(collection string, docs []map[string]any) {
		for _, doc := range docs {
			if _, err := store.Collection("dev_"+collection).Doc(doc["id"].(string)).Set(ctx, doc); err != nil {
				t.Fatalf("seed %s: %v", collection, err)
			}
		}
	}
	write("loans", company.input.Loans)
	write("loan_schedules", company.input.Schedules)
	write("capital", company.input.Capital)
	// Another company's documents must not be read.
	write("loans", []map[string]any{{"id": id + "-other", "company_id": id + "-other", "status": "approved", "amount": 99999.0, "created_at": day(9, 2)}})
	write("capital", []map[string]any{{"id": id + "-otherK", "provider_id": id + "-other", "amount": 99999.0, "created_at": day(9, 2)}})

	seed := map[string]any{
		"loans": map[string]any{l1 + ":product_type": "business", l2 + ":product_type": "personal"},
		// Polluted the way campaign D1 polluted it: the first release booked three times.
		"report_summary": map[string]any{
			"sales": map[string]any{"total_amount_released": 50000.0},
			"data":  map[string]any{"stale": map[string]any{"amount": 10000.0, "data_type": "release"}},
		},
		"report_events": map[string]any{"e1": map[string]any{"applied": true, "applied_at": day(9, 2)}},
	}
	if err := database.NewRef(company.base).Set(ctx, seed); err != nil {
		t.Fatalf("seed realtime database: %v", err)
	}
	return company
}

func (c *emulatorCompany) node(t *testing.T, child string) map[string]any {
	t.Helper()
	var node map[string]any
	if err := c.database.NewRef(c.base+child).Get(context.Background(), &node); err != nil {
		t.Fatalf("read %s%s: %v", c.base, child, err)
	}
	return node
}

// run goes through connect(), the wiring main uses.
func (c *emulatorCompany) run(t *testing.T, apply bool, wrap func(*deps)) (string, error) {
	t.Helper()
	opts := options{company: c.id, env: "dev", apply: apply, by: "emulator-test"}
	d, closeClients, err := connect(context.Background(), opts, io.Discard)
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	defer closeClients()
	if wrap != nil {
		wrap(&d)
	}
	var out bytes.Buffer
	err = run(context.Background(), opts, d, &out)
	return out.String(), err
}

func TestEmulator_DryRunWritesNothing_ApplyWritesExactlyTheRecomputedNode(t *testing.T) {
	company := seedEmulatorCompany(t)
	seeded := company.node(t, "")

	// Dry run: the whole company node is untouched.
	out, err := company.run(t, false, nil)
	if err != nil {
		t.Fatalf("dry run: %v\n%s", err, out)
	}
	if after := company.node(t, ""); !reflect.DeepEqual(after, seeded) {
		t.Fatalf("the dry run wrote to the database:\n got %v\nwant %v", after, seeded)
	}
	columns := strings.Join(strings.Fields(out), " ")
	for _, want := range []string{
		"source: 2 loans (2 released), 3 schedules (2 paid), 1 capital (1 counted), 0 dropped",
		"sales/total_amount_released 30000.00 50000.00 20000.00", // live is 20000 over
		"claims: 1 recorded, 0 not applied",
		"live differs from the recomputed summary",
		"dry run: nothing written",
	} {
		if !strings.Contains(columns, want) {
			t.Errorf("dry run output lacks %q:\n%s", want, out)
		}
	}

	// Apply: report_summary is exactly the recompute of the seeded documents,
	// computed here from the fixture and not from what the reader returned.
	if out, err = company.run(t, true, nil); err != nil {
		t.Fatalf("apply: %v\n%s", err, out)
	}
	want := normalize(triggers.RecomputeReport(company.input).Plan.SummaryNode())
	got := company.node(t, "/report_summary")
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("report_summary after apply:\n got %v\nwant %v", got, want)
	}
	// Hand-derived: L2 settles for 20000 + 500.5 - 200 - 100 - (0.1 + 0.2).
	sales := got["sales"].(map[string]any)
	// Variables, not constants: the sum must be float64 arithmetic in the order
	// the bookings are added, and it must survive the database round trip exactly.
	p2, i2, p3, e3, i3 := 1234.56, 78.9, 0.1, 0.2, 0.3
	wantCollections := (p2 + i2) + (p3 + i3) + (20200.5 - (p3 + e3))
	if sales["total_amount_released"] != 30000.0 || sales["total_collections"] != wantCollections {
		t.Errorf("sales: got %v, want 30000 released and %v collected", sales, wantCollections)
	}

	// Nothing else under the company changed, and exactly one run is recorded.
	after := company.node(t, "")
	if !reflect.DeepEqual(after["loans"], seeded["loans"]) || !reflect.DeepEqual(after["report_events"], seeded["report_events"]) {
		t.Errorf("apply changed loans or report_events: %v", after)
	}
	if len(after) != 4 {
		t.Errorf("company node children: %v, want loans, report_events, report_summary, report_recomputes", keysOf(after))
	}
	markers := after["report_recomputes"].(map[string]any)
	if len(markers) != 1 {
		t.Fatalf("%d run markers, want 1", len(markers))
	}
	for _, value := range markers {
		marker := value.(map[string]any)
		before := marker["before"].(map[string]any)
		if marker["by"] != "emulator-test" || marker["at"] == nil ||
			before["sales"].(map[string]any)["total_amount_released"] != 50000.0 ||
			!reflect.DeepEqual(marker["after"], withoutData(want)) || before["data"] != nil {
			t.Errorf("run marker: %v", marker)
		}
	}

	// Verification: a second dry run shows zero difference; a second apply
	// writes nothing.
	out, err = company.run(t, false, nil)
	if err != nil || !strings.Contains(out, "live equals the recomputed summary: zero difference") || !strings.Contains(out, "all-time totals: 0 of") {
		t.Fatalf("second dry run (err %v):\n%s", err, out)
	}
	out, err = company.run(t, true, nil)
	if err != nil || !strings.Contains(out, "apply: nothing to write") {
		t.Fatalf("second apply (err %v):\n%s", err, out)
	}
	if final := company.node(t, ""); !reflect.DeepEqual(final, after) {
		t.Fatal("the second apply wrote to the database")
	}
}

// The race with a live trigger: a trigger applies an event through the real
// report store after the tool read the live summary. The conditional write
// is refused, the trigger's increment survives, and no run is recorded.
func TestEmulator_Apply_IsRefusedWhenATriggerWritesDuringTheRun(t *testing.T) {
	company := seedEmulatorCompany(t)
	eventTime := time.Date(2026, 11, 13, 1, 0, 0, 0, time.UTC)
	plan := triggers.PlanCapitalReport(triggers.CapitalReportInput{Amount: 777, CapitalId: "late", Now: eventTime})

	out, err := company.run(t, true, func(d *deps) {
		source := d.source
		d.source = func(ctx context.Context) (triggers.RecomputeInput, error) {
			if err := triggers.NewRTDBReportStore(company.database).Apply(ctx, company.base, "late-event", eventTime, plan); err != nil {
				t.Errorf("trigger apply: %v", err)
			}
			return source(ctx)
		}
	})
	if err == nil || !strings.Contains(err.Error(), "a trigger changed the live summary during this run") {
		t.Fatalf("got %v, want the conditional write refused\n%s", err, out)
	}
	after := company.node(t, "")
	summary := after["report_summary"].(map[string]any)
	if summary["capital_usage"].(map[string]any)["total_capital"] != 777.0 || summary["sales"].(map[string]any)["total_amount_released"] != 50000.0 {
		t.Errorf("the live summary was replaced: %v", summary)
	}
	if after["report_recomputes"] != nil {
		t.Errorf("a refused apply recorded a run: %v", after["report_recomputes"])
	}
}

func keysOf(node map[string]any) []string {
	keys := make([]string, 0, len(node))
	for key := range node {
		keys = append(keys, key)
	}
	return keys
}
