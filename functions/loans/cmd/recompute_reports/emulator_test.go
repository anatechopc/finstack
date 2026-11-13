//go:build emulator

// Integration proofs for the recompute tool against the Firestore and
// Realtime Database emulators, through the real adapters:
//
//	cd apps/loans && firebase emulators:start --only database,firestore --project demo-finstack
//	cd functions/loans && FIRESTORE_EMULATOR_HOST=localhost:8081 \
//	  FIREBASE_DATABASE_EMULATOR_HOST='localhost:9000?ns=demo-finstack' \
//	  go test -tags emulator ./cmd/recompute_reports/ -run Emulator -v
//
// They skip without both emulator variables (never-touch-prod). CI does not
// start emulators, so CI does not run them.
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

// emulatorNames is the oracle for what each -env must read and write. The
// names are spelled out here on purpose: the code under test derives them.
var emulatorNames = map[string]struct{ environment, prefix, root string }{
	"dev":  {"development", "dev_", "dev/"},
	"stg":  {"staging", "stg_", "stg/"},
	"prod": {"production", "", ""},
}

// emulatorCompany is one company in the emulators, under one environment's
// names.
type emulatorCompany struct {
	t        *testing.T
	id, env  string
	prefix   string // Firestore collection prefix
	base     string // Realtime Database node of the company
	database *db.Client
	store    *firestore.Client
	runs     int
}

func newEmulatorCompany(t *testing.T, env string) *emulatorCompany {
	t.Helper()
	if os.Getenv("FIRESTORE_EMULATOR_HOST") == "" || os.Getenv("FIREBASE_DATABASE_EMULATOR_HOST") == "" {
		t.Skip("set FIRESTORE_EMULATOR_HOST=localhost:8081 and FIREBASE_DATABASE_EMULATOR_HOST='localhost:9000?ns=demo-finstack' to run the emulator proofs")
	}
	names := emulatorNames[env]
	// connect() derives every name from ENVIRONMENT; registering it here
	// restores the caller's value after the test.
	t.Setenv("ENVIRONMENT", names.environment)
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
	return &emulatorCompany{t: t, id: id, env: env, prefix: names.prefix, base: names.root + "companies/" + id, database: database, store: store}
}

func (c *emulatorCompany) writeDocs(collection string, docs []map[string]any) {
	c.t.Helper()
	for _, doc := range docs {
		if _, err := c.store.Collection(c.prefix+collection).Doc(doc["id"].(string)).Set(context.Background(), doc); err != nil {
			c.t.Fatalf("seed %s: %v", collection, err)
		}
	}
}

func (c *emulatorCompany) writeNode(node map[string]any) {
	c.t.Helper()
	if err := c.database.NewRef(c.base).Set(context.Background(), node); err != nil {
		c.t.Fatalf("seed realtime database: %v", err)
	}
}

func (c *emulatorCompany) node(child string) map[string]any {
	c.t.Helper()
	var node map[string]any
	if err := c.database.NewRef(c.base+child).Get(context.Background(), &node); err != nil {
		c.t.Fatalf("read %s%s: %v", c.base, child, err)
	}
	return node
}

// run goes through connect(), the wiring main uses. Each run is a minute
// after the previous one, so each gets its own run id.
func (c *emulatorCompany) run(opts options, wrap func(*deps)) (string, error) {
	c.t.Helper()
	opts.company, opts.env, opts.by = c.id, c.env, "emulator-test"
	if opts.env == "prod" {
		opts.confirmProd = c.id
	}
	if err := checkOptions(opts); err != nil {
		return "", err
	}
	d, closeClients, err := connect(context.Background(), opts, io.Discard)
	if err != nil {
		c.t.Fatalf("connect: %v", err)
	}
	defer closeClients()
	d.now = func() time.Time {
		c.runs++
		return time.Date(2026, 11, 13, 0, c.runs, 0, 0, time.UTC)
	}
	if wrap != nil {
		wrap(&d)
	}
	var out bytes.Buffer
	err = run(context.Background(), opts, d, &out)
	return out.String(), err
}

func day(month time.Month, d int) int64 {
	return time.Date(2026, month, d, 10, 30, 0, 0, time.UTC).UnixMilli()
}

// pollutedLive is a live summary polluted the way campaign D1 polluted it.
func pollutedLive() map[string]any {
	return map[string]any{
		"sales": map[string]any{"total_amount_released": 50000.0},
		"data":  map[string]any{"stale": map[string]any{"amount": 10000.0, "data_type": "release"}},
	}
}

