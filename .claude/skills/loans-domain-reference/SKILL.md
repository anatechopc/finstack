---
name: loans-domain-reference
description: "Use when working on finstack loan/lending code and you need the domain meaning behind it: LoanStatus values and transitions, open-term vs fixed-term loans, term strings like '1m'/'15d'/'15,30', amortization or interest math, additionalCharges/deductions/upfront collection, cash pool vs capital, UserRole or CompanyManagementType gating, OTP verification flows (mobile verification, payment acknowledgement), co-makers, requirements, reviews/karma. Also use when a variable name (interestDayMultiplier, bypassPaymentProof, verificationStatus, parentId) or a Firestore field is unclear."
---

# Loans Domain Reference (as implemented in finstack)

The lending-domain theory pack **as it applies to this codebase** — not a textbook.
Product = "Loooans" (triple-o), a loans marketplace connecting **borrowers** with
**lending providers** (companies). All paths below are relative to the repo root
`/Users/deibeeed/Projects/AnaheimTechnologies/finstack`.

**When NOT to use this skill:**
- Triaging a bug/symptom → `finstack-debugging-playbook`.
- Changing the schedule math or reporting → `finstack-loan-engine-and-reporting-campaign` (decision-gated; do not freelance edits to the calculators).
- Incident history behind a rule → `finstack-failure-archaeology`.
- OTP security weaknesses / rules-into-source → `finstack-security-hardening`.
- Layering, invariants, package graph → `finstack-architecture-contract`.

## 1. Marketplace model: who is who

| Concept | Meaning here | Code |
|---|---|---|
| Borrower | `UserRole.customer` — takes loans, pays via a teller | `packages/core/user_repository/lib/src/model/user_role.dart` |
| Lending provider | A `Company` document; owns products, loans, staff | `packages/core/company_repository/lib/src/model/company_entity.dart` |
| Staff roles | `appAdmin` (system), `admin` (provider admin), `loanOfficer` (approve/decline loans), `teller` (accepts payments, updates records), `reviewModerator` | `user_role.dart` (`companyManagedRoles` = admin, loanOfficer, teller, reviewModerator) |
| Management type | `CompanyManagementType.app` vs `.selfManaged` | `packages/core/company_repository/lib/src/model/company_management_type.dart` |

**`selfManaged` gates payments.** Recording a payment throws unless the staff
user's company is `selfManaged` (`apps/loans/lib/features/loans/bloc/payment_bloc.dart:85-87`,
comment: "for now, payment is only supported for self managed company types").
Tellers exist primarily for self-managed companies (`user_role.dart:18-26`).

## 2. Loan lifecycle — `LoanStatus`

One enum, `packages/loans/loan_repository/lib/src/model/loan_status.dart`, shared by
**both** `loans` and `loan_schedules` docs (snake_case names; `constant_identifier_names`
lint disabled for this):

| Status | Label | Set where (verified) |
|---|---|---|
| `pending` | Pending | Loan creation (`loans_bloc.dart:553`) |
| `declined` / `approved` | — | Staff status update (`_handleUpdateLoanStatusEvent`, `loans_bloc.dart:671`) |
| `payment_submitted` | Payment submitted | Borrower self-submits payment proof, awaits lender confirm (`apps/loans/lib/features/payments/bloc/payment_submission_bloc.dart:80`) |
| `paid_on_time` / `paid_late` | — | Teller records payment; picked by `schedule.dueAt` vs now (`payment_bloc.dart:92-99`) |
| `not_paid` / `not_paid_overdue` | — | Default schedule display state / overdue (`apps/loans/lib/features/products/screen/loan_schedule_widget.dart:191-207`) |
| `completed` | **Fully paid** | Early Settlement confirm (`apps/loans/lib/features/loans/bloc/loan_settlement_bloc.dart:166-173`) |
| `bad_debt` | Bad debt | Staff status update; excluded from settlement queries (`loan_settlement_bloc.dart:68,153`) |

Happy path: `pending → approved → (paid_on_time | paid_late)* → completed`.
On a **schedule** row the statuses mean per-installment state; on the **loan** they
mirror the latest activity.

## 3. THE BIG DISTINCTION: fixed-term vs open-term

**`period == 0` AND `dueAt == null` ⇒ open-term loan.** This is the single most
important domain fact. Documented on `packages/loans/loan_repository/lib/src/model/loan_entity.dart:94-118`;
set at creation (`apps/loans/lib/features/loans/bloc/loans_bloc.dart:550-557`:
`dueAt: period <= 0 ? null : ...`). Dispatch between the two calculators:
`loans_bloc.dart:359-379` and `:487-506` (`period != 0` → fixed, else open).

