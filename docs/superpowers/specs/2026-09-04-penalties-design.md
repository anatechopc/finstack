# Penalties (loooans#72) — design (finstack port)

Date: 2026-09-04 (original design 2026-09-03, built first against the pre-monorepo repos and ported here)
Status: approved by the owner; definitions half in progress on `feat/penalties-72-definitions`
Issues (all on the old `anatechopc/loooans` tracker): [loooans#72 Implement penalties](https://github.com/anatechopc/loooans/issues/72), [loooans#71 late tagging vs collection records](https://github.com/anatechopc/loooans/issues/71), [loooans#78 setting to allow late payments](https://github.com/anatechopc/loooans/issues/78). Not to be confused with finstack#71/#72, which are unrelated.
Related finstack issues filed during the port: [finstack#107](https://github.com/anatechopc/finstack/issues/107) (stored percentage charges use the running total), [finstack#108](https://github.com/anatechopc/finstack/issues/108) (campaign defect D5 in `loan_changes.go`).

## 1. Goal

Let a lending company define late-payment penalties, customize them per product, and charge them when an installment is confirmed late. Fix loooans#71 and loooans#78 in the same feature because all three share one decision: what counts as late.

## 2. What exists today

- `Charge` (`packages/loans/product_repository/lib/src/model/charge.dart`) is the only reusable money-rule type: id, amount, description, is_percentage, is_upfront_collection. Defined per product, inline, via `apps/loans/lib/features/products/widget/add_product/charges_section.dart`.
- Charges and deductions are computed once at loan creation (`apps/loans/lib/features/loans/bloc/loans_bloc.dart`, `Loan.create` ~516–545) through `ChargeCalculator` and flattened to doubles on the loan document. The product list is never re-read for that loan.
- Lateness is decided only at payment confirmation in `LoansBloc`: `paid_late` if the schedule's `due_at` is before now. `not_paid_overdue` is display-only. No daily job exists over schedules.
- Confirmation only runs for self-managed companies. App-managed companies use AutoCollect and never enter this handler.
- The settings repository holds per-user UI toggles only. The company profile card (`apps/loans/lib/features/users/widget/profile_widget.dart`) holds company-level actions.

## 3. Decisions

| # | Decision | Why |
|---|----------|-----|
| D1 | Penalties are defined per product; the company holds defaults that pre-fill new products (copy-on-create). | Customizable per offer, one place to set the norm, no runtime fallback chain. |
| D2 | Own `Penalty` model, not `Charge`. | `is_upfront_collection` is meaningless for a penalty; `frequency` is meaningless for a charge. |
| D3 | Penalties recur by `frequency`: once, daily, monthly, per installment (same as loan term). Amount is a pure function of days late. | Admin sets the cadence; no job is needed to compute it. Per installment follows the loan's own term, so a company default states a cadence correctly for any product. |
| D4 | Trigger is the existing payment-confirmation handler, using a new collection date. No daily job in this pass. | Matches the issue text. Fixes loooans#71 in the same line. A job is a later upgrade that reuses the same function. |
| D5 | The loan snapshots the product's penalties and `allow_late_payments` at creation. Confirmation and every quotation read the loan, never the live product. | Borrower is bound by the terms they saw when applying. Same rule charges already follow. |
| D6 | Provider may waive penalties at confirmation with a required reason. | Approved in mockup. Recorded on the row for audit. |
| D7 | Percentage base is the row's amount due as already displayed: `amortization` for term loans, `outstanding_balance` for open-term rows. Since 2026-11-19 this is the default for penalties saved without a "Based on" choice; see section 5.2. | The number the collector and borrower already see. |
| D8 | Penalty is collected in the same payment as the installment. | No separate receivable to track. |
| D9 | The two bugs found during the original review are NOT part of this feature in finstack. | Both are loan-math or reporting-engine changes gated by `finstack-loan-engine-and-reporting-campaign`; tracked as finstack#107 and finstack#108. |
| D10 | The penalty fields are written and read only by Flutter, so this is not a Class B (two-sided shape) change; there is no Go PR for the definitions. | `finstack-change-control` Class B definition. The moment a Go trigger reads a penalty field, it becomes Class B and the backend must tolerate the old shape first. |

## 4. Data model

All new list/bool/number fields use `@JsonKey(defaultValue: ...)` so documents written before this change still deserialize. Generated `.g.dart` files are not committed in finstack; regenerate with `packages/build_models.sh`.

### 4.1 `Penalty` (`packages/core/loooans_helpers/lib/src/data_helpers/model/penalty.dart`)

Every repository package depends on `loooans_helpers` and on nothing else in common, so the type lives there.

| Dart | Firestore | Type | Notes |
|------|-----------|------|-------|
| `id` | `id` | String | generated the same way `Charge.id` is |
| `name` | `name` | String | required, shown on chips and breakdown |
| `description` | `description` | String | optional, shown in dialog and offer detail |
| `amount` | `amount` | double | > 0; if percentage, 0 < amount ≤ 100 |
| `isPercentage` | `is_percentage` | bool | inferred from a trailing `%` in the amount box, as charges do |
| `frequency` | `frequency` | String enum | `once`, `daily`, `monthly`, `per_installment`; unknown → `once` |
| `basedOn` | `based_on` | String enum, optional | `missed_bill`, `outstanding_balance`; absent, null or unknown → null = the loan type's default (section 5.2). Not written when null, so older documents keep their shape |

`PenaltyFrequency` carries a `label`, a label `suffix` ("per day"), and `periods(daysLate, {termDays})`. `termDaysOf(term)` maps `1m` → 30, `15d` → 15, salary dates `a,b` → 15, otherwise 30. `Penalty.baseFor(isOpenTerm:)` gives the base in force: `based_on` for a percentage, otherwise the loan type's default.

### 4.2 Company (`companies`, `packages/core/company_repository`)

| Dart | Firestore | Default |
|------|-----------|---------|
| `defaultPenalties: List<Penalty>` | `default_penalties` | `[]` |

### 4.3 Product (`products`, `packages/loans/product_repository`)

| Dart | Firestore | Default |
|------|-----------|---------|
| `penalties: List<Penalty>` | `penalties` | `[]` |
| `allowLatePayments: bool` | `allow_late_payments` | `false` |

### 4.4 Loan (`loans`, `packages/loans/loan_repository`)

Copied from the product in `Loan.create` at the same point `isForceCollect` is copied. Existing loans carry no penalties; a backfill is a separate decision.

| Dart | Firestore | Default |
|------|-----------|---------|
| `penalties: List<Penalty>` | `penalties` | `[]` |
| `allowLatePayments: bool` | `allow_late_payments` | `false` |

### 4.5 Loan schedule row (`loan_schedules`, `packages/loans/loan_schedule_repository`)

| Dart | Firestore | Default | Meaning |
|------|-----------|---------|---------|
| `collectedAt: DateTime?` | `collected_at` | null | when the money was actually received (fix for loooans#71) |
| `daysLate: int` | `days_late` | 0 | calendar days from `due_at` to `collected_at`, floored at 0 |
| `penalty: double` | `penalty` | 0 | amount actually charged; 0 when waived, on time, or allowed late |
| `penalties: List<Penalty>` | `penalties` | `[]` | the definitions applied (copied from the loan at confirmation) |
| `penaltyWaivedBy: String?` | `penalty_waived_by` | null | user id of the provider who waived |
| `penaltyWaiveReason: String?` | `penalty_waive_reason` | null | required when waived |
| `originalDueAt: DateTime?` | `original_due_at` | null | open-term only (finstack#114, 2026-11-13): the cycle's own due date when the engine billed an overdue cycle as due today; lateness counts from it. Since section 5.1 (2026-11-19) new rows keep their own date and leave it null; the field stays so rows stored in between still load and count from it |

Penalty lines are recomputed from `penalties`, `days_late`, and the row's amount due wherever displayed. No new Firestore indexes; nothing queries on the new fields. Firestore rules: none of these fields is referenced by rules; see `finstack-security-hardening` if that changes.

## 5. Computation (`packages/loans/loan_schedule_repository/lib/src/penalty_calculator.dart`)

```dart
PenaltyResult computePenalties({
  required double amountDue,        // amortization, or outstandingBalance for open-term
  required List<Penalty> penalties, // from the loan snapshot
  required int daysLate,            // >= 0
  int termDays = 30,                // termDaysOf(loan.term); only per_installment uses it
});
```

```
if daysLate <= 0 or penalties is empty  -> total 0, no lines
periods(freq) = once: 1 | daily: daysLate | monthly: ceil(daysLate/30) | per_installment: ceil(daysLate/termDays)
base          = isPercentage ? amountDue * amount / 100 : amount
line.amount   = base * periods
total         = sum(line.amount)
```

`daysLate` is the difference in local calendar dates between the row's lateness date (`original_due_at` when set, otherwise `due_at`; see below) and the collection date, floored at 0; collected on the due date is on time. Across a daylight-saving change the count can be off by a day (finstack#125). `previewPenalty(schedule, loan, asOf)` applies the allow-late gate and is what unpaid rows display before confirmation. Worked example: amortization 5,000; ₱100 daily + 2% monthly; 19 days late → 1,900 + 100 = 2,000.

Open-term loans (finstack#114, 2026-11-13). When an open-term cycle is already past due, `calculateOpenTermSchedules` bills the row as due today so that interest accrues to today (golden G4c). Until #114 that made `daysLate` 0 for every open-term row, so open-term loans were never late and never penalized. The row now also carries `original_due_at`, the cycle's own due date, and every lateness and overdue decision uses `LoanSchedule.lateFrom` (`original_due_at ?? due_at`): `previewPenalty`, `resolveLateness`, the overdue labels, the Payment Center overdue list, and the revert-on-reject status. Billing still uses `due_at`. The "Allow late payments" option now behaves for open-term products as it does for fixed-term ones. Because `allow_late_payments` reads as false on loans written without it and `paid_late` does not depend on the loan having penalties, every open-term loan that does not allow late payments, including loans created before this feature, now confirms an overdue cycle as `paid_late` with its days late; money is charged only where the loan has penalties. The base stays the row's outstanding balance (D7): 1% per day on a 12,750 balance is 127.50 a day. Open-term placeholder rows (the principal release and top-ups) are not installments: no penalty, never late at confirmation, and no "Make payment" button. The Payment Center, like `LoansBloc`, gives the engine every stored row of an open-term loan as a past cycle, unpaid ones (rejected submissions) included, so the Payment Center, client detail and the borrower show the same rows; a stored row and a generated row with the same lateness day (local time) are one row, and the stored one is kept. Rows written by app builds older than this change have no `original_due_at` and count from `due_at`.

Known limits (open-term): a salary-day loan is late only while its last row falls on a salary day: one created on an off day is never late, and after a late payment (billed on an off day) it is never late again, because the next due date is then taken from the clock (finstack#144); a top-up made while a cycle is overdue raises the penalty base for all of the cycle's late days, not pro rata; and two or more missed cycles collapse into one row, so a "once" penalty is charged once, where a fixed-term loan charges it per row.

Owner decisions, 2026-11-19: the penalty base stays as it is, the missed installment (`amortization`) on fixed-term rows and the outstanding balance on open-term rows, until penalties get a "Based on" option. A later PR makes open-term bills keep their own dates instead of moving to today (section 5.1). Note for that PR: rows written in the meantime store the date interest was charged to in `due_at` and the cycle's own date in `original_due_at`; the next cycle starts from `original_due_at ?? due_at`, and its interest from `due_at`. (Section 5.1 starts the next cycle at the first scheduled date after `due_at` instead: for a `'15,30'` row with `original_due_at` Aug 30 and `due_at` Sep 16, the next salary day after Aug 30 is Sep 15, before the day the row's interest ended.)

### 5.1 Open-term bills by cycle (owner rules R1-R5, 2026-11-14 to 2026-11-19; finstack#144, #120, #117, #145)

The paragraphs above describe #114. These rules replace its billing (the "due today" row, the one-month cap, collapsed cycles, per-row open-term penalties). Golden set G14 (`apps/loans/test/services/open_term_billing_golden_test.dart`) pins each with the owner's numbers.

- **R1, bills keep their cycle dates.** `'1m'` and `'15d'` bills fall every 30 or 15 calendar days from the loan's creation day, the way the first bill always did; salary-day terms fall on the next salary day after the previous bill. A missed bill keeps its own row and date; nothing is computed from today or from a payment date. After a row stored by #114's clamp (`due_at` = the day it was computed), the next bill is the first scheduled date after `due_at`, and its interest runs from `due_at`, where the row's interest ended. Examples (10,000 at 5%): `'1m'` loan of Jul 2, clamp row due_at Aug 5 → next bill Aug 31, 26 days, 433.33 (before: Sep 4); `'15,30'` clamp row due_at Sep 16 seen Oct 20 → Sep 30 (233.33, 20 days late), Oct 15 (250, 5 days late), Oct 30 (before: Oct 30 only, 733.33, never late); a `'15,30'` loan created Aug 3 seen Sep 20 → Aug 15, Aug 30, Sep 15, Sep 30 (before: Sep 30 only, 966.67, never late).
- **R2, missed bills roll into the next payment.** Every bill due before today is its own row, then the bill due today or later. Each bills its own cycle: no interest accrued to today, no one-month cap. The borrower's Next payment is every bill already due plus the penalty, or the next bill when none is due. Owner's example: 40,000 at 5% on salary days 15 and 30, last bill Aug 30: the Sep 15 bill is 1,066.67 (16 days) and the Sep 30 bill 1,000; seen Sep 20 the borrower owes 1,066.67; seen Sep 30 with 0.1% a day, 1,066.67 + 1,000 + 15 × 40 = 2,666.67. Three missed `'1m'` bills (paid Aug 1, seen Nov 5) owe 3 × 500 = 1,500 (before: one row, 1,600 interest, 500 due).
- **R3, lateness per bill, penalty once per stretch.** Days late are per bill, from its own due date. Fixed-term rows are penalized per row as before. An open-term penalty is on the balance, so it is charged once for the loan: an overdue stretch runs from the earliest unpaid due date until no bill is late; "once" is charged once per stretch, daily per day of the stretch, monthly and per installment per started period of the stretch. A payment is charged the stretch's penalty up to its collection date less what earlier payments in the same stretch were charged up to theirs (a waive counts as charged), so a partial catch-up continues the stretch without charging a day twice. The base stays the row's outstanding balance. Owner's figures, balance 40,000, bills due Sep 15 and Sep 30 both paid Oct 2 (17 and 2 days late): daily 0.1% → 40 × 17 = 680 (per bill 760); monthly 10% → 4,000 × ceil(17/30) = 4,000 (per bill 8,000); per installment (15 days) 10% → 4,000 × ceil(17/15) = 8,000 (per bill 12,000). Only the Sep 15 bill paid Oct 2 → 680, then the Sep 30 bill paid Oct 10 → 320 (25 days in all); "once", monthly and per installment add nothing on Oct 10. The penalty is stored on the first late row of the payment; previews show it on the earliest unpaid bill and 0 on the others.
- **R4, an interest shortfall carries to the next bill.** The open-term interest field accepts any amount above 0. What the last stored row left unpaid of its amount due (`amortization − interestPayment`, to the centavo) is added to the first new bill's amount due (`amortization`); its `interest_charge` stays the cycle's interest, so the statement of account does not count it twice. 600 paid against a 1,000 bill → the next bill is 1,400. A row with no recorded interest payment (0: borrower submissions record none) counts as paid in full. The carry is not penalized on its own; when the next bill is late it is part of that bill, and the penalty base is still the balance. A bulk payment pays bills oldest first, each up to its amount due; a bill that gets nothing stays unpaid (1,800 over 1,400 + 1,000 → 1,400 + 400; 600 → 600 + 0).
- **R5, a top-up mid-cycle splits that cycle.** Approved top-ups only (see below). With nothing overdue, the cycle's bill = old balance × rate × days up to the top-up date + new balance × rate × days after it, split by calendar day. G9: 10,000 at 5%, top-up 2,000 + 100 five days into the cycle → 83.33 + 504.17 = 587.50 (before: 83.33 copied from the top-up row, 500 due). A top-up on a due date leaves that bill on the old balance; one made before a cycle starts (the previous bill paid early) puts the whole cycle on the new balance (605 on 12,100, fixing the absolute day difference of draft PR #131). The top-up row is shown, not billed (no amount due); it shows what the old balance accrued since the row before it. The balance added stays amount + charges (deductions ignored; #127 undecided). A top-up counts as already in a stored row's balance when the row was computed after it and the top-up is not after the row's due day.
- **Inputs are never changed (#145).** `calculateOpenTermSchedules` and `calculateOpenTerm` neither sort the caller's list nor change its rows; stored rows are listed as they are.
- **Paying order.** The engine bills only after the last stored row, so computed open-term bills are paid oldest first: client detail offers "Make payment" on the earliest computed bill only, the Payment Center hides the upcoming tile's Pay while bills are overdue, and the borrower's Pay now covers every bill already due.

Review of PR #146 (2026-11-19), also decided:

- **Only approved top-ups move the balance and the bill (#137).** No money is released for a pending or declined top-up; its row is shown and does not change the balance. G9 with the top-up pending or declined bills 500.00; approved, 587.50. A top-up takes effect on its creation day (no approval date is recorded).
- **Only an active loan bills.** A pending, declined, completed (settled) or bad-debt loan gets no new bills, no penalty preview and no "Make payment" in client detail, the borrower screen, the Payment Center or the statement of account.
- **The penalty base is the balance in force each day.** A percentage penalty for each charged period uses the balance on the day the period starts (before a top-up the old balance, from its day the new one), whichever bill carries the charge. Aug 31 and Sep 30 missed, a 2,000 top-up on Sep 10, collected Oct 5 at 0.1% a day of 10,000: 10 days x 10 + 25 days x 12 = 400 (before: 350, or 420 when the Sep 30 bill was confirmed first).
- **A submitted bill is settled at its transfer.** The submission records the transfer time on the row (`collected_at`, which confirmation also defaults to); rows submitted earlier get it from their payment. The penalty no longer depends on the order bills are confirmed in: bills due Aug 31 and Sep 30, submitted Sep 8 and Oct 8, each owe 900 (before: 4,800 when the later one was confirmed first). Rejecting a submission clears it.
- **A row from the old clamp carries what it charged but did not bill.** For the shortfall the amount due is the larger of `amortization` and `interest_charge`: 1,600 charged, 500 due, 500 paid -> 1,100 added to the next bill (also rows written by app builds not yet updated).
- **Days.** The schedule, interest days and top-up days are local calendar days (a loan reads the same on a UTC and a Manila device); interest days are counted in calendar days, so a daylight-saving change no longer drops one. A salary day a month does not have is the month's last day (`'15,30'` -> Feb 28, `'15,31'` -> Apr 30). Bills are generated one after another and the current bill is never dropped.
- **Top-up before the cycle.** When the previous bill was paid early and a top-up came before its due date, the top-up's days up to that date are added to the next bill (G9f: 605 + 2,100 x 5% x 3/30 = 615.50).
- **Screens.** The Payment Center loads loans with their top-ups, as client detail does (#135). The payment dialog shows each bill's amount due, not its balance (#142). Only the earliest unpaid open-term bill, stored (a rejected submission, now payable) or computed, offers "Make payment". A partial bulk payment leaves the loan's status at the earliest bill still unpaid.

Second review of PR #146 (2026-11-19):

- **A submitted bill ends its lateness at its transfer but has not been charged.** Only a bill that is no longer `payment_submitted` counts as having paid its share of the stretch. Two bills in one submission (Aug 31 and Sep 30, sent Oct 5; 100 once + 0.1% a day of 10,000) owe the stretch once, 100 + 35 x 10 = 450, in preview and in either confirmation order (was 0). Since the owner's flat-fee decision (section 5.2) the flat 100 is charged on each bill: 450 + 100 = 550. Rows submitted before the transfer time was recorded get it from their payment in every path: `confirm`, the Payment Center card and bulk payment, and `LoansBloc` (client detail and the borrower).
- **A top-up counts from its approval.** Approval records `approved_at` on the top-up (optional field; no Go code reads top-up documents). A stored bill holds a top-up only when it was computed after the approval; a top-up created Aug 6 and approved Sep 5 after the Aug 31 bill was stored is in the balance from Sep 5, its approval day (review of #149: the balance, the bill and the penalty base move on the approval day, not the creation day): Sep 30 = 83.33 + 504.17 = 587.50, then 605, 605 (it was 692.50 with the Aug 6-31 days billed; 500 for the loan's life before `approved_at`). Top-ups approved before this field existed keep the earlier rule (from the creation day; created before the bill = in it).
- **The schedule keeps the creation day's dates (third review).** `'1m'` / `'15d'` dates step from the loan's local creation day. A stored bill whose cycle date (`original_due_at ?? due_at`) is not a scheduled date but is one day before one (salary days included) is that bill, so a first bill the old engine dated on the creation day's UTC date, or a row written in another zone, adds no 1-day bill. A row on a scheduled date never absorbs the next one: salary days a day apart (`'15,16'`; `'1,30'` and `'1,31'` at a month end) keep their 1-day bill, its due date and its penalty. A row further from any scheduled date (an old build's clamp row, dated the day it was paid) does not move the schedule; its interest still ends where it ended. Loan of Jul 2, the Aug 1 bill paid Aug 9 by an old build: next Aug 31 (22 days, 366.67 + 133.33 carried = 500), then Sep 30. A device shows dates in its own calendar, so a loan created before 08:00 Manila shows its dates one day earlier on a UTC device; the bills are the same.
- **A confirmed borrower submission records the interest it paid** (its amount due), so a clamp row submitted by an older build carries the rest (1,600 charged, 500 shown → 1,100 to the next bill).
- **A pending application shows its projected first bill, read only**: status "Projected", no penalty, no "Make payment", not owed in any total.
- **The principal release is never a payment (#138).** Approval stores an app-managed open-term loan's principal release as a plain row (whole principal as `principal_payment`, nothing to collect); `LoanSchedule.isPrincipalRelease` recognises it. Every confirmation path refuses it (borrower submission, its confirmation, client detail, the Payment Center single and bulk payments) and it is never listed as owed. A confirmed borrower submission on an open-term bill records the interest due and principal 0. Billing never continues from the release row (balance 0), so app-managed open-term loans bill every cycle (500 per cycle on 10,000 at 5%; they billed 0 before, on develop too). Rows already confirmed this way keep `principal_payment` = the loan amount and `interest_payment` 0 (no backfill): the statement of account and the settlement balance still read them as principal repaid, and they need repair (principal 0, interest = the amount paid); billing needs none. The release is recognised exactly: open term, principal > 0, nothing charged or due, and a balance of 0 with no interest recorded, or a balance of exactly minus its principal (a teller's payment of it; a 0% loan's bill paid with principal keeps a balance, records interest, or, overpaid, ends above minus its principal).

The penalty base itself is section 5.2.

### 5.2 "Based on" (owner rules, 2026-11-14 to 2026-11-19)

Golden set G15 (`apps/loans/test/services/penalty_based_on_golden_test.dart`) pins each rule with the owner's numbers.

- **Two bases.** A percentage penalty is a percent of "the missed bill" (the bill's amount due, `amortization`, including an R4 carry) or of "the outstanding balance" ("principal" means the balance still owed, the same option). A flat amount is charged as entered; the dialog hides the choice for it and saves no `based_on`.
- **Counting follows the base.** Based on the missed bill: charged per missed bill, each bill counting its own days late, on fixed-term and open-term loans. Based on the outstanding balance: charged once for the loan per overdue stretch, R3's counting ("once" once per stretch, daily per day of the stretch, monthly and per installment per started period of the stretch; a partial catch-up charges up to its collection date and the stretch continues without charging those days again). A loan can mix both; each penalty is counted by its own base.
- **Saved percentages keep today's behaviour.** Company defaults, products and loan snapshots saved before this option have no `based_on`: a percentage on a fixed-term loan uses the missed installment (per bill), on an open-term loan the outstanding balance (per stretch).
- **Flat amounts are per missed bill (owner, 2026-11-19).** A flat amount has no base and is charged as entered on each missed bill, each bill counting its own days late, on both loan types and whatever `based_on` holds. This applies to flat penalties already saved: on open-term loans they were charged once per overdue stretch until this decision (the owner accepted the change; nothing was in production). Open-term, Sep 15 and Sep 30 bills paid Oct 2 (17 and 2 days late): 100 once → 100 + 100 = 200 (was 100); 50 a day → 850 + 100 = 950 (was 850). Fixed-term, Aug 31 and Sep 30 bills paid Oct 5: 100 once → 200, 50 a day → 1,750 + 250 = 2,000 (unchanged). Partial catch-up, 50 a day: the Sep 15 bill paid Oct 2 → 850, the Sep 30 bill paid Oct 10 → its own 10 days, 500.
- **The dialog.** "Based on" shows only for a percentage and starts on "The missed bill"; choosing "Per day" selects "The outstanding balance" until the lender picks a base themselves (review of #148: a base the lender picked is never switched back). Chips, quotation lines, the PDF and the payment breakdown name the base: "10% of the missed bill, once", "0.1% of the balance, per day", "₱100.00, once". A penalty without `based_on` shows its loan type's base; a company default, which serves both loan types, reads "of the missed bill (fixed term) or the balance (open term)".
- **Fixed-term balance base (for the owner to confirm; review of #148).** The balance in force each day of the stretch, as on open-term loans: the principal still owed that day, which is the balance before the earliest bill of the stretch not yet paid by then (that row's `outstanding_balance`, the balance after its principal, plus its `principal_payment`). A bill paid inside the stretch lowers it from its payment day. 10,000 at 5% with 2,500 installments (Aug 1 paid; Aug 31 bill: interest 400, principal 2,100, balance 5,900; Sep 30 bill: 295, 2,205, 3,695), both paid Oct 5: 8,000 every day; 0.1% a day over Aug 31 → Oct 5 = 35 days → 280, once (per bill on the missed bill at 1%: 875 + 125). Partial catch-up, the Aug 31 bill paid Oct 5 and the Sep 30 bill Oct 10: 280, then Oct 5 to Oct 9 on what is still owed after the Aug 31 payment: with its scheduled 2,100 principal 5 × 5.90 = 29.50; with 5,000 principal (balance 3,000) 5 × 3 = 15. The first version kept 8,000 for the whole stretch (40). Open-term already used the balance in force each day (section 5.1); there a principal payment inside a stretch lowers the next bill's balance (Sep 15 bill paid Oct 2 with 10,000 principal: 680, then 8 days on 30,000 = 240).
- **#140 dependency.** The bills computed after a paid fixed-term bill start from its stored balance, and teller payments today store it with the scheduled principal subtracted twice (#140). The partial catch-ups above then charge 19 instead of 29.50 (stored 3,800 instead of 5,900) and 4.50 instead of 15 (stored 900 instead of 3,000). They come out right once #140 is fixed; nothing here needs to change then.
- **Owner's figures (open-term, 40,000 at 5%, salary days 15 and 30, each bill taken as 1,000).** Sep 15 and Sep 30 bills paid Oct 2 (17 and 2 days late). On the balance: daily 0.1% → 680, monthly 10% → 4,000, per installment 10% → 8,000. On the missed bill: daily 1% → 170 + 20 = 190, monthly 10% → 100 + 100 = 200 (per installment 10% → 200 + 100 = 300). The 15th's bill paid on the 30th with the 30th's (on time), 10% once on the missed bill → 1,000 + 100 + 1,000 = 2,100. Partial catch-up, 1% a day on the missed bill: 170 (Oct 2), then 100 (Oct 10, 10 days). Mixed (1% a day on the bill + 0.1% a day on the balance), both paid Oct 2: 850 on the Sep 15 bill, 20 on the Sep 30 bill. With the engine's own Sep 15 bill (16 days, 1,066.67): 1% a day on the missed bill → 181.33 + 20 = 201.33.
- **Loan rows on fixed-term.** A fixed-term penalty on the balance needs the loan's other rows, as open-term ones do: `confirm` and the Payment Center bulk handler load them when the loan has one (`chargesPerStretch`); the other paths already passed them.

## 6. Trigger: payment confirmation (PR 3)

finstack has four confirmation paths, all self-managed: the client-detail teller dialog (`PaymentBloc`), the Payment Center single payment and bulk overdue payment (`PaymentCenterBloc`), and the borrower bank-transfer submission confirm (`PaymentConfirmationService.confirm`, reached from the Payment Center card and the client-detail review dialog). All four call `PaymentConfirmationService.applyLateness`, which runs `resolveLateness` (pure, `loan_schedule_repository`) against the loan snapshot and writes `collected_at`, `days_late`, `penalty`, `penalties`, `penalty_waived_by`, and `penalty_waive_reason` onto the row before the payment record is created. `paid_late` is written only when the collection date is after the due date on a loan with `allow_late_payments == false`.

Collection date: chosen by the teller in the dialog; defaults to now for teller payments and to the borrower's submission time (`Payment.created_at`) for submissions. Bulk overdue applies one date to every row; each row gets its own days late and penalty. A waive needs a reason; bulk and submission loops validate it before the first write.

Borrower submissions: the borrower's Next payment card, Pay in full total, and Submit payment dialog include the running penalty as of now (`previewPenalty`), so the transferred amount matches what the teller's confirmation computes when the collection date defaults to the submission time. The penalty is recorded on the row at confirmation and appears on the row and the statement of account.

Reporting: the Go trigger `loan_schedule_changes.go` reads only company_id, status, loan_id, interest_payment, principal_payment on document creation and ignores the new fields, so this is not Class B. Penalties are not added to `total_collections`; doing so would be a Class B change with its own Go PR. No reporting side effect: the trigger's status gate accepts paid_on_time and paid_late alike, so allow-late loans switching to paid_on_time change nothing there.

## 7. UI

- **7.1 Company defaults**: "Default penalties" section on the company card in `profile_widget.dart` (admins only), chips plus an add button opening the shared dialog; saved through `CompanyBloc`, with the in-memory list rolled back and an error snackbar on a failed save.
- **7.2 Add-product wizard**: a "Penalties" section widget under `apps/loans/lib/features/products/widget/add_product/`, placed after Deductions in both layouts, pre-filled from company defaults on a new product (inherited chips marked "Default"), "Reset to company defaults", and an "Allow late payments" checkbox (form key `allow_late_payments`) inside the same section because the AutoCollect toggles are placeholders here.
- **7.3 Shared dialog**: `apps/loans/lib/widgets/penalty_dialog.dart` with Amount, Name, Description, Frequency (once, daily, monthly, per installment), and Based on (percentages only; section 5.2).
- **7.4 Schedule rows**: `ClientDetailScheduleItem` and `LoanScheduleWidget` (table and list tile) take the loan and print `previewPenalty` in red under the amount due (`+ ₱… penalty · N days late` on the lender side, `+ ₱… penalty` for the borrower), plus `penalty charged` / `penalty waived` on confirmed rows. Offer previews pass no loan and show nothing.
- **7.5 Confirm dialogs**: one shared `PaymentPenaltySection` (`lib/widgets/`) with the collection date picker, a live breakdown (one line per penalty per row, `name · amount label × periods`), `Installment + penalty`, and a `Waive penalties` checkbox that reveals a required reason. Hosted in the client-detail make-payment dialog, both Payment Center dialogs, the Payment Center submission confirm dialog, and the client-detail review dialog.
- **7.6 Loan and offer detail**: every `QuotationWidget` with a loan in scope passes `penalties: loan.penalties` and `allowLatePayments: loan.allowLatePayments`; product previews fall back to the bloc's working list and the selected product's flag. When late payments are allowed, the quotation shows only "Late payments: Allowed, no penalties" and no penalty lines (the definitions are kept on the product for when the flag is turned off); otherwise each penalty reads "Penalty if paid late: <name>" with `amountLabel`. The PDF quotation follows the same rule from `loan.allowLatePayments` and `loan.penalties`.
- **7.7 Statement of account**: a `Penalty` column (last) per row, and total penalties appended to `additionalCharges` so the existing `Add: <description>` rendering and `totalAmountDue` include them on the screen and the PDF.

## 8. Not in this feature

- Daily accrual job; AutoCollect (app-managed) payments; backfilling penalties onto pre-existing loans; grace days and caps; re-syncing a pending loan to a product's newer penalties (decline and re-apply instead).
- finstack#107 (stored percentage charges against the running total) and finstack#108 (campaign D5): loan-math and reporting-engine changes gated by the campaign.
- Penalties in report aggregates (`total_collections`); collecting the penalty on a borrower submission (recorded as owed only).

## 9. Testing

- Unit tests: `packages/core/loooans_helpers/test/penalty_test.dart` (model, periods, termDaysOf); `packages/loans/loan_schedule_repository/test/penalty_calculator_test.dart`; `apps/loans/test/widgets/penalty_dialog_test.dart`.
- Unit tests (part 3): `packages/loans/loan_schedule_repository/test/penalty_calculator_test.dart` (`resolveLateness` group); `apps/loans/test/services/payment_confirmation_service_test.dart` (`applyLateness`); `apps/loans/test/features/payment_center/payment_center_confirm_test.dart` (late confirm); `apps/loans/test/widgets/payment_penalty_section_test.dart`; `apps/loans/test/features/products/loan_schedule_widget_penalty_test.dart` (overdue and waived rows render without overflow).
- Gate: `.claude/skills/finstack-testing-and-validation/scripts/analyze-source-only.sh` (0 errors outside `build/`, no new warnings/infos) and `cd apps/loans && fvm flutter test`; package suites green except the two known scaffold failures (`address_repository`, `bank_details_repository`).
- Manual verification on the development flavor recorded in the PR body and `apps/loans/MEMORY.md`: company defaults, wizard pre-fill/reset/allow-late, product edit, quotation listing, loan snapshot persistence, pre-existing loans unaffected.

## 10. Delivery

1. This branch, `feat/penalties-72-definitions` → `develop`: model, fields, calculator, dialog, bloc, wizard, company defaults, loan snapshot, quotations. No payment behavior change.
2. `feat/penalties-72-application` → `develop`, after 1: confirmation, collection date, waive, schedule-row lines, statement of account. Becomes Class B only if a Go trigger starts reading penalty fields. This branch stacks on 1; merge waits for PR #109 and the loan-engine campaign's Gate 1 because penalty math is on the money path. Gate 1 (the loan-engine golden suite, campaign Phase 1) is waived for this PR by the owner on 2026-09-08: the branch does not modify loan_calculation_service.dart or charge_calculator.dart, penalty math has its own suite, and the golden suite itself is tracked as finstack#112.
