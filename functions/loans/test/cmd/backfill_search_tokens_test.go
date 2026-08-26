package backfill_test

import (
	"context"
	"errors"
	"reflect"
	"sort"
	"strings"
	"testing"
	"time"

	backfill "com.loooans.app/cmd/backfill_search_tokens"
	"com.loooans.app/triggers"
)

const testNowMillis = int64(1755000000000)

// laterNowMillis is the clock a second pass runs on. A re-run never happens at
// the same instant as the first, so the fixtures must not pretend it does.
const laterNowMillis = testNowMillis + 86_400_000

// productCreatedAtMillis is deliberately far from testNowMillis so a create
// that stamps backfill time instead of the product's own age is visible.
const productCreatedAtMillis = int64(1700000000000)

// productDeletedAtMillis is the soft-delete stamp used by the Timestamp test.
const productDeletedAtMillis = int64(1710000000000)

// Re-runnability is the property under test: a second pass over an
// already-migrated collection must write nothing.
func TestNeedsUpdate(t *testing.T) {
	cases := []struct {
		name string
		doc  map[string]any
		want []string
		out  bool
	}{
		{"missing tokens", map[string]any{}, []string{"cr", "cru", "cruz"}, true},
		{"stale tokens", map[string]any{"search_tokens": []any{"old"}}, []string{"cr"}, true},
		{"current tokens", map[string]any{"search_tokens": []any{"cr", "cru"}}, []string{"cr", "cru"}, false},
		{"both empty", map[string]any{"search_tokens": []any{}}, nil, false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := backfill.NeedsUpdate(tc.doc, tc.want); got != tc.out {
				t.Errorf("NeedsUpdate = %v, want %v", got, tc.out)
			}
		})
	}
}

// ---------------------------------------------------------------- users ----

func sampleUser() map[string]any {
	return map[string]any{
		"id":            "user-1",
		"first_name":    "Juan",
		"middle_name":   "Reyes",
		"last_name":     "dela Cruz",
		"mobile_number": "09175550142",
		"email_address": "juan.cruz@gmail.com",
	}
}

// TestRunUsersCore_ComputesTheSameTokensAsTheTrigger is the most valuable test
// in this file. The backfill and the userChanges trigger must agree, field for
// field, about what feeds a user's tokens. If they disagree, the trigger
// rewrites every backfilled user on its next edit and the two never converge —
// silently, because both writes succeed.
//
// The fixture populates all five contributing fields with distinct values, so
// dropping any one of them from the backfill's argument list changes the token
// set and fails this test.
func TestRunUsersCore_ComputesTheSameTokensAsTheTrigger(t *testing.T) {
	store := newFakeUsers(map[string]map[string]any{"user-1": sampleUser()})

	report, err := backfill.RunUsersCore(context.Background(), store.deps(), false)
	if err != nil {
		t.Fatalf("RunUsersCore: %v", err)
	}

	want, needsWrite := triggers.SearchTokensForUser(sampleUser())
	if !needsWrite {
		t.Fatal("fixture already carries tokens — the comparison would be vacuous")
	}

	fields, ok := store.writes["user-1"]
	if !ok {
		t.Fatal("no write for user-1")
	}
	got, ok := fields["search_tokens"].([]string)
	if !ok {
		t.Fatalf("search_tokens has type %T, want []string", fields["search_tokens"])
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("backfill tokens = %v\ntrigger  tokens = %v", got, want)
	}

	assertReport(t, report, backfill.Report{Collection: "users", Scanned: 1, Updated: 1})
}

// A second pass over an already-migrated collection must write nothing —
// otherwise every re-run costs one userChanges invocation per user.
func TestRunUsersCore_SecondPassWritesNothing(t *testing.T) {
	store := newFakeUsers(map[string]map[string]any{"user-1": sampleUser()})

	if _, err := backfill.RunUsersCore(context.Background(), store.deps(), false); err != nil {
		t.Fatalf("pass 1: %v", err)
	}
	store.writes = map[string]map[string]any{}

	report, err := backfill.RunUsersCore(context.Background(), store.deps(), false)
	if err != nil {
		t.Fatalf("pass 2: %v", err)
	}
	if len(store.writes) != 0 {
		t.Errorf("pass 2 wrote %v — the backfill is not re-runnable", store.writes)
	}
	assertReport(t, report, backfill.Report{Collection: "users", Scanned: 1, Skipped: 1})
}

