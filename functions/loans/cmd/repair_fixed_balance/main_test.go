package main

import (
	"bytes"
	"context"
	"errors"
	"math"
	"strings"
	"testing"
	"time"
)

// The two rows the read-only count found (2026-11-19), as stored:
//   dev PRxL6LHifFWQjITEaQzq: 10,000 at 5% for 3 months; row 1 paid
//     3,172.09 (scheduled 3,172.0856, extra 0.0044): stored 10,000 -
//     3,172.09 - 3,172.0856 = 3,655.82; correct 10,000 - 3,172.09 = 6,827.91.
//   stg ta3EhKPebk913GDxCGAJ: 100,000 at 10% for 6 months; row 1 paid
//     12,960.74 (extra 0.0020): stored 74,078.52; correct 87,039.26.

func loanDoc(id string, amount float64, period int64) doc {
	return doc{id: id, data: map[string]any{"amount": amount, "additional_charges": int64(0), "period": period, "deleted_at": nil}}
}

func rowDoc(id, loanId, status string, due int64, principal, extra, balance float64) doc {
	return doc{id: id, updated: time.UnixMilli(due), data: map[string]any{
		"loan_id": loanId, "status": status, "due_at": due, "is_open_term": false,
		"principal_payment": principal, "extra_payment": extra, "outstanding_balance": balance, "deleted_at": nil,
	}}
}

const dec13 = int64(1797120000000) // 2026-12-13 00:00 UTC

func devLoan() ([]doc, []doc) {
	return []doc{loanDoc("PRxL6LHifFWQjITEaQzq", 10000, 3)},
		[]doc{rowDoc("W4PYWSxbNfziUVlJRe7X", "PRxL6LHifFWQjITEaQzq", "paid_on_time", dec13, 3172.09, 0.004353687551429175, 3655.824353687551)}
}

func near(a, b float64) bool { return math.Abs(a-b) < 0.005 }

func TestFindFixesMatchesTheDevAndStgRows(t *testing.T) {
	loans, rows := devLoan()
	loans = append(loans, loanDoc("ta3EhKPebk913GDxCGAJ", 100000, 6))
	rows = append(rows, rowDoc("Khh5ytQT5jypns2qmMv8", "ta3EhKPebk913GDxCGAJ", "paid_on_time", dec13, 12960.74, 0.001963733279, 74078.52196373329))

	fixes, manual := findFixes(loans, rows)

	if len(fixes) != 2 || len(manual) != 0 {
		t.Fatalf("fixes %d manual %d, want 2 and 0", len(fixes), len(manual))
	}
	dev, stg := fixes[0], fixes[1]
	if dev.rowId != "W4PYWSxbNfziUVlJRe7X" || !near(dev.stored, 3655.82) || !near(dev.correct, 6827.91) {
		t.Errorf("dev fix = %+v, want stored 3,655.82, correct 6,827.91", dev)
	}
	if stg.rowId != "Khh5ytQT5jypns2qmMv8" || !near(stg.stored, 74078.52) || !near(stg.correct, 87039.26) {
		t.Errorf("stg fix = %+v, want stored 74,078.52, correct 87,039.26", stg)
	}
}

func TestFindFixesLeavesCorrectAndOtherRowsAlone(t *testing.T) {
	open := loanDoc("open", 10000, 0)
	deleted := loanDoc("deleted", 10000, 3)
	deleted.data["deleted_at"] = int64(1)
	fine := loanDoc("fine", 10000, 3)
	loans := []doc{open, deleted, fine}
	deletedRow := rowDoc("r-deleted", "fine", "paid_on_time", dec13, 3172.09, 0.0044, 3655.82)
	deletedRow.data["deleted_at"] = int64(1)
	rows := []doc{
		// Shaped like the bug, but open-term or on a deleted loan or row.
		rowDoc("r-open", "open", "paid_on_time", dec13, 3172.09, 0.0044, 3655.82),
		rowDoc("r-del-loan", "deleted", "paid_on_time", dec13, 3172.09, 0.0044, 3655.82),
		deletedRow,
		// Stored correctly by the fixed app.
		rowDoc("r-fine", "fine", "paid_late", dec13, 3172.09, 0.0044, 6827.91),
	}
	// A computed-balance row not paid by a teller is never matched.
	rows = append(rows, rowDoc("r-submitted", "fine", "payment_submitted", dec13+1, 3330.69, 0, 166.53))

	if fixes, manual := findFixes(loans, rows); len(fixes) != 0 || len(manual) != 0 {
		t.Fatalf("fixes %+v manual %+v, want none", fixes, manual)
	}
}

