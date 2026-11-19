// Command repair_fixed_balance finds the fixed-term rows a teller payment
// stored with the principal subtracted twice (finstack#140) and, with
// -apply, rewrites their outstanding_balance.
//
// A computed fixed-term row already holds the balance after its scheduled
// principal; until the fix the teller handlers subtracted the principal paid
// again. A row is affected when it is paid (paid_on_time or paid_late, the
// statuses a teller payment writes) and its stored balance equals the
// previous balance minus the principal paid minus (the principal paid minus
// the extra payment), within half a centavo. The correct balance is the
// previous balance minus the principal paid. The previous balance is the
// row before it (as this run leaves it), or for the first row the loan's
// amount plus additional charges minus deductions.
//
// It defaults to a dry run, which only reads and lists each affected row
// (loan id, row id, stored and correct balance):
//
//	cd functions/loans
//	go run ./cmd/repair_fixed_balance -env dev
//
// -apply rewrites only those rows' outstanding_balance, and only when the row
// is unchanged since this run read it. It first records a run marker,
// {prefix}repair_runs/{runId}, with every row's balance before and after,
// and marks it applied when done. Production needs a second flag:
//
//	go run ./cmd/repair_fixed_balance -env prod -apply -confirm-prod loooans-prod
//
// Later paid rows of an affected loan whose balance follows the wrong one
// but does not match (a borrower submission confirmed after it, say) are
// listed for review and never rewritten.
//
// No trigger listens to loan_schedules updates (loanScheduleChanges fires on
// create only), and updated_at is left as it is, so a rewrite moves no report
// and no list order.
//
// Credentials are Application Default Credentials
// (`gcloud auth application-default login`). With FIRESTORE_EMULATOR_HOST set
// it talks to the Firestore emulator only (project demo-finstack).
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"math"
	"os"
	"os/user"
	"sort"
	"time"
)

// tolerance is half a centavo.
const tolerance = 0.005

// tellerPaid are the statuses a teller payment writes on the row it pays.
var tellerPaid = map[string]bool{"paid_on_time": true, "paid_late": true}

// anyPaid adds a submitted row, for the review list.
var anyPaid = map[string]bool{"paid_on_time": true, "paid_late": true, "payment_submitted": true}

type options struct {
	env         string // dev, stg or prod
	apply       bool
	confirmProd string
	by          string
}

// doc is one Firestore document as read.
type doc struct {
	id      string
	data    map[string]any
	updated time.Time // the document's update time, the precondition of a rewrite
}

// fix is one row to rewrite, or (in the review list) one row to look at.
type fix struct {
	loanId, rowId string
	dueAt         int64 // epoch milliseconds
	principal     float64
	stored        float64
	correct       float64 // the balance to write; unset in the review list
	updated       time.Time
}

// deps are the side effects of one run; main wires Firestore, the tests
// wire fakes.
type deps struct {
	// load reads every loan and every loan row of the environment.
	load func(ctx context.Context) (loans, rows []doc, err error)
	// rewrite sets the row's outstanding_balance if the row is unchanged
	// since it was read.
	rewrite func(ctx context.Context, f fix) error
	// mark merges fields into the run marker.
	mark func(ctx context.Context, runId string, fields map[string]any) error
	now  func() time.Time
}

