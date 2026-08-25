// Command backfill_search_tokens populates search_tokens on documents that
// predate the search work, and — for products — creates the product_views
// document the projection trigger would have created had the product been
// written since.
//
// It is safe to re-run: a pass over already-migrated documents writes nothing.
// It defaults to a dry run, so seeing what it would do costs only reads:
//
//	ENVIRONMENT=development go run ./cmd/backfill_search_tokens/cmd \
//	  -collection=users -project=loooans-dev-stg
//
//	ENVIRONMENT=development go run ./cmd/backfill_search_tokens/cmd \
//	  -collection=products -project=loooans-dev-stg
//
// Add -dry-run=false to actually write. ENVIRONMENT selects the Firestore
// collection prefix (dev_ / stg_ / none) exactly as it does for the deployed
// functions, so it must match the project being pointed at.
//
// Cost note: writing search_tokens to a user fires the userChanges trigger once
// per updated document. Each of those invocations is a no-op — the trigger sees
// the tokens already match and returns without writing — but the invocations are
// billed. The dry run's `updated` count is that invocation count.
package main

import (
	"context"
	"flag"
	"log"

	backfill "com.loooans.app/cmd/backfill_search_tokens"
)

func main() {
	collection := flag.String("collection", "", "users or products (NOT product_views)")
	project := flag.String("project", "", "Firebase project id, e.g. loooans-dev-stg")
	dryRun := flag.Bool("dry-run", true, "report what would change without writing")
	allowProduction := flag.Bool("allow-production", false,
		"required in addition to -dry-run=false to write to a production project")
	flag.Parse()

	report, err := backfill.Run(context.Background(), backfill.Options{
		Collection:      *collection,
		ProjectID:       *project,
		DryRun:          *dryRun,
		AllowProduction: *allowProduction,
	})
	if report != nil {
		log.Printf("%s", report)
		if report.Collection == backfill.CollectionUsers {
			log.Printf("userChanges invocations this pass would cost: %d", report.Updated)
		}
	}
	if err != nil {
		log.Fatalf("backfill failed: %v", err)
	}
}