// seedStandard writes the usual company: an active loan with a confirmed
// payment and a pending submission, a settled loan whose paid row carries
// another company's id, capital, and documents that must not be read. It
// returns the documents the recompute is expected to use.
func (c *emulatorCompany) seedStandard() triggers.RecomputeInput {
	id, l1, l2 := c.id, c.id+"-L1", c.id+"-L2"
	input := triggers.RecomputeInput{
		Company:      id,
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
			// A row of this company's loan that carries another company's id:
			// found because rows are read by loan, counted and reported.
			{"id": id + "-S3", "company_id": id + "-other", "loan_id": l2, "status": "paid_late", "principal_payment": 0.1, "extra_payment": 0.2, "interest_payment": 0.3,
				"paid_at": day(9, 20), "created_at": day(9, 20)},
			// A borrower submission nobody confirmed: not counted.
			{"id": id + "-S4", "company_id": id, "loan_id": l1, "status": "payment_submitted", "principal_payment": 500.0, "interest_payment": 5.0, "created_at": day(9, 25)},
		},
		Capital: []map[string]any{
			{"id": id + "-K1", "provider_id": id, "amount": 50000.0, "created_at": day(9, 1)},
		},
	}
	c.writeDocs("loans", input.Loans)
	c.writeDocs("loan_schedules", input.Schedules)
	c.writeDocs("capital", input.Capital)
	// Not this company's: another company's loan and capital, and a row that
	// names this company but belongs to the other company's loan.
	c.writeDocs("loans", []map[string]any{{"id": id + "-foreign", "company_id": id + "-other", "status": "approved", "amount": 99999.0, "created_at": day(9, 2)}})
	c.writeDocs("capital", []map[string]any{{"id": id + "-foreignK", "provider_id": id + "-other", "amount": 99999.0, "created_at": day(9, 2)}})
	c.writeDocs("loan_schedules", []map[string]any{{"id": id + "-foreignS", "company_id": id, "loan_id": id + "-foreign", "status": "paid_on_time",
		"principal_payment": 99999.0, "interest_payment": 1.0, "paid_at": day(9, 2)}})

	c.writeNode(map[string]any{
		"loans":          map[string]any{l1 + ":product_type": "business", l2 + ":product_type": "personal"},
		"report_summary": pollutedLive(),
		"report_events":  map[string]any{"e1": map[string]any{"applied": true, "applied_at": day(9, 2)}},
	})
	return input
}

// Under each environment's own names: a dry run writes nothing; an apply
// saves the node as it was and writes exactly the recompute; a second dry run
// shows zero difference; a restore puts the saved node back.
func TestEmulator_DryRunWritesNothing_ApplyWritesExactlyTheRecomputedNode(t *testing.T) {
	for env := range emulatorNames {
		t.Run(env, func(t *testing.T) {
			company := newEmulatorCompany(t, env)
			input := company.seedStandard()
			seeded := company.node("")

			// Dry run: the whole company node is untouched.
			out, err := company.run(options{loans: true}, nil)
			if err != nil {
				t.Fatalf("dry run: %v\n%s", err, out)
			}
			if after := company.node(""); !reflect.DeepEqual(after, seeded) {
				t.Fatalf("the dry run wrote to the database:\n got %v\nwant %v", after, seeded)
			}
			expectOutput(t, out,
				"source: 2 loans (2 released), 4 schedules (2 paid, 1 pending submissions), 1 capital (1 counted), 0 dropped",
				"pending submission, not counted: schedule "+company.id+"-S4 of loan "+company.id+"-L1: principal 500.00, interest 5.00",
				`counted, but its company_id is not this company: schedule `+company.id+`-S3 of loan `+company.id+`-L2: company_id "`+company.id+`-other"`,
				company.id+"-L1 paid_on_time 10000.00 10000.00 0.00 1234.56 78.90 0.00 0.00",
				"sales/total_amount_released 30000.00 50000.00 20000.00", // live is 20000 over
				"claims: 1 recorded, 0 not applied",
				"live differs from the recomputed summary",
				"dry run: nothing written",
			)

			// Apply: report_summary is exactly the recompute of the seeded
			// documents, computed here from the fixture and not from what the
			// reader returned.
			if out, err = company.run(options{apply: true}, nil); err != nil {
				t.Fatalf("apply: %v\n%s", err, out)
			}
			want := normalize(triggers.RecomputeReport(input).Plan.SummaryNode())
			got := company.node("/report_summary")
			if !reflect.DeepEqual(got, want) {
				t.Fatalf("report_summary after apply:\n got %v\nwant %v", got, want)
			}
			// Hand-derived: L2 settles for 20000 + 500.5 - 200 - 100 - (0.1 + 0.2).
			// Variables, not constants: the sum must be float64 arithmetic in the
			// order the bookings are added, and survive the round trip exactly.
			sales := got["sales"].(map[string]any)
			p2, i2, p3, e3, i3 := 1234.56, 78.9, 0.1, 0.2, 0.3
			wantCollections := (p2 + i2) + (p3 + i3) + (20200.5 - (p3 + e3))
			if sales["total_amount_released"] != 30000.0 || sales["total_collections"] != wantCollections {
				t.Errorf("sales: got %v, want 30000 released and %v collected", sales, wantCollections)
			}

			// Nothing else under the company changed, and the one run record
			// holds the complete node as it was.
			after := company.node("")
			if !reflect.DeepEqual(after["loans"], seeded["loans"]) || !reflect.DeepEqual(after["report_events"], seeded["report_events"]) {
				t.Errorf("apply changed loans or report_events: %v", after)
			}
			if len(after) != 4 {
				t.Errorf("company node children: %v, want loans, report_events, report_summary, report_recomputes", keysOf(after))
			}
			const applyRun = "20261113T000200Z" // the second run
			records := after["report_recomputes"].(map[string]any)
			record, _ := records[applyRun].(map[string]any)
			if len(records) != 1 || record == nil {
				t.Fatalf("run records: %v, want one under %s", keysOf(records), applyRun)
			}
			if !reflect.DeepEqual(record["previous"], seeded["report_summary"]) {
				t.Errorf("the saved copy is not the node as it was:\n got %v\nwant %v", record["previous"], seeded["report_summary"])
			}
			if record["by"] != "emulator-test" || record["applied"] != true || !reflect.DeepEqual(record["after"], withoutData(want)) {
				t.Errorf("run record: %v", record)
			}

			// Verification: a second dry run shows zero difference; a second
			// apply writes nothing.
			out, err = company.run(options{}, nil)
			if err != nil {
				t.Fatal(err)
			}
			expectOutput(t, out, "live equals the recomputed summary: zero difference", "all-time totals: 0 of")
			out, err = company.run(options{apply: true}, nil)
			if err != nil {
				t.Fatal(err)
			}
			expectOutput(t, out, "apply: nothing to write")
			if final := company.node(""); !reflect.DeepEqual(final, after) {
				t.Fatal("the second apply wrote to the database")
			}

			// Rollback: the saved node goes back, and that is a recorded run too.
			if out, err = company.run(options{apply: true, restore: applyRun}, nil); err != nil {
				t.Fatalf("restore: %v\n%s", err, out)
			}
			restored := company.node("")
			if !reflect.DeepEqual(restored["report_summary"], seeded["report_summary"]) {
				t.Fatalf("report_summary after the restore:\n got %v\nwant %v", restored["report_summary"], seeded["report_summary"])
			}
			if records := restored["report_recomputes"].(map[string]any); len(records) != 2 {
				t.Errorf("run records after the restore: %v, want 2", keysOf(records))
			}
		})
	}
}

