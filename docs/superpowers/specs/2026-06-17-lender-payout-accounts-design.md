# Lender payout (bank) accounts

**Date:** 2026-06-17
**Status:** Approved design — ready for implementation plan
**Depends on:** `feature/borrower-payment-submission` (PR #65) — extends its submit dialog + Payment model.

## Problem

The borrower payment submission feature (PR #65) blocks submission when the
lender has no bank details, but there is **no UI for a lender to add bank
details** and the `bank_details` collection is never written by the app. So the
feature is currently unusable end-to-end. This adds lender-side management of
**multiple** payout accounts and lets the borrower choose which to pay to.

## Decisions (from brainstorming)

- **Placement:** a "Payout accounts" section inside the existing `SettingsWidget`
  (opened from the Profile), shown only to a **self-managed company admin**.
- **Multiple accounts** (not single): list with Add / Edit / Delete.
- **Delete is soft** — the repository already sets `deletedAt` and `load` filters
  `deleted_at == null`. A soft-deleted account stays resolvable by id (for
  payments that referenced it).
- **Borrower** picks which account to pay to when there is more than one.
- **Record on the payment:** `Payment.paid_to_bank_details_id` (a reference). The
  Payment Center resolves it for display so the lender knows where to reconcile.
- **No backend change** — notifications don't use the account.

## Design

### Data model (`packages/loans/payment_repository`)

`Payment` / `PaymentEntity` gain `paidToBankDetailsId`
(`@JsonKey(name: 'paid_to_bank_details_id')`, `String?`). `Payment.create` gains
an optional `String? paidToBankDetailsId`. Nullable so teller payments and legacy
docs are unaffected.

### Bank details model/repo (`packages/core/bank_details_repository`) — reused as-is

`BankDetails.create({dataId, dataType, bankName, accountNumber, accountName})`,
`BankDetailsRepository` (`BaseRepository<BankDetails>`) `add` / `update` /
`delete` (soft) / `load`. The stored id field is **`dataId`** (camelCase, no
`@JsonKey`) — queries filter `field: 'dataId'`. No package change.

### Lender CRUD — `apps/loans/lib/features/bank_details/`

New `BankDetailsBloc` (`bloc/`):
- Constructor `BankDetailsBloc(BuildContext)` + `BankDetailsBloc.withDependencies({bankDetailsRepository, authService})` test seam. Repo typed `BaseRepository<BankDetails>` (so it is mockable).
- Events: `LoadBankDetailsEvent`, `AddBankDetailsEvent({bankName, accountName, accountNumber})`, `UpdateBankDetailsEvent({bankDetails})`, `DeleteBankDetailsEvent({bankDetails})`.
- State: `{status, List<BankDetails> accounts, message}`.
- All scoped to `authService.company.id`, `DataType.provider`.

### Lender UI — `SettingsWidget`

A "Payout accounts" section, rendered only when the signed-in user is a
self-managed company admin (mirror the role/`managementType` checks used
elsewhere). It lists accounts (`bank · accountName · accountNumber`) each with
Edit + Delete, and a "+ Add account" button. Add/Edit open a small form dialog
(bank name / account name / account number, all required). Wraps the section in a
`BlocProvider(create: BankDetailsBloc.new)` and registers the bloc in DI.

### Borrower UI — `submit_payment_dialog.dart` (modify)

Load **all** provider accounts (currently takes `.first`). Then:
- **0** → existing "lender hasn't set up bank details" message + Send disabled.
- **1** → show it, auto-selected (as today).
- **>1** → a dropdown (`bank · …last4`) to choose; **Send disabled until one is
  chosen**. Show the selected account's full details.

The chosen account id flows into `SubmitPaymentEvent` → `Payment.create(paidToBankDetailsId: ...)`. All payments of one submission share it.

### Payment Center — `pending_submission_section.dart` (modify)

Resolve `paid_to_bank_details_id` (`BankDetailsRepository.get(id)`) and show
"Paid to: `<bank>` …`<last4>`" on the pending-submission card. Resolve lazily; if
the id is null (e.g. a legacy/single-account-era submission) show nothing.

## Testing

- `Payment` model round-trip for `paid_to_bank_details_id`.
- `BankDetailsBloc` CRUD (load/add/update/delete) with a mocked repo.
- `SettingsWidget` payout section widget test (list renders; add dispatches; non-admin hidden).
- Borrower dialog: >1 accounts → dropdown shown, Send gated on selection; chosen id is recorded on the dispatched `SubmitPaymentEvent`.

## Rollout

Branch `feature/lender-payout-accounts` stacked on `feature/borrower-payment-submission`. Frontend-only PR; merge after / alongside #65. The console-managed Firestore rule must also allow a company admin to write `bank_details` for their own company (tracked with the payments rule).
