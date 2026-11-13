// Command recompute_reports rebuilds one company's Realtime Database
// report_summary from its Firestore documents (campaign Phase 4; design and
// per-total definitions in
// docs/superpowers/specs/2026-11-13-report-recompute-tool.md).
//
// It defaults to a dry run, which only reads and prints recomputed versus
// live totals; -loans adds one line per loan (ids and amounts):
//
//	cd functions/loans
//	go run ./cmd/recompute_reports -env dev -company <companyId> [-loans]
//
// -apply saves the complete live node under {company}/report_recomputes/{runId}
// and then replaces report_summary in one conditional write. Production needs
// the company id a second time:
//
//	go run ./cmd/recompute_reports -env prod -company <id> -apply -confirm-prod <id>
//
// -restore <runId> compares the node saved by that run with the live one;
// with -apply it writes the saved node back, under the same safeguards.
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
	loans       bool   // print one line per loan
	restore     string // run id whose saved node is written back
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
	// mark merges fields into the run record report_recomputes/{runId}.
	mark func(ctx context.Context, runId string, fields map[string]any) error
	// record reads a run record (nil when there is none).
	record func(ctx context.Context, runId string) (map[string]any, error)
	now    func() time.Time
}

func main() {
	var opts options
	flag.StringVar(&opts.company, "company", "", "company id (required)")
	flag.StringVar(&opts.env, "env", "", "dev, stg or prod (required)")
	flag.BoolVar(&opts.apply, "apply", false, "write (default: dry run, writes nothing)")
	flag.StringVar(&opts.confirmProd, "confirm-prod", "", "with -apply -env prod: the company id again, as confirmation")
	flag.StringVar(&opts.by, "by", operator(), "who runs this; recorded with the run")
	flag.BoolVar(&opts.loans, "loans", false, "also print one line per loan: id, status and amounts")
	flag.StringVar(&opts.restore, "restore", "", "run id: use the node saved by that run instead of a recompute")
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
	const notAKey = "/.#$[] "
	if opts.company == "" || strings.ContainsAny(opts.company, notAKey) {
		return fmt.Errorf("-company is required and must be one document id, got %q", opts.company)
	}
	if _, ok := targets[opts.env]; !ok {
		return fmt.Errorf("-env must be dev, stg or prod, got %q", opts.env)
	}
	if strings.ContainsAny(opts.restore, notAKey) {
		return fmt.Errorf("-restore must be a run id such as 20261113T024613Z, got %q", opts.restore)
	}
	if opts.apply && opts.env == "prod" && opts.confirmProd != opts.company {
		return fmt.Errorf("refusing to write to production: -apply -env prod also needs -confirm-prod %s", opts.company)
	}
	if opts.apply && opts.by == "" {
		return errors.New("-by must name who runs this")
	}
	return nil
}

