# Schedule math — worked examples and merge walkthrough

Companion to `../SKILL.md` §5-§6. Every number below was recomputed independently
(2026-07-07) and matches the Dart implementation. Regenerate all of them:

```bash
python3 .claude/skills/loans-domain-reference/scripts/regen_worked_examples.py
```

Paths are relative to the repo root `/Users/deibeeed/Projects/AnaheimTechnologies/finstack`.

## 1. Fixed-term amortization — full table

Formula (`apps/loans/lib/utils/extensions.dart:148-166`, doc comment at `:132-147`):

```
P = (Pv · R) / (1 − (1 + R)^−n)
  P  = payment per period
  Pv = present value (the amount being amortized = amount + additionalCharges − deductions)
  R  = periodic interest rate as a decimal (loan.interestRate / 100; '15d' ⇒ ÷2)
  n  = number of payments (loan.period in months; '15d' ⇒ ×2)
```

Row loop (`apps/loans/lib/services/loan_calculation_service.dart:97-135`):

```
interest  = OB × R
amort     = min(P, OB + interest)     // final-row clamp so OB lands on exactly 0
principal = amort − interest
OB       −= principal
```

### Example A — Pv = 10,000; interestRate = 3 (%/month); period = 6; term '1m'

`P = (10000 × 0.03) / (1 − 1.03⁻⁶) = 1,845.98`

| # | Beginning OB | Interest | Amortization | Principal | Ending OB |
|---|---|---|---|---|---|
| 1 | 10000.00 | 300.00 | 1845.98 | 1545.98 | 8454.02 |
| 2 | 8454.02 | 253.62 | 1845.98 | 1592.35 | 6861.67 |
| 3 | 6861.67 | 205.85 | 1845.98 | 1640.12 | 5221.55 |
| 4 | 5221.55 | 156.65 | 1845.98 | 1689.33 | 3532.22 |
| 5 | 3532.22 | 105.97 | 1845.98 | 1740.01 | 1792.21 |
| 6 | 1792.21 | 53.77 | 1845.98 | 1792.21 | 0.00 |

Total paid = **11,075.85**. Due dates: `startOf(day)` then +1 month per row
(`loan_calculation_service.dart:88-92, 130-134` — Jiffy month arithmetic, not +30d).

### Example B — same loan at term '15d'

`'15d'` doubles the payment count and halves the periodic rate
(`loan_calculation_service.dart:77-80`; same transform inside
`calculateMonthlyPayment`, `extensions.dart:157-160`):
R = 1.5%, n = 12 → **P = 916.80** per half-month, total 11,001.60.
Due dates advance +15 days per row. Note the UI enters the payment count and the
bloc halves it into months before calling the calculator (`loans_bloc.dart:457-461`)
— don't double-apply.

### Resuming a partially-paid fixed-term loan

When `paidSchedules` is non-empty (`loan_calculation_service.dart:69-84`):
amortization is taken from `paidSchedules.first.amortization` (NOT recomputed),
OB resumes from `paidSchedules.last.outstandingBalance`, dates resume from
`paidSchedules.last.dueAt`, and `n` is reduced by the paid count.
`calculateFixedTerm` returns only the **remaining computed** rows; callers prepend
the persisted paid rows themselves (`loans_functions.dart:32-40` — the fix for
fixed-term loans dropping their paid schedule from view).

## 2. Open-term proration — worked examples

Open-term (`period == 0`, `dueAt == null`) is interest-only
(`calculateOpenTermSchedules`, `loan_calculation_service.dart:147-300`):

```
amortization        = OB × monthlyRate                      // calculateMonthlyPaymentSimple, :34-39
interestDayMultiplier = |diffDays| / 30                     // :262 — "1 month = 30 days", :146
interestCharge      = OB × monthlyRate × interestDayMultiplier   // :265-266
principalPayment    = 0                                     // :284
```

`diffDays` = days between the last (paid) schedule's `dueAt` and the next due date.
Exactly **one** next-due row is generated per call (`numOfPayments = 1`, `:165`).
`totalLoanPayment = double.infinity` (`:241`) — sentinel: no fixed total exists.
The multiplier is persisted as `interest_day_multiplier` on the schedule doc
(`packages/loans/loan_schedule_repository/lib/src/model/loan_schedule_entity.dart:142-146`).