// listedOnly asserts that findFixes writes nothing and lists loan L with the
// rows in due-date order, their correct schedule balances and which match.
func listedOnly(t *testing.T, rows []doc, ids []string, correct []float64, matched []bool) manualRepair {
	t.Helper()
	fixes, manual := findFixes([]doc{loanDoc("L", 10000, 3)}, rows)
	if len(fixes) != 0 || len(manual) != 1 || manual[0].loanId != "L" {
		t.Fatalf("fixes %+v manual %+v, want L listed and nothing written", fixes, manual)
	}
	got := manual[0].rows
	if len(got) != len(ids) {
		t.Fatalf("rows = %+v, want %v", got, ids)
	}
	for i, r := range got {
		if r.id != ids[i] || !near(r.correct, correct[i]) || r.matched != matched[i] {
			t.Errorf("row %d = %+v, want %s correct %.2f matched %v", i, r, ids[i], correct[i], matched[i])
		}
	}
	return manual[0]
}

// G1 (10,000 at 5% for 3 months, P 3,672.0856). r1 paid by a teller before
// the fix: 10,000 - 3,172.09 - 3,172.0856 = 3,655.82 (correct 6,827.91).
// r2 computed from 3,655.82: interest 182.79, principal 3,489.29, balance
// 166.53. r3 computed from 166.53: interest 8.33, principal 166.53.
// Correct schedule balances: 6,827.91, 6,827.91 - 3,489.29 = 3,338.62,
// 3,338.62 - 166.53 = 3,172.09 (still owed).

func TestFindFixesListsTheReviewersChain(t *testing.T) {
	// r2 a confirmed submission (computed balance kept), r3 a teller payment
	// stored 166.53 - 166.53 - 166.53 = -166.53. A lone rewrite of r3 would
	// give 0.00 while 3,172.09 is owed.
	m := listedOnly(t, []doc{
		rowDoc("r3", "L", "paid_on_time", dec13+2, 166.53, 0, -166.53),
		rowDoc("r2", "L", "paid_on_time", dec13+1, 3489.29, 0, 166.53),
		rowDoc("r1", "L", "paid_on_time", dec13, 3172.09, 0.0044, 3655.82),
	}, []string{"r1", "r2", "r3"}, []float64{6827.91, 3338.62, 3172.09}, []bool{true, false, true})
	if !strings.Contains(m.reason, "2 of 3") {
		t.Errorf("reason = %q", m.reason)
	}
}

func TestFindFixesListsTwoConsecutiveMatches(t *testing.T) {
	// r2 also paid by a teller: 166.53 - 3,489.29 = -3,322.76.
	listedOnly(t, []doc{
		rowDoc("r1", "L", "paid_on_time", dec13, 3172.09, 0.0044, 3655.82),
		rowDoc("r2", "L", "paid_late", dec13+1, 3489.29, 0, 3655.82-3489.29-3489.29),
	}, []string{"r1", "r2"}, []float64{6827.91, 3338.62}, []bool{true, true})
}

