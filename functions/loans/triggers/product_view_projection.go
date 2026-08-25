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
	// NewViewID allocates a document ID without writing anything.
	NewViewID func() string
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
// The lookup is by `product_id` field rather than by document ID. Legacy
// documents were created with auto-generated IDs carrying product_id as a
// field, and the Dart service still reads them with
// `where('product_id', isEqualTo: …)`. Writing to product_views/{productId}
// instead would give every already-projected product a second document, with
// both appearing in every listing. The query is equality-only, so it is served
// by the automatic single-field index; product_views is small and product
// writes are rare, so a read per write is negligible.
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
		viewId := deps.NewViewID()
		if err := deps.CreateView(ctx, viewId, BuildProductViewCreate(viewId, product, company, now)); err != nil {
			return fmt.Errorf("create product_view %s for product %s: %w", viewId, productId, err)
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
// ProductViewEntity declares twelve fields `late` and non-nullable, so its
// fromJson throws — crashing the offers list — if any is absent. The create
// payload therefore carries every one of them, including the two the review
// flow owns thereafter (review_rating_avg, review_count), seeded from the
// company. deleted_at is written as an explicit null because Firestore's
// `isNull: true` filter, which both Dart read paths use, matches only
// documents where the field exists.
func BuildProductViewCreate(viewId string, product, company map[string]any, nowMillis int64) map[string]any {
	view := projectedProductFields(product, company)

	// ProductViewEntity.id is both the document ID and a stored field.
	view["id"] = viewId
	view["created_at"] = nowMillis
	view["updated_at"] = nowMillis
	view["deleted_at"] = productDeletedAt(product)

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
	return view
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

// productDeletedAt carries a soft-deleted product's deleted_at onto a newly
// created view. Without it the trigger — now the only creator — would publish
// a visible offer for a product that was deleted before it was ever projected.
func productDeletedAt(product map[string]any) any {
	raw, ok := product["deleted_at"]
	if !ok || raw == nil {
		return nil
	}
	if millis, ok := utils.ToInt64(raw); ok {
		return millis
	}
	return nil
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
					log.Sugar().Warnf("product_written: company %s not found", companyId)
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
		NewViewID: func() string { return views.NewDoc().ID },
		Now:       func() int64 { return time.Now().UnixMilli() },
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
		case "deleted_at":
			// Absent for a live product, and a NullValue once cleared —
			// intMillisFromValue reports !ok for both, which productDeletedAt
			// renders as an explicit null.
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
