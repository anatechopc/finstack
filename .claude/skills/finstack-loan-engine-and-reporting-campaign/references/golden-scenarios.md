# Golden scenario suite for the loan math core (Phase 1 working material)

Target under test: `apps/loans/lib/services/loan_calculation_service.dart`
(478 lines, static methods, pure except for wall-clock reads — see "Clock
coupling" below), plus `charge_calculator.dart` and the early-settlement
formula. Formula semantics live in loans-domain-reference; this file is the
test plan with hand-computed expected numbers.

Tests go in `apps/loans/test/services/loan_calculation_service_test.dart`
(one test already exists there — keep it) and siblings. Run:

```bash
cd apps/loans
fvm flutter test test/services/ --test-randomize-ordering-seed random
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

`calculateOpenTermSchedules` reads the real clock (`Jiffy.now()`) in two
places (verified in source):

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

There is no injectable clock. Two coping strategies, in preference order:

- **S1 (no code change): anchor scenarios so `now` is irrelevant.** Use loan
  dates relative to `DateTime.now()` (e.g. `final start =
  DateTime.now().subtract(const Duration(days: 1));`) so `nextDate` is
  always in the future, and for `'D1,D2'` make the start date fall exactly
  ON a salary day (path 1 or 2 of the branch, both now-free). Expected
  numbers stay deterministic because interest depends on day DIFFS, not
  absolute dates.
- **S2 (behavior-preserving seam, allowed pre-gate): add an optional
  `DateTime? now` parameter** defaulting to the real clock. This is a seam,
  not a math change — land it with the suite proving output is bit-identical
  when the parameter is omitted. Only do this if S1 cannot express a
  scenario you need (the third `'D1,D2'` sub-branch is the one that truly
  requires it).

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
| G5 | `calculateOpenTermSchedules` | 10000, 5%, term `'1,15'`, start ON day 1 (next month, future) | dueAt = day 15 same month; diff 14 days; multiplier 14/30 = 0.4667; interestCharge closeTo 233.33 | `'D1,D2'` comma parsing + salary-day hop |
| G5b | `calculateOpenTermSchedules` | term `'15,1'` (reversed order), start ON day 1 | identical to G5 (code min/maxes the two days) | salary-day ordering |
| G6 | `calculateOpenTermSchedules` | 10000, 5%, `'1m'`, start = Feb 1 of the next NON-LEAP year (test helper picks it, keeping it in the future) | dueAt = Mar 3 that year (Feb 1 + 30 CALENDAR days); multiplier exactly 1.0; interest 500.00 | month-boundary proration: 1 month = 30 days, NOT calendar month |
| G7 | early-settlement formula | family of 1 loan (10000 + 500 charges - 200 deductions - 100 upfront) + 2 paid open-term schedules (interestCharge 500 + principal 0; interestCharge 400 + extra 1000) | totalLoanAmount 10200; total payments 1900; remaining 8300 | D9 candidate bug (`=` vs `+=`): buggy code reports 10200-1400 = 8800 |
| G8 | `ChargeCalculator.applyChargesAndDeductionsDetailed` | base 10000; charges [5%, flat 150, upfront 2%]; deductions [1%, flat 50] | additionalCharges 650, upfront 200, deductions 150, totalAmount 10500 | percent-vs-flat parsing; upfront excluded from principal |
| G9 | `calculateOpenTerm` (finstack#33 RC2) | open-term loan, 1 paid schedule (OB 10000), 1 additional loan (2000 + 100 charges) dated after the paid schedule but in the past | additional-loan placeholder schedule has OB = 12100 EXACTLY ONCE; the adjacent computed schedule is updated in place to OB 12100 (the documented mutation at the end of `calculateOpenTerm`); the 12100 appears from the insertion point onward and nowhere earlier | double-counted OB (root cause 2 of finstack#33) |
| G10 | `calculateOpenTerm` (finstack#33 RC3) | 2 additional loans supplied NEWEST-FIRST in `loan.additionalLoanAmounts` | processing order is by `createdAt` ascending: first placeholder OB = base+A1, second = base+A1+A2 | reverse-order iteration (root cause 3 of finstack#33; the `sortedBy` at ~line 357) |
| G11 | bloc flow (finstack#33 RC1) | AdditionalLoanBloc success → LoansBloc refresh | `selectLoan()` invoked after success | stale-UI root cause 1 — NOT a math test; write as a bloc/widget test per finstack-testing-and-validation, or park it explicitly |

Notes:

- **G4a sentinel:** `totalLoanPayment = double.infinity` for open-term is
  intentional ("no fixed total"); pin it so a refactor that "fixes" it to 0
  or NaN is caught and forced to be a deliberate, documented change.
- **G7 requires an extraction first:** the formula currently lives inline in
  `LoanSettlementBloc._handleSettleLoanAccountEvent` (no seam). Extract it
  to a pure static (suggested: `LoanCalculationService.
  calculateSettlementBalance(loans, schedules)`) with the bloc delegating —
  behavior-preserving, allowed pre-gate. Write G7 against the extraction
  with the CURRENT (buggy, `=`) semantics first if you must ship the seam
  separately; flip the expectation in the same PR that fixes D9, never
  silently.
- **G9/G10 encode finstack#33** (PR finstack#33, closed issue finstack#4;
  full narrative in finstack-failure-archaeology). Root causes, restated as
  test oracles: (1) UI didn't refresh → G11; (2) OB mutated twice (bloc +
  service) → G9; (3) newest-first iteration → G10.
- The `'D1,D2'` third sub-branch (start date on NEITHER salary day) and the
  past-due-date clamp are wall-clock-dependent (see Clock coupling). Cover
  them only after the S2 seam exists; until then list them in the suite file
  as `// UNCOVERED: needs clock seam` comments so the gap is visible.

## Gate check

Phase 1 is done when:

```bash
cd apps/loans && fvm flutter test test/services/ --test-randomize-ordering-seed random
```

is green with G1-G10 present (G11 optional but tracked), every expected
number traces to a written derivation (commit the derivations in the test
file's comments or alongside the scenario), and a deliberately broken
constant (e.g. change `/ 30` to `/ 31` locally) fails at least one test.
That last mutation check is the cheap proof the suite actually bites.