// run is one dry run or one apply, of a recompute or of a saved node.
func run(ctx context.Context, opts options, d deps, out io.Writer) error {
	// Live first: its ETag makes the write conditional on no trigger having
	// written between this read and the write.
	before, etag, claims, err := d.live(ctx)
	if err != nil {
		return fmt.Errorf("read live summary: %w", err)
	}
	now := d.now().UTC()
	// The run record. It holds the complete node as it was, so any apply can
	// be undone with -restore.
	record := map[string]any{"at": now.UnixMilli(), "by": opts.by, "applied": false, "previous": before}

	var after map[string]any
	var refusals []string // why an apply of this result is refused
	label := "recomputed"
	if opts.restore != "" {
		saved, err := d.record(ctx, opts.restore)
		if err != nil {
			return fmt.Errorf("read run %s: %w", opts.restore, err)
		}
		if saved == nil {
			return fmt.Errorf("no run %s is recorded for company %s", opts.restore, opts.company)
		}
		// No "previous" means the node did not exist before that run.
		after, _ = saved["previous"].(map[string]any)
		label = "saved"
		record["restores"] = opts.restore
		fmt.Fprintf(out, "restore: the summary as it was before run %s (by %v)\n\n", opts.restore, saved["by"])
	} else {
		input, err := d.source(ctx)
		if err != nil {
			return fmt.Errorf("read source documents: %w", err)
		}
		result := triggers.RecomputeReport(input)
		after = normalize(result.Plan.SummaryNode())
		printSource(out, input, result)
		if opts.loans {
			printLoans(out, result.Loans, before)
		}
		unapplied, retryable := unsettledClaims(claims, now)
		fmt.Fprintf(out, "claims: %d recorded, %d not applied (%d of them younger than %d days)\n\n", len(claims), unapplied, retryable, retryDays)

		if after == nil {
			refusals = append(refusals, "the recompute is empty, so an apply would delete the live summary")
		}
		if dropped := len(result.Dropped); dropped > 0 {
			refusals = append(refusals, fmt.Sprintf("%d document(s) were dropped (listed above), so the recompute is incomplete", dropped))
		}
		if retryable > 0 {
			refusals = append(refusals, fmt.Sprintf("%d event(s) were claimed by a trigger and not applied in the last %d days; a redelivery after this write would count its document twice", retryable, retryDays))
		}
		record["documents"] = map[string]any{
			"loans": len(input.Loans), "schedules": len(input.Schedules), "capital": len(input.Capital),
			"released": result.Released, "paid": result.Paid, "capital_counted": result.Capital,
			"pending_submissions": len(result.Pending),
		}
	}

	rows, strays := compare(after, before)
	allTimeDiffer, periodDiffer := printTotals(out, label, rows)
	for _, path := range strays {
		fmt.Fprintf(out, "live node %s is not a total; an apply removes it\n", path)
	}
	fmt.Fprintf(out, "data items: %s %d, live %d\n", label, len(dataOf(after)), len(dataOf(before)))
	equal := reflect.DeepEqual(after, before)
	if equal {
		fmt.Fprintf(out, "live equals the %s summary: zero difference\n", label)
	} else {
		fmt.Fprintf(out, "live differs from the %s summary\n", label)
	}

	if !opts.apply {
		for _, refusal := range refusals {
			fmt.Fprintln(out, "an apply would be refused:", refusal)
		}
		fmt.Fprintln(out, "dry run: nothing written (add -apply to write)")
		return nil
	}
	if equal {
		fmt.Fprintln(out, "apply: nothing to write")
		return nil
	}
	if len(refusals) > 0 {
		return errors.New("refusing to apply: " + strings.Join(refusals, "; "))
	}

	// Save the previous node first: without the copy there is no write.
	runId := now.Format("20060102T150405Z")
	// Merging into another run's record would overwrite the node it saved.
	if existing, err := d.record(ctx, runId); err != nil {
		return fmt.Errorf("nothing written: cannot check whether run %s exists: %w", runId, err)
	} else if existing != nil {
		return fmt.Errorf("nothing written: a run %s is already recorded (two runs in the same second); run again", runId)
	}
	record["totals_differing"] = map[string]any{"all_time": allTimeDiffer, "period": periodDiffer}
	record["data_items"] = map[string]any{"before": len(dataOf(before)), "after": len(dataOf(after))}
	record["after"] = withoutData(after)
	if err := d.mark(ctx, runId, record); err != nil {
		return fmt.Errorf("nothing written: the previous summary could not be saved under run %s: %w", runId, err)
	}
	written, err := d.replace(ctx, etag, after)
	if err != nil {
		return fmt.Errorf("write summary (run %s holds the previous node): %w", runId, err)
	}
	if !written {
		note := map[string]any{"outcome": "not applied: the live summary changed during the run"}
		if err := d.mark(ctx, runId, note); err != nil {
			fmt.Fprintf(out, "run %s could not be marked as not applied: %v\n", runId, err)
		}
		return errors.New("nothing written: a trigger changed the live summary during this run; run again")
	}
	if err := d.mark(ctx, runId, map[string]any{"applied": true}); err != nil {
		return fmt.Errorf("the summary WAS replaced but run %s could not be marked applied: %w", runId, err)
	}
	fmt.Fprintf(out, "applied: report_summary replaced by %s; the previous node is saved at report_recomputes/%s\n", opts.by, runId)
	fmt.Fprintln(out, "verify: run the same command without -apply; it must print \"zero difference\"")
	fmt.Fprintf(out, "undo: -restore %s (dry run first, then with -apply)\n", runId)
	return nil
}

