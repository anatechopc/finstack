# Schedule math — worked examples and merge walkthrough

Companion to `../SKILL.md` §5-§6. Every number below was recomputed independently
(2026-07-07; open-term sections 2-3 rewritten 2026-11-19 for owner rules R1-R5)
and matches the Dart implementation. Regenerate all of them:

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

## 2. Open-term bills — owner rules R1-R5 (2026-11-19)

Open-term (`period == 0`, `dueAt == null`) is interest-only
(`calculateOpenTermSchedules`, `apps/loans/lib/services/loan_calculation_service.dart`;
golden set G14 in `apps/loans/test/services/open_term_billing_golden_test.dart`).
Before 2026-11-19 the engine generated ONE row from the last stored row and
clamped an overdue one to today (interest to today, amount due capped at a
month). Now:

```
bill dates (R1)     '1m' / '15d': creation day + 30k / 15k calendar days
                    'D1,D2': next salary day after the previous bill
first new bill      first scheduled date after the last stored row's due_at
rows (R2)           every bill due before today, then the bill due today or later
interestCharge      sum over the cycle of balance x monthlyRate x days / 30
                    (a top-up splits the cycle by calendar day, R5)
amortization        interestCharge (+ the last stored row's shortfall on the
                    first new bill, R4)
principalPayment    0;  totalLoanPayment = double.infinity (sentinel)
```

