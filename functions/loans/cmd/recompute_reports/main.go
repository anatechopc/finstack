// Command recompute_reports rebuilds one company's Realtime Database
// report_summary from its Firestore documents (campaign Phase 4; design and
// per-total definitions in
// docs/superpowers/specs/2026-11-13-report-recompute-tool.md).
//
// It defaults to a dry run, which only reads and prints recomputed versus
// live totals:
//
//	cd functions/loans
//	go run ./cmd/recompute_reports -env dev -company <companyId>
//
// -apply replaces the company's report_summary in one conditional write and
// records the run under {company}/report_recomputes. Production needs the
// company id a second time:
//
//	go run ./cmd/recompute_reports -env prod -company <id> -apply -confirm-prod <id>
//
// Credentials are Application Default Credentials
// (`gcloud auth application-default login`). With BOTH emulator variables set
// (FIRESTORE_EMULATOR_HOST and FIREBASE_DATABASE_EMULATOR_HOST=host:port?ns=name)
// it talks to the emulators only.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"math"
	"os"
	"os/user"
	"reflect"
	"sort"
	"strings"
	"time"

	"com.loooans.app/triggers"
)

// tolerance is the smallest difference reported for a total: half a centavo.
// Anything smaller is the order in which floating-point amounts were added.
const tolerance = 0.005

// retryDays is how long the platform may keep redelivering a failed event to
// a function deployed with --retry: 7 days, the default retry window in
// Google's "Retry event-driven functions" guide (read 2026-11-13).
const retryDays = 7

const retryWindow = retryDays * 24 * time.Hour

type options struct {
	company     string
	env         string // dev, stg or prod
	apply       bool
	confirmProd string
	by          string
}

// deps are the side effects of one run. main wires Firestore and the Realtime
// Database; the tests wire fakes.
type deps struct {
	// live reads the current report_summary (nil when absent), its ETag, and
	// the event claims under report_events.
	live func(ctx context.Context) (summary map[string]any, etag string, claims map[string]triggers.ClaimRecord, err error)
	// source reads the company's documents and product types.
	source func(ctx context.Context) (triggers.RecomputeInput, error)
	// replace writes the summary only if the live one still has this ETag.
	replace func(ctx context.Context, etag string, summary map[string]any) (written bool, err error)
	// mark records the run under report_recomputes/{runId}.
	mark func(ctx context.Context, runId string, marker map[string]any) error
	now  func() time.Time
}

func main() {
	var opts options
	flag.StringVar(&opts.company, "company", "", "company id (required)")
	flag.StringVar(&opts.env, "env", "", "dev, stg or prod (required)")
	flag.BoolVar(&opts.apply, "apply", false, "write the recomputed summary (default: dry run, writes nothing)")
	flag.StringVar(&opts.confirmProd, "confirm-prod", "", "with -apply -env prod: the company id again, as confirmation")
	flag.StringVar(&opts.by, "by", operator(), "who runs this; recorded in the run marker")
	flag.Parse()

	ctx := context.Background()
	err := checkOptions(opts)
	if err == nil {
		var d deps
		var closeClients func()
		if d, closeClients, err = connect(ctx, opts, os.Stdout); err == nil {
			err = run(ctx, opts, d, os.Stdout)
			closeClients()
		}
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "recompute_reports:", err)
		os.Exit(1)
	}
}

func operator() string {
	name := "unknown"
	if current, err := user.Current(); err == nil {
		name = current.Username
	}
	host, _ := os.Hostname()
	return name + "@" + host
}

// checkOptions runs before anything is read.
func checkOptions(opts options) error {
	if opts.company == "" || strings.ContainsAny(opts.company, "/.#$[] ") {
		return fmt.Errorf("-company is required and must be one document id, got %q", opts.company)
	}
	if _, ok := targets[opts.env]; !ok {
		return fmt.Errorf("-env must be dev, stg or prod, got %q", opts.env)
	}
	if opts.apply && opts.env == "prod" && opts.confirmProd != opts.company {
		return fmt.Errorf("refusing to write to production: -apply -env prod also needs -confirm-prod %s", opts.company)
	}
	if opts.apply && opts.by == "" {
		return errors.New("-by must name who runs this")
	}
	return nil
}