// dryRun must report what it would do and write nothing at all.
func TestRunUsersCore_DryRunWritesNothing(t *testing.T) {
	store := newFakeUsers(map[string]map[string]any{"user-1": sampleUser()})

	report, err := backfill.RunUsersCore(context.Background(), store.deps(), true)
	if err != nil {
		t.Fatalf("RunUsersCore: %v", err)
	}
	if len(store.writes) != 0 {
		t.Fatalf("dry run wrote %v", store.writes)
	}
	assertReport(t, report, backfill.Report{Collection: "users", Scanned: 1, Updated: 1})
}

// TestRunUsersCore_CountsOnlyWritesThatLanded is the report's honesty test.
//
// The writer this job uses batches: its Set() returns nil the moment the write
// is ENQUEUED, and whether it landed is known only after a flush. Counting
// that nil as success meant a run against a service account with no write
// permission reported `updated=499 failed=1` — the first full batch charged as
// written before anything at all was known about it, and the error charged to
// whichever document happened to fill the batch. main.go then quotes a trigger
// cost derived from that number and the operator concludes the backfill
// worked. This job has never run against a real Firestore, so its report is
// the only evidence anyone will ever have.
func TestRunUsersCore_CountsOnlyWritesThatLanded(t *testing.T) {
	store := newFakeUsers(map[string]map[string]any{
		"user-1": sampleUser(),
		"user-2": sampleUser(),
		"user-3": sampleUser(),
	})
	store.flushErr = errors.New("PermissionDenied: Missing or insufficient permissions")

	report, err := backfill.RunUsersCore(context.Background(), store.deps(), false)
	if err == nil {
		t.Error("every write failed and the pass returned nil — the exit code would say success")
	}
	assertReport(t, report, backfill.Report{
		Collection: "users", Scanned: 3, Updated: 0, Created: 0, Failed: 3,
	})
}

// TestRunUsersCore_CountsFlushFailuresWhenThePassAlsoFailed is the other half:
// a pass that stopped on a page read still has writes in flight behind it, and
// those outcomes must reach the report. The version this replaces returned the
// pass error and discarded the flush entirely, so 200 users could fail as one
// batch and be reported as `failed=0` — the operator re-runs for the single
// document named in the error and the rest stay unsearchable.
func TestRunUsersCore_CountsFlushFailuresWhenThePassAlsoFailed(t *testing.T) {
	store := newFakeUsers(map[string]map[string]any{
		"user-1": sampleUser(),
		"user-2": sampleUser(),
	})
	store.flushErr = errors.New("PermissionDenied: Missing or insufficient permissions")
	store.eachErr = errors.New("page users after 2 document(s): DeadlineExceeded")

	report, err := backfill.RunUsersCore(context.Background(), store.deps(), false)
	if err == nil {
		t.Fatal("expected the page error")
	}
	if !strings.Contains(err.Error(), "DeadlineExceeded") {
		t.Errorf("err = %v, want it to still name the page failure", err)
	}
	if !strings.Contains(err.Error(), "2 document(s) failed") {
		t.Errorf("err = %v, want it to also name the writes that did not land", err)
	}
	assertReport(t, report, backfill.Report{
		Collection: "users", Scanned: 2, Updated: 0, Failed: 2,
	})
}

// ------------------------------------------------------------- products ----

func sampleProduct() map[string]any {
	return map[string]any{
		"id":                  "prod-1",
		"provider_id":         "company-1",
		"loan_type":           "Salary Loan",
		"term":                "1m",
		"interest_rate":       8.0,
		"max_loanable_amount": 50000.0,
		"max_period":          int64(6),
		"allow_add_ons":       true,
		"created_at":          productCreatedAtMillis,
	}
}

func sampleCompany() map[string]any {
	return map[string]any{
		"name":         "Acme Lending",
		"tag_line":     "Fast cash for teachers",
		"review_count": int64(4),
		"total_rating": 18.0,
	}
}

