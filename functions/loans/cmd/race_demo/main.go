// race_demo shows why the report writers moved from Get-then-Set to one atomic
// multi-path update with server-side increments (campaign D2).
//
// It only runs against the Realtime Database emulator:
//
//	cd apps/loans && firebase emulators:start --only database --project demo-finstack
//	cd functions/loans && FIREBASE_DATABASE_EMULATOR_HOST=localhost:9000?ns=demo-finstack \
//	  go run ./cmd/race_demo -n 50
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"sync"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/db"
)

func main() {
	n := flag.Int("n", 50, "concurrent increments per mode")
	flag.Parse()

	host := os.Getenv("FIREBASE_DATABASE_EMULATOR_HOST")
	if host == "" {
		fmt.Fprintln(os.Stderr, "refusing to run: set FIREBASE_DATABASE_EMULATOR_HOST=localhost:9000?ns=demo-finstack (this tool never touches a real database)")
		os.Exit(2)
	}

	ctx := context.Background()
	// With the emulator variable set the SDK ignores this URL's host and talks
	// to the emulator (the variable itself must be host:port?ns=name).
	app, err := firebase.NewApp(ctx, &firebase.Config{DatabaseURL: "https://demo-finstack.firebaseio.com"})
	if err != nil {
		fail(err)
	}
	client, err := app.Database(ctx)
	if err != nil {
		fail(err)
	}

	base := fmt.Sprintf("race-demo/%d", time.Now().UnixNano())
	fmt.Printf("racy  Get-then-Set: %v of %d landed\n", run(ctx, *n, client.NewRef(base+"/racy"), racyIncrement), *n)
	fmt.Printf("atomic increment  : %v of %d landed\n", run(ctx, *n, client.NewRef(base+"/atomic"), atomicIncrement), *n)
}

func run(ctx context.Context, n int, ref *db.Ref, increment func(context.Context, *db.Ref) error) float64 {
	var wg sync.WaitGroup
	for range n {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := increment(ctx, ref); err != nil {
				fmt.Fprintln(os.Stderr, "increment:", err)
			}
		}()
	}
	wg.Wait()

	var total float64
	if err := ref.Get(ctx, &total); err != nil {
		fail(err)
	}
	return total
}

// racyIncrement is what applyToNodeValue used to do.
func racyIncrement(ctx context.Context, ref *db.Ref) error {
	var value float64
	if err := ref.Get(ctx, &value); err != nil {
		return err
	}
	return ref.Set(ctx, value+1)
}

// atomicIncrement is what the report store does now, for one node.
func atomicIncrement(ctx context.Context, ref *db.Ref) error {
	return ref.Set(ctx, map[string]any{".sv": map[string]any{"increment": 1}})
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