// The review's probe: the company's only loan is approved and has no
// product-type node, so the recompute is empty. An apply used to replace the
// live summary with nothing. It is refused and nothing changes.
func TestEmulator_Apply_IsRefusedWhenADocumentWasDropped(t *testing.T) {
	company := newEmulatorCompany(t, "dev")
	company.writeDocs("loans", []map[string]any{
		{"id": company.id + "-L1", "company_id": company.id, "status": "approved", "amount": 10000.0, "created_at": day(9, 2), "updated_at": day(9, 2)},
	})
	company.writeNode(map[string]any{"report_summary": pollutedLive()})
	seeded := company.node("")

	out, err := company.run(options{apply: true}, nil)
	if err == nil || !strings.Contains(err.Error(), "the recompute is empty") || !strings.Contains(err.Error(), "1 document(s) were dropped") {
		t.Fatalf("got %v, want the apply refused\n%s", err, out)
	}
	expectOutput(t, out, "dropped: loan "+company.id+"-L1: no product type")
	if after := company.node(""); !reflect.DeepEqual(after, seeded) {
		t.Fatalf("a refused apply changed the company node:\n got %v\nwant %v", after, seeded)
	}
}

// The race with a live trigger: a trigger applies an event through the real
// report store after the tool read the live summary. The conditional write
// is refused, the trigger's increment survives, and the run record says the
// run was not applied.
func TestEmulator_Apply_IsRefusedWhenATriggerWritesDuringTheRun(t *testing.T) {
	company := newEmulatorCompany(t, "dev")
	company.seedStandard()
	eventTime := time.Date(2026, 11, 13, 1, 0, 0, 0, time.UTC)
	plan := triggers.PlanCapitalReport(triggers.CapitalReportInput{Amount: 777, CapitalId: "late", Now: eventTime})

	out, err := company.run(options{apply: true}, func(d *deps) {
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
	after := company.node("")
	summary := after["report_summary"].(map[string]any)
	if summary["capital_usage"].(map[string]any)["total_capital"] != 777.0 || summary["sales"].(map[string]any)["total_amount_released"] != 50000.0 {
		t.Errorf("the live summary was replaced: %v", summary)
	}
	records, _ := after["report_recomputes"].(map[string]any)
	record, _ := records["20261113T000100Z"].(map[string]any)
	if len(records) != 1 || record["applied"] != false || record["outcome"] != "not applied: the live summary changed during the run" {
		t.Errorf("run records: %v", records)
	}
}

func keysOf(node map[string]any) []string {
	keys := make([]string, 0, len(node))
	for key := range node {
		keys = append(keys, key)
	}
	return keys
}
