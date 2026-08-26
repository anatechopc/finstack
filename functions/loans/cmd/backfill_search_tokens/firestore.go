package backfill

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"com.loooans.app/triggers"
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
	if err := checkEnvironmentMatchesProject(opts.ProjectID, environment); err != nil {
		return nil, err
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
	//
	// The core has already drained and reconciled its own writes, so this
	// normally finds nothing. Whatever it does find is JOINED onto the pass
	// error rather than dropped when one is already set. Dropping it was a
	// silent hole big enough to hide a whole trailing batch: 1,200 users, one
	// permission error at document 500, the last ~200 writes all failing for
	// the same reason and the operator told `failed=1`.
	if closeFailures := writer.close(); len(closeFailures) > 0 {
		if report != nil {
			report.Failed += len(closeFailures)
		}
		err = errors.Join(err, flushFailureError(closeFailures))
	}
	return report, err
}

// flushFailureError turns per-document flush failures into one error that
// names how many documents did not land and what one of them said.
func flushFailureError(failures map[string]error) error {
	if len(failures) == 0 {
		return nil
	}
	// Named deterministically rather than by map order, so two runs over the
	// same failure report the same document.
	id := sortedKeys(failures)[0]
	return fmt.Errorf("%d write(s) failed at flush, e.g. %s: %w", len(failures), id, failures[id])
}

// projectEnvironments pairs each known Firebase project with the ENVIRONMENT
// values that legitimately go with it. loooans-dev-stg hosts both development
// and staging, separated by the collection prefix.
var projectEnvironments = map[string][]string{
	"loooans-prod":    {"production"},
	"loooans-dev-stg": {"development", "staging"},
}

// checkEnvironmentMatchesProject refuses a run whose ENVIRONMENT does not go
// with its -project.
//
// The two select different things — the project selects the database, the
// environment selects the collection prefix — and nothing else checks that
// they agree. An operator with ENVIRONMENT=development still exported from an
// earlier dev run, executing against -project=loooans-prod, passes every other
// guard and then pages dev_users/dev_products INSIDE the production project:
// either creating a parallel dev_-prefixed dataset in prod, or (more likely)
// scanning zero documents and reporting a clean pass while production stays
// unbackfilled.
//
// Refused on a dry run too. A dry run against the wrong prefix reports counts
// that mean nothing, and those counts are what the decision to write is based
// on.
func checkEnvironmentMatchesProject(projectID, environment string) error {
	allowed, known := projectEnvironments[projectID]
	if !known {
		// An unrecognised project gets the substring heuristic instead: a
		// project that looks like production must be paired with production,
		// and only production may be pointed at one.
		if strings.Contains(projectID, "prod") != (environment == "production") {
			return fmt.Errorf(
				"ENVIRONMENT=%s does not match project %q — the project selects the database and "+
					"ENVIRONMENT selects the collection prefix, so a mismatch reads or writes the "+
					"wrong collections",
				environment, projectID)
		}
		return nil
	}
	for _, candidate := range allowed {
		if environment == candidate {
			return nil
		}
	}
	return fmt.Errorf(
		"ENVIRONMENT=%s does not match project %q (expected %s) — the project selects the "+
			"database and ENVIRONMENT selects the collection prefix, so a mismatch reads or "+
			"writes the wrong collections",
		environment, projectID, strings.Join(allowed, " or "))
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
			// triggers.MergeFields, not firestore.MergeAll — see its doc
			// comment. The payload is one array field today, for which the two
			// agree, but the rule is the document's, not the payload's.
			return writer.set(id, users.Doc(id), fields, triggers.MergeFields(fields))
		},
		Flush: writer.takeFailures,
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
			// No merge option: a create writes the whole document.
			return writer.set(viewId, views.Doc(viewId), view)
		},
		UpdateView: func(ctx context.Context, viewId string, fields map[string]any) error {
			// triggers.MergeFields, not firestore.MergeAll: this payload
			// carries company_profile_photo_url, a nested map that MergeAll
			// would merge leaf-by-leaf, leaving stale subkeys the projection
			// can never remove and a view that never converges.
			return writer.set(viewId, views.Doc(viewId), fields, triggers.MergeFields(fields))
		},
		Flush: writer.takeFailures,
		Now:   func() int64 { return time.Now().UnixMilli() },
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