// TestRunProductsCore_CreateIsTheTriggersOwnProjection pins the reuse itself.
// The create payload must be byte-for-byte what BuildProductViewCreate
// produces: ProductViewEntity declares fourteen fields `late`, and those two
// builders are the only thing enforcing that contract. A backfill that
// assembles its own map compiles, runs, and crashes the offers list.
func TestRunProductsCore_CreateIsTheTriggersOwnProjection(t *testing.T) {
	store := newFakeProducts(
		map[string]map[string]any{"prod-1": sampleProduct()},
		map[string]map[string]any{"company-1": sampleCompany()},
		nil,
	)

	report, err := backfill.RunProductsCore(context.Background(), store.deps(), false)
	if err != nil {
		t.Fatalf("RunProductsCore: %v", err)
	}

	want := triggers.BuildProductViewCreate("prod-1", sampleProduct(), sampleCompany(), testNowMillis)
	got, ok := store.created["prod-1"]
	if !ok {
		t.Fatalf("no view created; created=%v", keysOf(store.created))
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("create payload diverged from BuildProductViewCreate\n got = %#v\nwant = %#v", got, want)
	}

	assertReport(t, report, backfill.Report{
		Collection: "products", Scanned: 1, Created: 1, MissingView: 1,
	})
}

// created_at must be the PRODUCT's own creation time. loadNext() pages the
// marketplace with orderBy('created_at') ascending, so a backfill that stamps
// its own run time permanently reorders the marketplace by backfill order.
func TestRunProductsCore_CreatedAtComesFromTheProduct(t *testing.T) {
	store := newFakeProducts(
		map[string]map[string]any{"prod-1": sampleProduct()},
		map[string]map[string]any{"company-1": sampleCompany()},
		nil,
	)

	if _, err := backfill.RunProductsCore(context.Background(), store.deps(), false); err != nil {
		t.Fatalf("RunProductsCore: %v", err)
	}

	if got := store.created["prod-1"]["created_at"]; got != productCreatedAtMillis {
		t.Errorf("created_at = %v, want the product's own %v (backfill time is %v)",
			got, productCreatedAtMillis, testNowMillis)
	}
}

// The backfill reads products through the Firestore client, so a field stored
// as a Timestamp rather than as int millis arrives as a Go time.Time — while
// the trigger reads the same field out of a CloudEvent payload, where it has
// always been converted to millis. If only the trigger understands it, the two
// writers never converge: this pass writes deleted_at: null onto a soft-deleted
// product (publishing a deleted offer as live and breaking `isNull: true`), the
// next product write restores the millis, and the next run flips it back —
// so no second pass ever writes nothing, which is the job's whole premise.
func TestRunProductsCore_TimestampDatesProjectLikeTheTrigger(t *testing.T) {
	product := sampleProduct()
	product["created_at"] = time.UnixMilli(productCreatedAtMillis).UTC()
	product["deleted_at"] = time.UnixMilli(productDeletedAtMillis).UTC()

	store := newFakeProducts(
		map[string]map[string]any{"prod-1": product},
		map[string]map[string]any{"company-1": sampleCompany()},
		nil,
	)

	if _, err := backfill.RunProductsCore(context.Background(), store.deps(), false); err != nil {
		t.Fatalf("RunProductsCore: %v", err)
	}

	// The same logical product as the trigger sees it, post-flattening.
	triggerProduct := sampleProduct()
	triggerProduct["created_at"] = productCreatedAtMillis
	triggerProduct["deleted_at"] = productDeletedAtMillis
	want := triggers.BuildProductViewCreate("prod-1", triggerProduct, sampleCompany(), testNowMillis)

	got := store.created["prod-1"]
	if got["deleted_at"] != productDeletedAtMillis {
		t.Errorf("deleted_at = %v (%T), want %v — a soft-deleted product would be published as a live offer",
			got["deleted_at"], got["deleted_at"], productDeletedAtMillis)
	}
	if got["created_at"] != productCreatedAtMillis {
		t.Errorf("created_at = %v (%T), want the product's own %v",
			got["created_at"], got["created_at"], productCreatedAtMillis)
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("backfill and trigger disagree about the same product\nbackfill: %v\ntrigger:  %v", got, want)
	}
}