func main() {
	var opts options
	flag.StringVar(&opts.env, "env", "", "dev, stg or prod (required)")
	flag.BoolVar(&opts.apply, "apply", false, "rewrite the affected rows (default: dry run, writes nothing)")
	flag.StringVar(&opts.confirmProd, "confirm-prod", "", "with -apply -env prod: the project id loooans-prod, as confirmation")
	flag.StringVar(&opts.by, "by", operator(), "who runs this; recorded in the run marker")
	flag.Parse()

	ctx := context.Background()
	err := checkOptions(opts, flag.NArg())
	if err == nil {
		var d deps
		var closeClient func()
		if d, closeClient, err = connect(ctx, opts, os.Stdout); err == nil {
			err = run(ctx, opts, d, os.Stdout)
			closeClient()
		}
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "repair_fixed_balance:", err)
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
func checkOptions(opts options, extraArgs int) error {
	if extraArgs > 0 {
		return errors.New("unexpected arguments; usage: repair_fixed_balance -env dev|stg|prod [-apply] [-confirm-prod loooans-prod]")
	}
	target, ok := targets[opts.env]
	if !ok {
		return fmt.Errorf("-env must be dev, stg or prod, got %q", opts.env)
	}
	if opts.apply && opts.env == "prod" && opts.confirmProd != target.project {
		return fmt.Errorf("refusing to write to production: -apply -env prod also needs -confirm-prod %s", target.project)
	}
	if opts.confirmProd != "" && !(opts.apply && opts.env == "prod") {
		return errors.New("-confirm-prod applies to -apply -env prod only")
	}
	if opts.apply && opts.by == "" {
		return errors.New("-by must name who runs this")
	}
	return nil
}

// run is one dry run or one apply.
func run(ctx context.Context, opts options, d deps, out io.Writer) error {
	loans, rows, err := d.load(ctx)
	if err != nil {
		return err
	}
	fixes, review := findFixes(loans, rows)

	fmt.Fprintf(out, "%d loan(s), %d row(s) read\n", len(loans), len(rows))
	for _, f := range fixes {
		fmt.Fprintf(out, "affected: loan %s row %s due %s principal %.2f: stored %.2f, correct %.2f\n",
			f.loanId, f.rowId, day(f.dueAt), f.principal, f.stored, f.correct)
	}
	for _, f := range review {
		fmt.Fprintf(out, "review by hand: loan %s row %s due %s principal %.2f: balance %.2f follows a wrong one; not rewritten\n",
			f.loanId, f.rowId, day(f.dueAt), f.principal, f.stored)
	}
	fmt.Fprintf(out, "%d row(s) to rewrite, %d row(s) to review\n", len(fixes), len(review))

	if !opts.apply {
		fmt.Fprintln(out, "dry run: nothing written")
		return nil
	}
	if len(fixes) == 0 {
		fmt.Fprintln(out, "nothing to rewrite")
		return nil
	}

	now := d.now().UTC()
	runId := now.Format("20060102T150405Z")
	planned := make([]any, 0, len(fixes))
	for _, f := range fixes {
		planned = append(planned, map[string]any{"loan_id": f.loanId, "row_id": f.rowId, "before": f.stored, "after": f.correct})
	}
	// Recorded before any row is written, so an interrupted run still says
	// what it set out to change.
	if err := d.mark(ctx, runId, map[string]any{
		"tool": "repair_fixed_balance", "issue": "finstack#140", "env": opts.env,
		"by": opts.by, "at": now.UnixMilli(), "applied": false, "rows": planned,
	}); err != nil {
		return fmt.Errorf("record run marker %s: %w", runId, err)
	}

	results := make([]any, 0, len(fixes))
	failed := 0
	for _, f := range fixes {
		result := map[string]any{"loan_id": f.loanId, "row_id": f.rowId, "before": f.stored, "after": f.correct, "written": true}
		if err := d.rewrite(ctx, f); err != nil {
			failed++
			result["written"] = false
			result["error"] = err.Error()
			fmt.Fprintf(out, "not written: row %s: %v\n", f.rowId, err)
		}
		results = append(results, result)
	}
	if err := d.mark(ctx, runId, map[string]any{
		"applied": true, "finished_at": d.now().UTC().UnixMilli(), "rows": results,
	}); err != nil {
		return fmt.Errorf("finish run marker %s: %w", runId, err)
	}
	fmt.Fprintf(out, "run %s: wrote %d of %d row(s)\n", runId, len(fixes)-failed, len(fixes))
	if failed > 0 {
		return fmt.Errorf("%d row(s) not written (listed above); run again to see what is left", failed)
	}
	return nil
}

// findFixes returns the affected rows with their correct balance, and the
// later paid rows of affected loans that follow a wrong balance but do not
// match.
func findFixes(loans, rows []doc) (fixes, review []fix) {
	byLoan := map[string][]doc{}
	for _, r := range rows {
		if r.data["deleted_at"] != nil {
			continue
		}
		loanId, _ := r.data["loan_id"].(string)
		byLoan[loanId] = append(byLoan[loanId], r)
	}
	sort.Slice(loans, func(i, j int) bool { return loans[i].id < loans[j].id })

	for _, loan := range loans {
		if loan.data["deleted_at"] != nil || num(loan.data["period"]) == 0 {
			continue // deleted or open-term
		}
		loanRows := byLoan[loan.id]
		sort.SliceStable(loanRows, func(i, j int) bool {
			return millis(loanRows[i].data["due_at"]) < millis(loanRows[j].data["due_at"])
		})

		// prev is the balance before the row as stored; after is the same
		// balance as this run leaves it.
		prev := num(loan.data["amount"]) + num(loan.data["additional_charges"]) - num(loan.data["deductions"])
		after := prev
		affected := false
		for _, r := range loanRows {
			if r.data["is_open_term"] == true {
				continue
			}
			status, _ := r.data["status"].(string)
			p, x := num(r.data["principal_payment"]), num(r.data["extra_payment"])
			stored := num(r.data["outstanding_balance"])
			f := fix{loanId: loan.id, rowId: r.id, dueAt: millis(r.data["due_at"]), principal: p, stored: stored, updated: r.updated}

			if tellerPaid[status] && p-x >= tolerance && math.Abs(stored-(prev-p-(p-x))) < tolerance {
				f.correct = after - p
				fixes = append(fixes, f)
				affected = true
				after = f.correct
			} else {
				if affected && anyPaid[status] {
					review = append(review, f)
				}
				after = stored
			}
			prev = stored
		}
	}
	return fixes, review
}

// num reads a Firestore number (integer or double); anything else is 0.
func num(v any) float64 {
	switch n := v.(type) {
	case float64:
		return n
	case int64:
		return float64(n)
	case int:
		return float64(n)
	}
	return 0
}

// millis reads a date the app stores as epoch milliseconds (or a timestamp).
func millis(v any) int64 {
	if t, ok := v.(time.Time); ok {
		return t.UnixMilli()
	}
	return int64(num(v))
}

func day(ms int64) string {
	return time.UnixMilli(ms).UTC().Format("2006-01-02")
}
