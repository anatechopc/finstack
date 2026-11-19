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

	fixes, review := findFixes(loans, rows)

	if len(fixes) != 2 || len(review) != 0 {
		t.Fatalf("fixes %d review %d, want 2 and 0", len(fixes), len(review))
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

	if fixes, review := findFixes(loans, rows); len(fixes) != 0 || len(review) != 0 {
		t.Fatalf("fixes %+v review %+v, want none", fixes, review)
	}
}

func TestFindFixesChainsAndListsLaterRows(t *testing.T) {
	// Row 1 and row 2 both paid by a teller before the fix (rows sorted by
	// due date whatever the read order): row 2 was computed from 3,655.82
	// (interest 182.79, principal 3,489.29, computed balance 166.53) and
	// stored 166.53 - 3,489.29 = -3,322.76. Correct: 6,827.91 - 3,489.29 =
	// 3,338.62. Row 3, a confirmed submission, kept the computed balance
	// that follows the wrong one: listed for review, not rewritten.
	loans := []doc{loanDoc("L", 10000, 3)}
	rows := []doc{
		rowDoc("r3", "L", "payment_submitted", dec13+2, 166.53, 0, 0),
		rowDoc("r2", "L", "paid_late", dec13+1, 3489.29, 0, 3655.82-3489.29-3489.29),
		rowDoc("r1", "L", "paid_on_time", dec13, 3172.09, 0.0044, 3655.82),
	}

	fixes, review := findFixes(loans, rows)

	if len(fixes) != 2 {
		t.Fatalf("fixes = %+v, want r1 and r2", fixes)
	}
	if fixes[0].rowId != "r1" || !near(fixes[0].correct, 6827.91) {
		t.Errorf("r1 = %+v, want correct 6,827.91", fixes[0])
	}
	if fixes[1].rowId != "r2" || !near(fixes[1].correct, 3338.62) {
		t.Errorf("r2 = %+v, want correct 3,338.62 (from the corrected r1)", fixes[1])
	}
	if len(review) != 1 || review[0].rowId != "r3" {
		t.Errorf("review = %+v, want r3", review)
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

func TestApplyRecordsTheMarkerAndRewritesOnlyTheMatchedRows(t *testing.T) {
	loans, rows := devLoan()
	rows = append(rows, rowDoc("fine", "PRxL6LHifFWQjITEaQzq", "not_paid", dec13+1, 3489.29, 0, 166.53))
	store := &fakeStore{loans: loans, rows: rows}
	var out bytes.Buffer

	if err := run(context.Background(), options{env: "dev", apply: true, by: "t"}, store.deps(), &out); err != nil {
		t.Fatal(err)
	}

	if len(store.rewritten) != 1 || store.rewritten[0].rowId != "W4PYWSxbNfziUVlJRe7X" || !near(store.rewritten[0].correct, 6827.91) {
		t.Fatalf("rewritten = %+v, want only the dev row at 6,827.91", store.rewritten)
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
