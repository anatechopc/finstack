// Package backfill populates search_tokens on existing documents.
//
// Documents written before the search work carry no search_tokens and are
// therefore invisible to search — the backfill's completeness is a correctness
// requirement, not a nicety. It is safe to re-run: documents that already carry
// what the triggers would write are skipped, so a second pass writes nothing.
//
// Two collections, two shapes:
//
//   - users. Tokens are computed through triggers.SearchTokensForUser, the same
//     function userChanges and userCreated call. Computing them from a
//     separately-assembled argument list here would let the two disagree about
//     which fields feed the tokens, and then the trigger would rewrite every
//     backfilled user on its next edit — forever, silently, because both writes
//     succeed.
//
//   - products, NOT product_views. Nothing in Dart ever created a
//     product_views document, so a product may have no view at all; paging
//     product_views cannot create the missing ones, and the projection trigger
//     only fires when a product is next written, which for a dormant product
//     may be never. Paging products and running the trigger's own upsert
//     (triggers.HandleProductWrittenCore) creates what is missing and completes
//     what is partial, using the exact projection the trigger uses. That
//     projection — BuildProductViewCreate / BuildProductViewUpdate — is the only
//     thing enforcing ProductViewEntity's fourteen `late` fields, so it is
//     reused rather than reimplemented.
//
// Writing search_tokens to a user fires userChanges once per updated document.
// Each of those invocations is a no-op — the trigger recomputes, finds the
// tokens already match and returns without writing — but it is not free, which
// is why the report states the count.
package backfill

import (
	"context"
	"fmt"
	"log"
	"reflect"
	"sort"

	"com.loooans.app/triggers"
)

// Report counts one pass over one collection. Every counter is filled the same
// way in a dry run as in a real one, so `-dry-run=true` answers "what would
// this do" exactly.
type Report struct {
	Collection string
	// Scanned counts documents read from the collection being paged.
	Scanned int
	// Created counts product_views documents created. Always 0 for users.
	Created int
	// Updated counts documents written. For products this counts VIEWS, not
	// products: a product with duplicate views contributes one per view.
	Updated int
	// Skipped counts documents that already carry what would be written.
	Skipped int
	// MissingView counts products with no product_views document at all — the
	// offers that were invisible to the marketplace, not merely unsearchable.
	MissingView int
	// Failed counts documents whose projection returned an error. The pass
	// continues past them so one bad document cannot strand the rest, and Run
	// returns a non-nil error at the end so the exit code still reflects it.
	Failed int
}

func (r Report) String() string {
	return fmt.Sprintf(
		"%s: scanned=%d created=%d updated=%d skipped=%d missing_view=%d failed=%d",
		r.Collection, r.Scanned, r.Created, r.Updated, r.Skipped, r.MissingView, r.Failed)
}

// NeedsUpdate reports whether doc's stored tokens differ from want.
//
// doc is a document as the Firestore client returns it, so search_tokens is
// []any of strings — never []string. The comparison is index-by-index rather
// than set-based because every token producer sorts (tokenizer.go, phone.go,
// entities.go) and every writer writes what they produced.
func NeedsUpdate(doc map[string]any, want []string) bool {
	rawValues, _ := doc["search_tokens"].([]any)

	existing := make([]string, 0, len(rawValues))
	for _, raw := range rawValues {
		if value, ok := raw.(string); ok {
			existing = append(existing, value)
		}
	}

	if len(existing) != len(want) {
		return true
	}
	for i := range existing {
		if existing[i] != want[i] {
			return true
		}
	}
	return false
}

// UserDeps is the users pass's I/O, injected so the run loop is testable
// without Firestore.
type UserDeps struct {
	// EachUser visits every users document. The adapter pages; the core does
	// not know or care where a page boundary falls.
	EachUser func(ctx context.Context, visit func(id string, user map[string]any) error) error
	// UpdateUser merges fields onto the user document.
	UpdateUser func(ctx context.Context, id string, fields map[string]any) error
}

// RunUsersCore writes search_tokens onto every users document that does not
// already carry the tokens the trigger would write.
func RunUsersCore(ctx context.Context, deps UserDeps, dryRun bool) (*Report, error) {
	report := &Report{Collection: "users"}

	err := deps.EachUser(ctx, func(id string, user map[string]any) error {
		report.Scanned++

		// The trigger's own function, not a re-derivation: it decides both what
		// the tokens are and whether they already match. Its bool is the same
		// recursion guard that stops userChanges re-firing on its own write,
		// which is exactly the "already migrated" test this pass needs.
		tokens, needsWrite := triggers.SearchTokensForUser(user)
		if !needsWrite {
			report.Skipped++
			return nil
		}

		if dryRun {
			report.Updated++
			return nil
		}
		if err := deps.UpdateUser(ctx, id, map[string]any{"search_tokens": tokens}); err != nil {
			// Counted as failed and NOT as updated: one unwritable user must
			// not strand the rest, and the summary has to stay honest about
			// what actually landed.
			report.Failed++
			log.Printf("users/%s: %v", id, err)
			return nil
		}
		report.Updated++
		return nil
	})
	if err != nil {
		return report, err
	}
	return report, failureError(report)
}

