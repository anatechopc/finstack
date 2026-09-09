//go:build emulator

// Emulator-backed proofs for the report writers (campaign Phase 2):
//
//	cd apps/loans && firebase emulators:start --only database --project demo-finstack
//	cd functions/loans && FIREBASE_DATABASE_EMULATOR_HOST=localhost:9000?ns=demo-finstack \
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
	host := os.Getenv("FIREBASE_DATABASE_EMULATOR_HOST")
	if host == "" {
		t.Skip("set FIREBASE_DATABASE_EMULATOR_HOST=localhost:9000?ns=demo-finstack to run the emulator proofs")
	}
	// With the emulator variable set the SDK ignores this URL's host and talks
	// to the emulator (the variable itself must be host:port?ns=name).
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

// Concurrency proof (D2): 50 concurrent applies through the atomic path all land.
func TestEmulator_Apply_ConcurrentIncrements_LoseNothing(t *testing.T) {
	client := emulatorClient(t)
	store := triggers.NewRTDBReportStore(client)
	base := isolatedEnv(t) + "/companies/C1"
	plan := triggers.ReportPlan{Increments: map[string]float64{"sales/total_amount_released": 1}}

	var wg sync.WaitGroup
	for range 50 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := store.Apply(context.Background(), base, plan); err != nil {
				t.Errorf("apply: %v", err)
			}
		}()
	}
	wg.Wait()

	if got := readTotal(t, client, base+"/report_summary/sales/total_amount_released"); got != 50 {
		t.Fatalf("atomic increments: got %v, want 50", got)
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

// Idempotency proof (D1): only one of several concurrent claims wins, and a
// released claim can be taken again.
func TestEmulator_ClaimEvent_OnlyOneDeliveryWins(t *testing.T) {
	client := emulatorClient(t)
	store := triggers.NewRTDBReportStore(client)
	base := isolatedEnv(t) + "/companies/C1"

	var wg sync.WaitGroup
	var mu sync.Mutex
	wins := 0
	for range 10 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			claimed, err := store.ClaimEvent(context.Background(), base, "e1")
			if err != nil {
				t.Errorf("claim: %v", err)
				return
			}
			if claimed {
				mu.Lock()
				wins++
				mu.Unlock()
			}
		}()
	}
	wg.Wait()
	if wins != 1 {
		t.Fatalf("claims won: got %d, want exactly 1", wins)
	}

	if err := store.ReleaseEvent(context.Background(), base, "e1"); err != nil {
		t.Fatalf("release: %v", err)
	}
	claimed, err := store.ClaimEvent(context.Background(), base, "e1")
	if err != nil || !claimed {
		t.Fatalf("after release the claim must be available again: claimed=%v err=%v", claimed, err)
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
}