func TestFindFixesListsAPartlyWrittenChain(t *testing.T) {
	// r1 already rewritten to 6,827.91 by hand, r2 still -3,322.76: neither
	// matches any more, the negative balance lists the loan.
	m := listedOnly(t, []doc{
		rowDoc("r1", "L", "paid_on_time", dec13, 3172.09, 0.0044, 6827.91),
		rowDoc("r2", "L", "paid_late", dec13+1, 3489.29, 0, -3322.76),
	}, []string{"r1", "r2"}, []float64{6827.91, 3338.62}, []bool{false, false})
	if m.reason != "a row has a negative balance" {
		t.Errorf("reason = %q", m.reason)
	}
}

func TestFindFixesListsAMatchThatIsNotTheLastRow(t *testing.T) {
	// A rejected submission stored after r1 (computed from 3,655.82).
	listedOnly(t, []doc{
		rowDoc("r1", "L", "paid_on_time", dec13, 3172.09, 0.0044, 3655.82),
		rowDoc("r2", "L", "not_paid_overdue", dec13+1, 3489.29, 0, 166.53),
	}, []string{"r1", "r2"}, []float64{6827.91, 3338.62}, []bool{true, false})
}

func TestFindFixesRewritesALoneMatchOnTheLastRow(t *testing.T) {
	// r1 stored correctly (6,827.91); r2 computed from it (interest 341.40,
	// principal 3,330.69, balance 3,497.22) and paid by a teller before the
	// fix: 3,497.22 - 3,330.69 = 166.53. Correct 6,827.91 - 3,330.69 =
	// 3,497.22.
	fixes, manual := findFixes([]doc{loanDoc("L", 10000, 3)}, []doc{
		rowDoc("r1", "L", "paid_on_time", dec13, 3172.09, 0.0044, 6827.91),
		rowDoc("r2", "L", "paid_on_time", dec13+1, 3330.69, 0, 166.529854),
	})

	if len(manual) != 0 || len(fixes) != 1 || fixes[0].rowId != "r2" || !near(fixes[0].correct, 3497.22) {
		t.Fatalf("fixes %+v manual %+v, want r2 rewritten to 3,497.22", fixes, manual)
	}
}

type fakeStore struct {
	loans, rows []doc
	rewritten   []fix
	marks       []map[string]any
	failRow     string
}

func (s *fakeStore) deps() deps {
	return deps{
		load: func(context.Context) ([]doc, []doc, error) { return s.loans, s.rows, nil },
		rewrite: func(_ context.Context, f fix) error {
			if f.rowId == s.failRow {
				return errors.New("precondition failed: the row changed")
			}
			s.rewritten = append(s.rewritten, f)
			return nil
		},
		mark: func(_ context.Context, runId string, fields map[string]any) error {
			s.marks = append(s.marks, map[string]any{"runId": runId, "fields": fields})
			return nil
		},
		now: func() time.Time { return time.Date(2026, 11, 19, 9, 30, 0, 0, time.UTC) },
	}
}

func TestDryRunListsAndWritesNothing(t *testing.T) {
	loans, rows := devLoan()
	store := &fakeStore{loans: loans, rows: rows}
	var out bytes.Buffer

	if err := run(context.Background(), options{env: "dev", by: "t"}, store.deps(), &out); err != nil {
		t.Fatal(err)
	}

	if len(store.rewritten) != 0 || len(store.marks) != 0 {
		t.Fatalf("dry run wrote: rows %v marks %v", store.rewritten, store.marks)
	}
	want := "affected: loan PRxL6LHifFWQjITEaQzq row W4PYWSxbNfziUVlJRe7X due 2026-12-13 principal 3172.09: stored 3655.82, correct 6827.91"
	if !strings.Contains(out.String(), want) || !strings.Contains(out.String(), "dry run: nothing written") {
		t.Errorf("output:\n%s\nwant the line %q", out.String(), want)
	}
}