// ProductDeps is the products pass's I/O. LoadCompany, CreateView and
// UpdateView are handed to triggers.ProductViewDeps after the backfill wraps
// them with its cache, its skip decision and its counters.
type ProductDeps struct {
	// EachProduct visits every products document.
	EachProduct func(ctx context.Context, visit func(id string, product map[string]any) error) error
	// LoadCompany returns the companies document, or (nil, nil) when there is
	// none. Called at most once per company — the backfill caches.
	LoadCompany func(ctx context.Context, companyId string) (map[string]any, error)
	// FindViews returns every product_views document carrying this product_id,
	// keyed by document ID. It returns the DATA and not just the IDs the
	// trigger asks for, because the backfill's skip decision has to compare the
	// projection against what is already stored, and re-reading each view for
	// that would double the read cost of the job.
	FindViews  func(ctx context.Context, productId string) (map[string]map[string]any, error)
	CreateView func(ctx context.Context, viewId string, view map[string]any) error
	UpdateView func(ctx context.Context, viewId string, fields map[string]any) error
	// Now returns the current time as epoch milliseconds.
	Now func() int64
}

// RunProductsCore pages products and runs the projection trigger's own upsert
// against each one, creating the view when none exists and updating every
// existing view otherwise.
//
// It pages products rather than product_views on purpose. A product with no
// view is invisible to the marketplace entirely, not merely unsearchable, and
// nothing but this pass or a future write to that product will ever create one.
func RunProductsCore(ctx context.Context, deps ProductDeps, dryRun bool) (*Report, error) {
	report := &Report{Collection: "products"}
	companies := map[string]map[string]any{}

	err := deps.EachProduct(ctx, func(id string, product map[string]any) error {
		report.Scanned++

		// HandleProductWrittenCore refuses a product with no id, which in a
		// batch would strand every product after this one. The document ID is
		// the product ID by construction, so supply it rather than fail.
		if productId, _ := product["id"].(string); productId == "" {
			product["id"] = id
		}

		// existing is repopulated by FindViewIDsByProduct below, before any
		// UpdateView call for this product can run.
		var existing map[string]map[string]any

		viewDeps := triggers.ProductViewDeps{
			LoadCompany: func(ctx context.Context, companyId string) (map[string]any, error) {
				if company, cached := companies[companyId]; cached {
					return company, nil
				}
				company, err := deps.LoadCompany(ctx, companyId)
				if err != nil {
					return nil, err
				}
				// A nil company is cached too: "this lender does not exist" is
				// an answer worth not paying for once per product.
				companies[companyId] = company
				return company, nil
			},
			FindViewIDsByProduct: func(ctx context.Context, productId string) ([]string, error) {
				views, err := deps.FindViews(ctx, productId)
				if err != nil {
					return nil, err
				}
				existing = views
				if len(views) == 0 {
					report.MissingView++
				}
				return sortedKeys(views), nil
			},
			CreateView: func(ctx context.Context, viewId string, view map[string]any) error {
				if !dryRun {
					// Counted after the write, so a failed write shows up in
					// Failed and never in Created.
					if err := deps.CreateView(ctx, viewId, view); err != nil {
						return err
					}
				}
				report.Created++
				return nil
			},
			UpdateView: func(ctx context.Context, viewId string, fields map[string]any) error {
				if !viewNeedsUpdate(existing[viewId], fields) {
					report.Skipped++
					return nil
				}
				if !dryRun {
					if err := deps.UpdateView(ctx, viewId, fields); err != nil {
						return err
					}
				}
				report.Updated++
				return nil
			},
			Now: deps.Now,
		}

		if err := triggers.HandleProductWrittenCore(ctx, product, viewDeps); err != nil {
			// One unprojectable product must not strand the rest of the
			// catalogue: count it, name it, keep going, exit non-zero.
			report.Failed++
			log.Printf("products/%s: %v", id, err)
		}
		return nil
	})
	if err != nil {
		return report, err
	}
	return report, failureError(report)
}

// viewNeedsUpdate reports whether the stored view is missing anything the
// projection would write.
func viewNeedsUpdate(existing map[string]any, fields map[string]any) bool {
	if existing == nil {
		return true
	}

	for key, want := range fields {
		// updated_at is a write stamp, not content. Comparing it would make
		// every pass rewrite every view — and because the marketplace listing
		// is orderBy('updated_at', descending), each backfill run would then
		// reshuffle the entire offers list for no reason.
		if key == "updated_at" {
			continue
		}

		if key == "search_tokens" {
			tokens, _ := want.([]string)
			if NeedsUpdate(existing, tokens) {
				return true
			}
			continue
		}

		stored, present := existing[key]
		// Presence is checked separately from value because for deleted_at the
		// difference is load-bearing: both Dart read paths filter
		// where('deleted_at', isNull: true), and Firestore matches that only
		// when the field EXISTS. An absent deleted_at is not an equal-to-null
		// deleted_at — it is an offer missing from every listing.
		if !present || !sameFieldValue(stored, want) {
			return true
		}
	}
	return false
}

// sameFieldValue compares a stored Firestore value against a projected one.
// A type difference counts as a difference on purpose: the projection writes
// int64 where the Dart entity declares `late int` and float64 where it declares
// `late double`, and a document storing the other type is one this pass exists
// to fix.
func sameFieldValue(stored, want any) bool {
	if stored == nil || want == nil {
		return stored == nil && want == nil
	}
	// DeepEqual rather than ==, which panics when both sides hold the same
	// non-comparable dynamic type.
	return reflect.DeepEqual(stored, want)
}

func failureError(report *Report) error {
	if report.Failed == 0 {
		return nil
	}
	return fmt.Errorf("%s: %d document(s) failed; re-run to retry them", report.Collection, report.Failed)
}

func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for key := range m {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}