// Legacy views carry auto-generated document IDs with product_id as a field.
// The backfill must find them by that field and update them in place —
// inventing its own ID gives every already-projected product a second view.
func TestRunProductsCore_UpdatesEveryExistingViewInPlace(t *testing.T) {
	store := newFakeProducts(
		map[string]map[string]any{"prod-1": sampleProduct()},
		map[string]map[string]any{"company-1": sampleCompany()},
		map[string]map[string]any{
			"legacy-a": {"product_id": "prod-1"},
			"legacy-b": {"product_id": "prod-1"},
		},
	)

	report, err := backfill.RunProductsCore(context.Background(), store.deps(), false)
	if err != nil {
		t.Fatalf("RunProductsCore: %v", err)
	}

	if len(store.created) != 0 {
		t.Errorf("created %v — existing views must be updated, not duplicated", keysOf(store.created))
	}
	want := triggers.BuildProductViewUpdate(sampleProduct(), sampleCompany(), testNowMillis)
	for _, viewID := range []string{"legacy-a", "legacy-b"} {
		got, ok := store.updated[viewID]
		if !ok {
			t.Errorf("%s not updated — a duplicate left stale is a duplicate nobody notices", viewID)
			continue
		}
		if !reflect.DeepEqual(got, want) {
			t.Errorf("%s update payload diverged from BuildProductViewUpdate\n got = %#v\nwant = %#v",
				viewID, got, want)
		}
	}

	assertReport(t, report, backfill.Report{Collection: "products", Scanned: 1, Updated: 2})
}

// Re-runnability for the product path. Pass 1 creates the view; pass 2 sees a
// view that already carries every projected field and must write nothing.
// updated_at is excluded from that comparison on purpose — it changes every
// run, and rewriting it would float every offer to the top of the marketplace
// (orderBy('updated_at', descending)) on each backfill pass.
func TestRunProductsCore_SecondPassWritesNothing(t *testing.T) {
	store := newFakeProducts(
		map[string]map[string]any{"prod-1": sampleProduct()},
		map[string]map[string]any{"company-1": sampleCompany()},
		nil,
	)

	if _, err := backfill.RunProductsCore(context.Background(), store.deps(), false); err != nil {
		t.Fatalf("pass 1: %v", err)
	}
	store.created = map[string]map[string]any{}
	store.updated = map[string]map[string]any{}
	// Pass 2 runs on a later clock, as a real re-run would. Everything the
	// projection derives from the product is unchanged; only updated_at would
	// differ, and that must not count as a change.
	store.now = laterNowMillis

	report, err := backfill.RunProductsCore(context.Background(), store.deps(), false)
	if err != nil {
		t.Fatalf("pass 2: %v", err)
	}
	if len(store.created)+len(store.updated) != 0 {
		t.Errorf("pass 2 wrote created=%v updated=%v — the backfill is not re-runnable",
			keysOf(store.created), keysOf(store.updated))
	}
	assertReport(t, report, backfill.Report{Collection: "products", Scanned: 1, Skipped: 1})
}

