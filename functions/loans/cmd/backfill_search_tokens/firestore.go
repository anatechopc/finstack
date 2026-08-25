package backfill

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"com.loooans.app/utils"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Collection names this job accepts.
const (
	CollectionUsers = "users"
	// CollectionProducts is `products`, NOT `product_views`. See the package
	// comment: paging the views cannot create the ones that were never written.
	CollectionProducts = "products"
)

// pageSize is how many documents one query pulls. Also the write-batch size —
// the BulkWriter's jobs are drained every pageSize writes so a failure is
// surfaced while the run is still in progress rather than at the very end.
const pageSize = 500

// Options configures one pass.
type Options struct {
	// Collection is CollectionUsers or CollectionProducts.
	Collection string
	// ProjectID is the Firebase/GCP project, e.g. loooans-dev-stg.
	ProjectID string
	// DryRun reports what would change and writes nothing. Defaults to true at
	// the flag layer; a zero-value Options is a *writing* run, so callers must
	// set it deliberately.
	DryRun bool
	// AllowProduction must be set for a writing run against a production
	// project. A dry run never needs it.
	AllowProduction bool
}

// Run executes one pass over one collection against a real Firestore.
//
// The environment-based collection prefix comes from utils.GetCollectionPrefix,
// i.e. from the ENVIRONMENT variable — the same source every trigger uses.
// Running with ENVIRONMENT unset against a dev project would page the
// unprefixed production-shaped collections and find nothing, so it is rejected
// rather than reported as a clean zero-document pass.
func Run(ctx context.Context, opts Options) (*Report, error) {
	if opts.Collection == "product_views" {
		return nil, fmt.Errorf(
			"collection %q: page %q instead — nothing in the app ever created a product_views "+
				"document, so paging the views cannot create the ones that are missing",
			opts.Collection, CollectionProducts)
	}
	if opts.Collection != CollectionUsers && opts.Collection != CollectionProducts {
		return nil, fmt.Errorf("collection must be %q or %q, got %q",
			CollectionUsers, CollectionProducts, opts.Collection)
	}
	if opts.ProjectID == "" {
		return nil, fmt.Errorf("-project is required")
	}
	if err := checkProductionGuard(opts); err != nil {
		return nil, err
	}

	environment := os.Getenv("ENVIRONMENT")
	if environment == "" {
		return nil, fmt.Errorf("ENVIRONMENT is required (development|staging|production) — " +
			"it selects the Firestore collection prefix")
	}
	prefix := utils.GetCollectionPrefix()

	client, err := firestore.NewClient(ctx, opts.ProjectID)
	if err != nil {
		return nil, fmt.Errorf("firestore client for %s: %w", opts.ProjectID, err)
	}
	defer client.Close()

	mode := "DRY RUN (no writes)"
	if !opts.DryRun {
		mode = "WRITING"
	}
	log.Printf("%s — project=%s environment=%s collection=%s%s",
		mode, opts.ProjectID, environment, prefix, opts.Collection)

	writer := newBulkWriter(ctx, client, opts.DryRun)
	defer writer.abandon()

	var report *Report
	if opts.Collection == CollectionUsers {
		report, err = RunUsersCore(ctx, firestoreUserDeps(client, prefix, writer), opts.DryRun)
	} else {
		report, err = RunProductsCore(ctx, firestoreProductDeps(client, prefix, writer), opts.DryRun)
	}

	// Pending writes are flushed even when the pass reported an error: the
	// documents that did succeed should land rather than be thrown away.
	if flushErr := writer.close(); flushErr != nil && err == nil {
		err = flushErr
	}
	return report, err
}

// checkProductionGuard refuses a writing run against production unless it was
// asked for explicitly. Dry runs are always allowed — reading production to see
// what a backfill *would* do is exactly how you decide whether to run it.
func checkProductionGuard(opts Options) error {
	if opts.DryRun || opts.AllowProduction {
		return nil
	}
	if strings.Contains(opts.ProjectID, "prod") || os.Getenv("ENVIRONMENT") == "production" {
		return fmt.Errorf(
			"refusing to write to %q: production runs need -allow-production as well as -dry-run=false",
			opts.ProjectID)
	}
	return nil
}

func firestoreUserDeps(client *firestore.Client, prefix string, writer *bulkWriter) UserDeps {
	users := client.Collection(prefix + "users")
	return UserDeps{
		EachUser: func(ctx context.Context, visit func(id string, user map[string]any) error) error {
			return eachDocument(ctx, users, visit)
		},
		UpdateUser: func(ctx context.Context, id string, fields map[string]any) error {
			return writer.set(users.Doc(id), fields, firestore.MergeAll)
		},
	}
}