| | Fixed-term | Open-term |
|---|---|---|
| `period` | months to pay (stored in months, `loan_entity.dart:82-83`) | `0` |
| `dueAt` | last schedule due date | `null` |
| Payments | amortized principal + interest | **interest-only**; principal only reduced by extra/closing payments |
| Ends when | schedule exhausted | borrower closes via **Early Settlement** (§8) |
| Schedule | full table generated upfront | one next-due row generated at a time |
| Calculator | `LoanCalculationService.calculateFixedTerm` | `calculateOpenTerm` / `calculateOpenTermSchedules` |

Both live in `apps/loans/lib/services/loan_calculation_service.dart` (the arithmetic
core of the whole product — treat with campaign-level care).

### Term string grammar (`loan.term`, overloaded)

| Term value | Meaning | Where handled |
|---|---|---|
| `'1m'` | monthly | fixed: `loan_calculation_service.dart:88-92`; open: fallthrough `+30 days` (`:225-227`) |
| `'15d'` | every 15 days (twice-monthly). Fixed-term: payment count ×2, monthly rate ÷2 (`:77-80`; also `extensions.dart:157-160`). UI-entered payment count is halved into months at `loans_bloc.dart:457-461` | both calculators |
| `'D1,D2'` (e.g. `'15,30'`) | two salary days-of-month — **open-term only**. Comes from the borrower's profile: `employmentDetails.salaryDays` joined with `,` (`loans_bloc.dart:476-485`). Next due date advances to the other salary day / next month (`loan_calculation_service.dart:189-222`) | `calculateOpenTermSchedules`, `Loan.completeTerm` (`loan.dart:57-93`) |

Always check `term` before assuming monthly. Human-readable rendering:
`Loan.completeTerm` getter.

## 4. Money fields and charges

On a loan doc (`loan_entity.dart`): `amount` (principal requested),
`additional_charges`, `deductions`, `additional_charge_upfront_collection`
(`:122-126`, default 0).

- **`loanAmount = amount + additionalCharges - deductions`** — `LoanCalculationService.calculateLoanAmount` (`loan_calculation_service.dart:30-32`). This is the amount that gets amortized.
- **Upfront-collection charges are NOT rolled into the amortized amount** — they are collected at release: `receivable = totalAmount - totalUpfrontCollection` (`loans_bloc.dart:381`, `:472`).
- Settlement uses `(amount + additionalCharges) - (deductions + additionalChargeUpfrontCollection)` (`loan_settlement_bloc.dart:100-101`).

Charges are defined per product as `Charge` objects
(`packages/loans/product_repository/lib/src/model/charge.dart`): `amount`,
`is_percentage`, `is_upfront_collection`. Parsing/applying:
`apps/loans/lib/services/charge_calculator.dart` —
`parseChargeAmount` treats a trailing `%` as percentage, else flat (`:17-23`);
`applyChargesAndDeductions` applies percentages **of the base amount** (not
compounding) and routes upfront charges into `totalUpfrontCollection` (`:25-59`).

## 5. Schedule math (the two formulas)

Full worked tables + additional-loan merge walkthrough:
[references/schedule-math.md](references/schedule-math.md).
Regenerate the numbers: `python3 scripts/regen_worked_examples.py` (from this skill dir).

**Fixed-term amortization** — `P = (Pv*R) / [1 - (1 + R)^(-n)]`, implemented in
`apps/loans/lib/utils/extensions.dart:132-167` (`calculateMonthlyPayment` on `num`),
looped in `calculateFixedTerm` (`loan_calculation_service.dart:44-142`).
Verified example: Pv=10,000, rate 3%/month (`interestRate` field = `3.0`), 6 months,
term `'1m'` → **P = 1,845.98**, total paid **11,075.85**, row 1 interest 300.00 /
principal 1,545.98 → OB 8,454.02. Same loan at `'15d'`: n=12, R=1.5% → P = 916.80.

**Open-term proration** — "1 month = 30 days" convention (comment at
`loan_calculation_service.dart:146`):
`interestDayMultiplier = diffDays / 30` (`:262`), where `diffDays` = days between the
last schedule's due date and the next due date. Then
`interestCharge = outstandingBalance * monthlyRate * interestDayMultiplier` (`:265-266`)
and the scheduled `amortization` collapses to the interest charge — interest-only,
`principalPayment: 0` (`:280-284`). `totalLoanPayment` is `double.infinity` as a
sentinel: an open-term loan has no fixed total (`:241`).
Verified example: OB=10,000, 5%/month, salary days `'15,30'`, 15 days elapsed →
multiplier 0.5, interest **250.00**, scheduled amortization **250.00**, principal 0.
The multiplier is persisted on the schedule doc as `interest_day_multiplier`
(`packages/loans/loan_schedule_repository/lib/src/model/loan_schedule_entity.dart:143-146`).

## 6. Additional loans (top-ups) — the sort invariant

