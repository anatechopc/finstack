# Golden scenario suite for the loan math core (Phase 1 working material)

> **Status 2026-09-08: implemented** (finstack#112). G1–G10 live in
> `apps/loans/test/services/` (four files, derivations in comments); G5c
> (start on the second salary day) was added as a bonus now-free branch.
> The table below stays as the design record.

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
the S2 seam; `Jiffy.now()` before it) in ONE place since the owner rules R1-R5
(2026-11-19): it lists every bill due before today, then the bill due today or
later. Before R1 it read it twice: the clamp `if (nextDate.isSameOrBefore(now))
nextDate = now.startOf(day)` and the `'D1,D2'` branch, which took the next
salary day from TODAY's day-of-month when the start date was on neither (both
gone; bills are on scheduled dates).

A third, sneakier coupling sat in `calculateOpenTerm`'s additional-loan loop,
which positioned each additional loan by comparing `schedule.createdAt` with
`additionalLoanAmount.createdAt`. Since R5 top-up rows are positioned by date;
whether a top-up is already in a stored row's balance still compares the
stored row's `createdAt` (rows computed in a run carry `createdAt =
DateTime.timestamp()`). Consequence for fixtures, kept from before: date
additional-loan fixtures in the PAST relative to the test run, otherwise they sort after the
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
| G4c | `calculateOpenTermSchedules` (S2 seam) | paid row due Aug 1 (OB 10000), `now` = 2026-09-08 noon | FLIPPED 2026-11-19 (R1/R2): the Aug 31 bill keeps its date, 30 days, 500, no `original_due_at`, then the Sep 30 bill (500). Was: snapped to Sep 8, 38/30, 633.33, amortization capped at 500. With `now` = Aug 15: due Aug 31, 500 (unchanged) | overdue bills keep their dates; no accrual to today, no cap (#120) |
| G5d | `calculateOpenTermSchedules` (S2 seam) | `'1,15'` start on neither day; `now` fixed | start Sep 5 / now Sep 8 → due Sep 15, 10 d, 166.67; start Sep 18 / now Sep 20 → due Oct 1, 13 d, 216.67; `'5,20'` start Sep 2 / now Sep 3 → due Sep 5, 3 d, 50.00 | `'D1,D2'` start on neither day: since R1 the next salary day after the start date (same numbers as when it came from today) |
| G5 | `calculateOpenTermSchedules` | 10000, 5%, term `'1,15'`, start ON day 1 (next month, future) | dueAt = day 15 same month; diff 14 days; multiplier 14/30 = 0.4667; interestCharge closeTo 233.33 | `'D1,D2'` comma parsing + salary-day hop |
| G5b | `calculateOpenTermSchedules` | term `'15,1'` (reversed order), start ON day 1 | identical to G5 (code min/maxes the two days) | salary-day ordering |
| G6 | `calculateOpenTermSchedules` | 10000, 5%, `'1m'`, start = Feb 1 of the next NON-LEAP year (test helper picks it, keeping it in the future) | dueAt = Mar 3 that year (Feb 1 + 30 CALENDAR days); multiplier exactly 1.0; interest 500.00 | month-boundary proration: 1 month = 30 days, NOT calendar month |
| G7 | early-settlement formula | family of 1 loan (10000 + 500 charges - 200 deductions - 100 upfront) + an open-term row (interest 500) and a fixed-term row (interest 400 + principal 1000) | released 10200; CURRENT formula = released − last row only = 8800 (pinned); accumulation would give 8300 but is NOT the target (subtracts interest from principal) — finstack#116 decides the formula | D9 and its siblings (see aggregation-triggers.md D9) |
| G8 | `ChargeCalculator.applyChargesAndDeductionsDetailed` | base 10000; charges [5%, flat 150, upfront 2%]; deductions [1%, flat 50] | additionalCharges 650, upfront 200, deductions 150, totalAmount 10500 | percent-vs-flat parsing; upfront excluded from principal |
| G9 | `calculateOpenTerm` (finstack#33 RC2) | open-term loan, 1 paid schedule (OB 10000), 1 additional loan (2000 + 100 charges) dated after the paid schedule but in the past | additional-loan placeholder schedule has OB = 12100 EXACTLY ONCE (83.33 accrued, amortization 0); the due row has OB 12100 and FLIPPED 2026-11-19 (R5, #117) bills 83.33 + 504.17 = 587.50 (was 83.33 copied, 500 due); G9b-G9f: top-up at 14:30 (587.50), on the due date (500, old balance), in a missed cycle (598.00 then 605.00), stamped after the bill (500), previous cycle paid early (605.00 + the top-up's 3 unbilled days 10.50 = 615.50 since the #146 review; #131's review probe) | double-counted OB (root cause 2 of finstack#33); the top-up split |
| G10 | `calculateOpenTerm` (finstack#33 RC3) | 2 additional loans supplied NEWEST-FIRST in `loan.additionalLoanAmounts` | processing order is by `createdAt` ascending: first placeholder OB = base+A1, second = base+A1+A2; FLIPPED 2026-11-19 (R5): the due row bills 83.33 + 40.33 + 578.83 = 702.50 (was 40.33 copied) | reverse-order iteration (root cause 3 of finstack#33; the `sortedBy` at ~line 357) |
| G11 | bloc flow (finstack#33 RC1) | AdditionalLoanBloc success → LoansBloc refresh | `selectLoan()` invoked after success | stale-UI root cause 1 — NOT a math test; write as a bloc/widget test per finstack-testing-and-validation, or park it explicitly |
| G12 | penalties: `resolveLateness` / `PaymentConfirmationService.applyLateness` (`test/services/penalty_golden_test.dart`, 11 scenarios) | company default penalties copied to a product, snapshotted on the loan; a row 5 days late on a 2,500 amortization (100 once + 25/day) | defaults imposed → 225 and `paid_late`; no company defaults → `paid_late` but 0, nothing to penalize or waive; allow-late product → `paid_on_time`, 0; open-term base is the outstanding balance (600); monthly and per-installment cadence; waive needs a reason and keeps the terms; the loan snapshot does not follow later edits | a penalty charged without a definition, the wrong base or cadence, a waive that erases the record, a snapshot that follows the product |
| G13 | open-term lateness (finstack#114): `calculateOpenTermSchedules` (S2 seam) → `previewPenalty` / `resolveLateness` / `applyLateness` (`test/services/penalty_open_term_golden_test.dart`, 7 scenarios) | the G4c loan (paid cycle due Aug 1, OB 10,000, 5%) with 100 once + 1%/day of the balance; seen Sep 8 noon | INTEREST FLIPPED 2026-11-19 (R1/R2; penalties unchanged): the bill is due Aug 31, 500 (was due Sep 8, 633.33, `originalDueAt` Aug 31); `'15,30'` bills Aug 30 250 and Sep 15 266.67 (was one row due Sep 16, 533.33), both paid together still 2,000 once (R3). Penalties: 8 days late, 100 + 800 = 900, `paid_late`; allow-late → 8 days recorded, 0, `paid_on_time`; on time (seen Aug 15, or on Aug 31 itself) → no original due date, 0; `'15,30'` paid Aug 15 seen Sep 16 → due Aug 30, 17 days, 100 + 1,700 + 100 × ceil(17/15) = 2,000; stored row keeps `original_due_at` and reads back 8 days, a pre-#114 document counts from `due_at`; collected Sep 5 → 5 days, 600; the principal-release placeholder → 0, and confirming it → `paid_on_time`, 0 days. Before #114 every one of these was 0 days, 0 | lateness read from the billing date (open-term never late), the salary-day term read as 30 days, the original due date lost on the stored row, a penalty on a placeholder row |
| G14 | owner rules R1-R5 (2026-11-19): `calculateOpenTermSchedules` / `calculateOpenTerm` (S2 seam), `borrowerAmountsDue`, `resolveLatenessTogether` / `previewPenalty` / `applyLateness` with the loan's rows, `splitOpenTermInterest` (`test/services/open_term_billing_golden_test.dart`, 48 scenarios; G14t-u from the fourth #146 review: billing never continues from a stored principal release (500 per cycle, Pay in full 2,000 by Oct 5), the one-day rule for salary days; G14s from the third: an old build's clamp row does not move the schedule (Aug 31, 22 days, 500 due, then Sep 30); G14p-r from the second: a stored bill within a day of its date is that bill (no 1-day bill under UTC or Manila), a top-up counts from its approval (692.50, 605, 605), two bills in one submission owe 450 once; G14i-o from the first: approved top-ups only 587.50 vs 500, per-day penalty base 400, active loans only (7 bills vs none), clamp-row shortfall 1,500, UTC vs Manila same bills, month-end salary days, 899 bills with the current one last) | 40,000 at 5% on `'15,30'`; 10,000 and 20,000 `'1m'`/`'15d'`; penalties 0.1%/day, 10%/month, 10%/installment, 100 once | salary-day example: Sep 15 1,066.67 + Sep 30 1,000 + 15 × 40 = 2,666.67; next bill after a late payment on its scheduled date (`'1m'` Aug 31 500, clamp row 433.33 interest and 500.00 due with its 66.67 unbilled charge (moved in the #146 review, was 433.33); `'15d'` Aug 1 200 then Aug 16; #144 repros: Sep 30 / Oct 15 / Oct 30 and Aug 15 / Aug 30 / Sep 15 / Sep 30); three missed bills 1,500 (Pay in full 2,000); penalty once per stretch 680 / 4,000 / 8,000 (per bill 760 / 8,000 / 12,000); partial catch-up 680 then 320, no second "once"; two stretches 300 + 300; shortfall 600 of 1,000 → 1,400, chain 1,400, bulk split 1,400 + 400 / 600 + 0 / 1,400 + 1,600; top-up 83.33 + 504.17 = 587.50; the engine leaves the caller's rows and list unchanged (#145 probe: 15,000 / 500 / 7,600) | bills moved to today, one-month cap, missed bills collapsed, the salary day taken from the clock, a balance penalty per bill, a lost shortfall, a partial top-up cycle, mutated inputs |

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
- G5d and G4c run through the S2 seam (2026-09-08). Since the owner rules
  R1-R5 (2026-11-19, G14) an overdue bill keeps its date and bills its own
  cycle; the one-month cap G4c pinned (campaign D12, finstack#120) is gone.
- **G14** (`test/services/open_term_billing_golden_test.dart`, 51 scenarios)
  pins R1-R5 with the owner's numbers; its derivations are at the top of the
  file. Run it under `TZ=Asia/Manila` too (G14m compares zones). Since the
  #146 review the engine counts days in calendar days, so G5 and G5b pass
  under `America/New_York` as well.

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
