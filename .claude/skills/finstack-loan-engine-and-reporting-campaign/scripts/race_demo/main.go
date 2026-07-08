// race_demo demonstrates the lost-update race in the finstack report
// aggregation writers (functions/loans/triggers/loan_changes.go
// applyToNodeValue: non-transactional Get -> Set on an RTDB node).
//
// EMULATOR ONLY. The program refuses to start unless
// FIREBASE_DATABASE_EMULATOR_HOST is set, so it can never touch a real
// project ("never touch prod data by hand" rule).
//
// Usage (from this directory; or just run ./run.sh):
//
//	# terminal 1 — start the RTDB emulator (any project id works):
//	firebase emulators:start --only database --project demo-race
//
//	# terminal 2 — reproduce the race (get-then-set, mirrors applyToNodeValue):
//	# (CGO_ENABLED=0 is the macOS dyld LC_UUID workaround; harmless elsewhere)
//	CGO_ENABLED=0 FIREBASE_DATABASE_EMULATOR_HOST=localhost:9000 go run . -n 50
//
//	# then prove the fix (RTDB transaction — race-free):
//	CGO_ENABLED=0 FIREBASE_DATABASE_EMULATOR_HOST=localhost:9000 go run . -n 50 -txn
//
// Expected: without -txn the final value is usually < n (lost updates);
// with -txn the final value is exactly n. If the racy run happens to land
// on n, raise -n or rerun — the schedule-dependent interleave is the point.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"math/rand"
	"os"
	"sync"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/db"
)

func main() {
	var useTxn bool
	var n int
	var node string
	flag.BoolVar(&useTxn, "txn", false, "use an RTDB transaction per increment (race-free) instead of get-then-set (racy, mirrors applyToNodeValue)")
	flag.IntVar(&n, "n", 50, "number of concurrent +1.0 increments")
	flag.StringVar(&node, "node", "race_demo/total_amount_released", "RTDB node to increment")
	flag.Parse()

	if os.Getenv("FIREBASE_DATABASE_EMULATOR_HOST") == "" {
		log.Fatal("refusing to run: FIREBASE_DATABASE_EMULATOR_HOST is not set.\n" +
			"This tool must only run against the RTDB emulator, never a real project.\n" +
			"Start one with: firebase emulators:start --only database --project demo-race")
	}

	ctx := context.Background()
	app, err := firebase.NewApp(ctx, &firebase.Config{
		// Non-https, no-scheme URL => the Admin SDK treats this as an
		// emulator URL ("host:port/?ns=namespace") and authenticates with a
		// static "owner" token (no ADC needed).
		DatabaseURL: "localhost:9000/?ns=demo-race",
	})
	if err != nil {
		log.Fatalf("firebase.NewApp: %v", err)
	}

	client, err := app.Database(ctx)
	if err != nil {
		log.Fatalf("app.Database: %v", err)
	}

	ref := client.NewRef(node)
	if err := ref.Set(ctx, 0.0); err != nil {
		log.Fatalf("reset node: %v", err)
	}

	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if useTxn {
				if err := incrementTxn(ctx, ref, 1.0); err != nil {
					log.Printf("txn increment failed: %v", err)
				}
			} else {
				if err := incrementRacy(ctx, ref, 1.0); err != nil {
					log.Printf("racy increment failed: %v", err)
				}
			}
		}()
	}
	wg.Wait()

	var final float64
	if err := ref.Get(ctx, &final); err != nil {
		log.Fatalf("read final value: %v", err)
	}

	mode := "GET-THEN-SET (mirrors applyToNodeValue)"
	if useTxn {
		mode = "TRANSACTION (Ref.Transaction)"
	}
	fmt.Printf("mode:     %s\n", mode)
	fmt.Printf("writes:   %d x +1.0\n", n)
	fmt.Printf("expected: %d\n", n)
	fmt.Printf("actual:   %.0f\n", final)
	if final != float64(n) {
		fmt.Printf("LOST UPDATES: %.0f increments were overwritten by concurrent writers\n", float64(n)-final)
		os.Exit(1)
	}
	fmt.Println("no lost updates")
}

// incrementRacy reproduces applyToNodeValue from
// functions/loans/triggers/loan_changes.go: read the current value, then
// write value+delta. Two concurrent callers can read the same value and one
// increment is lost.
func incrementRacy(ctx context.Context, ref *db.Ref, delta float64) error {
	var value float64
	if err := ref.Get(ctx, &value); err != nil {
		return fmt.Errorf("get: %w", err)
	}
	if err := ref.Set(ctx, value+delta); err != nil {
		return fmt.Errorf("set: %w", err)
	}
	return nil
}

// incrementTxn is the race-free equivalent using an RTDB transaction
// (compare-and-swap with automatic retry).
//
// NOTE: the SDK's Transaction gives up after a fixed number of internal
// retries ("transaction aborted after failed retries") under very heavy
// contention on one node, so we retry the whole transaction with backoff.
// The production fix needs the same property: a failed transaction must
// surface an error so Eventarc redelivers the event — which is only safe
// once the handler is idempotent.
func incrementTxn(ctx context.Context, ref *db.Ref, delta float64) error {
	var err error
	for attempt := 0; attempt < 20; attempt++ {
		err = ref.Transaction(ctx, func(t db.TransactionNode) (interface{}, error) {
			var value float64
			if uErr := t.Unmarshal(&value); uErr != nil {
				return nil, uErr
			}
			return value + delta, nil
		})
		if err == nil {
			return nil
		}
		time.Sleep(time.Duration(10+rand.Intn(50)) * time.Millisecond)
	}
	return err
}
