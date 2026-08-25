package triggers_test

import (
	"context"
	"errors"
	"testing"

	"com.loooans.app/triggers"
)

const testNowMillis = int64(1755000000000)

// sampleProduct mirrors a flattened products document. interest_rate and
// max_loanable_amount arrive as float64 here (Firestore DoubleValue); the
// integer-valued case is covered separately by
// TestBuildProductView_NumericTypesMatchDartEntity.
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
	}
}

// sampleCompany mirrors a companies document as the Firestore Go client
// returns it: integers as int64, doubles as float64.
func sampleCompany() map[string]any {
	return map[string]any{
		"name":         "Acme Lending",
		"tag_line":     "Fast cash for teachers",
		"review_count": int64(4),
		"total_rating": 18.0,
		"company_profile_photo_url": map[string]any{
			"url": "https://example.test/acme.png",
		},
	}
}

func TestBuildProductViewUpdate(t *testing.T) {
	view := triggers.BuildProductViewUpdate(sampleProduct(), sampleCompany(), testNowMillis)

	if view["product_id"] != "prod-1" {
		t.Errorf("product_id = %v, want prod-1", view["product_id"])
	}
	if view["company_id"] != "company-1" {
		t.Errorf("company_id = %v, want company-1", view["company_id"])
	}
	if view["company_name"] != "Acme Lending" {
		t.Errorf("company_name = %v, want Acme Lending", view["company_name"])
	}
	if view["loan_type"] != "Salary Loan" {
		t.Errorf("loan_type = %v, want Salary Loan", view["loan_type"])
	}

	tokens, ok := view["search_tokens"].([]string)
	if !ok {
		t.Fatalf("search_tokens missing or wrong type: %T", view["search_tokens"])
	}
	assertHas(t, tokens, "salary")
	assertHas(t, tokens, "acme")
}

func TestBuildProductViewUpdate_ToleratesMissingFields(t *testing.T) {
	view := triggers.BuildProductViewUpdate(map[string]any{"id": "prod-2"}, nil, testNowMillis)

	if view["product_id"] != "prod-2" {
		t.Errorf("product_id = %v, want prod-2", view["product_id"])
	}
	if _, ok := view["search_tokens"].([]string); !ok {
		t.Error("search_tokens must always be present, even if empty")
	}
}

// TestBuildProductViewCreate_HasEveryRequiredEntityField pins defect D2. This
// trigger is the ONLY creator of product_views documents, so a document it
// creates must carry every field ProductViewEntity declares `late` and
// non-nullable — fromJson throws on any of them being absent, which crashes
// the offers list rather than degrading it.
func TestBuildProductViewCreate_HasEveryRequiredEntityField(t *testing.T) {
	view := triggers.BuildProductViewCreate("view-1", sampleProduct(), sampleCompany(), testNowMillis)

	// product_view_entity.dart:31-104 — every `late` non-nullable field.
	required := []string{
		"created_at", "updated_at", "id", "company_id", "company_name",
		"product_id", "loan_type", "term", "interest_rate",
		"max_loanable_amount", "review_rating_avg", "review_count",
		"max_period", "allow_add_ons",
	}
	for _, key := range required {
		value, ok := view[key]
		if !ok {
			t.Errorf("create payload is missing required field %q", key)
			continue
		}
		if value == nil {
			t.Errorf("required field %q is nil; fromJson would throw", key)
		}
	}

	if view["id"] != "view-1" {
		t.Errorf("id = %v, want the allocated doc id view-1", view["id"])
	}
}

// TestBuildProductViewCreate_DeletedAtPresentAndNil pins defect D3. Both Dart
// read paths filter `where('deleted_at', isNull: true)`, which in Firestore
// matches only documents where the field EXISTS and is null. A created
// document missing the key entirely is invisible in every listing while
// looking perfect in the console.
func TestBuildProductViewCreate_DeletedAtPresentAndNil(t *testing.T) {
	view := triggers.BuildProductViewCreate("view-1", sampleProduct(), sampleCompany(), testNowMillis)

	value, ok := view["deleted_at"]
	if !ok {
		t.Fatal("deleted_at key absent — the document would never match where('deleted_at', isNull: true)")
	}
	if value != nil {
		t.Errorf("deleted_at = %v, want an explicit nil for a live product", value)
	}
}