// run is one dry run or one apply.
func run(ctx context.Context, opts options, d deps, out io.Writer) error {
	// Live first: its ETag makes the write conditional on no trigger having
	// written between this read and the write.
	before, etag, claims, err := d.live(ctx)
	if err != nil {
		return fmt.Errorf("read live summary: %w", err)
	}
	input, err := d.source(ctx)
	if err != nil {
		return fmt.Errorf("read source documents: %w", err)
	}
	result := triggers.RecomputeReport(input)
	after := normalize(result.Plan.SummaryNode())
	now := d.now().UTC()

	documents := len(input.Loans) + len(input.Schedules) + len(input.Capital)
	fmt.Fprintf(out, "source: %d loans (%d released), %d schedules (%d paid), %d capital (%d counted), %d dropped\n",
		len(input.Loans), result.Released, len(input.Schedules), result.Paid, len(input.Capital), result.Capital, len(result.Dropped))
	for i, note := range result.Dropped {
		if i == 20 {
			fmt.Fprintf(out, "  dropped: ... and %d more\n", len(result.Dropped)-i)
			break
		}
		fmt.Fprintln(out, "  dropped:", note)
	}
	unapplied, retryable := unsettledClaims(claims, now)
	fmt.Fprintf(out, "claims: %d recorded, %d not applied (%d of them younger than %d days)\n\n", len(claims), unapplied, retryable, retryDays)

	rows, strays := compare(after, before)
	allTimeDiffer, periodDiffer := printTotals(out, rows)
	for _, path := range strays {
		fmt.Fprintf(out, "live node %s is not a total; an apply removes it\n", path)
	}
	fmt.Fprintf(out, "data items: recomputed %d, live %d\n", len(dataOf(after)), len(dataOf(before)))
	equal := reflect.DeepEqual(after, before)
	if equal {
		fmt.Fprintln(out, "live equals the recomputed summary: zero difference")
	} else {
		fmt.Fprintln(out, "live differs from the recomputed summary")
	}

	if !opts.apply {
		fmt.Fprintln(out, "dry run: nothing written (add -apply to write)")
		return nil
	}
	if equal {
		fmt.Fprintln(out, "apply: nothing to write")
		return nil
	}
	if documents == 0 {
		return fmt.Errorf("refusing to apply: no documents found for company %s (wrong id or environment?); an apply would delete the live summary", opts.company)
	}
	if retryable > 0 {
		return fmt.Errorf("refusing to apply: %d event(s) were claimed by a trigger and not applied in the last %d days; a redelivery after this write would count its document twice. Run again once they are applied or older than that", retryable, retryDays)
	}

	written, err := d.replace(ctx, etag, after)
	if err != nil {
		return fmt.Errorf("write summary: %w", err)
	}
	if !written {
		return errors.New("nothing written: a trigger changed the live summary during this run; run again")
	}
	runId := now.Format("20060102T150405Z")
	marker := map[string]any{
		"at": now.UnixMilli(),
		"by": opts.by,
		"documents": map[string]any{
			"loans": len(input.Loans), "schedules": len(input.Schedules), "capital": len(input.Capital),
			"released": result.Released, "paid": result.Paid, "capital_counted": result.Capital,
			"dropped": len(result.Dropped),
		},
		"totals_differing": map[string]any{"all_time": allTimeDiffer, "period": periodDiffer},
		"data_items":       map[string]any{"before": len(dataOf(before)), "after": len(dataOf(after))},
		"before":           withoutData(before),
		"after":            withoutData(after),
	}
	if err := d.mark(ctx, runId, marker); err != nil {
		return fmt.Errorf("the summary WAS replaced but the run marker %s was not recorded: %w", runId, err)
	}
	fmt.Fprintf(out, "applied: report_summary replaced, run recorded at report_recomputes/%s by %s\n", runId, opts.by)
	fmt.Fprintln(out, "verify: run again without -apply; it must print \"zero difference\"")
	return nil
}

