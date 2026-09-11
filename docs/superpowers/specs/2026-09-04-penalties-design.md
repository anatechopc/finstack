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
| D7 | Percentage base is the row's amount due as already displayed: `amortization` for term loans, `outstanding_balance` for open-term rows. | The number the collector and borrower already see. |
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

`PenaltyFrequency` carries a `label`, a chip `suffix`, and `periods(daysLate, {termDays})`. `termDaysOf(term)` maps `1m` → 30, `15d` → 15, salary dates `a,b` → 15, otherwise 30.

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

`daysLate` is the difference in local calendar dates between `due_at` and the collection date, floored at 0; collected on the due date is on time. `previewPenalty(schedule, loan, asOf)` applies the allow-late gate and is what unpaid rows display before confirmation. Worked example: amortization 5,000; ₱100 daily + 2% monthly; 19 days late → 1,900 + 100 = 2,000.

## 6. Trigger: payment confirmation (PR 3, not in this branch)

`PayLoanScheduleEvent` gains `collectedAt` (default now), `waivePenalty`, `waiveReason`. The self-managed confirmation branch resolves lateness from the collection date against the loan snapshot (`resolveLateness`), sets `paid_late` only when late on a loan that does not allow late payments, and writes `collected_at`, `days_late`, `penalty`, `penalties`, and the waive fields onto the row before the payment record is created. `paid_late` rows already feed the Go trigger `loan_schedule_changes.go`; verify report aggregates when this ships.

## 7. UI

- **7.1 Company defaults**: "Default penalties" section on the company card in `profile_widget.dart` (admins only), chips plus an add button opening the shared dialog; saved through `CompanyBloc`, with the in-memory list rolled back and an error snackbar on a failed save.
- **7.2 Add-product wizard**: a "Penalties" section widget under `apps/loans/lib/features/products/widget/add_product/`, placed after Deductions in both layouts, pre-filled from company defaults on a new product (inherited chips marked "Default"), "Reset to company defaults", and an "Allow late payments" checkbox (form key `allow_late_payments`) inside the same section because the AutoCollect toggles are placeholders here.
- **7.3 Shared dialog**: `apps/loans/lib/widgets/penalty_dialog.dart` with Amount, Name, Description, Frequency (once, daily, monthly, per installment).
- **7.4–7.5 Schedule rows and confirm dialog**: PR 3.
- **7.6 Loan and offer detail**: every `QuotationWidget` with a loan in scope passes `penalties: loan.penalties` and `allowLatePayments: loan.allowLatePayments`; product previews fall back to the bloc's working list and the selected product's flag. When late payments are allowed, the quotation shows only "Late payments: Allowed, no penalties" and no penalty lines (the definitions are kept on the product for when the flag is turned off); otherwise each penalty reads "Penalty if paid late: <name>" with `amountLabel`. The PDF quotation follows the same rule from `loan.allowLatePayments` and `loan.penalties`.
- **7.7 Statement of account**: PR 3.

## 8. Not in this feature

- Daily accrual job; AutoCollect (app-managed) payments; backfilling penalties onto pre-existing loans; grace days and caps; re-syncing a pending loan to a product's newer penalties (decline and re-apply instead).
- finstack#107 (stored percentage charges against the running total) and finstack#108 (campaign D5): loan-math and reporting-engine changes gated by the campaign.

## 9. Testing

- Unit tests: `packages/core/loooans_helpers/test/penalty_test.dart` (model, periods, termDaysOf); `packages/loans/loan_schedule_repository/test/penalty_calculator_test.dart`; `apps/loans/test/widgets/penalty_dialog_test.dart`.
- Gate: `.claude/skills/finstack-testing-and-validation/scripts/analyze-source-only.sh` (0 errors outside `build/`, no new warnings/infos) and `cd apps/loans && fvm flutter test`; package suites green except the two known scaffold failures (`address_repository`, `bank_details_repository`).
- Manual verification on the development flavor recorded in the PR body and `apps/loans/MEMORY.md`: company defaults, wizard pre-fill/reset/allow-late, product edit, quotation listing, loan snapshot persistence, pre-existing loans unaffected.

## 10. Delivery

1. This branch, `feat/penalties-72-definitions` → `develop`: model, fields, calculator, dialog, bloc, wizard, company defaults, loan snapshot, quotations. No payment behavior change.
2. `feat/penalties-72-application` → `develop`, after 1: confirmation, collection date, waive, schedule-row lines, statement of account. Becomes Class B only if a Go trigger starts reading penalty fields.