// A view whose stored fields all match but which is MISSING deleted_at must
// still be rewritten: both Dart read paths filter where('deleted_at', isNull:
// true), and Firestore matches that only when the field exists. An absent
// deleted_at is not an equal-to-null deleted_at, and a skip here would leave
// the offer invisible in every listing while looking perfect in the console.
// TestRunProductsCore_ConvergesOnANestedMapWithFewerKeys is the backfill half
// of the nested-map finding.
//
// company_profile_photo_url is a MAP (Dart's handleImageUrlToJson returns
// ImageUrl.toJson()). The stored view carries a thumbnail the company no
// longer has. After one pass the view must hold exactly the company's map, and
// a second pass must then write nothing.
//
// The write semantics asserted here — each top-level key of the payload
// replaced wholesale — are what triggers.MergeFields asks Firestore for, and
// are pinned on the wire by TestMergeFields_ReplacesNestedMapsWholesale in the
// triggers module. Under the firestore.MergeAll it replaced, Firestore merged
// the map leaf by leaf: the thumbnail survived, sameFieldValue kept seeing a
// difference, and every pass rewrote the same document forever without ever
// being able to remove it.
func TestRunProductsCore_ConvergesOnANestedMapWithFewerKeys(t *testing.T) {
	company := sampleCompany()
	company["company_profile_photo_url"] = map[string]any{"url": "b"}

	store := newFakeProducts(
		map[string]map[string]any{"prod-1": sampleProduct()},
		map[string]map[string]any{"company-1": company},
		map[string]map[string]any{"view-1": {
			"product_id": "prod-1",
			"company_profile_photo_url": map[string]any{
				"url":       "a",
				"thumbnail": "t",
			},
		}},
	)

	if _, err := backfill.RunProductsCore(context.Background(), store.deps(), false); err != nil {
		t.Fatalf("pass 1: %v", err)
	}

	photo, ok := store.views["view-1"]["company_profile_photo_url"].(map[string]any)
	if !ok {
		t.Fatalf("company_profile_photo_url = %T, want map[string]any",
			store.views["view-1"]["company_profile_photo_url"])
	}
	if _, stale := photo["thumbnail"]; stale {
		t.Errorf("thumbnail survived: the company no longer carries it, so the view can "+
			"never converge and every pass rewrites it. got %v", photo)
	}
	if got := photo["url"]; got != "b" {
		t.Errorf("url = %v, want b", got)
	}

	store.created = map[string]map[string]any{}
	store.updated = map[string]map[string]any{}
	store.now = laterNowMillis

	report, err := backfill.RunProductsCore(context.Background(), store.deps(), false)
	if err != nil {
		t.Fatalf("pass 2: %v", err)
	}
	if len(store.created)+len(store.updated) != 0 {
		t.Errorf("pass 2 wrote created=%v updated=%v — the nested map never converged",
			keysOf(store.created), keysOf(store.updated))
	}
	assertReport(t, report, backfill.Report{Collection: "products", Scanned: 1, Skipped: 1})
}

func TestRunProductsCore_RepairsViewMissingDeletedAt(t *testing.T) {
	store := newFakeProducts(
		map[string]map[string]any{"prod-1": sampleProduct()},
		map[string]map[string]any{"company-1": sampleCompany()},
		nil,
	)
	if _, err := backfill.RunProductsCore(context.Background(), store.deps(), false); err != nil {
		t.Fatalf("pass 1: %v", err)
	}
	store.created = map[string]map[string]any{}
	store.updated = map[string]map[string]any{}
	store.now = laterNowMillis
	delete(store.views["prod-1"], "deleted_at")

	report, err := backfill.RunProductsCore(context.Background(), store.deps(), false)
	if err != nil {
		t.Fatalf("pass 2: %v", err)
	}
	if _, ok := store.updated["prod-1"]; !ok {
		t.Error("view missing deleted_at was skipped — it stays invisible to every listing")
	}
	assertReport(t, report, backfill.Report{Collection: "products", Scanned: 1, Updated: 1})
}

// Every product of the same lender must cost one companies read, not one per
// product. A naive per-product read multiplies the job's cost by the size of
// the catalogue for a handful of distinct lenders.
func TestRunProductsCore_ReadsEachCompanyOnce(t *testing.T) {
	second := sampleProduct()
	second["id"] = "prod-2"

	store := newFakeProducts(
		map[string]map[string]any{"prod-1": sampleProduct(), "prod-2": second},
		map[string]map[string]any{"company-1": sampleCompany()},
		nil,
	)

	if _, err := backfill.RunProductsCore(context.Background(), store.deps(), false); err != nil {
		t.Fatalf("RunProductsCore: %v", err)
	}
	if store.companyReads != 1 {
		t.Errorf("companies read %d times for 2 products of 1 lender, want 1", store.companyReads)
	}
}