func TestApplyRecordsTheMarkerAndRewritesOnlyTheLoneLastRow(t *testing.T) {
	loans, rows := devLoan()
	// A chain on another loan: listed, never written.
	loans = append(loans, loanDoc("L", 10000, 3))
	rows = append(rows,
		rowDoc("r1", "L", "paid_on_time", dec13, 3172.09, 0.0044, 3655.82),
		rowDoc("r2", "L", "paid_late", dec13+1, 3489.29, 0, 3655.82-3489.29-3489.29))
	store := &fakeStore{loans: loans, rows: rows}
	var out bytes.Buffer

	if err := run(context.Background(), options{env: "dev", apply: true, by: "t"}, store.deps(), &out); err != nil {
		t.Fatal(err)
	}

	if len(store.rewritten) != 1 || store.rewritten[0].rowId != "W4PYWSxbNfziUVlJRe7X" || !near(store.rewritten[0].correct, 6827.91) {
		t.Fatalf("rewritten = %+v, want only the dev row at 6,827.91", store.rewritten)
	}
	if !strings.Contains(out.String(), "needs a manual or recompute repair: loan L (2 of 2 row(s) match") ||
		!strings.Contains(out.String(), "row r2 due 2026-12-13 paid_late: interest 0.00 principal 3489.29 extra 0.0000 balance -3322.76, correct schedule balance 3338.62 [double subtraction]") {
		t.Errorf("output:\n%s", out.String())
	}
	if !store.rewritten[0].updated.Equal(time.UnixMilli(dec13)) {
		t.Errorf("the rewrite must carry the row's update time as its precondition")
	}
	if len(store.marks) != 2 {
		t.Fatalf("marks = %v, want the plan and the finish", store.marks)
	}
	first := store.marks[0]["fields"].(map[string]any)
	planned := first["rows"].([]any)[0].(map[string]any)
	if first["applied"] != false || !near(planned["before"].(float64), 3655.82) || !near(planned["after"].(float64), 6827.91) {
		t.Errorf("first mark = %v, want applied false with before 3,655.82 and after 6,827.91", first)
	}
	last := store.marks[1]["fields"].(map[string]any)
	if last["applied"] != true || store.marks[1]["runId"] != "20261119T093000Z" {
		t.Errorf("last mark = %v", store.marks[1])
	}
}

func TestApplyReportsARowThatChanged(t *testing.T) {
	loans, rows := devLoan()
	store := &fakeStore{loans: loans, rows: rows, failRow: "W4PYWSxbNfziUVlJRe7X"}
	var out bytes.Buffer

	err := run(context.Background(), options{env: "dev", apply: true, by: "t"}, store.deps(), &out)

	if err == nil || !strings.Contains(out.String(), "not written: row W4PYWSxbNfziUVlJRe7X") {
		t.Fatalf("err %v, output:\n%s", err, out.String())
	}
	result := store.marks[1]["fields"].(map[string]any)["rows"].([]any)[0].(map[string]any)
	if result["written"] != false {
		t.Errorf("marker row = %v, want written false", result)
	}
}

func TestCheckOptions(t *testing.T) {
	for _, c := range []struct {
		name string
		opts options
		ok   bool
	}{
		{"no env", options{by: "t"}, false},
		{"unknown env", options{env: "production", by: "t"}, false},
		{"dry run dev", options{env: "dev", by: "t"}, true},
		{"dry run prod", options{env: "prod", by: "t"}, true},
		{"apply stg", options{env: "stg", apply: true, by: "t"}, true},
		{"apply prod without confirmation", options{env: "prod", apply: true, by: "t"}, false},
		{"apply prod with the wrong confirmation", options{env: "prod", apply: true, by: "t", confirmProd: "prod"}, false},
		{"apply prod confirmed", options{env: "prod", apply: true, by: "t", confirmProd: "loooans-prod"}, true},
		{"confirmation without apply", options{env: "prod", by: "t", confirmProd: "loooans-prod"}, false},
		{"apply without a name", options{env: "dev", apply: true}, false},
	} {
		if err := checkOptions(c.opts, 0); (err == nil) != c.ok {
			t.Errorf("%s: err = %v, want ok %v", c.name, err, c.ok)
		}
	}
	if checkOptions(options{env: "dev", by: "t"}, 1) == nil {
		t.Error("extra arguments must be refused")
	}
}
