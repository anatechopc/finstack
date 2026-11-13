# Golden scenario suite for the loan math core (Phase 1 working material)

> **Status 2026-09-08: implemented** (finstack#112). G1–G10 live in
> `apps/loans/test/services/` (four files, derivations in comments); G5c
> (start on the second salary day) was added as a bonus now-free branch.
> The table below stays as the design record.
>
> **2026-11-13: G9 and G10 flipped by finstack#117** (campaign D10, fixed):
> after a top-up the due row charges the new balance for the days left in
> its cycle and its amount due follows. G9b–G9e were added with it (top-up
> with a time of day, top-up on the due date, overdue row, top-up stamped
> after the due date).

Target under test: `apps/loans/lib/services/loan_calculation_service.dart`
(~510 lines, static methods, pure except for wall-clock reads — see "Clock
coupling" below), plus `charge_calculator.dart` and the early-settlement
formula. Formula semantics live in loans-domain-reference; this file is the
test plan with hand-computed expected numbers.

Tests go in `apps/loans/test/services/loan_calculation_service_test.dart`
(one test already exists there — keep it) and siblings. Run:

```bash
cd apps/loans
TZ=UTC fvm flutter test test/services/ --test-randomize-ordering-seed random
```

Test mechanics (fixture idioms, `closeTo`, bloc seams) are
finstack-testing-and-validation's territory; only scenario-specific notes
appear here.

## Fixture recipe (verified constructors)

- Models use late-field cascade construction — the existing test does
  `LoanSchedule()..id = 'real-sched-1'..loanId = …..dueAt = DateTime(…)…`.
  Prefer this over the `.create` factories in tests when you need to control
  `createdAt` (the factories pin `createdAt = DateTime.timestamp()`).
- `AdditionalLoanAmount` (in `loan_repository`): construct with
  `AdditionalLoanAmount()..id = 'al-1'..loanId = …..amount = …
  ..additionalCharges = …..advanceCharges = …..deductions = …
  ..createdAt = …..updatedAt = …..status = LoanStatus.approved`.
- `Loan` for `calculateOpenTerm(loan: …)`: cascade-set at minimum `id`,
  `createdAt`, `additionalChargeUpfrontCollection`, `additionalLoanAmounts`.
- Assert money with `closeTo(expected, 0.01)` — the engine does raw double
  arithmetic; never assert exact equality on derived amounts.

## Clock coupling (read before writing any open-term scenario)

`calculateOpenTermSchedules` reads the clock (`now ?? DateTime.now()` since
the S2 seam; `Jiffy.now()` before it) in two places (verified in source):

1. The clamp `if (nextDate.isSameOrBefore(now)) nextDate = now.startOf(day)`
   — fires when the computed next due date is in the past.
2. The `'D1,D2'` branch: when the start date's day-of-month matches neither
   salary day, the next date is derived from TODAY's day-of-month.

A third, sneakier coupling sits in `calculateOpenTerm`'s additional-loan
loop: it positions each additional loan by comparing `schedule.createdAt`
against `additionalLoanAmount.createdAt`, and schedules computed in the same
run carry `createdAt = DateTime.timestamp()` (i.e. NOW — set by
`LoanSchedule.create`). Consequence for fixtures: date additional-loan
fixtures in the PAST relative to the test run, otherwise they sort after the
freshly computed schedules and the insertion point shifts.

The clock is injectable since 2026-09-08 (S2 below). Two coping strategies,
in preference order — S1 still applies to every scenario that can use it:

- **S1 (no code change): anchor scenarios so `now` is irrelevant.** Use loan
  dates relative to `DateTime.now()` (e.g. `final start =
  DateTime.now().subtract(const Duration(days: 1));`) so `nextDate` is
  always in the future, and for `'D1,D2'` make the start date fall exactly
  ON a salary day (path 1 or 2 of the branch, both now-free). Expected
  numbers stay deterministic because interest depends on day DIFFS, not
  absolute dates.
- **DST caveat (campaign D11):** the suite assumes a zone without daylight
  saving; the CI test step pins `TZ=UTC` and the gate command below does
  too. jiffy floors day diffs and adds days as a Duration, so under DST a
  proration across a spring-forward is one day short and a due date across
  a fall-back lands at 23:00 the previous day (G5/G5b fail under US rules,
  G5c under EU rules, G2's fixed dates under Australia/Sydney — verified).
  Do not "fix" the fixtures with UTC anchors; that would hide the defect.
- **Parked (tracked here, not in the test files):** G11 (UI refresh after an
  additional loan — a widget flow, not math). The past-due clamp and the
  `'D1,D2'` neither-day branch are covered by G4c/G5d through the S2 seam
  (optional `now` on `calculateOpenTermSchedules` / `calculateOpenTerm`,
  landed 2026-09-08 in #115).
- **S2 (DONE 2026-09-08): optional `DateTime? now` parameter** on
  `calculateOpenTermSchedules` and `calculateOpenTerm`, defaulting to the
  real clock. A seam, not a math change: every earlier scenario omits it and
  stays green (the bit-identical proof); G4c and G5d pass a fixed date.

## The worked-derivation method template (G1)

This is the "prove it, don't just install it" recipe: every scenario's
expected numbers must be derived on paper (or in a throwaway script that is
NOT the code under test) before the test is written. G1 in full:

**Inputs:** `amount = 10000`, `monthsToPay = 3`, `interestRate = 5` (percent
per month), `term = '1m'`, any past `date`, `paidSchedules = []`.

**Step 1 — amortization** (formula in code:
`extensions.dart::calculateMonthlyPayment`, `P = (Pv*R)/(1-(1+R)^-n)`):

```
R = 5/100 = 0.05          n = 3          Pv = 10000
(1+R)^n  = 1.05^3 = 1.157625
(1+R)^-n = 1/1.157625 = 0.86383760
P = (10000 * 0.05) / (1 - 0.86383760) = 500 / 0.13616240 = 3672.0856
```

**Step 2 — amortization table** (loop in `calculateFixedTerm`: interest =
OB*R; principal = P - interest; OB -= principal; last row amortization =
`min(P, OB + interest)`):

| # | beginning OB | interest | principal | ending OB |
|---|-------------:|---------:|----------:|----------:|
| 1 | 10000.00 | 500.00 | 3172.09 | 6827.91 |
| 2 | 6827.91 | 341.40 | 3330.69 | 3497.22 |
| 3 | 3497.22 | 174.86 | 3497.22 | 0.00 |

**Step 3 — assertions:** `monthlyAmortization` closeTo 3672.09 (0.01);
3 schedules; per-row `interestCharge`/`principalPayment`/`outstandingBalance`
closeTo the table (0.01); `totalLoanPayment` closeTo 11016.26 (0.05); due
dates step by exactly 1 calendar month (`term == '1m'`).

Every other scenario documents inputs + expected numbers the same way; the
derivations below are abbreviated but were computed by the same method.
Recompute them yourself before trusting a failing/passing test — that
double-derivation IS the proof.

## Scenario table

| ID | Method / target | Inputs (summary) | Expected (hand-derived) | Guards against |
|----|-----------------|------------------|-------------------------|----------------|
| G1 | `calculateFixedTerm` | 10000, 3 mo, 5%, `'1m'` | table above | amortization formula drift |
| G2 | `calculateFixedTerm` | 10000, 3 mo, 5%, `'15d'` | 6 payments, R=0.025/period, P closeTo 1815.50; total closeTo 10893.00 (tol 0.05) | `'15d'` doubling/halving logic |
| G3 | `calculateFixedTerm` | resume with 1 persisted paid schedule | output contains ONLY computed schedules (all `id == NO_ID`), count = n-1, amortization taken from `paidSchedules.first.amortization` | teller double-count (EXISTS — keep) |
| G4a | `calculateOpenTermSchedules` | 10000, 5%, `'1m'`, start = now-1d | 1 schedule; dueAt = start+30d; multiplier 1.0; interestCharge 500.00; principalPayment 0; OB stays 10000; amortization 500.00; `totalLoanPayment == double.infinity` (sentinel — pin it) | 30-day-month convention; interest-only invariant |
| G4b | `calculateOpenTermSchedules` | same but `'15d'` | dueAt = start+15d; multiplier 0.5; interestCharge 250.00 | 15-day proration |
| G4c | `calculateOpenTermSchedules` (S2 seam) | paid row due Aug 1 (OB 10000), `now` = 2026-09-08 noon | next due Aug 31 is past → snaps to Sep 8; diff 38 → multiplier 38/30; interestCharge 633.33; amortization stays 500 (pinned oddity); with `now` = Aug 15: due Aug 31, 500 | past-due clamp (the overdue path penalties run on) |
| G5d | `calculateOpenTermSchedules` (S2 seam) | `'1,15'` start on neither day; `now` fixed | start Sep 5 / now Sep 8 → due Sep 15, 10 d, 166.67; start Sep 18 / now Sep 20 → due Oct 1, 13 d, 216.67; `'5,20'` start Sep 2 / now Sep 3 → due Sep 5, 3 d, 50.00 | `'D1,D2'` third sub-branch (next due derived from today) |
| G5 | `calculateOpenTermSchedules` | 10000, 5%, term `'1,15'`, start ON day 1 (next month, future) | dueAt = day 15 same month; diff 14 days; multiplier 14/30 = 0.4667; interestCharge closeTo 233.33 | `'D1,D2'` comma parsing + salary-day hop |
| G5b | `calculateOpenTermSchedules` | term `'15,1'` (reversed order), start ON day 1 | identical to G5 (code min/maxes the two days) | salary-day ordering |
| G6 | `calculateOpenTermSchedules` | 10000, 5%, `'1m'`, start = Feb 1 of the next NON-LEAP year (test helper picks it, keeping it in the future) | dueAt = Mar 3 that year (Feb 1 + 30 CALENDAR days); multiplier exactly 1.0; interest 500.00 | month-boundary proration: 1 month = 30 days, NOT calendar month |
| G7 | early-settlement formula | family of 1 loan (10000 + 500 charges - 200 deductions - 100 upfront) + an open-term row (interest 500) and a fixed-term row (interest 400 + principal 1000) | released 10200; CURRENT formula = released − last row only = 8800 (pinned); accumulation would give 8300 but is NOT the target (subtracts interest from principal) — finstack#116 decides the formula | D9 and its siblings (see aggregation-triggers.md D9) |
| G8 | `ChargeCalculator.applyChargesAndDeductionsDetailed` | base 10000; charges [5%, flat 150, upfront 2%]; deductions [1%, flat 50] | additionalCharges 650, upfront 200, deductions 150, totalAmount 10500 | percent-vs-flat parsing; upfront excluded from principal |
| G9 | `calculateOpenTerm` (finstack#33 RC2) | open-term loan, 1 paid schedule (OB 10000), 1 additional loan (2000 + 100 charges) dated after the paid schedule but in the past | additional-loan placeholder schedule has OB = 12100 EXACTLY ONCE and keeps the interest accrued on the old balance, 10000 × 5% × 5/30 = 83.33; the adjacent computed schedule is updated in place (the mutation at the end of `calculateOpenTerm`): OB 12100, days left 30 − 5 = 25, interest 12100 × 5% × 25/30 = 504.17, amortization 504.17 (finstack#117; it copied 83.33 and kept 500 before); the 12100 appears from the insertion point onward and nowhere earlier | double-counted OB (root cause 2 of finstack#33); top-up interest copied onto the due row (D10) |
| G10 | `calculateOpenTerm` (finstack#33 RC3) | 2 additional loans supplied NEWEST-FIRST in `loan.additionalLoanAmounts` (A2 = 3000, two days after A1) | processing order is by `createdAt` ascending: first placeholder OB = base+A1 (83.33), second = base+A1+A2 = 15100 (12100 × 5% × 2/30 = 40.33); the computed schedule ends at 15100 with 25 − 2 = 23 days left: 15100 × 5% × 23/30 = 578.83, amortization 578.83 (finstack#117) | reverse-order iteration (root cause 3 of finstack#33; the `sortedBy` at ~line 357) |
| G9b–G9e | `calculateOpenTerm` (S2 seam, finstack#117) | fixed dates: paid row due Aug 1 (OB 10000), one top-up of 2000 + 100 | **G9b** top-up Aug 6 14:30, now Aug 15: 5 + 25 days → 83.33 and 504.17 (the whole days from the top-up time to the due date would be 24); **G9c** top-up on the due date Aug 31: stamped 00:00:00 the same-instant branch replaces the due row with the top-up row (30 days, 500, no due row); stamped 10:15 the top-up row has 30 days / 500 and the due row 0 days / 0 / amount due 0; **G9d** now Sep 8 (38-day overdue row), top-up Aug 3: 2 days → 33.33, 36 days left → 726.00, amortization capped at 605 (one month on the new balance, finstack#120); **G9e** top-up stamped after the due date: days left floor at 0, never negative | time-of-day day loss; the two due-date branches; the cap on the new balance; negative interest |
| G11 | bloc flow (finstack#33 RC1) | AdditionalLoanBloc success → LoansBloc refresh | `selectLoan()` invoked after success | stale-UI root cause 1 — NOT a math test; write as a bloc/widget test per finstack-testing-and-validation, or park it explicitly |
| G12 | penalties: `resolveLateness` / `PaymentConfirmationService.applyLateness` (`test/services/penalty_golden_test.dart`, 11 scenarios) | company default penalties copied to a product, snapshotted on the loan; a row 5 days late on a 2,500 amortization (100 once + 25/day) | defaults imposed → 225 and `paid_late`; no company defaults → `paid_late` but 0, nothing to penalize or waive; allow-late product → `paid_on_time`, 0; open-term base is the outstanding balance (600); monthly and per-installment cadence; waive needs a reason and keeps the terms; the loan snapshot does not follow later edits | a penalty charged without a definition, the wrong base or cadence, a waive that erases the record, a snapshot that follows the product |

Notes:

- **G4a sentinel:** `totalLoanPayment = double.infinity` for open-term is
  intentional ("no fixed total"); pin it so a refactor that "fixes" it to 0
  or NaN is caught and forced to be a deliberate, documented change.
- **G7 (extraction DONE 2026-09-08 as
  `LoanCalculationService.calculateSettlementBalance`, the bloc delegates):**
  written against the CURRENT formula on purpose. The review of PR #115
  showed the formula is wrong four ways (aggregation-triggers.md D9), so
  the expectation flips with finstack#116's decided formula, never
  silently, and never to a plain `+=` (8300 is not the answer either).
- **G9/G10 encode finstack#33** (PR finstack#33, closed issue finstack#4;
  full narrative in finstack-failure-archaeology). Root causes, restated as
  test oracles: (1) UI didn't refresh → G11; (2) OB mutated twice (bloc +
  service) → G9; (3) newest-first iteration → G10.
- **Top-up interest (finstack#117, campaign D10 — FIXED 2026-11-13):** the
  top-up row keeps the old balance for the days since the previous row; the
  computed due row charges the new balance for the days left and its amount
  due follows. Days left = the due row's own day count minus the days the
  top-up row counted, so the parts always add up to the cycle. Only the
  computed row is recomputed: a persisted row that follows a top-up keeps
  the earlier copy behaviour (and its balance gets the top-up added a
  second time on screen — open defect, see `apps/loans/MEMORY.md`).
- The `'D1,D2'` third sub-branch (start date on NEITHER salary day) and the
  past-due-date clamp are wall-clock-dependent (see Clock coupling); covered
  by G5d and G4c through the S2 seam since 2026-09-08. G4c also pins that an
  overdue row's amortization stays capped at one month's interest while
  interestCharge keeps growing — current behaviour, pinned; campaign D12,
  finstack#120 (owner decides what an overdue row should bill).

## Gate check

Phase 1 is done when:

```bash
cd apps/loans && TZ=UTC fvm flutter test test/services/ --test-randomize-ordering-seed random
```

is green with G1-G10 present (G11 optional but tracked), every expected
number traces to a written derivation (commit the derivations in the test
file's comments or alongside the scenario), and a deliberately broken
constant (e.g. change `/ 30` to `/ 31` locally) fails at least one test.
That last mutation check is the cheap proof the suite actually bites.
