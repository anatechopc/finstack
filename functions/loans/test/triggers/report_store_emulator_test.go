//go:build emulator

// Emulator-backed proofs for the report writers (campaign Phase 2):
//
//	cd apps/loans && firebase emulators:start --only database --project demo-finstack
//	cd functions/loans && FIREBASE_DATABASE_EMULATOR_HOST='localhost:9000?ns=demo-finstack' \
//	  CGO_ENABLED=0 go test -tags emulator ./test/triggers/ -run Emulator -v
//
// They refuse to run without the emulator variable (never-touch-prod).
package triggers_test

import (
	"context"
	"fmt"
	"os"
	"sync"
	"testing"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/db"

	"com.loooans.app/triggers"
)

func emulatorClient(t *testing.T) *db.Client {
	t.Helper()
	if os.Getenv("FIREBASE_DATABASE_EMULATOR_HOST") == "" {
		t.Skip("set FIREBASE_DATABASE_EMULATOR_HOST='localhost:9000?ns=demo-finstack' to run the emulator proofs")
	}
	// With the emulator variable set the SDK ignores this URL's host and talks
	// to the emulator with its own emulator token (no auth option needed).
	app, err := firebase.NewApp(context.Background(), &firebase.Config{DatabaseURL: "https://demo-finstack.firebaseio.com"})
	if err != nil {
		t.Fatalf("firebase app: %v", err)
	}
	client, err := app.Database(context.Background())
	if err != nil {
		t.Fatalf("database client: %v", err)
	}
	return client
}

// isolatedEnv returns a unique RTDB env prefix so runs never share nodes.
func isolatedEnv(t *testing.T) string {
	t.Helper()
	return fmt.Sprintf("test-%d", time.Now().UnixNano())
}

func readTotal(t *testing.T, client *db.Client, path string) float64 {
	t.Helper()
	var total float64
	if err := client.NewRef(path).Get(context.Background(), &total); err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return total
}

// Concurrency proof (D2): 50 concurrent applies of the full six-node release
// plan (plus its data item) through the atomic multi-path path all land.
func TestEmulator_Apply_ConcurrentMultiPathIncrements_LoseNothing(t *testing.T) {
	client := emulatorClient(t)
	store := triggers.NewRTDBReportStore(client)
	base := isolatedEnv(t) + "/companies/C1"
	plan, _ := triggers.PlanLoanReport(triggers.LoanReportInput{
		Status: "approved", OldStatus: "pending", Amount: 1, ProductType: "business", LoanId: "L1", Now: testNow,
	})

	var wg sync.WaitGroup
	for i := range 50 {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			if err := store.Apply(context.Background(), base, fmt.Sprintf("e%d", i), testNow, plan); err != nil {
				t.Errorf("apply: %v", err)
			}
		}(i)
	}
	wg.Wait()

	for _, path := range summaryPaths("total_amount_released", "business") {
		if got := readTotal(t, client, base+"/report_summary/"+path); got != 50 {
			t.Errorf("%s: got %v, want 50", path, got)
		}
	}
}

// The contrast: the old Get-then-Set loses updates under the same load. Logged,
// not asserted, because a lucky interleaving could land more than expected.
func TestEmulator_RacyGetSet_LosesUpdates(t *testing.T) {
	client := emulatorClient(t)
	ref := client.NewRef(isolatedEnv(t) + "/companies/C1/report_summary/sales/racy")

	var wg sync.WaitGroup
	for range 50 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			var value float64
			if err := ref.Get(context.Background(), &value); err != nil {
				t.Errorf("get: %v", err)
				return
			}
			if err := ref.Set(context.Background(), value+1); err != nil {
				t.Errorf("set: %v", err)
			}
		}()
	}
	wg.Wait()

	got := readTotal(t, client, ref.Path)
	t.Logf("racy Get/Set landed %v of 50 increments (the atomic path lands 50/50)", got)
	if got > 50 {
		t.Fatalf("impossible total %v", got)
	}
}