Open-term loans accept top-ups: `Loan.additionalLoanAmounts`
(`loan.dart:95`, populated from the `AdditionalLoanAmount` model —
`packages/loans/loan_repository/lib/src/model/additional_loan_amount_entity.dart`:
`loan_id`, `amount`, `additional_charges`, `advance_charges`, `deductions`, own
`LoanStatus`). Related: a child loan can carry `parent_id` (`loan_entity.dart:134-137`);
Early Settlement completes parent + children together (`loan_settlement_bloc.dart:142-173`).

**INVARIANT: merge additional loans into the schedule sorted by `createdAt`
ascending** — `loan_calculation_service.dart:354-358`
(`loan.additionalLoanAmounts.sortedBy((a) => a.createdAt)`). Processing newest-first
made later iterations overwrite earlier schedules' outstanding balances →
double-counted principal. That was the first real production bug
(finstack#4, fixed by PR finstack#33) — full narrative in `finstack-failure-archaeology`.
If you touch `calculateOpenTerm`, do not remove or reorder this sort.

## 7. Capital vs cash pool (two different pots)

| | `capital` | `cash_pool` |
|---|---|---|
| Belongs to | lending provider (`provider_id`) | borrower (`user_id`) |
| Meaning | funds the provider injects to lend out | borrower's **prepaid balance** held with the provider |
| Package | `packages/loans/capital_repository` | `packages/loans/cash_pool_repository` |
| App feature | `apps/loans/lib/features/capital/` (`capital_bloc.dart:39-44`) | `apps/loans/lib/features/cash_pool/` |

Cash pool is an append-only ledger of `CashPool` entries with `CashPoolStatus`
(`cash_pool_status.dart`): `add_to_pool`, `acknowledged_payment`, `change`
("Withdraw as change"), `savings`. Balance =
`add_to_pool − acknowledged_payment − change − savings`
(`apps/loans/lib/features/cash_pool/bloc/cash_pool_functions.dart:4-32`).

On every teller-recorded payment (`payment_bloc.dart:214-271`): load the borrower's
pool, compare `totalPayment = interest + principal` to the balance, then append an
`acknowledged_payment` entry deducting `min(totalPayment, balance)` with an audit
comment. **If the payment exceeds the pool, the excess is "collected from user in
person"** — that's a physical-cash business reality, not a bug.

## 8. Payments, confirmation modes, Early Settlement

Teller payment recording (`payment_bloc.dart:_handlePayLoanScheduleEvent`) has three
mutually exclusive confirmation modes (`:105-154`):

1. **Manual** — requires transaction photo + borrower signature uploads (default).
2. **Force** — no proof; only if `SettingsService.forcePaymentConfirmation` is on; audit comment records the teller.
3. **OTP-acknowledged** — borrower confirms via SMS OTP (§9); audit comment records borrower + teller.

Modes 2 and 3 set `bypassPaymentProof: event.force || event.otpVerified` on
`Payment.create` (`:161`) — passing `false` here while skipping proof was the
silently-swallowed-payment bug (PR finstack#38; see `finstack-failure-archaeology`).
Open-term payments start with `loan_schedule_id = NO_ID` and the schedule doc is
created after the payment (`:191-208`); the backend denormalizes `payments.loan_id`
(home: `finstack-architecture-contract`).

**Early Settlement** = the only way an open-term loan ends
(`loan_settlement_bloc.dart`): computes remaining balance across the parent loan and
its `parent_id` children, then marks them all `LoanStatus.completed` (`:130-173`).
Borrower-side payment submission (pending→confirmed with lender confirmation) lives in
`apps/loans/lib/features/payments/` + `payment_center/`.

## 9. OTP business flows (two of them)

Full step-by-step with file anchors: [references/otp-flows.md](references/otp-flows.md).
Delivery is a dedicated Android phone running `apps/sms-gateway` consuming the RTDB
`otp/` queue — operations in `finstack-run-deploy-operate`. Known open security
findings on this design → `finstack-security-hardening` (do not "fix" ad hoc).

**(a) First-login mobile verification.** GoRouter blocks every authenticated route
until **both** Firebase `emailVerified` **and** the mobile bit are set
(`apps/loans/lib/app/routing/router.dart:82-92`):
`user.verificationStatus & UserVerificationStatus.mobileNumberVerified.value != 0`.
`verificationStatus` is a **bitmask** (`packages/core/user_repository/lib/src/model/user_verification_status.dart`):
unverified 0, aiVerified 1, **mobileNumberVerified 2**, facebookProfileVerified 4.
Go sets bit 2 + `mobile_verified_at` (millis) transactionally on successful verify
(`functions/loans/api/users/verify_otp.go:30, 96-106`); changing `mobile_number`
clears both via the `userChanges` trigger (`functions/loans/triggers/user_changes.go:52-65`).
**90-day change lock:** after verification the number can't be changed for 90 days —
client computation in `apps/loans/lib/utils/mobile_lock.dart:13-22`. (Server-side
enforcement is in console-managed Firestore rules — UNVERIFIABLE from repo; see
`finstack-security-hardening`.)

**(b) Payment acknowledgement.** Teller requests an OTP **for the borrower**
(`payment_bloc.dart:289-311` → `userRepository.requestOtpForUser(targetUserId: borrowerId)`),
borrower receives the SMS and reads the code to the teller, teller verifies
(`:313-336`), then records the payment with `otpVerified: true` (§8 mode 3).
Server-side, `reason == "payment"` deliberately triggers **no** post-action
(`verify_otp.go:94-95`) — the confirmation lives at the payment site.

**Invariant (both flows):** the `reason`/`objective` driving post-verify actions is
read from the RTDB entry at `otp/{hash}`, **never from the request body**
(`verify_otp.go:62-64`) — a caller must not be able to escalate a payment OTP into a
profile mutation. Entries are keyed by hash/token, never by `userId`.

## 10. Co-makers, requirements, reviews, karma

- **Co-makers**: guarantor user ids on the loan — `co_maker_user_ids`
  (`loan_entity.dart:128-132`). Products define `requiredCoMakerCount`; creation
  throws if the count isn't met (`loans_bloc.dart:510-514`).
- **Requirements**: documents the borrower must upload per product —
  `RequirementSubmission { url, name, requirement_id }`
  (`packages/loans/loan_repository/lib/src/model/requirement_submission.dart`),
  stored inline on the loan (`loan_entity.dart:85-86`).
- **Reviews**: borrowers review providers. Submitting a review appends a `Review`
  doc AND client-side increments the company aggregates `reviewCount` /
  `totalRating` and the denormalized `product_views.reviewRatingAvg`
  (`loans_bloc.dart:634-660`; company fields at `company_entity.dart:78-87`).
  Average rating is always `totalRating / reviewCount` — no stored average on the
  company. Admin/reviewModerator responses live on the review doc
  (`response`, `responded_at/by_id/by_name` — `review_entity.dart:58-74`;
  feature = loooans#47 in old-repo numbering, NOT finstack PR #47).
  Backend notifications: `reviewCreated`/`reviewUpdated` triggers (inventory home:
  `finstack-run-deploy-operate`).
- **Karma**: borrower credit-worthiness score, a plain `double karma` on the user
  (`user_entity.dart:105`), displayed in `features/reports/widgets/credit_karma_widget.dart`.
  As of 2026-07-07 `packages/loans/karma_transaction_repository` exists on disk but is
  **not wired into app DI** (dormant — status home: `finstack-roadmap-and-frontier`).

## 11. Field-name gotchas worth memorizing

- Dates are int64 **millis since epoch** everywhere; Go writers must use
  `.UnixMilli()` (invariant home + incident: `finstack-architecture-contract`,
  `finstack-failure-archaeology` Timestamp saga).
- Firestore field names are snake_case via `@JsonKey(name: ...)` — but
  `verificationStatus` is camelCase in Firestore (no JsonKey rename,
  `user_entity.dart:120`), and so is `dataId` in bank details (a past silent-match
  bug). Check the entity file before writing queries.
- `NO_ID = 'no-id'` is the "not yet persisted" sentinel (`loooans_helpers`), load-bearing
  in open-term payment flow (§8).
- The `LoanStatus` enum serializes by **name** (snake_case string) in queries
  (`loan_settlement_bloc.dart:150-154` uses `.name`).

## Provenance and maintenance

Authored 2026-07-07 from repo inspection on branch `feature/chat-messaging`
(every path/line cited was read; worked examples computed independently and matched
the Dart formulas). Line numbers drift — re-anchor with the greps below before
trusting them in a changed file.

Re-verification one-liners (run from repo root):

```bash
grep -n "" packages/loans/loan_repository/lib/src/model/loan_status.dart   # enum values
sed -n '94,118p' packages/loans/loan_repository/lib/src/model/loan_entity.dart  # open-term + term docs
grep -n "sortedBy\|diffDays / 30\|1 - (1 + R)" apps/loans/lib/services/loan_calculation_service.dart apps/loans/lib/utils/extensions.dart  # math anchors
grep -n "selfManaged\|bypassPaymentProof" apps/loans/lib/features/loans/bloc/payment_bloc.dart  # payment gates
grep -n "verificationBitMobileNumber" functions/loans/api/users/verify_otp.go  # bit value 2
grep -n "mobileNumberVerified" apps/loans/lib/app/routing/router.dart  # router gate
python3 .claude/skills/loans-domain-reference/scripts/regen_worked_examples.py  # re-derive example numbers
```

Volatile facts: dormant `karma_transaction_repository` / `transaction_*` packages,
chat-era line numbers, and console-managed rules status — all dated 2026-07-07.
