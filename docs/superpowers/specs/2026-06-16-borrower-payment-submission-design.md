# Borrower payment submission (upload proof, lender confirms)

**Date:** 2026-06-16
**Status:** Approved design — ready for implementation plan
**Issue:** [anatechopc/finstack#64](https://github.com/anatechopc/finstack/issues/64)

## Problem

The borrower-side "Pay now" / "Pay in full" buttons on the loan-detail screen
currently show a placeholder dialog (`TODO: redirect to payment channel`). There
is no way for a borrower to actually pay.

The product intent is for a borrower to pay the lender **directly** (off-app bank
transfer to the lender's preferred bank account). Integrating a payment gateway
(PayMaya / UnionBank) is out of scope for now. Instead we simplify: the borrower
**uploads a screenshot** of the bank-transfer transaction as proof, and the
**lender confirms (or rejects)** the payment.

## Goals (v1)

- Borrower can submit a payment for the **next due schedule** ("Pay now") or the
  **entire remaining balance** ("Pay in full") by attaching a transaction
  screenshot.
- Borrower can see **where to pay** (the lender's bank details).
- A submitted payment is **pending** until a lender acts on it.
- Lenders (admin / loan officer) are **notified** of submissions and
  **confirm or reject** them from the existing **Payment Center**.
- On confirm, the schedule(s) are marked paid and the loan status advances —
  reusing the existing teller confirm logic.
- On reject, the schedule(s) revert to unpaid so the borrower can resubmit.

## Non-goals (v1)

- No payment-gateway integration.
- No overpayment / change / cash-pool handling — the borrower submits the exact
  scheduled amount (cash pool is the teller flow's concern, left untouched).
- No partial payment of a single schedule.

## Existing infrastructure reused

| Piece | Location | Reuse |
|---|---|---|
| `Payment` / `PaymentEntity` | `packages/loans/payment_repository` | add a status lifecycle |
| `Payment.create(...)` proof validation (`bypassPaymentProof`) | same | borrower passes `transactionPhotoUrl` → proof present, no bypass |
| `StorageRepository.upload(data, folder, fileName, includeOriginal)` → `ImageUrl` | `packages/core/storage_repository` | upload the screenshot |
| Teller confirm path (mark schedule `paid_on_time`/`paid_late`, set `paidAt`, `paymentId`, advance loan status) | `apps/loans/lib/features/payment_center/bloc/payment_center_bloc.dart` | extract/reuse for lender confirm |
| `paymentCreated` Go trigger (notifies admins/loan officers) | `functions/loans/triggers/payment_created.go` | de-dup per submission |
| `BankDetailsRepository` (company `bank_name`/`account_number`/`account_name`) | `packages/core/bank_details_repository` | show lender's account to borrower |
| `LoanSchedule` (`paymentId`, `paidAt`, `status`) + `LoanStatus` enum incl. `payment_submitted` | `packages/loans/loan_schedule_repository` | mark schedules submitted/paid |

## Design

### 1. Data model — `packages/loans/payment_repository`

New enum `PaymentStatus { pending, confirmed, rejected }`.

`PaymentEntity` gains:

- `status` — `@JsonKey(name: 'status', defaultValue: PaymentStatus.confirmed)`.
  The default keeps **existing** payment docs and **teller-created** payments
  valid (they are confirmed at creation). Borrower submissions set `pending`.
- `rejectionReason` — `@JsonKey(name: 'rejection_reason')` `String?`, set on reject.
- `submissionId` — `@JsonKey(name: 'submission_id')` `String?`, groups the
  per-schedule payments created by one "Pay in full" submission (also set for a
  single "Pay now" so the model is uniform).

`Payment.create(...)` gains `PaymentStatus status = PaymentStatus.confirmed` and
`String? submissionId`. The teller flow continues to create `confirmed`
payments (it already sets `confirmedBy`/`confirmedAt`); the borrower flow passes
`status: PaymentStatus.pending`, `confirmedBy: null`, `confirmedAt: null`.

Proof: the borrower's screenshot is the proof, so `Payment.create` is called with
`transactionPhotoUrl` set and `bypassPaymentProof: false` (validation passes).

Regenerate `payment_entity.g.dart`. Round-trip + default tests added.

### 2. Borrower submit flow

Entry: `apps/loans/lib/features/loans/screens/loan_details.dart` `_nextPayment`
— replace the two TODO dialogs (`Pay now`, `Pay in full`) with a **Submit
payment** dialog (`apps/loans/lib/features/payments/widget/submit_payment_dialog.dart`).

Dialog contents:

- **Lender bank details** — query `BankDetailsRepository` for the loan's company
  (`data_id == company.id`, `data_type == company`). Show bank name / account
  name / account number. If none configured, show a clear message ("The lender
  hasn't set up bank details yet — contact them") and disable submit.
- **Amount** — Pay now = next due schedule amount; Pay in full = sum of remaining
  unpaid schedules.
- **Screenshot picker** — reuse the app's existing file/image picker pattern;
  required.

On submit, a new `PaymentSubmissionBloc`
(`apps/loans/lib/features/payments/bloc/`):

1. `storageRepository.upload(data: bytes, folder: 'users/{userId}/loans/{loanId}', fileName, includeOriginal: true)` → `ImageUrl`.
2. Generate one `submissionId`.
3. **Pay now:** create 1 pending `Payment` for the next due schedule.
   **Pay in full:** create one pending `Payment` per remaining unpaid schedule,
   all sharing the screenshot `ImageUrl` and the `submissionId`.
4. For each linked schedule: `status = payment_submitted`, `paymentId = payment.id`
   (so the borrower sees "Payment submitted" and can't double-submit).
5. Emit success → dialog closes, loan view refreshes.

Re-submitting after a rejection: the rejected payment stays as an audit record;
the borrower submits a new pending payment for the (reverted) schedule.

### 3. Lender confirm / reject — existing Payment Center

`apps/loans/lib/features/payment_center/`:

- New **"Pending submissions"** view listing payments where `status == pending`
  scoped to the lender's company's loans, **grouped by `submission_id`** (so a
  Pay-in-full shows as one item covering N schedules). Each item shows borrower,
  amount, the screenshot (tap to view), and the schedule(s) it covers.
- **Confirm** → for each payment in the submission, reuse the teller confirm
  logic: `status = confirmed`, `confirmedBy = lender.id`, `confirmedAt = now`;
  mark each schedule `paid_on_time` (or `paid_late` if `dueAt` is past) + set
  `paidAt`; advance the loan status. **No cash pool** (exact amount).
- **Reject** → for each payment: `status = rejected`, `rejectionReason = <reason>`;
  revert each schedule (`paymentId = null`, status back to `not_paid` /
  `not_paid_overdue` based on `dueAt`) so the borrower can resubmit.

The confirm/reject mark-paid logic is extracted into a shared helper/service so
both the teller flow and the lender-confirm flow use one implementation.

### 4. Notifications — Go backend

- **On submit (lender notified):** the existing `paymentCreated` trigger already
  notifies admins/loan officers. Update it to **de-dup by `submission_id`** —
  notify only once per submission (for Pay-in-full, otherwise it fires per
  schedule). Implementation: only notify when the created payment is the first of
  its `submission_id` (or carry a `notify` marker on a single primary payment).
- **On confirm/reject (borrower notified):** new `paymentUpdated` Go trigger
  (mirrors `reviewUpdated`, adapter+core split). Fires on the `status` transition
  `pending → confirmed` or `pending → rejected` and notifies the borrower
  (`payment.user_id`) — "Your payment was confirmed" / "Your payment was rejected:
  <reason>". Registered in `loooans_cloud_functions.go` and `deploy_functions.sh`.

### 5. Testing

- **Flutter:** `PaymentSubmissionBloc` tests (upload → pending payment creation for
  Pay now and Pay in full; failure paths). Payment Center confirm/reject bloc
  tests. `Payment`/`PaymentEntity` model tests (status round-trip, default →
  confirmed, submission_id). Widget test for the submit dialog (no-bank-details
  state, submit disabled without a screenshot).
- **Go:** adapter+core tests for the new `paymentUpdated` trigger (confirm vs
  reject vs no-op transitions) and the `paymentCreated` de-dup.

## Open considerations

- **Bank details absence:** v1 just blocks submission with a message. Adding a
  lender bank-details setup screen is a separate task if not already present.
- **Pay-in-full as N payments:** chosen to fit the per-schedule `Payment.loanScheduleId`
  model and reuse schedule linkage; grouped via `submission_id`. An alternative
  (one payment referencing many schedules) was rejected as a larger model change.

## Rollout

Independent feature branch `feature/borrower-payment-submission` off `develop`.
Touches `payment_repository` (model) — generated code is gitignored, so the build
regenerates it. The Firestore rule for who may write/confirm payments is
console-managed (same as reviews) and tracked separately.