// A product that is already soft-deleted must not be resurrected as a visible
// offer by the trigger that now owns creation.
func TestBuildProductViewCreate_PropagatesProductDeletedAt(t *testing.T) {
	product := sampleProduct()
	product["deleted_at"] = int64(1700000000000)

	view := triggers.BuildProductViewCreate("view-1", product, sampleCompany(), testNowMillis)

	if view["deleted_at"] != int64(1700000000000) {
		t.Errorf("deleted_at = %v (%T), want the product's own int64 millis", view["deleted_at"], view["deleted_at"])
	}
}

// TestBuildProductViewUpdate_OmitsFieldsOwnedElsewhere pins the second half of
// D2. review_rating_avg / review_count are maintained by the review flow
// (loans_bloc.dart:653-654) and created_at by creation; re-writing any of them
// on every product edit resets live data.
func TestBuildProductViewUpdate_OmitsFieldsOwnedElsewhere(t *testing.T) {
	view := triggers.BuildProductViewUpdate(sampleProduct(), sampleCompany(), testNowMillis)

	for _, key := range []string{"review_rating_avg", "review_count", "created_at"} {
		if _, ok := view[key]; ok {
			t.Errorf("update payload must not contain %q — it is owned elsewhere", key)
		}
	}
}

// TestBuildProductView_TimestampsAreEpochMillis pins defect D4. Dart writes
// dates through handleDateTimeToJson (millisecondsSinceEpoch), so the stored
// type is an integer. A Go time.Time would be stored as a Firestore Timestamp,
// and Firestore orders by TYPE before value — mixing the two silently splits
// orderBy('updated_at', descending: true) into two blocks.
func TestBuildProductView_TimestampsAreEpochMillis(t *testing.T) {
	create := triggers.BuildProductViewCreate("view-1", sampleProduct(), sampleCompany(), testNowMillis)
	for _, key := range []string{"created_at", "updated_at"} {
		got, ok := create[key].(int64)
		if !ok {
			t.Fatalf("create %s is %T, want int64 epoch millis", key, create[key])
		}
		if got != testNowMillis {
			t.Errorf("create %s = %d, want %d", key, got, testNowMillis)
		}
	}

	update := triggers.BuildProductViewUpdate(sampleProduct(), sampleCompany(), testNowMillis)
	got, ok := update["updated_at"].(int64)
	if !ok {
		t.Fatalf("update updated_at is %T, want int64 epoch millis", update["updated_at"])
	}
	if got != testNowMillis {
		t.Errorf("update updated_at = %d, want %d", got, testNowMillis)
	}
}

// The numeric types have to match what json_serializable generates for the
// Dart entity: `late int` fields are cast directly (`as int`), so a Firestore
// double there is a runtime TypeError, not a coercion.
func TestBuildProductView_NumericTypesMatchDartEntity(t *testing.T) {
	product := sampleProduct()
	// A product whose rate and ceiling were stored as whole numbers arrives
	// from the event as IntegerValue, not DoubleValue.
	product["interest_rate"] = int64(8)
	product["max_loanable_amount"] = int64(50000)

	view := triggers.BuildProductViewCreate("view-1", product, sampleCompany(), testNowMillis)

	if _, ok := view["interest_rate"].(float64); !ok {
		t.Errorf("interest_rate is %T, want float64 (Dart: late double)", view["interest_rate"])
	}
	if _, ok := view["max_loanable_amount"].(float64); !ok {
		t.Errorf("max_loanable_amount is %T, want float64 (Dart: late double)", view["max_loanable_amount"])
	}
	if _, ok := view["max_period"].(int64); !ok {
		t.Errorf("max_period is %T, want int64 (Dart: late int)", view["max_period"])
	}
	if _, ok := view["review_count"].(int64); !ok {
		t.Errorf("review_count is %T, want int64 (Dart: late int)", view["review_count"])
	}
	if _, ok := view["review_rating_avg"].(float64); !ok {
		t.Errorf("review_rating_avg is %T, want float64 (Dart: late double)", view["review_rating_avg"])
	}

	update := triggers.BuildProductViewUpdate(product, sampleCompany(), testNowMillis)
	if _, ok := update["interest_rate"].(float64); !ok {
		t.Errorf("update interest_rate is %T, want float64", update["interest_rate"])
	}
	if _, ok := update["max_period"].(int64); !ok {
		t.Errorf("update max_period is %T, want int64", update["max_period"])
	}
}