Interest continues from the last stored row's `due_at` (where its interest
ended). A row stored by #143's clamp has `due_at` = the day it was computed and
the cycle date in `original_due_at`; the next bill is the first scheduled date
after `due_at`. The engine never changes its inputs (#145).

### Example C — OB = 10,000; interestRate = 5 (%/month)

| Case | Bills |
|---|---|
| `'15,30'`, last bill Aug 30, seen Sep 20 | Sep 15: 16 d, 266.67 (missed); Sep 30: 15 d, 250.00 |
| `'1m'`, loan Jul 2, paid Aug 1, seen Sep 8 (G4c) | Aug 31: 30 d, 500 (missed, 8 days late); Sep 30: 500. Before: one row due Sep 8, 38 d, 633.33, 500 due |
| `'1m'`, clamp row due_at Aug 5, seen Aug 20 | Aug 31: 26 d, 433.33 (before: Sep 4, 30 d, 500) |
| `'15,30'`, clamp row due_at Sep 16, seen Oct 20 (#144) | Sep 30: 14 d, 233.33; Oct 15: 250; Oct 30: 250 (before: Oct 30 only, 733.33, never late) |
| `'15,30'`, created Aug 3, seen Sep 20 (#144) | Aug 15: 200; Aug 30: 250; Sep 15: 266.67; Sep 30: 250 (before: Sep 30 only, 966.67) |
| `'1m'`, paid Aug 1, seen Nov 5 (#120) | Aug 31, Sep 30, Oct 30: 500 each, owed now; Nov 29: 500 |
| 20,000, the Aug 1 bill (1,000) paid 600 (R4) | Aug 31: interestCharge 1,000, amortization 1,400 |

Owner's salary-day example (40,000 at 5%): missing the 15th means the 30th's
payment is both bills plus penalties: 1,066.67 + 1,000 + 15 x 40 (0.1% a day)
= 2,666.67.

**Penalties (R3).** Days late are per bill. An open-term penalty is on the
balance, so it is charged once per overdue stretch (earliest unpaid due date
until no bill is late), and a payment is charged the stretch's penalty to its
collection date less what earlier payments in the stretch were charged. A
percentage uses the balance in force on the day each charged period starts (a
top-up raises it from its own day). A submitted bill is settled at its transfer
(`collected_at` recorded at submission), whatever the confirmation order,
but has not been charged until it is confirmed: two bills in one submission
owe the stretch once. A top-up counts from its approval (`approved_at`) when
deciding whether a stored bill already holds it. Owner's
figures (40,000; bills Sep 15 and Sep 30 paid Oct 2): 0.1%/day 680, 10%/month
4,000, 10%/installment (15 days) 8,000. Code: `_openTermStretchPenalty` in
`packages/loans/loan_schedule_repository/lib/src/penalty_calculator.dart`;
`resolveLatenessTogether` for several rows paid together.

### Next-due-date selection

- `'D1,D2'` (e.g. `'15,30'`, min/max applied): the next of each month's two
  salary days after the previous bill; a day the month does not have is its last
  day (`'15,30'` → Feb 28, `'15,31'` → Apr 30; before 2026-11-19 they rolled
  into Mar 2 / May 1).
- `'15d'` → anchor + 15k; anything else → anchor + 30k. The anchor is the
  earliest stored bill's cycle date (`original_due_at ?? due_at`) when the loan
  has stored bills, otherwise the local creation day.
- All days are local calendar days (creation day, stored rows, top-ups, today),
  and interest days are counted in calendar days, so the same loan reads the
  same on a UTC and a Manila device and a daylight-saving change cannot drop a
  day. Only an active loan bills (not pending, declined, completed, bad debt).

## 3. Additional-loan (top-up) merge

`calculateOpenTerm` builds the display/SOA timeline:
`[principal release row 0] + stored rows (sorted copy) + bills`, then inserts
one row per top-up.

1. **Row 0** (principal release): `dueAt = loan.createdAt`, `principalLoan =
   amount`, `isPlaceholder: true`. Not an installment.
2. **THE INVARIANT:** top-ups are processed `sortedBy((a) => a.createdAt)`
   ascending (finstack#4 / PR finstack#33).
3. **Billing (R5)** happens in `calculateOpenTermSchedules`: only an APPROVED
   top-up moves the balance (#137; a pending or declined row is shown with the
   balance unchanged). A top-up not yet in
   the last stored row's balance (the row was computed before it, or it is after
   the row's due day) splits its cycle by calendar day; a top-up before the cycle
   started puts the whole cycle on the new balance, and its days before that
   cycle (the previous bill paid early) are added to it (G9f 615.50); one on
   the due date leaves
   that bill on the old balance. G9: 83.33 + 504.17 = 587.50; G10: 83.33 +
   40.33 + 578.83 = 702.50. Balance added: `amount + additionalCharges`
   (deductions ignored, #127 undecided).
4. **Display:** the top-up row sits before the first bill due on or after its
   day; `OB = balance before + amount + charges`; `interestCharge` = what the old
   balance accrued since the row before it (83.33 in G9); `amortization = 0` (not
   a bill). No row is changed in place.

Each top-up's `advance_charges` lands as `advanceInterestPayments` on its row;
its own `LoanStatus` rides along (pending top-ups also count, #137).

## 4. Early Settlement arithmetic

`LoanCalculationService.calculateSettlementBalance`
(`apps/loans/lib/services/loan_calculation_service.dart`; extracted verbatim
from `loan_settlement_bloc.dart` on 2026-09-08, the bloc delegates):

```
totalLoanAmount  = Σ over parent + parent_id children:
                     (amount + additionalCharges) − (deductions + additionalChargeUpfrontCollection)
totalLoanPayment = per schedule with a payment id: (isOpenTerm ? interestCharge : interestPayment)
                     + principalPayment + extraPayment          // ASSIGNED, not summed — finstack#116
remainingBalance = totalLoanAmount − totalLoanPayment
```

CAUTION: the whole formula is wrong and under redesign (finstack#116): only
the last row counts, unconfirmed submissions are credited, open-term rows
credit the charge not the cash, and top-ups are ignored. Golden test G7
pins the current 8800 for the reference family until that lands.

Confirmation marks parent + all children `LoanStatus.completed`
(`loan_settlement_bloc.dart:155-162`). Do not fix the formula ad hoc; route via
`finstack-loan-engine-and-reporting-campaign` (finstack#116).

## 5. Charge application order (`apps/loans/lib/services/charge_calculator.dart`)

- Percentages are always **of the base amount** — never compounding on prior charges
  (`:36, :44, :52`).
- `isUpfrontCollection` charges skip `totalAmount` entirely and accumulate in
  `totalUpfrontCollection` (`:33-41`).
- Receivable handed to the borrower = `totalAmount − totalUpfrontCollection`
  (`loans_bloc.dart:472`, `:381`).