### Example C — OB = 10,000; interestRate = 5 (%/month)

| Days since last due date | Multiplier | Interest due |
|---|---|---|
| 15 (salary days `'15,30'`) | 0.5 | **250.00** |
| 30 | 1.0 | 500.00 |
| 45 (borrower skipped a salary date) | 1.5 | **750.00** |

### Next-due-date selection (`:189-231`)

- `term == 'D1,D2'` (e.g. `'15,30'`): if the current date IS the earlier salary day →
  jump to the later one this month; if it IS the later one → earlier day next month;
  otherwise snap forward to the nearest upcoming salary day (`:197-222`). min/max
  applied, so `'30,15'` behaves identically.
- `term == '15d'` → +15 days; anything else → +30 days.
- If the computed date is not in the future, it clamps to today (`:229-231`).

## 3. Additional-loan (top-up) merge — what actually happens

`calculateOpenTerm` (`loan_calculation_service.dart:304-477`) builds the display/SOA
timeline: `[placeholder row 0] + paidSchedules + [next generated row]`, then splices
each top-up in.

1. **Placeholder row 0** (`:336-352`): `dueAt = loan.createdAt`,
   `principalPayment = principalLoan = amount`,
   `advanceInterestPayments = loan.additionalChargeUpfrontCollection`,
   `isPlaceholder: true`.
2. **THE INVARIANT** (`:354-358`): top-ups are processed
   `sortedBy((a) => a.createdAt)` — ascending. Processing newest-first lets later
   iterations overwrite earlier rows' outstanding balances (the finstack#4 /
   PR finstack#33 double-count bug — narrative in `finstack-failure-archaeology`).
3. For each top-up: find the first schedule (past row 0) with
   `createdAt >= topUp.createdAt` (`:361-377`); append at the end if none.
4. **Same-instant case** (`:380-402`): if the anchor row's `dueAt` equals the top-up's
   `createdAt`, the anchor row is REPLACED by an additional-loan row with
   `OB = anchorOB + topUp.amount + topUp.additionalCharges`.
5. **Insert case** (`:403-467`): compute `diffDays` from the top-up's `createdAt` to the
   anchor (or the prior row when the anchor is an unpersisted `NO_ID` row, `:406-429`),
   `multiplier = diffDays/30`, `interest = anchorOB × rate × multiplier`; insert the
   row, then propagate the new OB and interest onto the displaced anchor row
   (`:464-466`).

Each top-up's `advance_charges` lands as `advanceInterestPayments` on its inserted row
(`:397, :458`); its own `LoanStatus` rides along (`:399, :460`).

## 4. Early Settlement arithmetic

`apps/loans/lib/features/loans/bloc/loan_settlement_bloc.dart`:

```
totalLoanAmount  = Σ over parent + parent_id children:
                     (amount + additionalCharges) − (deductions + additionalChargeUpfrontCollection)   // :100-101
totalLoanPayment = per paid schedule: (isOpenTerm ? interestCharge : interestPayment)
                     + principalPayment + extraPayment                                                  // :104-110
remainingBalance = totalLoanAmount − totalLoanPayment                                                   // :112
```

Confirmation marks parent + all children `LoanStatus.completed` (`:166-173`).

CAUTION (open, as of 2026-07-07): the `totalLoanPayment` loop uses `=` not `+=`
(`:104-110`), so only the LAST schedule's payment is counted. Whether this is a live
defect or masked by call patterns is a campaign question — do not fix ad hoc; route
via `finstack-loan-engine-and-reporting-campaign`.

## 5. Charge application order (`apps/loans/lib/services/charge_calculator.dart`)

- Percentages are always **of the base amount** — never compounding on prior charges
  (`:36, :44, :52`).
- `isUpfrontCollection` charges skip `totalAmount` entirely and accumulate in
  `totalUpfrontCollection` (`:33-41`).
- Receivable handed to the borrower = `totalAmount − totalUpfrontCollection`
  (`loans_bloc.dart:472`, `:381`).