// A company with no reviews yet must seed zeroes rather than divide by zero.
func TestBuildProductViewCreate_SeedsZeroReviewCountersWithoutCompany(t *testing.T) {
	view := triggers.BuildProductViewCreate("view-1", sampleProduct(), nil, testNowMillis)

	if view["review_count"] != int64(0) {
		t.Errorf("review_count = %v (%T), want int64(0)", view["review_count"], view["review_count"])
	}
	if view["review_rating_avg"] != 0.0 {
		t.Errorf("review_rating_avg = %v (%T), want 0.0", view["review_rating_avg"], view["review_rating_avg"])
	}
}

// The review counters on product_views are a denormalization OF THE COMPANY —
// both the live Dart writer (loans_bloc.dart:653-654) and the dead
// createFromProductAndCompany derive them as company.total_rating /
// company.review_count. Seeding a flat zero for a lender that already has
// reviews would display "no reviews" until the next review is submitted.
func TestBuildProductViewCreate_SeedsReviewCountersFromCompany(t *testing.T) {
	view := triggers.BuildProductViewCreate("view-1", sampleProduct(), sampleCompany(), testNowMillis)

	if view["review_count"] != int64(4) {
		t.Errorf("review_count = %v, want int64(4) from the company", view["review_count"])
	}
	if view["review_rating_avg"] != 4.5 {
		t.Errorf("review_rating_avg = %v, want 4.5 (total_rating 18 / review_count 4)", view["review_rating_avg"])
	}
}

// tag_line lives on the COMPANY, not the product — product_entity.dart has no
// such field, company_entity.dart:59 does, and the dead Dart projection read
// company.tagLine. Sourcing it from the product would make it permanently
// empty and drop a third of the offer tokens.
func TestBuildProductView_TagLineComesFromCompany(t *testing.T) {
	product := sampleProduct()
	product["tag_line"] = "not-a-real-product-field"

	view := triggers.BuildProductViewUpdate(product, sampleCompany(), testNowMillis)

	if view["tag_line"] != "Fast cash for teachers" {
		t.Errorf("tag_line = %v, want the company's tag line", view["tag_line"])
	}
	tokens, _ := view["search_tokens"].([]string)
	assertHas(t, tokens, "teachers")
}

// max_period and allow_add_ons are `late` with a Dart defaultValue, so an
// absent key is legal — but the value written must match the default the app
// would have applied, or the same product renders differently depending on
// which side wrote the view.
func TestBuildProductViewCreate_MatchesDartDefaults(t *testing.T) {
	view := triggers.BuildProductViewCreate("view-1", map[string]any{"id": "prod-3"}, nil, testNowMillis)

	if view["max_period"] != int64(1) {
		t.Errorf("max_period = %v, want int64(1) (Dart defaultValue)", view["max_period"])
	}
	if view["allow_add_ons"] != true {
		t.Errorf("allow_add_ons = %v, want true (Dart defaultValue)", view["allow_add_ons"])
	}

	// An explicit 0 means "open term" and must survive, not fall back to 1.
	openTerm := triggers.BuildProductViewCreate("view-1", map[string]any{
		"id":         "prod-4",
		"max_period": int64(0),
	}, nil, testNowMillis)
	if openTerm["max_period"] != int64(0) {
		t.Errorf("max_period = %v, want int64(0) preserved for an open-term product", openTerm["max_period"])
	}
}

// --- upsert behaviour (defect D1) ---------------------------------------

type fakeProductViewStore struct {
	company     map[string]any
	companyErr  error
	existingIDs []string
	findErr     error

	loadedCompanyID string
	created         map[string]map[string]any
	updated         map[string]map[string]any
	newIDs          int
}

func (f *fakeProductViewStore) deps() triggers.ProductViewDeps {
	f.created = map[string]map[string]any{}
	f.updated = map[string]map[string]any{}
	return triggers.ProductViewDeps{
		LoadCompany: func(_ context.Context, companyId string) (map[string]any, error) {
			f.loadedCompanyID = companyId
			return f.company, f.companyErr
		},
		FindViewIDsByProduct: func(_ context.Context, _ string) ([]string, error) {
			return f.existingIDs, f.findErr
		},
		CreateView: func(_ context.Context, viewId string, view map[string]any) error {
			f.created[viewId] = view
			return nil
		},
		UpdateView: func(_ context.Context, viewId string, fields map[string]any) error {
			f.updated[viewId] = fields
			return nil
		},
		NewViewID: func() string {
			f.newIDs++
			return "generated-1"
		},
		Now: func() int64 { return testNowMillis },
	}
}