// Idempotency proof (D1): only one of several concurrent claims wins; the
// others see a fresh lease; after the apply the marker says applied.
func TestEmulator_ClaimEvent_OnlyOneDeliveryWins(t *testing.T) {
	client := emulatorClient(t)
	store := triggers.NewRTDBReportStore(client)
	base := isolatedEnv(t) + "/companies/C1"

	var wg sync.WaitGroup
	var mu sync.Mutex
	wins, inProgress := 0, 0
	for range 10 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			result, err := store.ClaimEvent(context.Background(), base, "e1", testNow)
			if err != nil {
				t.Errorf("claim: %v", err)
				return
			}
			mu.Lock()
			defer mu.Unlock()
			switch result {
			case triggers.ClaimWon:
				wins++
			case triggers.ClaimInProgress:
				inProgress++
			}
		}()
	}
	wg.Wait()
	if wins != 1 || inProgress != 9 {
		t.Fatalf("claims: %d won, %d in progress; want 1 and 9", wins, inProgress)
	}

	if err := store.Apply(context.Background(), base, "e1", testNow, triggers.ReportPlan{}); err != nil {
		t.Fatalf("apply: %v", err)
	}
	result, err := store.ClaimEvent(context.Background(), base, "e1", testNow.Add(time.Hour))
	if err != nil || result != triggers.ClaimApplied {
		t.Fatalf("after apply the claim must report applied: %v err=%v", result, err)
	}
}

// Double delivery through the real store: the same loan event twice books one release.
func TestEmulator_HandleLoanChange_DoubleDelivery_BooksOnce(t *testing.T) {
	client := emulatorClient(t)
	env := isolatedEnv(t)
	if err := client.NewRef(env+"/companies/C1/loans/L1:product_type").Set(context.Background(), "business"); err != nil {
		t.Fatalf("seed product type: %v", err)
	}
	deps := triggers.ReportDeps{
		Store: triggers.NewRTDBReportStore(client),
		Now:   func() time.Time { return testNow },
	}
	ev := triggers.LoanChangeEvent{
		EventId: "e1", CompanyId: "C1", LoanId: "L1", Status: "approved", OldStatus: "pending", Amount: 10000,
	}

	outcomes := []triggers.ReportOutcome{}
	for range 2 {
		outcome, err := triggers.HandleLoanChangeCore(context.Background(), env, ev, deps)
		if err != nil {
			t.Fatalf("handle: %v", err)
		}
		outcomes = append(outcomes, outcome)
	}
	if outcomes[0] != triggers.ReportApplied || outcomes[1] != triggers.ReportAlreadyApplied {
		t.Fatalf("outcomes: %v", outcomes)
	}

	base := env + "/companies/C1/report_summary/"
	if got := readTotal(t, client, base+"sales/total_amount_released"); got != 10000 {
		t.Fatalf("sales/total_amount_released: got %v, want 10000 (booked once)", got)
	}
	if got := readTotal(t, client, base+"total_summary/year:2026:month:9:week:37:day:9/total_amount_released"); got != 10000 {
		t.Fatalf("day bucket: got %v, want 10000", got)
	}
	var item map[string]any
	if err := client.NewRef(base+"data/"+itemKey).Get(context.Background(), &item); err != nil || item["data_type"] != "release" {
		t.Fatalf("data item: %v err=%v", item, err)
	}
	var summary map[string]any
	if err := client.NewRef(env+"/companies/C1/report_summary").Get(context.Background(), &summary); err != nil {
		t.Fatal(err)
	}
	// The client streams report_summary in full: only the reporting nodes may
	// live there, never claims or any future bookkeeping.
	for child := range summary {
		switch child {
		case "sales", "products", "total_summary", "capital_usage", "data":
		default:
			t.Fatalf("unexpected child %q under report_summary", child)
		}
	}
}