// bulkWriter batches the round trips while keeping each write's outcome
// attached to the document it was for.
//
// The reused trigger core hands writes over one document at a time, so a
// WriteBatch would have to be threaded through it. A BulkWriter takes them one
// at a time and batches internally — but Set() only ENQUEUES: it returns nil
// as soon as the job is accepted, and whether the write landed is known only
// from that job's Results() after a flush. A caller that treated the nil from
// Set() as success would count the first pageSize-1 documents as written
// before anything at all was known about them, and a run against a service
// account with no write permission would report `updated=499 failed=1`. This
// job has never run against a real Firestore, so its report is the only
// evidence anyone will have that it worked.
//
// So: set() reports only whether the write was ACCEPTED, each job is kept
// beside its document id, and takeFailures() drains and hands back exactly the
// documents whose writes did not land. Attribution is per document, not per
// batch — the job carries its own result, so a failure is never charged to
// whichever document happened to fill the batch.
type bulkWriter struct {
	writer  *firestore.BulkWriter
	pending []pendingWrite
	// failures accumulates across drains until takeFailures collects them, so
	// a mid-run drain (every pageSize writes) does not lose what it found.
	failures map[string]error
	closed   bool
}

// pendingWrite is one enqueued write and the document it belongs to.
type pendingWrite struct {
	id  string
	job *firestore.BulkWriterJob
}

func newBulkWriter(ctx context.Context, client *firestore.Client, dryRun bool) *bulkWriter {
	if dryRun {
		// No writer at all on a dry run: set() is never reached, and not
		// allocating one means a dry run cannot write even if it were.
		return &bulkWriter{}
	}
	return &bulkWriter{writer: client.BulkWriter(ctx)}
}

// set enqueues a write against document id. The returned error covers only a
// failure to ENQUEUE; whether the write landed is reported through
// takeFailures, keyed by the same id.
func (w *bulkWriter) set(id string, doc *firestore.DocumentRef, data any, opts ...firestore.SetOption) error {
	if w.writer == nil {
		return fmt.Errorf("write to %s attempted on a dry run", doc.Path)
	}
	job, err := w.writer.Set(doc, data, opts...)
	if err != nil {
		return err
	}
	w.pending = append(w.pending, pendingWrite{id: id, job: job})
	if len(w.pending) >= pageSize {
		w.drain()
	}
	return nil
}

// drain blocks until every enqueued write has a result and records the ones
// that failed against the document they were for.
func (w *bulkWriter) drain() {
	if w.writer == nil || len(w.pending) == 0 {
		return
	}
	w.writer.Flush()

	for _, write := range w.pending {
		if _, err := write.job.Results(); err != nil {
			if w.failures == nil {
				w.failures = map[string]error{}
			}
			w.failures[write.id] = err
		}
	}
	w.pending = w.pending[:0]
}

// takeFailures matches UserDeps.Flush / ProductDeps.Flush. The context is
// unused: the flush waits on jobs the BulkWriter already owns.
func (w *bulkWriter) takeFailures(context.Context) map[string]error {
	return w.collectFailures()
}

// collectFailures drains and returns every write that has failed since the
// last call, keyed by document id, clearing them so nothing is reported twice.
func (w *bulkWriter) collectFailures() map[string]error {
	w.drain()
	failures := w.failures
	w.failures = nil
	return failures
}

// close drains what is left, ends the writer, and hands back any failures the
// final flush found. Idempotent, so abandon() and Run() may both call it.
func (w *bulkWriter) close() map[string]error {
	if w.writer == nil || w.closed {
		return nil
	}
	failures := w.collectFailures()
	w.writer.End()
	w.closed = true
	return failures
}

// abandon is the deferred safety net for an early return that skipped close().
func (w *bulkWriter) abandon() {
	if err := flushFailureError(w.close()); err != nil {
		log.Printf("flushing pending writes: %v", err)
	}
}