// TestHandleProductWrittenCore_UpdatesExistingView pins defect D1. Legacy
// product_views documents carry auto-generated doc IDs with product_id as a
// FIELD; writing to product_views/{productId} would leave every such product
// with two view documents, both showing up in every listing.
func TestHandleProductWrittenCore_UpdatesExistingView(t *testing.T) {
	store := &fakeProductViewStore{company: sampleCompany(), existingIDs: []string{"legacy-abc"}}
	deps := store.deps()

	if err := triggers.HandleProductWrittenCore(context.Background(), sampleProduct(), deps); err != nil {
		t.Fatalf("HandleProductWrittenCore: %v", err)
	}

	if len(store.created) != 0 {
		t.Errorf("created %v — an existing view must be updated, not duplicated", store.created)
	}
	fields, ok := store.updated["legacy-abc"]
	if !ok {
		t.Fatalf("updated %v, want the existing doc legacy-abc", store.updated)
	}
	if fields["company_name"] != "Acme Lending" {
		t.Errorf("company_name = %v, want Acme Lending", fields["company_name"])
	}
	if store.loadedCompanyID != "company-1" {
		t.Errorf("looked up company %q, want company-1", store.loadedCompanyID)
	}
}

func TestHandleProductWrittenCore_CreatesWhenNoViewExists(t *testing.T) {
	store := &fakeProductViewStore{company: sampleCompany()}
	deps := store.deps()

	if err := triggers.HandleProductWrittenCore(context.Background(), sampleProduct(), deps); err != nil {
		t.Fatalf("HandleProductWrittenCore: %v", err)
	}

	if len(store.updated) != 0 {
		t.Errorf("updated %v — nothing existed to update", store.updated)
	}
	view, ok := store.created["generated-1"]
	if !ok {
		t.Fatalf("created %v, want a doc under the newly allocated id", store.created)
	}
	// ProductViewEntity.id is both the doc ID and a stored field; the Dart
	// service reads back doc.data(), so a mismatch breaks get-by-id.
	if view["id"] != "generated-1" {
		t.Errorf("id field = %v, want the allocated doc id", view["id"])
	}
	if _, ok := view["created_at"]; !ok {
		t.Error("a created document must carry created_at")
	}
}

// If duplicates already exist, every one of them must stay in sync — picking
// one arbitrarily would leave the others showing stale data forever.
func TestHandleProductWrittenCore_UpdatesEveryDuplicate(t *testing.T) {
	store := &fakeProductViewStore{company: sampleCompany(), existingIDs: []string{"legacy-a", "legacy-b"}}
	deps := store.deps()

	if err := triggers.HandleProductWrittenCore(context.Background(), sampleProduct(), deps); err != nil {
		t.Fatalf("HandleProductWrittenCore: %v", err)
	}

	if len(store.updated) != 2 {
		t.Errorf("updated %d docs, want 2", len(store.updated))
	}
}

func TestHandleProductWrittenCore_RequiresProductID(t *testing.T) {
	store := &fakeProductViewStore{company: sampleCompany()}
	deps := store.deps()

	err := triggers.HandleProductWrittenCore(context.Background(), map[string]any{"loan_type": "Salary Loan"}, deps)
	if err == nil {
		t.Fatal("a product with no id must be an error, not a silently skipped projection")
	}
	if len(store.created)+len(store.updated) != 0 {
		t.Error("nothing may be written for a product with no id")
	}
}

// A transient company read failure must abort rather than project an empty
// company_name over a good denormalized value.
func TestHandleProductWrittenCore_CompanyReadFailureWritesNothing(t *testing.T) {
	store := &fakeProductViewStore{companyErr: errors.New("deadline exceeded"), existingIDs: []string{"legacy-abc"}}
	deps := store.deps()

	if err := triggers.HandleProductWrittenCore(context.Background(), sampleProduct(), deps); err == nil {
		t.Fatal("a company read failure must surface as an error")
	}
	if len(store.created)+len(store.updated) != 0 {
		t.Error("nothing may be written when the company could not be read")
	}
}