// A products document with no `id` field would abort the trigger core and, in
// a batch, the whole remaining pass. The document ID is the product ID by
// construction, so the backfill supplies it.
func TestRunProductsCore_FallsBackToTheDocumentID(t *testing.T) {
	product := sampleProduct()
	delete(product, "id")

	store := newFakeProducts(
		map[string]map[string]any{"prod-1": product},
		map[string]map[string]any{"company-1": sampleCompany()},
		nil,
	)

	report, err := backfill.RunProductsCore(context.Background(), store.deps(), false)
	if err != nil {
		t.Fatalf("RunProductsCore: %v", err)
	}
	if got := store.created["prod-1"]["product_id"]; got != "prod-1" {
		t.Errorf("product_id = %v, want prod-1 from the document ID", got)
	}
	assertReport(t, report, backfill.Report{
		Collection: "products", Scanned: 1, Created: 1, MissingView: 1,
	})
}

func TestRunProductsCore_DryRunWritesNothing(t *testing.T) {
	store := newFakeProducts(
		map[string]map[string]any{"prod-1": sampleProduct()},
		map[string]map[string]any{"company-1": sampleCompany()},
		nil,
	)

	report, err := backfill.RunProductsCore(context.Background(), store.deps(), true)
	if err != nil {
		t.Fatalf("RunProductsCore: %v", err)
	}
	if len(store.created)+len(store.updated) != 0 {
		t.Fatalf("dry run wrote created=%v updated=%v", keysOf(store.created), keysOf(store.updated))
	}
	assertReport(t, report, backfill.Report{
		Collection: "products", Scanned: 1, Created: 1, MissingView: 1,
	})
}

// The products pass counts CREATES the same way, and a create that never
// landed is the worse half: the product had no view at all, so an operator
// told `created=1` records an offer that is still invisible to the
// marketplace as published.
func TestRunProductsCore_CountsOnlyCreatesThatLanded(t *testing.T) {
	store := newFakeProducts(
		map[string]map[string]any{"prod-1": sampleProduct()},
		map[string]map[string]any{"company-1": sampleCompany()},
		nil,
	)
	store.flushErr = errors.New("PermissionDenied: Missing or insufficient permissions")

	report, err := backfill.RunProductsCore(context.Background(), store.deps(), false)
	if err == nil {
		t.Fatal("the create never landed and the pass returned nil")
	}
	assertReport(t, report, backfill.Report{
		Collection: "products", Scanned: 1, Created: 0, Updated: 0, MissingView: 1, Failed: 1,
	})
}

// ---------------------------------------------------------------- safety ----
//
// Every case below returns before Run builds a Firestore client, so these need
// no credentials and reach no network. If one of these guards regresses, the
// test does not silently pass — it tries to talk to Firestore and fails.

// Writing to production must take a second, explicit opt-in. -dry-run=false
// alone is one typo away from the wrong project.
func TestRun_RefusesProductionWritesWithoutTheFlag(t *testing.T) {
	_, err := backfill.Run(context.Background(), backfill.Options{
		Collection: backfill.CollectionProducts,
		ProjectID:  "loooans-prod",
		DryRun:     false,
	})
	if err == nil {
		t.Fatal("a writing run against loooans-prod was allowed")
	}
	if !strings.Contains(err.Error(), "allow-production") {
		t.Errorf("error = %v, want it to name -allow-production", err)
	}
}

// A dry run against production is allowed — reading production to decide
// whether to run the backfill is the point of having a dry run. It must fail
// for want of credentials or ENVIRONMENT, never at the production guard.
func TestRun_AllowsProductionDryRuns(t *testing.T) {
	t.Setenv("ENVIRONMENT", "")

	_, err := backfill.Run(context.Background(), backfill.Options{
		Collection: backfill.CollectionProducts,
		ProjectID:  "loooans-prod",
		DryRun:     true,
	})
	if err == nil || !strings.Contains(err.Error(), "ENVIRONMENT") {
		t.Fatalf("err = %v, want the ENVIRONMENT check — a dry run must pass the production guard", err)
	}
}

// An unset ENVIRONMENT would page the unprefixed collections, find nothing, and
// report a clean zero-document pass. That is the most dangerous possible
// outcome for a completeness job, so it is an error instead.
func TestRun_RejectsMissingEnvironment(t *testing.T) {
	t.Setenv("ENVIRONMENT", "")

	_, err := backfill.Run(context.Background(), backfill.Options{
		Collection: backfill.CollectionUsers,
		ProjectID:  "loooans-dev-stg",
		DryRun:     true,
	})
	if err == nil || !strings.Contains(err.Error(), "ENVIRONMENT") {
		t.Fatalf("err = %v, want an ENVIRONMENT error rather than an empty pass", err)
	}
}