func firestoreProductDeps(client *firestore.Client, prefix string, writer *bulkWriter) ProductDeps {
	products := client.Collection(prefix + "products")
	companies := client.Collection(prefix + "companies")
	views := client.Collection(prefix + "product_views")

	return ProductDeps{
		EachProduct: func(ctx context.Context, visit func(id string, product map[string]any) error) error {
			return eachDocument(ctx, products, visit)
		},
		LoadCompany: func(ctx context.Context, companyId string) (map[string]any, error) {
			snap, err := companies.Doc(companyId).Get(ctx)
			if err != nil {
				// Same distinction the trigger draws: a company that does not
				// exist is broken referential integrity but must not block the
				// projection, while any other error is transient and is
				// propagated rather than allowed to blank a good denormalization.
				if status.Code(err) == codes.NotFound {
					log.Printf("company %s not found", companyId)
					return nil, nil
				}
				return nil, err
			}
			return snap.Data(), nil
		},
		FindViews: func(ctx context.Context, productId string) (map[string]map[string]any, error) {
			// Lookup is by the product_id FIELD, not by document ID: legacy
			// views carry auto-generated IDs, and the Dart service still reads
			// them with where('product_id', isEqualTo: …). Equality-only, so
			// the automatic single-field index serves it.
			iter := views.Where("product_id", "==", productId).Documents(ctx)
			defer iter.Stop()

			found := map[string]map[string]any{}
			for {
				doc, err := iter.Next()
				if err == iterator.Done {
					break
				}
				if err != nil {
					return nil, err
				}
				found[doc.Ref.ID] = doc.Data()
			}
			return found, nil
		},
		CreateView: func(ctx context.Context, viewId string, view map[string]any) error {
			return writer.set(views.Doc(viewId), view)
		},
		UpdateView: func(ctx context.Context, viewId string, fields map[string]any) error {
			return writer.set(views.Doc(viewId), fields, firestore.MergeAll)
		},
		Now: func() int64 { return time.Now().UnixMilli() },
	}
}

// eachDocument pages a collection by document ID and visits every document.
//
// Paging explicitly rather than streaming the whole collection keeps each query
// inside its own deadline, so a large collection cannot fail the job partway
// through with a stream timeout. Ordering by document ID gives a stable cursor
// that no concurrent field write can move.
func eachDocument(ctx context.Context, coll *firestore.CollectionRef, visit func(id string, doc map[string]any) error) error {
	query := coll.OrderBy(firestore.DocumentID, firestore.Asc).Limit(pageSize)
	var cursor *firestore.DocumentSnapshot
	seen := 0

	for {
		page := query
		if cursor != nil {
			// The snapshot form, not the raw ID: it derives the cursor values
			// from the query's own OrderBy, so the two cannot drift apart.
			page = page.StartAfter(cursor)
		}

		docs, err := page.Documents(ctx).GetAll()
		if err != nil {
			return fmt.Errorf("page %s after %d document(s): %w", coll.ID, seen, err)
		}
		if len(docs) == 0 {
			return nil
		}

		for _, doc := range docs {
			if err := visit(doc.Ref.ID, doc.Data()); err != nil {
				return err
			}
		}

		seen += len(docs)
		log.Printf("%s: %d document(s) scanned", coll.ID, seen)

		if len(docs) < pageSize {
			return nil
		}
		cursor = docs[len(docs)-1]
	}
}

// bulkWriter batches the round trips without losing individual write errors.
//
// The reused trigger core hands writes over one document at a time, so a
// WriteBatch would have to be threaded through it. A BulkWriter takes them one
// at a time and batches internally — but its errors surface only through each
// job's Results(), so the jobs are kept and drained every pageSize writes. A
// backfill that silently dropped write failures would report a clean pass over
// documents it never fixed, which is the one outcome worse than not running it.
//
// A drained error is reported against whichever document triggered the drain
// rather than the one that actually failed, so the Failed counter's attribution
// is approximate to within one batch. The error text names the real document
// path, and re-running is the remedy either way.
type bulkWriter struct {
	writer *firestore.BulkWriter
	jobs   []*firestore.BulkWriterJob
	closed bool
}

func newBulkWriter(ctx context.Context, client *firestore.Client, dryRun bool) *bulkWriter {
	if dryRun {
		// No writer at all on a dry run: set() is never reached, and not
		// allocating one means a dry run cannot write even if it were.
		return &bulkWriter{}
	}
	return &bulkWriter{writer: client.BulkWriter(ctx)}
}

func (w *bulkWriter) set(doc *firestore.DocumentRef, data any, opts ...firestore.SetOption) error {
	if w.writer == nil {
		return fmt.Errorf("write to %s attempted on a dry run", doc.Path)
	}
	job, err := w.writer.Set(doc, data, opts...)
	if err != nil {
		return err
	}
	w.jobs = append(w.jobs, job)
	if len(w.jobs) >= pageSize {
		return w.drain()
	}
	return nil
}

func (w *bulkWriter) drain() error {
	if w.writer == nil || len(w.jobs) == 0 {
		return nil
	}
	w.writer.Flush()

	var firstErr error
	for _, job := range w.jobs {
		if _, err := job.Results(); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	w.jobs = w.jobs[:0]
	return firstErr
}

func (w *bulkWriter) close() error {
	if w.writer == nil || w.closed {
		return nil
	}
	err := w.drain()
	w.writer.End()
	w.closed = true
	return err
}

// abandon is the deferred safety net for an early return that skipped close().
func (w *bulkWriter) abandon() {
	if err := w.close(); err != nil {
		log.Printf("flushing pending writes: %v", err)
	}
}
