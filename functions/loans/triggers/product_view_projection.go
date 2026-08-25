package triggers

import (
	"context"
	"errors"
	"fmt"
	"time"

	"cloud.google.com/go/firestore"
	"com.loooans.app/utils"
	"com.loooans.app/utils/search"
	"github.com/cloudevents/sdk-go/v2/event"
	"github.com/golang/protobuf/proto"
	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// ProductViewDeps are the collaborators HandleProductWrittenCore needs,
// injected so the upsert decision is unit-testable without Firestore.
type ProductViewDeps struct {
	// LoadCompany returns the companies document that owns the product, or
	// (nil, nil) when no such company exists. company_name, tag_line and the
	// review counters are denormalized onto the view from it.
	LoadCompany func(ctx context.Context, companyId string) (map[string]any, error)
	// FindViewIDsByProduct returns the IDs of every product_views document
	// carrying this product_id. Lookup is by FIELD, not by document ID — see
	// the doc ID note on HandleProductWrittenCore.
	FindViewIDsByProduct func(ctx context.Context, productId string) ([]string, error)
	// CreateView writes a brand-new product_views document under viewId.
	CreateView func(ctx context.Context, viewId string, view map[string]any) error
	// UpdateView merges the projected fields onto an existing document.
	UpdateView func(ctx context.Context, viewId string, fields map[string]any) error
	// Now returns the current time as epoch milliseconds.
	Now func() int64
}

// HandleProductWrittenCore projects a products document onto its product_views
// document, creating that document if it does not exist yet.
//
// Ownership of this projection lives here rather than in the Flutter client so
// that no client version can write a view that is missing fields or
// unsearchable. Nothing in Dart ever created a product_views document — the
// `add` path is dead code — so this trigger is the only creator, which is why
// the create payload below has to be complete rather than merely sufficient.
//
// The LOOKUP is by `product_id` field rather than by document ID. Legacy
// documents were created with auto-generated IDs carrying product_id as a
// field, and the Dart service still reads them with
// `where('product_id', isEqualTo: …)`. Looking up product_views/{productId}
// instead would give every already-projected product a second document, with
// both appearing in every listing. The query is equality-only, so it is served
// by the automatic single-field index; product_views is small and product
// writes are rare, so a read per write is negligible.
//
// A CREATE, on the other hand, keys the new document on the product ID — see
// the comment on that branch below. The two are not in tension: the field
// query still finds every legacy auto-ID document, so no existing ID changes.
func HandleProductWrittenCore(ctx context.Context, product map[string]any, deps ProductViewDeps) error {
	productId, _ := product["id"].(string)
	if productId == "" {
		return errors.New("product_view_projection: product has no id")
	}

	// The company is read before anything is written. A transient read failure
	// aborts the whole projection rather than proceeding with an empty
	// company_name, which the update path would otherwise merge over a
	// perfectly good denormalized value.
	var company map[string]any
	if companyId, _ := product["provider_id"].(string); companyId != "" {
		loaded, err := deps.LoadCompany(ctx, companyId)
		if err != nil {
			return fmt.Errorf("read company %s for product %s: %w", companyId, productId, err)
		}
		company = loaded
	}

	viewIds, err := deps.FindViewIDsByProduct(ctx, productId)
	if err != nil {
		return fmt.Errorf("find product_views for %s: %w", productId, err)
	}

	now := deps.Now()

	if len(viewIds) == 0 {
		// The created document is keyed on the product ID, not on a freshly
		// allocated random one. Firestore triggers are delivered at-least-once,
		// so the same product write can arrive twice; two deliveries (or two
		// rapid edits) that both query before either write lands each see zero
		// views. With a random ID each would create its own document, leaving
		// one product with two views — the exact duplication the field lookup
		// exists to prevent, and one the update-every-duplicate loop below
		// would then keep permanently in sync so nobody ever notices. A
		// deterministic ID makes concurrent creates converge on one document.
		viewId := productId
		if err := deps.CreateView(ctx, viewId, BuildProductViewCreate(viewId, product, company, now)); err != nil {
			return fmt.Errorf("create product_view for product %s: %w", productId, err)
		}
		return nil
	}

	// More than one match means duplicates already exist in the data. Update
	// every one of them: picking a single winner would leave the others
	// showing stale data indefinitely.
	fields := BuildProductViewUpdate(product, company, now)
	for _, viewId := range viewIds {
		if err := deps.UpdateView(ctx, viewId, fields); err != nil {
			return fmt.Errorf("update product_view %s: %w", viewId, err)
		}
	}
	return nil
}

// BuildProductViewCreate returns the complete product_views document for a
// product that has no view yet.
//
// ProductViewEntity declares fourteen fields `late` (twelve of them without a
// defaultValue), so its fromJson throws — crashing the offers list — if any is
// absent. The create payload therefore carries every one of them, including the
// two the review flow owns thereafter (review_rating_avg, review_count), seeded
// from the company.
func BuildProductViewCreate(viewId string, product, company map[string]any, nowMillis int64) map[string]any {
	view := projectedProductFields(product, company)

	// ProductViewEntity.id is both the document ID and a stored field.
	view["id"] = viewId
	view["updated_at"] = nowMillis

	// created_at is the PRODUCT's own creation time when it has one, not the
	// moment this projection ran: loadNext() pages the marketplace with
	// orderBy('created_at') ASCENDING (product_view_firestore_service.dart:198),
	// and Task 7 backfills every product in a single burst, which would
	// otherwise order that stream by backfill order rather than by product age.
	createdAt := nowMillis
	if millis, ok := productMillis(product, "created_at"); ok {
		createdAt = millis
	}
	view["created_at"] = createdAt

	// The review counters on a view are a denormalization of the company:
	// both the live Dart writer (loans_bloc.dart:653-654) and the retired
	// ProductView.createFromProductAndCompany derive them the same way. A
	// company with no reviews yet seeds zeroes rather than dividing by zero.
	reviewCount := mapInt64(company, "review_count", 0)
	reviewRatingAvg := 0.0
	if reviewCount > 0 {
		reviewRatingAvg = mapFloat64(company, "total_rating") / float64(reviewCount)
	}
	view["review_count"] = reviewCount
	view["review_rating_avg"] = reviewRatingAvg

	return view
}

// BuildProductViewUpdate returns only the fields this projection owns, to be
// merged onto an existing product_views document.
//
// It deliberately omits created_at and the two review counters:
// review_rating_avg and review_count are maintained by the review flow, and
// re-deriving them from the company on every product edit would race that
// flow's own write. created_at belongs to creation.
func BuildProductViewUpdate(product, company map[string]any, nowMillis int64) map[string]any {
	view := projectedProductFields(product, company)
	view["updated_at"] = nowMillis

	// A company that is genuinely absent must not blank a denormalization that
	// is already correct. (A company READ FAILURE never reaches here — the
	// core aborts before writing anything.) Merging company_name: "" plus
	// search_tokens rebuilt without the lender's name would make the offer
	// unfindable by lender, silently, on the next unrelated product edit.
	// Create still writes the empty shape, because there is nothing there to
	// preserve and the entity requires the keys.
	if company == nil {
		for _, key := range companyDerivedKeys {
			delete(view, key)
		}
	}
	return view
}

// companyDerivedKeys are the view fields whose value comes from the companies
// document rather than from the product. search_tokens belongs here because two
// of its three inputs (company name, tag line) are company-derived; rebuilding
// it from loan_type alone would strip the lender's name out of the index.
// company_id is NOT in the list — it is product.provider_id.
var companyDerivedKeys = []string{
	"company_name",
	"tag_line",
	"company_profile_photo_url",
	"search_tokens",
}

// projectedProductFields is the field set common to both payloads: everything
// this trigger derives from the products document and its company.
func projectedProductFields(product, company map[string]any) map[string]any {
	companyName := mapString(company, "name")
	loanType := mapString(product, "loan_type")
	// tag_line is a COMPANY field — product_entity.dart has none. Reading it
	// off the product would leave it permanently empty and silently drop a
	// third of the offer's search tokens.
	tagLine := mapString(company, "tag_line")

	view := map[string]any{
		"company_id":   mapString(product, "provider_id"),
		"company_name": companyName,
		"product_id":   mapString(product, "id"),
		"loan_type":    loanType,
		"term":         mapString(product, "term"),
		// Written as float64 / int64 to match the Dart entity's `late double`
		// and `late int`: json_serializable casts int fields directly
		// (`as int`), so a Firestore double there is a runtime TypeError.
		"interest_rate":       mapFloat64(product, "interest_rate"),
		"max_loanable_amount": mapFloat64(product, "max_loanable_amount"),
		// Defaults mirror the entity's own @JsonKey defaultValue, so a view
		// written here renders identically to one parsed with the field
		// absent. An explicit 0 means "open term" and is preserved.
		"max_period":    mapInt64(product, "max_period", 1),
		"allow_add_ons": mapBool(product, "allow_add_ons", true),
		"search_tokens": search.ProductViewTokens(companyName, loanType, tagLine),
		// deleted_at follows the PRODUCT on BOTH paths, because the view's
		// lifecycle is the product's. Products are only ever soft-deleted
		// (product_firestore_service.dart:29-35 sets deleted_at and calls
		// update), which arrives here as an ordinary write: if the update path
		// left the view's deleted_at alone, the deleted offer would stay
		// visible to `where('deleted_at', isNull: true)` AND be floated to the
		// top of the marketplace by the bumped updated_at, which the listing
		// orders by descending. Clearing deleted_at has to restore the offer
		// for the same reason. It is written unconditionally — as an explicit
		// null for a live product — because Firestore's `isNull: true`, used by
		// both Dart read paths, matches only documents where the field exists.
		"deleted_at": productDeletedAt(product),
	}

	// tag_line and company_profile_photo_url are nullable on the entity;
	// writing an explicit null when the company carries neither keeps the
	// document shape identical to what the Dart projection produced.
	if tagLine != "" {
		view["tag_line"] = tagLine
	} else {
		view["tag_line"] = nil
	}
	view["company_profile_photo_url"] = mapValue(company, "company_profile_photo_url")

	return view
}

// productDeletedAt renders the product's deleted_at the way the view stores it:
// epoch millis when the product is soft-deleted, and an explicit null — never
// an absent key — when it is live.
func productDeletedAt(product map[string]any) any {
	if millis, ok := productMillis(product, "deleted_at"); ok {
		return millis
	}
	return nil
}

// productMillis reads an epoch-millis field off the product, reporting !ok when
// it is absent, null, or not a number.
func productMillis(product map[string]any, key string) (int64, bool) {
	raw, ok := product[key]
	if !ok || raw == nil {
		return 0, false
	}
	return utils.ToInt64(raw)
}

func mapValue(m map[string]any, key string) any {
	if m == nil {
		return nil
	}
	return m[key]
}

func mapString(m map[string]any, key string) string {
	value, _ := mapValue(m, key).(string)
	return value
}

// mapFloat64 coerces a Firestore number to float64. Firestore hands integral
// values back as int64, so a rate stored as 8 rather than 8.0 must still land
// in the view as a double.
func mapFloat64(m map[string]any, key string) float64 {
	switch value := mapValue(m, key).(type) {
	case float64:
		return value
	case int64:
		return float64(value)
	case int:
		return float64(value)
	default:
		return 0
	}
}

// mapInt64 returns def only when the key is absent or unusable — a stored zero
// is a real value and is kept.
func mapInt64(m map[string]any, key string, def int64) int64 {
	raw := mapValue(m, key)
	if raw == nil {
		return def
	}
	if value, ok := utils.ToInt64(raw); ok {
		return value
	}
	return def
}

func mapBool(m map[string]any, key string, def bool) bool {
	value, ok := mapValue(m, key).(bool)
	if !ok {
		return def
	}
	return value
}

// ProductWritten is the CloudEvent adapter. It wires real Firestore into the
// core. Registered as the productWritten entry point, firing on every write to
// products/{productId}.
//
// No recursion guard is needed: this fires on products, and everything it
// writes goes to product_views.
func ProductWritten(ctx context.Context, ev event.Event) error {
	log, logErr := utils.InitializeLogger("product_written")
	if logErr != nil {
		return logErr
	}

	var data firestoredata.DocumentEventData
	if err := proto.Unmarshal(ev.Data(), &data); err != nil {
		return fmt.Errorf("proto.Unmarshal: %w", err)
	}

	// A hard delete leaves no new value. Products are soft-deleted in practice
	// (deleted_at), which arrives here as an ordinary update; a genuine
	// document removal is out of this projection's scope.
	if data.GetValue() == nil {
		log.Debug("product document removed, nothing to project")
		return nil
	}

	product := flattenProductFields(data.GetValue().GetFields())

	app, fbErr := utils.InitializeFirebase(ctx)
	if fbErr != nil {
		return fbErr
	}
	fs, fsErr := app.Firestore(ctx)
	if fsErr != nil {
		return fmt.Errorf("failed to instantiate firestore client: %w", fsErr)
	}
	defer fs.Close()

	prefix := utils.GetCollectionPrefix()
	views := fs.Collection(prefix + "product_views")

	deps := ProductViewDeps{
		LoadCompany: func(ctx context.Context, companyId string) (map[string]any, error) {
			snap, err := fs.Collection(prefix + "companies").Doc(companyId).Get(ctx)
			if err != nil {
				// A company that genuinely does not exist must not block the
				// projection — the offer is still worth publishing, and the
				// next product write picks the name up. Any other error is
				// transient and is propagated, because merging an empty
				// company_name over a good one destroys data.
				if status.Code(err) == codes.NotFound {
					// Error, not warn: a product pointing at a company that
					// does not exist is broken referential integrity, not a
					// normal state.
					log.Sugar().Errorf("product_written: company %s not found", companyId)
					return nil, nil
				}
				return nil, err
			}
			return snap.Data(), nil
		},
		FindViewIDsByProduct: func(ctx context.Context, productId string) ([]string, error) {
			iter := views.Where("product_id", "==", productId).Documents(ctx)
			defer iter.Stop()

			ids := []string{}
			for {
				doc, err := iter.Next()
				if err == iterator.Done {
					break
				}
				if err != nil {
					return nil, err
				}
				ids = append(ids, doc.Ref.ID)
			}
			return ids, nil
		},
		CreateView: func(ctx context.Context, viewId string, view map[string]any) error {
			_, err := views.Doc(viewId).Set(ctx, view)
			return err
		},
		UpdateView: func(ctx context.Context, viewId string, fields map[string]any) error {
			_, err := views.Doc(viewId).Set(ctx, fields, firestore.MergeAll)
			return err
		},
		Now: func() int64 { return time.Now().UnixMilli() },
	}

	return HandleProductWrittenCore(ctx, product, deps)
}

// flattenProductFields converts the event payload into the map the projection
// reads, keeping each number's own type: integers stay int64 so the builders
// can coerce per the Dart entity's declared type rather than guessing.
func flattenProductFields(fields map[string]*firestoredata.Value) map[string]any {
	out := map[string]any{}
	for key, value := range fields {
		switch key {
		case "id", "provider_id", "loan_type", "term":
			out[key] = value.GetStringValue()
		case "interest_rate", "max_loanable_amount", "max_period":
			if number, ok := numericValue(value); ok {
				out[key] = number
			}
		case "allow_add_ons":
			if _, ok := value.GetValueType().(*firestoredata.Value_BooleanValue); ok {
				out[key] = value.GetBooleanValue()
			}
		case "created_at", "deleted_at":
			// Both are int millis when Dart wrote them (handleDateTimeToJson)
			// and a Timestamp when anything Go did; intMillisFromValue accepts
			// either and reports !ok for absent, null and every other type.
			// deleted_at is absent for a live product and a NullValue once
			// cleared, which productDeletedAt renders as an explicit null;
			// created_at falls back to projection time.
			if millis, ok := intMillisFromValue(value); ok {
				out[key] = millis
			}
		}
	}
	return out
}

func numericValue(v *firestoredata.Value) (any, bool) {
	switch v.GetValueType().(type) {
	case *firestoredata.Value_IntegerValue:
		return v.GetIntegerValue(), true
	case *firestoredata.Value_DoubleValue:
		return v.GetDoubleValue(), true
	default:
		return nil, false
	}
}