// The production guard checks that -allow-production was supplied. It does not
// check that ENVIRONMENT agrees with the project, and this is the mistake that
// makes: the operator means production, passes -allow-production, and still
// has ENVIRONMENT=development exported from an earlier dev dry run. Every
// other guard passes and the job then pages dev_users inside loooans-prod.
func TestRun_RefusesAnEnvironmentThatDoesNotMatchTheProject(t *testing.T) {
	t.Setenv("ENVIRONMENT", "development")

	_, err := backfill.Run(context.Background(), backfill.Options{
		Collection:      backfill.CollectionUsers,
		ProjectID:       "loooans-prod",
		DryRun:          false,
		AllowProduction: true,
	})
	if err == nil {
		t.Fatal("ENVIRONMENT=development against loooans-prod was allowed")
	}
	if !strings.Contains(err.Error(), "does not match project") {
		t.Errorf("err = %v, want it to name the mismatch", err)
	}
}

// Refused on a dry run too. A dry run against the wrong prefix reports counts
// that mean nothing, and those counts are exactly what the decision to run for
// real is based on.
func TestRun_RefusesAMismatchedDryRun(t *testing.T) {
	t.Setenv("ENVIRONMENT", "production")

	_, err := backfill.Run(context.Background(), backfill.Options{
		Collection: backfill.CollectionUsers,
		ProjectID:  "loooans-dev-stg",
		DryRun:     true,
	})
	if err == nil {
		t.Fatal("ENVIRONMENT=production against loooans-dev-stg was allowed")
	}
	if !strings.Contains(err.Error(), "does not match project") {
		t.Errorf("err = %v, want it to name the mismatch", err)
	}
}

// The original plan said to page product_views. Doing so cannot create the
// views that were never written, so the name is rejected with the reason
// rather than quietly accepted.
func TestRun_RejectsProductViews(t *testing.T) {
	_, err := backfill.Run(context.Background(), backfill.Options{
		Collection: "product_views",
		ProjectID:  "loooans-dev-stg",
		DryRun:     true,
	})
	if err == nil || !strings.Contains(err.Error(), backfill.CollectionProducts) {
		t.Fatalf("err = %v, want a rejection pointing at %q", err, backfill.CollectionProducts)
	}
}

// ----------------------------------------------------------------- fakes ----

type fakeUsers struct {
	docs   map[string]map[string]any
	writes map[string]map[string]any
	// flushErr, when set, makes every write one that is ACCEPTED and never
	// lands: UpdateUser returns nil exactly as firestore.BulkWriter.Set does
	// when it merely enqueues, the stored document is left untouched, and
	// Flush reports the lot as failed. This is the shape a service account
	// without write permission produces.
	flushErr error
	accepted []string
	// eachErr, when set, is returned by EachUser once every document has been
	// visited — a page read that failed partway through a large collection,
	// with a batch of writes still unflushed behind it.
	eachErr error
}

func newFakeUsers(docs map[string]map[string]any) *fakeUsers {
	return &fakeUsers{docs: docs, writes: map[string]map[string]any{}}
}

func (f *fakeUsers) deps() backfill.UserDeps {
	return backfill.UserDeps{
		EachUser: func(ctx context.Context, visit func(id string, user map[string]any) error) error {
			for _, id := range sortedKeys(f.docs) {
				if err := visit(id, f.docs[id]); err != nil {
					return err
				}
			}
			return f.eachErr
		},
		UpdateUser: func(ctx context.Context, id string, fields map[string]any) error {
			f.writes[id] = fields
			if f.flushErr != nil {
				f.accepted = append(f.accepted, id)
				return nil
			}
			mergeStored(f.docs[id], fields)
			return nil
		},
		Flush: func(ctx context.Context) map[string]error {
			return takeAccepted(&f.accepted, f.flushErr)
		},
	}
}