func printSource(out io.Writer, input triggers.RecomputeInput, result triggers.RecomputeResult) {
	fmt.Fprintf(out, "source: %d loans (%d released), %d schedules (%d paid, %d pending submissions), %d capital (%d counted), %d dropped\n",
		len(input.Loans), result.Released, len(input.Schedules), result.Paid, len(result.Pending), len(input.Capital), result.Capital, len(result.Dropped))
	for _, note := range result.Dropped {
		fmt.Fprintln(out, "  dropped:", note)
	}
	for _, note := range result.Pending {
		fmt.Fprintln(out, "  pending submission, not counted:", note)
	}
	for _, note := range result.Mismatched {
		fmt.Fprintln(out, "  counted, but its company_id is not this company:", note)
	}
}

// printLoans prints what was booked per loan beside the releases the live
// data list holds for it. Ids, statuses and amounts only.
func printLoans(out io.Writer, loans []triggers.LoanLine, live map[string]any) {
	liveReleased := map[string]float64{}
	for _, value := range dataOf(live) {
		if item, _ := value.(map[string]any); item["data_type"] == "release" {
			loanId, _ := item["loan_id"].(string)
			amount, _ := item["amount"].(float64)
			liveReleased[loanId] += amount
		}
	}
	width := len("loan")
	for _, loan := range loans {
		width = max(width, len(loan.Id))
	}
	for id := range liveReleased {
		width = max(width, len(id))
	}
	fmt.Fprintf(out, "\n%-*s %-17s %12s %12s %13s %14s %12s %12s %12s  %s\n", width,
		"loan", "status", "amount", "released", "live_released", "paid_principal", "interest", "remainder", "bad_debt", "note")
	for _, loan := range loans {
		fmt.Fprintf(out, "%-*s %-17s %12.2f %12.2f %13.2f %14.2f %12.2f %12.2f %12.2f  %s\n", width,
			loan.Id, loan.Status, loan.Amount, loan.Released, liveReleased[loan.Id], loan.PaidPrincipal, loan.Interest, loan.Remainder, loan.BadDebt, loan.Note)
		delete(liveReleased, loan.Id)
	}
	// Releases the live list holds for loans Firestore no longer has.
	orphans := make([]string, 0, len(liveReleased))
	for id := range liveReleased {
		orphans = append(orphans, id)
	}
	sort.Strings(orphans)
	for _, id := range orphans {
		fmt.Fprintf(out, "%-*s %-17s %12s %12.2f %13.2f %14s %12s %12s %12s  %s\n", width,
			id, "(no document)", "", 0.0, liveReleased[id], "", "", "", "", "released in the live data list only")
	}
	fmt.Fprintln(out)
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
	path         string
	target, live float64 // target: the recomputed (or saved) value
}

func (r totalRow) differs() bool { return math.Abs(r.live-r.target) >= tolerance }

// compare lists every total of either summary by path. The data list is left
// out: it holds items, not totals. Live nodes that are not numbers are
// returned as strays.
func compare(target, live map[string]any) (rows []totalRow, strays []string) {
	targetTotals, liveTotals := map[string]float64{}, map[string]float64{}
	flatten(target, "", targetTotals, &strays)
	strays = nil // only the live node is checked for strays
	flatten(live, "", liveTotals, &strays)
	for path, value := range targetTotals {
		rows = append(rows, totalRow{path, value, liveTotals[path]})
	}
	for path, value := range liveTotals {
		if _, ok := targetTotals[path]; !ok {
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
func printTotals(out io.Writer, label string, rows []totalRow) (allTimeDiffer, periodDiffer int) {
	width := len("total")
	for _, row := range rows {
		width = max(width, len(row.path))
	}
	allTime, period := 0, 0
	fmt.Fprintf(out, "%-*s %16s %16s %16s\n", width, "total", label, "live", "live-"+label)
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
		fmt.Fprintf(out, "%-*s %16.2f %16.2f %16.2f\n", width, row.path, row.target, row.live, row.live-row.target)
	}
	fmt.Fprintf(out, "\nall-time totals: %d of %d differ by %.3f or more\n", allTimeDiffer, allTime, tolerance)
	fmt.Fprintf(out, "period totals (total_summary): %d of %d differ by %.3f or more (only those are listed)\n", periodDiffer, period, tolerance)
	return allTimeDiffer, periodDiffer
}