// normalize gives the node the shape it has when read back from the
// Realtime Database: JSON numbers, and no node at all when empty.
func normalize(node map[string]any) map[string]any {
	encoded, err := json.Marshal(node)
	if err != nil {
		panic(err) // the node holds only strings, numbers and maps
	}
	var out map[string]any
	if err := json.Unmarshal(encoded, &out); err != nil {
		panic(err)
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

func dataOf(summary map[string]any) map[string]any {
	data, _ := summary["data"].(map[string]any)
	return data
}

func withoutData(summary map[string]any) map[string]any {
	out := map[string]any{}
	for key, value := range summary {
		if key != "data" {
			out[key] = value
		}
	}
	return out
}

// unsettledClaims counts the events a trigger claimed and did not apply, and
// how many of those the platform may still redeliver.
func unsettledClaims(claims map[string]triggers.ClaimRecord, now time.Time) (unapplied, retryable int) {
	for _, claim := range claims {
		if claim.Applied {
			continue
		}
		unapplied++
		if now.Sub(time.UnixMilli(claim.ClaimedAt)) < retryWindow {
			retryable++
		}
	}
	return unapplied, retryable
}

type totalRow struct {
	path             string
	recomputed, live float64
}

func (r totalRow) differs() bool { return math.Abs(r.live-r.recomputed) >= tolerance }

// compare lists every total of either summary by path. The data list is left
// out: it holds items, not totals. Live nodes that are not numbers are
// returned as strays.
func compare(recomputed, live map[string]any) (rows []totalRow, strays []string) {
	recomputedTotals, liveTotals := map[string]float64{}, map[string]float64{}
	flatten(recomputed, "", recomputedTotals, &strays)
	strays = nil // the recomputed node holds totals only
	flatten(live, "", liveTotals, &strays)
	for path, value := range recomputedTotals {
		rows = append(rows, totalRow{path, value, liveTotals[path]})
	}
	for path, value := range liveTotals {
		if _, ok := recomputedTotals[path]; !ok {
			rows = append(rows, totalRow{path, 0, value})
		}
	}
	sort.Slice(rows, func(i, j int) bool { return rows[i].path < rows[j].path })
	sort.Strings(strays)
	return rows, strays
}

func flatten(node map[string]any, prefix string, totals map[string]float64, strays *[]string) {
	for key, value := range node {
		path := prefix + key
		switch typed := value.(type) {
		case map[string]any:
			if path != "data" {
				flatten(typed, path+"/", totals, strays)
			}
		case float64:
			totals[path] = typed
		default:
			*strays = append(*strays, path)
		}
	}
}

// printTotals prints every all-time total and the period totals
// (total_summary buckets) that differ, and returns how many of each differ.
func printTotals(out io.Writer, rows []totalRow) (allTimeDiffer, periodDiffer int) {
	width := len("total")
	for _, row := range rows {
		width = max(width, len(row.path))
	}
	allTime, period := 0, 0
	fmt.Fprintf(out, "%-*s %16s %16s %16s\n", width, "total", "recomputed", "live", "live-recomputed")
	for _, row := range rows {
		isPeriod := strings.HasPrefix(row.path, "total_summary/")
		if isPeriod {
			period++
		} else {
			allTime++
		}
		if row.differs() {
			if isPeriod {
				periodDiffer++
			} else {
				allTimeDiffer++
			}
		} else if isPeriod {
			continue
		}
		fmt.Fprintf(out, "%-*s %16.2f %16.2f %16.2f\n", width, row.path, row.recomputed, row.live, row.live-row.recomputed)
	}
	fmt.Fprintf(out, "\nall-time totals: %d of %d differ by %.3f or more\n", allTimeDiffer, allTime, tolerance)
	fmt.Fprintf(out, "period totals (total_summary): %d of %d differ by %.3f or more (only those are listed)\n", periodDiffer, period, tolerance)
	return allTimeDiffer, periodDiffer
}