// takeAccepted reports every write that was accepted since the last call as
// having failed with err, and clears them. A nil err means the writes landed.
func takeAccepted(accepted *[]string, err error) map[string]error {
	if err == nil {
		return nil
	}
	failures := map[string]error{}
	for _, id := range *accepted {
		failures[id] = err
	}
	*accepted = nil
	return failures
}

type fakeProducts struct {
	docs      map[string]map[string]any
	companies map[string]map[string]any
	views     map[string]map[string]any // viewId -> stored document
	created   map[string]map[string]any // viewId -> raw create payload
	updated   map[string]map[string]any // viewId -> raw update payload
	// now is settable so a second pass can run at a LATER wall clock, the way
	// a re-run really would. Holding it constant would make the second-pass
	// tests pass even if updated_at were part of the skip comparison.
	now          int64
	companyReads int
	// flushErr / accepted: see fakeUsers.
	flushErr error
	accepted []string
}

func newFakeProducts(docs, companies, views map[string]map[string]any) *fakeProducts {
	if views == nil {
		views = map[string]map[string]any{}
	}
	return &fakeProducts{
		docs:      docs,
		companies: companies,
		views:     views,
		created:   map[string]map[string]any{},
		updated:   map[string]map[string]any{},
		now:       testNowMillis,
	}
}

func (f *fakeProducts) deps() backfill.ProductDeps {
	return backfill.ProductDeps{
		EachProduct: func(ctx context.Context, visit func(id string, product map[string]any) error) error {
			for _, id := range sortedKeys(f.docs) {
				if err := visit(id, f.docs[id]); err != nil {
					return err
				}
			}
			return nil
		},
		LoadCompany: func(ctx context.Context, companyID string) (map[string]any, error) {
			f.companyReads++
			return f.companies[companyID], nil
		},
		FindViews: func(ctx context.Context, productID string) (map[string]map[string]any, error) {
			found := map[string]map[string]any{}
			for viewID, view := range f.views {
				if view["product_id"] == productID {
					found[viewID] = view
				}
			}
			return found, nil
		},
		CreateView: func(ctx context.Context, viewID string, view map[string]any) error {
			f.created[viewID] = view
			if f.flushErr != nil {
				f.accepted = append(f.accepted, viewID)
				return nil
			}
			stored := map[string]any{}
			mergeStored(stored, view)
			f.views[viewID] = stored
			return nil
		},
		UpdateView: func(ctx context.Context, viewID string, fields map[string]any) error {
			f.updated[viewID] = fields
			if f.flushErr != nil {
				f.accepted = append(f.accepted, viewID)
				return nil
			}
			mergeStored(f.views[viewID], fields)
			return nil
		},
		Flush: func(ctx context.Context) map[string]error {
			return takeAccepted(&f.accepted, f.flushErr)
		},
		Now: func() int64 { return f.now },
	}
}

// mergeStored applies a payload the way the projection's own write does —
// every top-level key of the payload replaced wholesale, which is what
// triggers.MergeFields asks Firestore for (a firestore.MergeAll would instead
// merge nested maps leaf by leaf; see TestMergeAll_MergesNestedMapsLeafByLeaf
// in the triggers module, which pins that difference on the wire) — and
// stores string arrays as []any — the shape the Firestore client hands back on
// the next read. Keeping that fidelity is what makes the second-pass tests
// mean anything: NeedsUpdate reads []any, so a fake that stored []string would
// report "needs update" forever and hide a real non-idempotency.
func mergeStored(dst map[string]any, fields map[string]any) {
	for key, value := range fields {
		if tokens, ok := value.([]string); ok {
			dst[key] = toAnySlice(tokens)
			continue
		}
		dst[key] = value
	}
}

func toAnySlice(values []string) []any {
	out := make([]any, 0, len(values))
	for _, value := range values {
		out = append(out, value)
	}
	return out
}

func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for key := range m {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

func keysOf(m map[string]map[string]any) []string { return sortedKeys(m) }

func assertReport(t *testing.T, got *backfill.Report, want backfill.Report) {
	t.Helper()
	if got == nil {
		t.Fatal("nil report")
	}
	if *got != want {
		t.Errorf("report = %+v, want %+v", *got, want)
	}
}
