# MEMORY.md

Log of refactoring and bug fix work done across multiple sessions.

---

## Fixed-term principal shortfall goes on the next bill (#152, owner 2026-11-19)

- **Owner decisions 2026-11-20 (recorded on #152), third commit on #156:**
  - No extra bill after a short LAST payment. The rest of the last bill is a second row of the same bill (same `due_at`, interest 0, new optional field `part_paid_at` = when the short payment was collected; `LoanSchedule.lateFrom` uses it when later than the due date). Each receipt is its own stored row, payment document and cash-pool entry. `loanScheduleChanges` books each row on create: 175.29 + 3,000 on the first, 0 + 505.82 on the rest.
  - `LoanCalculationService.oneBillPerDueDate` folds the rows of one bill for every list (LoansBloc → client detail, borrower schedule/Pay now/PDF; the Payment Center expanded history). The Payment Center's actionable list was already one row (only the open rest is unpaid). While the rest is owed it is the bill, payable again; once paid, one row has the bill's amount, the sums paid and the penalties.
  - Penalties within the bill (my default, for the owner): once-only penalties are not charged again on the rest when the short payment was late (`penalty_calculator.dart`). The rest counts its days from the short payment (via `lateFrom`), so no day is charged twice. Carried shortfalls (option B) unchanged. Open-term unchanged.
  - Fills: a last bill on a whole-centavo balance rounds its interest once (a 960-case grid found 177.19 + 3,543.70 for a shown 3,720.88).
  - `ExpandLoanEvent` is registered in `PaymentCenterBloc.withDependencies`.
  - Tests: G16 33 (G16i 3 with penalties: 283.60 then 49.72; twice 328.19; on time then late 199.44; the grid); handlers 15 (3 bills in client detail and in the Payment Center history, one payment per receipt); dialogs 14. Mutations: fold off 7 fail, once-only skip off 2 fail. Full suite 659 (UTC, seed 2126639374); `test/services/` 185 under UTC and Manila; packages 21/21.
  - Manual run 3 (2026-11-20 09:10 Manila, read only): client detail and the Payment Center history list 3 bills (Dec 4 3,681.11 open); Dec 4 not paid short on the shared loan. Wrote only the sign-in device doc (not listed: gcloud needs `gcloud auth login`, interactive).

Branch `feat/fixed-term-shortfall-152` → develop (draft PR, after #151).

- **Engine (`calculateFixedTerm`):** resuming after stored rows, the next bill = amortization + the last stored row's principal shortfall (its `amortization - interestCharge` less `principalPayment`, to the centavo; paid rows only). The last bill is always balance + interest (was `min(P, balance + interest)`). When every bill is stored and the last paid row leaves more than 0.005, one more row bills the balance: due on the last due date, interest 0, balance after 0 (rule 2, my default, asked of the owner in the PR). Stored rows with the same due date sort by balance, highest first. G1: 500 + 3,000 → bill 2 3,844.18 (350.00 + 3,494.18), bill 3 3,681.11, total 11,025.29 (on time 11,016.26).
- **Completion:** `_fixedTermFullyPaid` (confirm and `completeLoanIfFullyPaid`) also needs a paid row at 0.005 or less (`LoanCalculationService.leavesPrincipal`). Client detail's `PaymentBloc` calls it too since the second review below.
- **Readers:** client detail, the Payment Center (actionable and expanded), Pay now and the PDF all read the engine's rows. The borrower's compact schedule tile showed `monthlyAmortization` for every fixed-term row; it now shows the row's `amortization`. The three teller dialogs no longer refuse 0 interest on fixed-term rows (the field is read-only there; the remainder row bills none). The fixed-term SOA does not exist (open-term only).
- **Rule 3:** a fixed-term interest shortfall cannot be recorded today (read-only field, bulk and submissions record the computed interest); the engine would not carry one → #154. Found: the single-payment dialogs send the last installment (and the remainder row) to "settle your account" → #155, fixed in this PR (second review below).
- **Tests:** G16 `test/services/fixed_term_shortfall_golden_test.dart` (23 after the review below; derivations at the top); `fixed_term_teller_payment_test.dart` +4 (client detail and Payment Center with 3,000 principal, the last bill short then its remainder on a fake-Firestore loan, the compact tile). Two completion tests in `payment_center_confirm_test.dart` had a paid final row holding 5,000; now 0. No golden moved. Full suite 631 (UTC, seed 316780408); `test/services/` 174 under UTC and Manila; packages 21/21. Mutation (no carry, no last-bill rule): 6 G16 tests fail.
- **Manual run (dev, 2026-11-19 22:44 Manila):** seed loan `AlWAkiTsiUIvG7Ia6g8D`, Oct 4 paid 500 + 3,000 with signature: Nov 4 3,844.18 (350.00 + 3,494.18, penalty 676.63 at 15 days), Dec 4 3,681.12 (175.29 + 3,505.82) in client detail and the Payment Center. Wrote `dev_loan_schedules/dAz09ZDes7ZEeIUXypcY` (balance 7,000, penalty 1,789.16), `dev_payments/qCkkR7vl9rxOZ6bHtmpc`, `dev_cash_pool/tYAGCaN8ytfYzTtMj1sM` (0.00), updated `dev_loans/AlWAkiTsiUIvG7Ia6g8D` (paid_late) and `dev_user_loan_views/57yxnZlF4tEME3OF9ROd`, a sign-in device doc under `dev_users/KMW6r9PhCJeo5AFKXqb126RXFIX2/devices/`, and 4 Storage objects under `users/BPnzQj9P732iwBdHiUR3/loans/AlWAkiTsiUIvG7Ia6g8D/` (the camera photo's object has an empty file name).
- **Open:** loans already marked completed with principal owed keep their status (no repair here); client detail lists their remainder row, the Payment Center does not (completed loans bill nothing).
- **Review of #156 (rounding):** the manual run showed Dec 4 3,681.12 (bill 2's principal projected unrounded, 3,494.1756), which became 3,681.11 once bill 2 was paid at the dialog's 3,494.18; the shown bills summed to 7,525.30, a centavo over the 7,525.29 owed. A bill that carries a shortfall is now in centavos: amount = `_toCentavo(amortization)` + carry, principal = `_toCentavo(amount - interest)`, and the next row starts from that balance. Dev row as stored (3,672.0856463124487): 3,844.18 then 3,681.11, shown 7,525.29 = owed (new golden). G16f moved with it (bill 2 2,381.00 = 225 + 2,156.00, shown 9,658.60 = owed). Bills that carry nothing keep the unrounded amortization (G1 unchanged; its three shown bills read 3 × 3,672.09 = 11,016.27 against 11,016.26 owed, before and after this PR). Mutation (rule off): 8 tests fail. Full suite 632 (UTC, seed 2128536313); `test/services/` 175 under UTC and Manila; packages 21/21. The dev screen was not rerun; the engine change is covered by the integration test (Dec 3,681.11 before and after).
- **Second review of #156 (#155 folded in, "Closes #155"):** both single-payment dialogs sent a payment to "settle your account" when principal >= the row's balance after; with a carry bill 2 tripped it (500 + 2,900 → 3,589.18 >= 3,510.82; from a carry of 185.03), and the last bill and the remainder row always did. One helper, `PaymentConfirmationService.isEarlyPayoff`, called by `client_detail_dialogs.dart` and `payment_center_dialogs.dart`: fixed-term principal up to the bill (+ 0.005) is a payment; settlement only for more than the bill that also clears the balance before the row; open-term unchanged (principal >= balance). Client detail's `PaymentBloc` now calls `completeLoanIfFullyPaid` after writing the row (it never completed a loan; it could not record a last bill before). Fills: a carried bill's interest is rounded once and its principal is the bill less it, so the dialog fills add up to the shown bill (500 + 2,999.50: 350.03 + 3,494.65 = 3,844.68, was + 3,494.66). Tests: G16 29 (G16h 5, the probe), `settle_prompt_test.dart` 14 (both dialogs: carried bill 2, last bill, remainder recorded; 7,100 payoff and open-term 10,000 settle; open-term interest only recorded; the probe's fills), `fixed_term_teller_payment_test.dart` 15 (client detail last bill and remainder complete the loan; Payment Center last bill as billed completes it). Mutations: old check in the helper 10 fail; no interest rounding 3 fail. Full suite 655 (UTC, seed 3513909870); `test/services/` 181 under UTC and Manila; packages 21/21. Penalties untouched (the double counting the review found awaits the owner). Manual run 2 (dev, 23:18 Manila): Nov 4 recorded as filled (350.00 + 3,494.18), no settle prompt, 676.63 charged; Dec 4 3,681.11 (same as projected) and its Confirm goes to the payment proof, cancelled. Wrote `dev_loan_schedules/HCTo8PtFSAHAYkhUL1P7` (balance 3,505.82), `dev_payments/hDo52NdVD0g6v6RVM3Rl`, `dev_cash_pool/uLxu9zN1T2qCmEzapdZ8` (0.00), updated the loan and `dev_user_loan_views/57yxnZlF4tEME3OF9ROd`, device doc `dev_users/KMW6r9PhCJeo5AFKXqb126RXFIX2/devices/O7PLcMCdGMQQcMCHpVtn`, overwrote the 4 Storage objects of run 1.

## Top-up on an overdue open-term loan: deduct, add to the next bill, or cancel (owner, 2026-11-19)

Branch `feat/topup-overdue-warning`, draft PR stacked on #146 (`feat/openterm-billing-by-cycle`).

- **Warning (creation):** client detail "Additional loan" and the Payment Center "Amount" button call `askTopUpOverdueChoice` (`lib/features/loans/widget/top_up_overdue_dialogs.dart`) after the amount is entered. It shows only when a bill is past due: amount = `borrowerAmountsDue(...).nextDueAmount` (Pay now: every bill due + the stretch penalty once; submitted bills excluded), via `TopUpOverdueService.overdue`. "Deduct" is disabled when the overdue amount is more than the cash the top-up hands over (`proceedsOf`: amount − deductions − upfront charges). Only `overdue_choice` (`deduct` / `next_bill`) is stored on the top-up; nothing else is written then.
- **Approval (`AdditionalLoanBloc`):** only a pending top-up can be approved or declined (a second approval no longer moves `approved_at`). For `deduct`: recompute on the approval day with the top-up still pending (`TopUpOverdueService.schedulesOf` = LoansBloc's computation), refuse unless the total equals what the approve dialog showed (`expectedDeduction`) and fits the proceeds; record `overdue_deduction` first (an interrupted approval then refuses a retry), write one confirmed payment per bill (`bypassPaymentProof`, comment names the top-up) through `PaymentConfirmationService.persistPaidSchedule` (moved out of the Payment Center), rows `paid_late`/`paid_on_time` collected at approval with their penalties, interest = amount due, principal 0; then `deducted_payment_ids`, status approved, `approved_at` (after the rows' `created_at`, so `_includesTopUp` keeps the top-up for the next bill), loan status = last bill's. Decline writes nothing else. No cash-pool entry (orchestrator decision, option A): the pool is the borrower's prepaid balance; the released cash is handed over outside the app.
- **Worked example:** 40,000 at 5%, '15d', bill 1,000 missed 5 days, Late fee 100 + 0.1%/day → 300; top-up 10,000 → 1,300 deducted, 8,700 released; next bill 333.33 + 833.33 = 1,166.67. Add to the next bill: on that bill's day 1,000 + 1,166.67 + 800 = 2,966.67.
- **Tests:** `test/services/top_up_overdue_test.dart` 10, `test/features/top_up_overdue_test.dart` 19 (bloc through the real handlers + both dialogs). Full suite 530 (UTC, random); `test/services/` 117 under UTC and Manila. Six guard mutations each fail a test. Manual browser run NOT done (needs an overdue loan in dev).
- **Review of #149 (2026-11-19):** B1/B2 two approvals at once (two devices, or a double tap) wrote two payments and two rows: approval and decline now go through `LoanRepository.transactAdditionalLoanAmount` (a Firestore transaction on the top-up doc, `AdditionalLoanAmountFirestoreService.transact`); "deduct" first claims the pending top-up with its plan (`deduction_plan`: per bill the row and payment JSON, ids `<topUpId>-<n>`; `overdue_deduction`, `deducted_at`, `deducted_payment_ids`), then writes them with `set` at those ids (new `PaymentRepository.set`, `LoanScheduleRepository.set`, `Payment.fromJson`, `LoanSchedule.fromJson`), then approves in a second transaction. The approval event runs sequentially (`asyncExpand`) and the screen disables Approve/Decline while the bloc is loading. S3 an approval that stopped part way is completed by approving again (same plan, same ids; decline refused while claimed). S4 the engine and the penalty base move a top-up's balance from `effectiveAt` = `approvedAt ?? createdAt` (owner to confirm); G14q moved 692.50 → 587.50 (83.33 + 504.17), nothing else moved; probe: added Sep 21, approved Sep 26 → Oct 1 bill 1,083.33, penalty 750 (same day: 1,166.67, 800). N5 deducted payments carry `submission_id` = top-up id (Go sends one push). `persistPaidSchedule` moved back into the Payment Center (unchanged from #146). Tests: unit 13, integration 25 (store fake with fresh objects and atomic top-up changes; two devices, approve vs decline, double tap, both interruption points, the Payment Center warning); 9 mutations incl. no transaction.
- **Re-check of #149 (2026-11-19):** a stored plan can go stale (claim, stop, a teller pays a planned bill, replay → two paid rows for one cycle). `TopUpOverdueService.check` compares the plan with the stored rows: a planned cycle paid or submitted by another payment makes it stale, and a stale plan is never written. None of its rows written → the claim is released (deduction 0) and the next approval works the amount out again; some written → refused for an admin. Chosen over skipping and adjusting because the other payment may have recorded principal or a shortfall (R4) that the later planned bills do not know, and the approver confirmed a release that no longer holds. Writes are now row first, then payment (no row = no payment). While claimed, client detail's "Make payment" and the Payment Center's Pay are off for the planned bills (`TopUpOverdueService.isClaimedBill`); the borrower's Pay now is not blocked (the check catches a submission). Merged #146 at aac8c04 (merge commit): one `LoanRepository.update(updateAdditionalLoanAmounts:)` flag with #146's meaning (default false: new top-ups are added, existing ones are written only when true). This branch's approval and decline write the top-up through `transactAdditionalLoanAmount`, so they no longer call `update` with true; adding a top-up uses the default; the deduction's loan-status write passes false. #146's `stale_top_up_payment_test.dart` forwards `transactAdditionalLoanAmount` to the real repository on `fake_cloud_firestore`, so its approval test runs the transaction.
- **Develop merged (#148 at 1c50bb8, 2026-11-19):** conflicts only in docs (MEMORY, the penalties spec, golden-scenarios); the calculator merged cleanly with both #148's bases and this branch's `effectiveAt`. With #148's flat-per-bill rule the two-bill deduction (loan created D-35, bills D-20 and D-5) moved 2,900 → 3,000 (flat 100 on each bill + the balance 0.1%/day once, 800), released 7,100 → 7,000, row penalties [900, 0] → [900, 100]. One-bill figures (1,300, 1,260, 750, 800, 2,966.67) and the Oct 1 split [700, 0] (the second bill due that day, not late) did not move.
- **Known limits:** the plan's documents are written one by one (not in one batch), but a stopped approval is completed by the next, or refused when its bills were paid elsewhere; the statement of account still dates top-ups by creation (#110).

## Penalty "Based on": the missed bill or the outstanding balance (2026-11-19)

Branch `feat/penalty-based-on`, draft PR stacked on #146 (`feat/openterm-billing-by-cycle`). Owner rules 2026-11-14 to 2026-11-19.

- **Model:** `PenaltyBase { missedBill ('missed_bill'), outstandingBalance ('outstanding_balance') }` and `Penalty.basedOn` (`based_on`, optional; absent/unknown → null; not written when null, so saved penalties keep their shape). `Penalty.baseFor(isOpenTerm:)`: the missed bill for a flat amount (owner, below); for a percentage `basedOn`, or without it the loan type's default (fixed-term missed installment, open-term balance). `PenaltyFrequency.suffix` now reads "per day" etc.
- **Calculator:** `_penaltiesFor` counts each penalty by its base: missed bill = per bill (`computePenalties` on the row's `amortization`, its own days late) on both loan types; balance = once per overdue stretch (the R3 code, now `_Stretch`, also for fixed-term rows). Fixed-term balance base = the balance in force each day: `outstanding_balance + principal_payment` of the earliest stretch bill not yet paid that day (first version: the first bill's, constant; changed in the review below); flagged for the owner. Open-term keeps the balance in force each day. `chargesPerStretch(loan, isOpenTerm:)` makes `confirm` and the bulk handler (`_stretchLoanRows`, was `_openTermLoanRows`) load the loan's rows for a fixed-term loan with a balance penalty.
- **UI:** the dialog shows "Based on" (radio) only for a percentage, starts on the missed bill, and selects the balance when "Per day" is picked; a flat amount saves no base. Labels: "10% of the missed bill, once", "0.1% of the balance, per day", "₱100.00, once"; a penalty without `based_on` shows its loan type's base (wizard: `tempProductView.maxPeriod <= 0`; quotations: `loan.period == 0`, offers `productView.maxPeriod`); company default chips (both types) say "of the missed bill (fixed term) or the balance (open term)" and wrap to 3 lines.
- **Tests:** G15 `test/services/penalty_based_on_golden_test.dart` (22, derivations at the top); `test/features/penalty_based_on_test.dart` (10: dialog, labels, wizard chips with a mocked `ProductBloc` — the real one builds Firestore-backed final repositories — and the stored shape company → product → loan, the payment dialog and borrower amounts with a missed-bill penalty on two open-term bills: 1,000 + 300, Pay in full 1,800); `penalty_dialog_test` and `loooans_helpers/test/penalty_test.dart` extended. Full suite 534 under `TZ=UTC`, random order (seed 238675403); `test/services/` 129 under UTC and Manila; G12/G13/G14 unchanged. Mutation (missed-bill penalty counted once per stretch on the bill's amount): 14 fail; reverted.
- **Manual browser run: skipped.** Signing in registers the browser as a new device in dev Firestore (`SessionLoader.loadSession` → `userRepository.addDevice`) and app start signs in anonymously; the rule was no writes.
- **Open:** the owner confirms the fixed-term balance base; fixed-term partial catch-ups depend on #140 (below). Flat amounts: decided, per missed bill (below).
- **Review of #148 (2026-11-19, same day):** S1 the fixed-term balance base is now the balance in force each day (the balance before the earliest stretch bill not yet paid that day), not the first bill's for the whole stretch: G15 F3 moved 40 → 29.50 (this PR's own golden); probe with 5,000 principal → 15 (40 before). It reads the stored balance that the next computed bill starts from, so #140 changes it: 19 instead of 29.50, 4.50 instead of 15 (F7/F8 pin both shapes). N1 "Per day" pre-selects the balance only until the lender picks a base. N2 quotation and PDF lines share `penaltyQuotationLines` (PDF via `pdfPenaltyLines`), tested for both bases and a saved penalty without the field; open-term principal paid inside a stretch (680, then 240 on 30,000). Full suite 544 (seed 1135178469); `test/services/` 134 under UTC and Manila. Mutations: counting 14 fail; base fixed per stretch 5 fail; N1 guard off 1 fails.
- **Owner's flat-fee decision (2026-11-19):** a flat amount is charged per missed bill on both loan types, each bill its own days late, saved ones included (`Penalty.baseFor` returns the missed bill for every flat amount). Moved, old → new: G13d both bills together 2,000 → 2,200; G14e partial with "100 once" 780 then 320 → 780 then 420; G14r one submission 450 (+0) → 450 + 100 = 550; G15 O6 open-term 100 once 100 → 200, 50 a day 850 → 950; integration (open_term_late_payments_test) two missed bills 3,900 (+0) → 3,900 + 100, Oct 5 Next payment 4,600 → 4,700 and Pay in full 5,100 → 5,200, bulk [3,900, 0] → [3,900, 100], dialog 4,600 → 4,700, rejection more than a term old 5,100 / 6,516.67 → 5,200 / 6,616.67, one submission 450 → 550; penalty_based_on_test dialog 1,300 → 1,400, borrower 1,300 / 1,800 → 1,400 / 1,900. New G15 O6b: 50 a day flat, 850 then the Sep 30 bill's own 10 days, 500. Merged develop (#146 = 1c60fde) first. Full suite 550 (seed 2844102246); `test/services/` 135 under UTC and Manila; counting mutation 30 fail.

## Open-term bills keep their cycle dates (owner rules R1-R5; #144, #120, #117, #145; 2026-11-19)

Branch `feat/openterm-billing-by-cycle` → develop (draft PR, stacked on #143, which merged as 7857570; develop merged in). Supersedes draft PR #131.

- **Engine (`calculateOpenTermSchedules`):** R1 bills on scheduled dates (`'1m'`/`'15d'` = creation day + 30k/15k calendar days; salary days = next salary day after the previous bill; never from today). R2 every bill due before today is its own row, then the next bill; no accrual to today, no one-month cap. R4 the last stored row's shortfall (`amortization − interestPayment`, to the centavo; 0 = no amount recorded = paid in full) is added to the next bill's `amortization`, not to `interest_charge`. R5 a top-up not yet in the stored balance splits its cycle by calendar day. Interest runs from the last stored row's `due_at`; after a #143 clamp row the next bill is the first scheduled date after `due_at` (not after `original_due_at`, which can land before the day its interest ended). Inputs are never changed (#145): no in-place sort, no row mutation; top-up rows are positioned by date and have `amortization` 0.
- **Penalties (`penalty_calculator.dart`):** R3 an open-term penalty is one per overdue stretch (earliest unpaid due date until no bill is late), charged with a payment up to its collection date less what earlier payments in the stretch charged. `previewPenalty`/`resolveLateness` take `loanRows`; `resolveLatenessTogether` resolves rows paid together. Fixed-term unchanged.
- **Flows:** client detail (row preview, payment and review dialogs, PaymentBloc) and the Payment Center (overdue dialog, bulk handler, pending-submission card) pass the loan's rows. The bulk handler splits the entered interest oldest first (`PaymentConfirmationService.splitOpenTermInterest`); a bill that gets nothing stays unpaid. `confirm` loads the loan's stored rows for open-term. Borrower: Pay now = every bill already due + the penalty once (`borrowerAmountsDue.payNow`). Computed bills are paid oldest first: client detail shows "Make payment" on the earliest computed bill only; the Payment Center hides the upcoming tile's Pay while bills are overdue. The overdue tile/dialog sum `amortization` for open-term. `MakeOverduePaymentEvent` is registered in `PaymentCenterBloc.withDependencies` for tests.
- **Goldens moved (deliberately):** G4c (Sep 8, 38 d, 633.33 / 500 due → Aug 31, 30 d, 500 + the Sep 30 bill), G9 due row (83.33 / 500 → 587.50), G10 (40.33 / 500 → 702.50), G13 interest only (633.33 → 500; 533.33 → 250 + 266.67); penalties unchanged. New: G9b-G9f, G14 (20). Under `America/New_York` only G5/G5b fail (D11); a first version stepped dates with Jiffy `add(days:)` from the creation day and failed G9/G10/G14c there, fixed by calendar-day steps.
- **Tests (first round):** full suite 442 under `TZ=UTC` (develop 412); `test/services/` 76; packages: loan_schedule_repository 30, loooans_helpers 19, loan_repository 1. Mutations: clamp a past bill to today again → 40 of 99 targeted tests fail; per-bill open-term penalty → 13 fail. Manual browser run NOT done (needs an overdue open-term loan in dev = an unapproved database write); steps in the PR body.
- **Stored rows:** no backfill. Rows from #143's clamp keep `due_at` / `original_due_at` and are listed as stored; old app builds that still clamp keep writing such rows, which the engine continues from. `original_due_at` stays in the model so those rows load.
- **Review of #146 (2026-11-19, same day):** B1 a submitted bill is settled at its transfer (`collected_at` written at submission; older rows get it from their payment in `confirm` and the Payment Center card; reject clears it): A/B confirmed in either order 900 + 900 (was 4,800). S1 only approved top-ups move balance and bill (#137). S2 penalty base = balance in force on each charged period's first day (400 in the probe). S3 pending/declined/completed/bad-debt loans bill nothing (`LoanCalculationService.billsOpenTerm`: engine, client detail, borrower, Payment Center, SOA). S4 Payment Center loads loans with top-ups (#135). S5 shortfall uses max(amortization, interest_charge) (clamp row 1,600/500/500 → +1,100). S6 local calendar days everywhere; interest days in calendar days (G5/G5b now pass under New York). S7 dialog shows amount due (#142). S8 "Make payment" on the earliest unpaid open-term bill, stored or computed. N1 a partial bulk payment leaves the loan at the earliest unpaid bill's status. N2 Payment Center single path passes the loan's rows (`loanRowsOf`). N3 bulk handler split into `_settleOverdueRows` / `_openTermLoanRows` / `_persistPaidSchedule` (82 lines). N4 a top-up's days before an early-paid due date are billed (G9f 615.50). N5 a missing salary day is the month end. N6 bills generated one after another, the current bill never dropped. Goldens moved: G9f 605 → 615.50 (N4), G14b clamp row amount due 433.33 → 500 (S5). Full suite 470.
- **Second review of #146 (2026-11-19):** a submitted bill ends its lateness at its transfer but is not charged until confirmed (one submission of two bills → 450 once, was 0); older submissions get their transfer time in every path (`confirm`, Payment Center card and bulk, `LoansBloc`, which now reads `PaymentRepository`); top-ups record `approved_at` on approval (optional field, JSON default null, no Go reader) and `_includesTopUp` uses it (G14q 692.50/605/605; pre-field top-ups keep the creation-time rule); step terms continue from the earliest stored bill's cycle date (no 1-day bill for old-engine first rows; G14l's fixture gained the Aug 1 row its interest implies, a lone clamp row continues from itself, Dec 5, 1,600); a confirmed borrower submission records interest paid = amount due (submitted clamp row carries 1,100); a pending application shows its projected first bill read only. Full suite 483.
- **Third review of #146 (2026-11-19):** step terms anchor on the local creation day again; a stored bill within one day of a scheduled date counts as that bill (no 1-day bills), an old build's clamp row does not move the schedule (G14s: Aug 31, 22 days, 500 due); G14l's lone clamp row moved back from Dec 5 / 1,600 (second review) to Nov 29 / 1,500; G14p now expects 30 or 31 days depending on the zone. #138: `LoanSchedule.isPrincipalRelease` (placeholder, or the plain row approval stores for app-managed companies); refused by the submission bloc, `confirm`, `PaymentBloc` and both Payment Center handlers (`PaymentConfirmationService.rejectPrincipalRelease`), never listed as owed or payable; a confirmed open-term submission records interest due and principal 0; already-confirmed rows not backfilled. A pending application's projected bill shows "Projected". `MakePaymentEvent` registered in the Payment Center test seam. Full suite 494.
- **Fourth review of #146 (2026-11-19):** the engine never continues from a stored principal release (it billed 0 after it, develop too); `isPrincipalRelease` is exact (balance 0 with no interest recorded, or negative; a 0% bill paid with principal does not match); the one-day rule now applies to salary days (a Manila-written Aug 15 row read on a UTC device: Aug 30, 16 days, not a 1-day bill). Stored releases confirmed before #138 still need data repair for the statement of account and settlement (principal 0, interest = amount paid); billing needs none. Full suite 498.
- **Fifth review of #146 (2026-11-19):** the one-day window applies only to a stored row off the schedule; a row on a scheduled date keeps the next bill a day later (`'15,16'` Aug 16, `'1,30'` Mar 1, `'1,31'` Feb 1: 1 day, 16.67 each; G14v). `isPrincipalRelease`'s negative-balance case is exact: balance = minus the principal paid (an overpaid 0% bill, balance -2,000 after 12,000, is a bill). Full suite 501.
- **Stale top-ups (review of #149, on #146, 2026-11-19):** `LoanRepository.update` wrote back every loaded top-up, so a teller payment from a screen opened while a top-up was pending reset it to pending after approval (client detail on develop; the Payment Center since #146 loads top-ups), and #146 bills approved top-ups only. New flag `updateAdditionalLoanAmounts` (default false): existing top-ups are written only when true (top-up approval/decline in `AdditionalLoanBloc`); new top-ups (no id) are always added. Every other `loanRepository.update` caller only changes the loan's status. `LoanRepository.withFirestore` and `AdditionalLoanBloc.withDependencies` are test seams; `stale_top_up_payment_test.dart` runs the real repository on `fake_cloud_firestore` (new app dev dependency). Full suite 506.
- **Not covered / open:** top-ups approved before `approved_at` existed keep the creation-time rule; the amount a borrower actually transferred is not recorded (the payment document has no amount: a short transfer counts as paid in full, an excess gets no credit); top-up deductions (#127); the SOA's own top-up handling (#110, it does not pass top-ups to the engine); completed or pending open-term loans now list every scheduled bill since their last stored row in client detail (one row before); an interest overpayment is not credited; the Payment Center loads loans without top-ups (#135).

## Fixed-term teller payments subtract the principal once; the oldest installment is paid first (#140, #150; 2026-11-19)

Branch `fix/fixed-term-payments-140` → develop (draft PR, after #146; placed below the #146 entry so it merges cleanly with #148/#149).

- **#140:** a computed fixed-term row holds the balance after its scheduled principal; the three teller paths (client detail `PaymentBloc`, Payment Center single and bulk) subtracted the principal paid again. All three now call `PaymentConfirmationService.recordTellerPayment`: fixed-term moves the balance by the difference from the scheduled principal (principal above it is the extra payment, a short payment raises it back), open-term subtracts as before. G1 row 1: stored 6,827.91 (was 3,655.82), next bills 3,672.09 + 3,672.09 (3,672.08 when the dialog's rounded 3,172.09 is paid), total 11,016.26; 1,000 extra 5,827.91 (was 2,655.82).
- **#150:** client detail offers "Make payment" on the earliest unpaid fixed-term installment only (`_isPayableInstallment`, the #146 rule); a rejected stored installment (`not_paid_overdue`) is now payable.
- **Tests:** G1t (5) in `test/services/loan_calculation_service_test.dart`; `test/features/payment/fixed_term_teller_payment_test.dart` (8, real handlers; 7 fail on develop with 3,655.82 / 2,655.82 / 3,655.83 + 166.53). Full suite 519 (develop 506), `test/services/` 112 under UTC and Manila, no golden moved. Manual run: dev seed loan (Amagi, Seed Fixed Monthly) shows "Make payment" on Oct 4 only.
- **Data:** repair tool `functions/loans/cmd/repair_fixed_balance` (see functions MEMORY); dry run dev 1 row, stg 1 row; not applied; production not counted.
- **Merged develop (#148 1c50bb8, #149 c90b09e), no conflicts:** #149's top-up deduction (`TopUpOverdueService.settle`) is open-term only and writes no balance; no other new writer of a fixed-term balance. G15 F7/F8 now store R2 through `recordTellerPayment`: the two cases that copied the old handler lines are gone (5,000 principal: 900 → 3,000, R3 4.50 → 15; scheduled 2,100: 3,800 → 5,900, R3 19 → 29.50, the same figures as the cases that stay); G15 28 → 26 tests.
- **Open:** a fixed-term principal short of the schedule leaves a residual no remaining row bills (#152); the Payment Center bulk overdue payment ignores the entered total principal, and its upcoming fixed-term tile stays payable while installments are overdue (#153; left out because #149 edits those lines).

## Open-term loans honour "Allow late payments" (finstack#114, 2026-11-13)

Branch `feat/openterm-late-payments-114` → develop (draft PR). Owner request: open-term products get the same allow-late option as fixed-term ones. The fault: `calculateOpenTermSchedules` bills an overdue cycle as due today so interest accrues to today, and every lateness reader compared that billing date with the collection date, so open-term rows were always 0 days late and never penalized.

- **Model:** `LoanSchedule.originalDueAt` (`original_due_at`, nullable, older documents load as null) and the getter `LoanSchedule.lateFrom` (`originalDueAt ?? dueAt`). Flutter-only: no Go code reads `due_at` or the new field (grep of `functions/`), so not Class B; the Go report gate treats `paid_on_time` and `paid_late` the same.
- **Engine:** the clamp is unchanged (G4c stays 633.33 interest / 500 amortization; #120 owns that cap); when it moves the date to an earlier day it records the old one on the row.
- **Readers switched to `lateFrom`:** `previewPenalty`, `resolveLateness` (so every confirmation path through `applyLateness`, the payment dialog breakdown, the pending-submission card, the client-detail and borrower rows), the client-detail "Overdue" label, the borrower table's "Not paid (overdue)", the Payment Center overdue marking, the overdue tile's date range, and `revertedStatus` on a rejected submission.
- **Placeholder rows:** `previewPenalty` and `resolveLateness` treat an open-term placeholder (principal release, top-up) as never late. Before, a flat penalty was previewed on the principal-release row (due on the creation day), and confirming it gave `paid_late`, 68 days, 100 (review probe). The client-detail row no longer offers "Make payment" on the principal-release row: paying it would record the whole principal as repaid on the creation day (the dialog prefills principal = loan amount), and the Payment Center already filtered placeholders out. The borrower's Next payment / Pay in full (`borrowerAmountsDue` in `loan_details.dart`, extracted for tests) skip placeholders: before, the principal-release row was the "next payment" of every open-term loan (₱0.00 plus that phantom penalty) and Pay in full included top-up rows' copied amortization.
- **Rejected submissions (review of #143):** the Payment Center regenerates the cycle beside a stored unpaid row and de-duplicated by `due_at` day; a rejected open-term row keeps `due_at` = the submit day, so the cycle appeared twice (review probe: 900 + 900 = 1,800 penalty, 600 + 633.33 interest; develop: 300 and the same doubled interest). Now a stored row and a regenerated row are one cycle when their `lateFrom` days match (compared in local time; stored dates come back in UTC), or, on an open-term loan, when the stored row is dated after the last paid row (covers rows stored before `original_due_at`). The stored row is kept (it has the id): 900 once, interest 600 once. A pre-#114 rejected row counts from its own `due_at` (300 in the probe). Client detail and the borrower screen already counted once (LoansBloc feeds stored rows to the engine as history).
- **Found, not changed:** the Payment Center and the borrower table already called a row due today "overdue" (they compare instants and today 00:00 is before now), while lateness counts calendar days (due today = on time); the client-detail row did not. Open-term rows billed as due today were therefore already in the Payment Center's overdue list, paid on time with no penalty. The payment dialog shows the open-term balance as "Installment" (#142).
- **Tests:** G13 (7 hand-derived scenarios, `test/services/penalty_open_term_golden_test.dart`), `test/features/open_term_late_payments_test.dart` (14: client-detail row incl. no "Make payment" on the principal release, borrower table, payment dialog, borrower totals incl. a rejected row counted once, Payment Center bloc through `SelectBorrowerEvent` — now registered in `withDependencies` — incl. the rejected-submission cases), 3 package tests. Full suite 408 green under `TZ=UTC`. Mutation: `lateFrom => dueAt` fails 14 of the first 17 new app tests; reverting the dedupe, the `resolveLateness` guard and the button fails their 4 tests. The relative-date widget/bloc tests fail under `America/New_York` when the 38 days before today cross a clock change (D11, same as G5/G5b); G13 passes there.
- **Behaviour change:** `allow_late_payments` reads as false on loans written without it, and `paid_late` does not depend on the loan having penalties. So every open-term loan that does not allow late payments, including loans created before the penalties feature, now confirms an overdue cycle as `paid_late` with `days_late`, sets the loan status to `paid_late`, and shows Overdue. Money is charged only where the loan has penalties (loans created since the penalties feature whose product has them). What `paid_late` on a loan changes otherwise (checked 2026-11-13): the label "Paid (late)", orange in the loan-clients list and on the Payment Center card's schedule rows (its loan badge is green for both); the dashboard counts it as Active like `paid_on_time`; the Go report gate (`report_core.go` `isCollectionStatus`) books both alike; Go loan notifications fire only for pending/approved/declined; reviews are gated on `completed`; nothing writes karma. Not run in a browser: dev has no overdue open-term loan and making one needs a database write the owner has not approved; steps are in the PR body.
- **Known limits:** a salary-day loan is late only while its last row falls on a salary day: one created on an off day is never late, and after a late payment (billed on an off day) it is never late again (#144); a top-up while a cycle is overdue raises the penalty base for all its late days (review: 1,300 against 1,150 pro rata); two missed cycles collapse into one open-term row, so a "once" penalty is charged once (40 days → 4,100) where fixed-term charges it per row. Rows written by app builds older than this change (borrowers on un-updated mobile apps) have no `original_due_at` and confirm 0 days late.
- **Owner decisions 2026-11-19:** the penalty base stays (fixed-term: the missed installment; open-term: the outstanding balance) until penalties get a "Based on" option. A later PR makes open-term bills keep their own dates; for it: rows written in the meantime store the interest end date in `due_at` and the cycle date in `original_due_at`; next cycles start from `original_due_at ?? due_at`, interest from `due_at`.
- **Second review (2026-11-19):** the Payment Center gave the engine only paid rows while `LoansBloc` gives it every stored row, so once a rejected submission was more than a term old the Payment Center hid a cycle that client detail and the borrower showed (review probe: paid 80 days ago, submitted 45 days ago, rejected → 2 rows and 6,700 elsewhere, 1 row and 5,100 in the Payment Center). Both `_getActionableSchedules` and the expanded history now pass every stored open-term row, as `LoansBloc` does; the only merge left is the same lateness day in local time (`PaymentCenterBloc.mergeUnpaid`, which takes a zone offset for tests). The earlier "dated after the last paid row" rule is gone. The 2-days-ago rejection now shows the stored row overdue (900) plus the next cycle as upcoming, the same rows as client detail.

## Percentage charges stored against the principal (finstack#107, 2026-09-09)

Branch `feat/charges-base-107` → develop. `LoansBloc._handleAddLoanEvent` persisted `additional_charges` / `deductions` through two ad-hoc folds that multiplied percentage charges by the running charge-adjusted `totalAmount`, while the quotation used `ChargeCalculator` with the principal as base (G8). The handler now takes both figures from `ChargeCalculator.applyChargesAndDeductionsDetailed(baseAmount: amount, …)`, the same call that feeds the quotation, so there is one computation and no second implementation to test. Evidence: G8 (`test/services/charge_calculator_test.dart`) + suite green. No bloc-level test in this PR: `LoansBloc` takes a `BuildContext` and has no `withDependencies` seam, so a regression test needs a widget harness with nine mocked repositories (feasible, ~60 lines; add it or the seam the next time the bloc is touched). Pre-existing loans keep their stored values (no backfill). The independent review re-derived G8: old stored charges/deductions 675/155 vs new 650/150, and confirmed every downstream reader (settlement, SOA, reports, the Go completed branch) only becomes more consistent.

## Loan-engine golden suite — campaign Phase 1 / Gate 1 (finstack#112, 2026-09-08)

Branch `feat/golden-suite-112` (off `develop`). `fvm flutter test test/services/` is now the Gate 1 oracle: 29 tests, 24 of them golden scenarios (G1–G10, the clock-seam G4c/G5d, three G7 cases) in four files (`loan_calculation_service_test.dart` G1–G3, `loan_calculation_open_term_test.dart` G4–G6 + G9/G10, `loan_calculation_settlement_test.dart` G7, `charge_calculator_test.dart` G8). Every expected number was derived by hand first; the derivations are comments at the top of each file.

- **Extraction (behaviour-preserving):** `LoanCalculationService.calculateSettlementBalance(loans:, schedules:)`; `LoanSettlementBloc` delegates. G7 pins the CURRENT output (8800). The independent code review of PR #115 showed the formula is wrong four ways (assigns not accumulates — and production credits the least recently updated row because rows load newest-first; unconfirmed submissions credited; open-term credits the charge not the recorded cash; top-ups ignored) and that `+=` (8300) is not the fix either. finstack#116 re-scoped to a formula decision; flip G7 there.
- **Review follow-ups landed in PR #115:** `TZ=UTC` pinned on the CI "Run app tests" step and in the gate command (the suite is confirmed red under New York / London / Sydney time — campaign D11, catalogued); `SettingsService.resetForTest()` now also closes the discarded controller and is called in every setUp that initialises the singleton (search overlay, borrowers screen, main-screen borrowers, loan offers); G1/G2 compute inside each test; G7 fixtures use row states the payment blocs can write; G9 names finstack#117; campaign D9/D10/D11 rows and the loans-domain-reference line refs updated.
- **Clock seam (owner-requested 2026-09-08; built on `feat/clock-seam-112` as PR #119, then folded into #115 by fast-forward so there is one golden-suite PR):** optional `DateTime? now` on `calculateOpenTermSchedules` / `calculateOpenTerm` (defaults to the wall clock; no caller changes; the earlier scenarios omit it and stay green). G4c pins the overdue clamp (due date snaps to today; 38/30 → 633.33; amortization stays capped at 500 — questionable, flagged in the reference) and G5d the `'1,15'` neither-day branch (next due derived from today, interest from the start date).
- **Mutation check:** `/ 30` → `/ 31` in `loan_calculation_service.dart` fails all 10 open-term scenarios (verified, then restored).
- **Clock coupling:** scenarios anchor dates so `now` cannot matter (yesterday / a fixed future month / past-dated additional loans). The past-due clamp and the `'D1,D2'` third sub-branch are covered through the clock seam (G4c/G5d, below). G11 (UI refresh after an additional loan) parked — widget flow, not math.
- **G9 pins a confirmed defect (finstack#117, campaign D10):** the computed schedule adjacent to an additional-loan placeholder is mutated to the placeholder's *prorated* interest (83.33 on 12100). Owner decided 2026-09-08: the next row charges the new balance for the remaining days (504.17). Flip G9 with that fix.
- **Settings test flake fixed:** `settings_service_test.dart` was order-dependent (`SettingsService.initialize` is idempotent by design; the router calls it lazily). Added `SettingsService.resetForTest()` (`@visibleForTesting`) and call it in `setUp`; green under seeds 1/4/5/random.
- Fresh-worktree bootstrap: `packages/get_dependencies.sh` → `packages/build_models.sh` → `apps/loans` `fvm flutter pub get` (`*.g.dart` are not versioned); package `pub get` rewrites every `packages/*/*/analysis_options.yaml` — revert, never stage.

---

## Issue #47 — Reviews: admin responses to borrower reviews (IN PROGRESS)

Adds the ability for a company's `admin`/`reviewModerator` to respond to a borrower review; the borrower sees the response and gets notified. Tracks `anatechopc/loooans` issue #47. Branch: `develop` (uncommitted as of 2026-06-02).

**Locked design decisions:** one response per review; response is editable + deletable; `admin` + `reviewModerator` of the review's `provider_id` company may respond; borrower notified only on the **first** response-set transition (not every edit), to avoid spam.

**Done so far:**
- **Data model** (`packages/loans/review_repository`) — `Review`/`ReviewEntity` gained `response`, `respondedAt`, `respondedById`, `respondedByName` (snake_case JSON keys). Helpers on `Review`: `hasResponse`, `setResponse(...)`, `clearResponse()` — all four fields always written/cleared together so the doc never holds a partial response. 9 package tests green.
- **Go trigger** (`functions/loans/triggers/review_updated.go`) — see `functions/loans/MEMORY.md`. Fires only on `response` first-set transition, notifies `review.user_id`. 8 tests green.
- **Borrower-side rendering** (`apps/loans/lib/features/products/widget/loan_offer_detail/loan_offer_reviews_section.dart`) — new private `_ReviewResponseBlock` shown beneath a review when `review.hasResponse`. Indented + left-accent so it reads as a nested reply; header "Response from {respondedByName}" + `respondedAt` date; **black text** (grey is unreadable on the green background — see memory). Widget test at `test/features/products/widget/loan_offer_detail/loan_offer_reviews_section_test.dart` (3 cases, TDD red→green). This is the app's first real widget test beyond the VGV counter boilerplate — uses the existing `tester.pumpApp()` helper in `test/helpers/`.

**Admin side (images 4–5) — DONE (2026-06-02):** new feature dir `lib/features/reviews/`.
- `bloc/reviews_bloc.dart` (+ `reviews_event.dart`, `reviews_state.dart`) — `ReviewsBloc`. Events: `LoadCompanyReviewsEvent` (loads `provider_id == authService.company.id`), `RespondToReviewEvent` (sets response with logged-in admin's `user.id` / `completeNameEasternOrder`), `DeleteReviewResponseEvent` (clears). Two constructors: default `ReviewsBloc(BuildContext)` for DI, `ReviewsBloc.withDependencies({reviewRepository, authService})` for tests. Repo field typed as `BaseRepository<Review>` (abstract/mockable) because concrete `ReviewRepository` is a `final class` (can't be mocked). 4 bloc tests.
- `widget/review_response_dialog.dart` — `ReviewResponseDialog` + `showReviewResponseDialog(context, review:)`. Original review on top, `Message` field (prefilled in edit mode), Send; **Delete response** button shown only when `review.hasResponse`. 5 widget tests.
- `widget/reviews_dialog.dart` — `ReviewsDialog({required summary})` + `showReviewsDialog(context)`. Header summary via pure `reviewsSummary(Company)` (kept out of the widget so it's testable without the auth singleton); list reuses borrower `LoanOfferReviewItem` (so existing responses render) + a Respond/Edit button per row. 5 widget tests.
- Score card wired in `lib/features/reports/widgets/report_cards_widget.dart` — replaced the commented `'reviews'` block with a real `ScoreCardWidget` (★ `avg.toStringAsFixed(1)` `(reviewCount)` from `AuthenticationService.instance.company`, no GoogleFonts), `footerIcon` opens `showReviewsDialog`. Added `namedReportCards(context)['reviews']!` to the compact grid (the full grid picks it up via `.values`).
- `ReviewsBloc` registered in `lib/app/di/bloc_providers.dart` (ReviewRepository was already provided in `repository_providers.dart`).
- **All 17 app tests pass; `flutter analyze` clean on all touched files.**

**Still remaining:**
- **Firestore rules — DEFERRED** (user chose to skip for now, 2026-06-02). NOTE: repo Firestore rules are NOT the source of truth — `apps/loans/firestore.rules` is the stale default template (its `allow` expired 2024-06-22) and `firebase.json` references only `firestore.indexes.json`; only `firestore:indexes` is deployed (`scripts/deploy-indexes.sh`). Real rules are **console-managed manually** (same pattern as prod RTDB rules). The review-response permission (admin/reviewModerator of the review's `provider_id` company may write only `response*` fields; borrowers read-only) must be added there separately.
- PR not yet opened; all work still uncommitted on `develop`.

---

## Lender payout accounts (2026-06-17, branch `feature/lender-payout-accounts`)

Makes the borrower-payment-submission feature usable: lenders had no way to set
bank details, so the borrower's Submit dialog was permanently blocked. Stacked on
`feature/borrower-payment-submission` (PR #65). Spec/plan in `docs/superpowers/`.

- **Lender CRUD** — `lib/features/bank_details/`: `BankDetailsBloc` (Load/Add/Update/Delete over `BaseRepository<BankDetails>`, scoped to `authService.company.id` + `DataType.provider`). `PayoutAccountsSection` + `showBankDetailsFormDialog` rendered inside `SettingsWidget`, gated to a self-managed company admin (`hasCompany && userRole.index > customer && managementType == selfManaged`). Delete is **soft** (repo sets `deletedAt`; `load` filters `deleted_at == null`).
- **Multiple accounts**: lender can keep several; the borrower Submit dialog shows a dropdown when >1 (auto-selects when exactly 1), Send requires a selection. The chosen account id is recorded via new `Payment.paidToBankDetailsId` (`paid_to_bank_details_id`). Payment Center pending-submission card resolves it (`get(id)`, cached + hasError-guarded) → "Paid to: <bank> …<last4>".
- **GOTCHA**: the `bank_details` stored id field is **`dataId`** (camelCase — `BankDetailsEntity.dataId` has NO `@JsonKey`, unlike its snake_case siblings). Query `field: 'dataId'`, NOT `data_id`. The original submit dialog used `data_id` and silently matched nothing — fixed.
- **Firestore rule** (console-managed, deferred): a company admin may write `bank_details` where `dataId == their company` — tracked with the payments rule.

---

## Refactoring Plan

Full plan documented at: `~/.claude-personal/plans/tender-tickling-kahn.md`

### Phase 0: Quick Wins — COMPLETED

- Fixed `LoansState` Equatable `props` in `lib/features/loans/bloc/loans_state.dart`
- Fixed `ProductState` Equatable `props` in `lib/features/products/bloc/product_state.dart`
- Fixed `ReportsState` Equatable `props` in `lib/features/reports/bloc/reports_state.dart`
- Guarded service re-initialization in `lib/app/view/app.dart` redirect callback with `_initialized` flag
- Removed dead/commented-out code in `loans_functions.dart`, `product_state.dart`, `loans_state.dart`

### Phase 1: Extract Shared Utility Functions — COMPLETED

- **1A** — Created `lib/services/charge_calculator.dart` (charge/deduction calculation helper, percentage parsing)
  - Replaced 2 identical charge loops in `loans_bloc.dart`
  - Replaced 6 inline percentage parsers in `product_bloc.dart`
  - Replaced charge loop in `loans_bloc_extension_add_loan_amount.dart`
- **1B** — Created `lib/services/address_builder.dart`
  - Replaced inline address construction in `CompanyBloc`, `RegistrationBloc`, `UserBloc`, `AuthenticationBloc`
- **1C** — Created `lib/services/session_loader.dart`
  - Extracted ~75 duplicate lines from `initializeAuth()` and `_handleLoginEvent()` in `authentication_bloc.dart`

### Phase 2: Extract Loan Calculation Service — COMPLETED

- Created `lib/services/loan_calculation_service.dart` with `LoanCalculationResult`, `calculateFixedTerm()`, `calculateOpenTerm()`, `calculateLoanAmount()`
- Wired into `LoansBloc`, replaced mutable globals
- Deleted `lib/features/loans/bloc/loans_functions.dart`
- Deleted `lib/features/loans/bloc/loans_bloc_extension_calculate_loan_open.dart`
- Updated `reports_bloc_extension_soa.dart`

### Phase 3: Split `app_widgets.dart` — COMPLETED

- Split `lib/widgets/app_widgets.dart` (1,661 lines) into:
  - `lib/widgets/form_widgets.dart`
  - `lib/widgets/button_widgets.dart`
  - `lib/widgets/dialog_widgets.dart`
  - `lib/widgets/profile_widgets.dart`
  - `lib/widgets/notification_widgets.dart`
  - `lib/widgets/layout_widgets.dart`
- `app_widgets.dart` became a barrel file re-exporting all new files

### Phase 4: Split `app.dart` Routing & Providers — COMPLETED

- Created `lib/app/routing/router.dart`
- Created `lib/app/di/repository_providers.dart`
- Created `lib/app/di/bloc_providers.dart`
- Created `lib/app/view/alpha_banner.dart`
- Created `lib/app/theme.dart`
- Simplified `app.dart` to compose these pieces

### Phase 5: Break Up LoansBloc God Object — COMPLETED

- **5A** — Extracted `PaymentBloc` (`lib/features/loans/bloc/payment_bloc.dart`)
- **5B** — Extracted `LoanSettlementBloc` (`lib/features/loans/bloc/loan_settlement_bloc.dart`)
- **5C** — Extracted `AdditionalLoanBloc` (`lib/features/loans/bloc/additional_loan_bloc.dart`)
- **5D** — Slimmed down remaining `LoansBloc`, removed unused dependencies

### Phase 6: Split Giant UI Screens — COMPLETED

- **6A** — `loan_client_detail.dart` (1,947 lines) split into `lib/features/users/widget/client_detail/`
- **6B** — `add_product_screen.dart` (1,642 lines) split into `lib/features/products/widget/add_product/`
- **6C** — `add_user_widget.dart` (1,134 lines) split into `lib/features/users/widget/add_user/`
- **6E** — Remaining 700+ line screens split (`loan_application.dart`, `update_profile_screen.dart`, `loan_offer_detail.dart`)

### Phase 7: Move Notification Creation to Go Backend — COMPLETED

- **7A** — Created `triggers/notification_helpers.go` in Go backend with shared helpers
- **7B** — Modified `triggers/loan_changes.go` to create notification documents on loan status changes
- **7C** — Created `triggers/review_created.go` (Firestore trigger on reviews collection)
- **7D** — Created `triggers/payment_created.go` (Firestore trigger on payments collection)
- **7E** — Removed all notification creation calls from Flutter `loans_bloc.dart`
- **7F** — Slimmed `notification_service.dart` from 583 to ~140 lines (kept FCM token management + notification stream only)

### Phase 8: Reduce Singleton Coupling — COMPLETED

- All 9 BLoCs now accept `AuthenticationService` as a constructor parameter instead of using `.instance`
- `PaymentBloc` also accepts `SettingsService`
- `SessionLoader` updated to accept optional `AuthenticationService` and `DeviceService` parameters
- `NotificationService.instance` kept in `AuthenticationBloc` (justified by lifecycle ordering)

### Phase 9: Theme Consolidation — COMPLETED

- **9A** — Expanded `lib/app/theme.dart` with comprehensive Material 3 theme tokens:
  - `ColorScheme` with all brand colors mapped to semantic roles
  - `TextTheme` with Urbanist font at all standard sizes (displayLarge through labelSmall)
  - `InputDecorationTheme` matching form widget patterns
  - `FilledButtonThemeData` and `OutlinedButtonThemeData`
  - `DialogThemeData` with green background
  - `CardThemeData`, `ChipThemeData`, `ProgressIndicatorThemeData`
- **9B** — Added design token constants to `lib/utils/screen_helpers.dart`:
  - `AppSpacing` (xs, sm, md, lg, xl, xxl)
  - `AppTypography` (displayLarge through labelSmall font sizes)
- **9C** — Created `DESIGN.md` with full design system documentation

### Phase 10: Widget Theme Compliance — COMPLETED

Updated widget files to use theme values instead of hardcoded styling:

- **button_widgets.dart** — Removed `GoogleFonts.urbanist()` textStyle; buttons now inherit from theme
- **form_widgets.dart** — Replaced `GoogleFonts` with `TextStyle`, removed explicit dialog `backgroundColor`
- **dialog_widgets.dart** — Removed explicit `backgroundColor: AppColors.green1` from 4 dialogs; removed explicit `CircularProgressIndicator` color
- **display_widgets.dart** — Removed `GoogleFonts.urbanist()` from RichText
- **notification_widgets.dart** — Replaced `AppColors.white` with `colorScheme.surface`, replaced hardcoded `TextStyle` with theme text styles

---

## Bug Fixes (Post-Refactoring)

### google_fonts AssetManifest.json error

- **Symptom:** `google_fonts was unable to load font Urbanist-Regular` / `Unable to load asset: 'AssetManifest.json'`
- **Cause:** Build cache corruption
- **Fix:** `fvm flutter clean && fvm flutter pub get`

### Loan offer selection UI bugs (3 related issues)

- **Symptom 1:** Draggable sheet bounces down and back up when selecting a different loan offer
- **Symptom 2:** Background color of loan detail doesn't match the selected item's color
- **Symptom 3:** Selected indicator (white border) not showing on the loan offer item
- **Root cause:** Non-admin `BlocListener` in `loan_offers_widget.dart` always navigated via GoRouter on product selection, causing `MainScreen` to rebuild (resetting sheet position, `_selectedColor`, and `_selectedIndex`)
- **Fix in `loan_offers_widget.dart` (line 80-84):** Wrapped GoRouter navigation in `if (isCompactOrMedium)` so desktop doesn't navigate on product selection
- **Fix in `loan_offer_item.dart`:** Added `didUpdateWidget` override to sync internal `_selectedState` with parent's `widget.selected` prop

### Selection delay when switching loan offer items

- **Symptom:** ~1 second delay before the newly selected item appears selected
- **Root cause:** Grid's `BlocBuilder.buildWhen` didn't include `ProductStatus.loading`, so the old item didn't visually deselect until the BLoC finished network calls
- **Fix in `loan_offers_widget.dart` (line 310-317):** Added `ProductStatus.loading` to the grid's `buildWhen` list

### Progressive loading for loan offer detail

- **Symptom:** Entire detail panel waited for reviews to load before showing anything
- **Root cause:** `_handleSelectProductEvent` in `product_bloc.dart` loaded product + reviews sequentially before emitting `selected`
- **Fix in `product_bloc.dart` (lines 738-772):** Restructured to emit `selected` immediately after product/charges/deductions are ready, then load reviews in background and emit `ProductState.refresh()` when done
- **Fix in `loan_offer_detail.dart`:** Wrapped `_reviews()` and `_compactBody()` methods in `BlocBuilder<ProductBloc, ProductState>` with `buildWhen` for `ProductStatus.selected` and `ProductStatus.refresh`, so reviews populate asynchronously

### Wrong principal balance for consecutive additional loans (Issue #4)

- **Symptom:** Adding 2+ additional loans to an open-term loan showed the same (wrong) principal balance for all
- **Root cause 1 (stale UI):** `BlocListener<AdditionalLoanBloc>` success handler in `loan_client_detail.dart` didn't call `selectLoan()` to refresh loan data after a successful additional loan
- **Fix:** Added `loansBloc.selectLoan()` call before popping the dialog
- **Root cause 2 (double-counted OB):** `_handleAddLoanAmountEvent` in `additional_loan_bloc.dart` mutated the last Firestore schedule's `outstandingBalance += totalAmount`, but `calculateOpenTerm` already adds additional loan amounts in its dedicated loop
- **Fix:** Removed the `Future.microtask` block that updated the schedule's OB; also removed unused `LoanScheduleRepository` dependency
- **Root cause 3 (wrong processing order):** `loan.additionalLoanAmounts` was iterated in reverse chronological order (newest first), causing older loans to pick up inflated OB values and overwrite newer schedules
- **Fix in `loan_calculation_service.dart`:** Added `sortedBy((a) => a.createdAt)` before the `for` loop
- **PR:** #33

---

## Completed Work (continued)

### SMS OTP Payment Verification (Issue #66) — 2026-02-18

**Status:** Implemented. Pending deployment and testing.

**Approach:** Uses a dedicated Android device as SMS gateway, Firebase RTDB as message queue. Avoids telco registration.

**Flutter changes:**
- `authentication_bloc.dart` — Added `_otpToken` field, `_handleVerifyOtpEvent` now uses stored token (hash) instead of userId to read OTP from RTDB
- `user_network_service.dart` — Added `requestOtpForUser()` and `verifyPaymentOtp()` methods
- `user_repository.dart` — Added proxy methods for the above
- `payment_event.dart` — Added `RequestPaymentOtpEvent`, `VerifyPaymentOtpEvent`, and `otpVerified` flag on `PayLoanScheduleEvent`
- `payment_state.dart` — Added `otpRequested`, `otpVerified` statuses + `token`, `expireAt` fields
- `payment_bloc.dart` — Added `UserRepository` dependency, OTP request/verify handlers, `otpVerified` branch in payment handler with SMS OTP audit comment
- `payment_otp_dialog.dart` — **New** widget: loading spinner, 6-digit input, countdown timer, verify/resend/cancel buttons
- `client_detail_dialogs.dart` — Uncommented "thru Mobile OTP" button, implemented mobile-otp branch with OTP dialog + cash pool reminder

**Key architecture:**
- Teller requests OTP → Go backend writes to RTDB `otp/{hash}` with `sms_status: "pending"`
- Android gateway listens for pending entries, sends SMS, updates status to "sent"
- Borrower enters code on teller's device → Flutter verifies via `verifyPaymentOtp` endpoint
- Payment recorded with SMS OTP audit trail

**Note:** `verifyPaymentOtp` Flutter URL is `$LOOOANS_BASE_API_URL/users/verify/payment-otp` — ensure API routing matches Go function entry point.

---

## SMS OTP Payment Fix (PR #38) — 2026-03-11

**Issue:** OTP-verified payments did not create a payment document. Schedule was not marked as paid.

**Root cause:** `Payment.create()` factory requires proof (`transactionPhotoUrl` or `autoCollectRef`) unless `bypassPaymentProof` is `true`. The OTP path passed `bypassPaymentProof: event.force` (false), so it threw. Exception was caught silently.

**Fixes applied:**
- `payment_bloc.dart` — `bypassPaymentProof: event.force || event.otpVerified`
- `payment_bloc.dart` — OTP audit comment now fetches borrower via `userRepository.get(id: loan.userId)` and logs their details; teller recorded as `processed_by`
- `payment_otp_dialog.dart` — Added `SizedBox(height: 8)` between action buttons
- `database.rules.json` — Comprehensive RTDB rules for all paths (otp, sessions, reports, loans, gateway_status, force_logout). Split into dev-stg and prod files.
- `firebase.json` — Wired `database.rules.json` for `firebase deploy --only database`
- `database.rules.prod.json` — Separate prod rules (no `dev/`/`stg/` prefixes). Deploy manually with `firebase database:rules:set`.
- `docs/DATA_FLOW.md` — Added payment verification methods table
- `docs/ERD.md` — Added Payment entity field descriptions
- `apps/loans/README.md` — Added RTDB rules deployment instructions

**RTDB rules deployed to `loooans-dev-stg`**. Production pending.

**Issue #66 (Borrower acknowledgement) closed.**

---

## Payment Center Feature (Issue #11) — 2026-03-19

**Status:** Implemented. Pending manual testing.

**What:** Unified Payment Center — a standalone screen where tellers can search for a borrower, view all their loans (including add-on loans), and make payments directly without navigating to individual loan detail screens.

**Files created (11):**
- `features/payment_center/bloc/payment_center_bloc.dart` — Standalone BLoC handling search, loan loading, payment processing, OTP
- `features/payment_center/bloc/payment_center_event.dart` — Events (search, select, expand, pay, OTP)
- `features/payment_center/bloc/payment_center_state.dart` — State with status enum + copyWith
- `features/payment_center/model/borrower_loan_group.dart` — Groups parent Loan with children and actionable schedules
- `features/payment_center/screen/payment_center_screen.dart` — Main screen with search + two-section loan list
- `features/payment_center/widget/borrower_search_widget.dart` — TypeAhead search for borrowers
- `features/payment_center/widget/borrower_loan_section.dart` — Section A: borrower's loans with actions
- `features/payment_center/widget/co_maker_loan_section.dart` — Section B: read-only co-maker loans
- `features/payment_center/widget/loan_card_widget.dart` — Expandable loan card with inline payables
- `features/payment_center/widget/payable_tile_widget.dart` — Single payable row with Pay button
- `features/payment_center/widget/payment_center_dialogs.dart` — Payment dialog + OTP dialog (adapted from client_detail_dialogs)

**Files modified (4):**
- `app/routing/paths.dart` — Added `paymentCenter` path
- `app/routing/router.dart` — Added GoRoute inside ShellRoute
- `app/di/bloc_providers.dart` — Registered PaymentCenterBloc
- `utils/constants.dart` — Added menu item (teller + admin only)

**Key architecture decisions:**
- Standalone BLoC — does not depend on LoansBloc, PaymentBloc, or existing payment dialog
- Payment logic replicated from PaymentBloc (signature/OTP/force paths, cash pool deduction)
- Reuses existing dialogs: `showSettleAccountDialog`, `showSignatureDialog` from client_detail_dialogs
- Loans grouped by parent/child relationship with actionable schedules (overdue + next upcoming)
- Auto-refreshes after payment via `RefreshBorrowerDataEvent`

---

## Pending Work

**Subtask #67 (take photo + signature before payment):** Verified FULLY IMPLEMENTED — signature pad, selfie capture, Cloud Storage upload, integrated into payment and additional loan flows.

### SMS OTP — Remaining items
- Deploy RTDB rules to `loooans-prod` when ready
- Extend SMS OTP to additional loan flow (future)

---

## Key Notes

- Always use `fvm flutter` (not plain `flutter`) — project uses FVM with Flutter 3.38.4
- Run `fvm flutter analyze` after changes to verify no errors
- Pre-existing info/warning issues exist (deprecated `withOpacity`, TODO style, `reassemble` usage) — not introduced by this work
- The Go backend is at `loooans/go/loooans_cloud_functions/`
- Three Firebase flavors: development, staging (`loooans-dev-stg`), production (`loooans-prod`)
- Design system documented in `DESIGN.md`; theme tokens defined in `lib/app/theme.dart`
- Prefer using theme values (`Theme.of(context).colorScheme`, `Theme.of(context).textTheme`) over hardcoded `AppColors` and `GoogleFonts` in widgets

---

## Mobile Number Verification UI (issue #13)

- New `MobileVerificationScreen` at `Paths.mobileVerification` reused by login gate and post-profile-edit re-verify.
- 4-minute resend cooldown; OTP expiry stays at 5 minutes (existing backend behavior). `AuthenticationState.requestOtp` now carries a `canResendAt: DateTime` for the screen's countdown.
- `LoginScreen` no longer hosts OTP dialogs — replaced by `GoRouter.of(context).go(Paths.mobileVerification)`. The dormant `aiVerified` branch and `VerifyWidget` were deleted.
- `AuthenticationBloc._checkUserVerificationStatus` now actually checks `(user.verificationStatus & UserVerificationStatus.mobileNumberVerified.value) == 0`. The bloc's verify path now calls backend `UserRepository.verifyOtp` instead of client-side RTDB compare.
- Profile widget shows ✓ icon when verified; "Verify" CTA when unverified. Update-profile mobile field is disabled with "Editable in N days" while inside the 90-day window.
- After a profile mobile-number change saves successfully, `UserBloc` emits `UserState.requireMobileVerify`, and `UpdateProfileScreen` routes to `Paths.mobileVerification`.
- Follow-up #134 covers `bloc_test` and widget tests (deferred — `AuthenticationBloc` currently uses `AuthenticationService.instance` singleton and takes `BuildContext` directly; testable refactor is part of the same issue).

---

## DateTime fields — helpers expect millis (PR #47)

`handleDateTimeFromJson` and `handleDateTimeNullableFromJson` in `loooans_helpers/data_helpers/constants.dart` accept either a `num` (millis since epoch — the codebase convention) or a Firestore `Timestamp` (duck-typed via `.toDate()` to avoid a cloud_firestore dependency in `loooans_helpers`). New entities should keep using these helpers via `@JsonKey(fromJson: handleDateTimeNullableFromJson, toJson: handleDateTimeToJson)`.

If a `TypeError: Instance of 'Timestamp' is not a subtype of type 'num'` ever surfaces again, the culprit is a backend producer that wrote a raw `time.Time` instead of `.UnixMilli()` — fix it at the producer. The Flutter helper's tolerance is defensive, not a license to store Timestamps deliberately.

---

## Flutter 3.38.4 → 3.44.0 upgrade (issue #46, 2026-05-25)

Bumped the project to the latest stable Flutter. Branch: `chore/flutter-3.44-upgrade`.

**Required toolchain bumps** (driven by plugins Flutter 3.44 pulls in):
- AGP `8.7.2` → `8.11.1` (`android/settings.gradle`)
- Kotlin `1.9.20` → `2.2.20` (settings.gradle + `kotlin-stdlib-jdk7` in app/build.gradle)
- Gradle wrapper `8.9` → `8.14.3`
- `compileSdk`/`targetSdk` `34` → `36`
- Java source/target `1_8` → `17`, `jvmTarget` `1.8` → `17` (Java 8 is "obsolete" warning otherwise)
- `org.gradle.jvmargs` `1536M` → `4096M` (Jetifier OOM during dex transforms — the same gotcha noted in root memory; 2048M wasn't enough at this point, used 4096M)
- Flutter 3.44 auto-added migration shims: `android.builtInKotlin=false`, `android.newDsl=false` in `gradle.properties` — keep these.

**Real bugs surfaced and fixed:**
- `scripts/bump_version.sh` used millis-since-epoch as the build number (`$(date +%s%N)/1000000`) → 13-digit values like `1778731308889` overflow Android's `Int` `versionCode` (max ~2.1B). Old AGP silently truncated; new toolchain throws `For input string: "..."`. Switched to `date +%s` (seconds, ~10 digits, fits until 2038). Also re-bumped `pubspec.yaml` to a valid current value.
- `packages/core/storage_repository` had `sdk: ">=2.18.0 <3.0.0"` — impossibly restrictive vs Dart 3. Latent bug pub had been tolerating. Widened to `>=3.0.0 <4.0.0`.

**Codemod:** 54 `.withOpacity(x)` call sites → `.withValues(alpha: x)` across `lib/` (deprecated in Flutter 3.27+, will become an error in a future release). Pure syntactic substitution.

**Build verification:**
- Web build ✅, Android debug APK ✅, analyzer 0 errors (132 infos/warnings, all pre-existing)
- iOS not verified locally (no CocoaPods on this machine); plugin versions changed so `Podfile.lock` will need refreshing on a Mac.
- 2 package tests fail (`address_repository`, `bank_details_repository`) — confirmed pre-existing on `develop`, scaffold tests that construct Firestore-backed repos without `Firebase.initializeApp()`.

**Known follow-ups (not in this PR):**
- KGP → Built-in Kotlin migration: 5 plugins still use KGP (camera_android_camerax, device_info_plus, firebase_remote_config, package_info_plus, shared_preferences_android). Future Flutter releases will fail if KGP is still in use — plugin updates needed.
- SPM (Swift Package Manager) for iOS plugins: `printing`, `flutter_keyboard_visibility`, `flutter_local_notifications` — future-deprecation warning.
- Wasm dry-run flags incompatibilities in `image` package + `flutter_keyboard_visibility_web` (`dart:html`) — only affects wasm builds, not the default JS build.

CI workflows auto-extract the Flutter version from `apps/loans/.fvmrc` — no workflow edits needed.

### iOS migration (same PR, after CocoaPods became available)

- `ios/Podfile` platform uncommented and set to `iOS 13.0` (Flutter 3.44 rejects iOS 12 minimum).
- `IPHONEOS_DEPLOYMENT_TARGET` bumped 12.0 → 13.0 across all 9 flavor/build-type combinations in `Runner.xcodeproj/project.pbxproj`.
- Flutter auto-migrated:
  - **UIScene lifecycle**: `AppDelegate.swift` now uses `@main` + `FlutterImplicitEngineDelegate`, plugins register via `didInitializeImplicitFlutterEngine`. `Info.plist` gained `UIApplicationSceneManifest`.
  - `.gitignore` adds `.build/`, `.swiftpm/`.
  - `AppFrameworkInfo.plist` drops stale `MinimumOSVersion 11.0`.
  - `Runner.xcscheme` LastUpgradeVersion 1430 → 1510.
- `Podfile.lock` now tracked. Only 3 cocoapods remain (`flutter_keyboard_visibility`, `flutter_local_notifications`, `printing` — the non-SPM plugins) plus the `Flutter` runtime. Everything else (Firebase, AppCheck, etc.) moved to Swift Package Manager.

### SPM is enabled — repo moved to a no-space path

Flutter 3.44 auto-enables Swift Package Manager. Initially that **broke on the old project path** (`/Users/.../Anaheim Technologies/...`): Flutter URL-encodes the path when locating `pubspec.yaml` for SPM Package.swift, producing `%20` which never resolves to a real file. The repo was relocated to `/Users/deibeeed/Projects/AnaheimTechnologies/finstack` (no space) and SPM auto-integration now succeeds.

What SPM integration added when it succeeded:
- `Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` and `Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved` — SPM's lockfile equivalent. Tracked in git.
- `<PreActions>` block on each flavor xcscheme (`development`, `staging`, `production`) running `$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh prepare` before Xcode build. Generated per-flavor by `flutter build ios` — if you add a new flavor, run a build once to populate.
- `Podfile.lock` dropped from 1682 lines to 33 once SPM took over the bulk of dependencies.

The 3 plugins that don't yet support SPM still pull in via CocoaPods; both managers coexist transparently. `pod install` runs in <1 second after the first build because there's so little for it to do.

Future-Flutter warning: "Disabling Swift Package Manager will not be allowed in a future version of Flutter" — so this stays on, no caveat. If a future plugin or dependency needs the repo path to not have spaces again, keep it that way.

---

## Borrower Payment Submission — Flutter side (branch `feature/borrower-payment-submission`, finstack #64)

Borrowers can now submit their own payment proof for confirmation, instead of only tellers recording payments in the Payment Center.

- **`PaymentStatus` lifecycle** (`packages/loans/payment_repository`): `pending` / `confirmed` / `rejected`. `@JsonKey(defaultValue: PaymentStatus.confirmed)` so legacy + teller-created docs (no `status` field) deserialize as `confirmed` — no migration needed. Borrower submissions start `pending`; teller/force/OTP paths stay `confirmed`.
- **`submission_id` grouping**: Pay-in-full spans multiple schedules → all the payments from one submit share a single `submission_id`. Lets the Payment Center group a multi-schedule submission as one reviewable unit and lets the Go `paymentCreated` trigger de-dup lender notifications per submission.
- **`PaymentSubmissionBloc`** (`lib/features/payments/bloc/`) + submit dialog (`lib/features/payments/widget/`): borrower picks the lender's payout account (bank details via `BankDetailsRepository` filtered to `DataType.provider`), uploads a transaction screenshot, and the bloc writes one `pending` `Payment` per selected schedule. Open-term schedules carry `id == NO_ID` at submit time → payment is added first, then the schedule, then the payment is backfilled with the real `loan_schedule_id`. Schedules are flipped to `LoanStatus.payment_submitted`.
- **Payment Center pending-submissions**: tellers confirm/reject pending borrower submissions, reusing `PaymentConfirmationService` (same confirm/reject path that flips schedule status and writes `confirmed_by` / `confirmed_at` / `rejection_reason`). Covered by `test/features/payment_center/payment_center_confirm_test.dart`.
- **`loan_id` denormalized onto `Payment`** (`payment_entity.dart` / `payment.dart` `Payment.create(loanId:)`): every creation site now writes the real loan id directly on the payment. Needed because open-term payments are created with `loan_schedule_id = NO_ID`, so the Go trigger's schedule fallback can't resolve the loan at creation time — `loan_id` makes lender notification work for all loan types. Wired at all three `Payment.create` sites: borrower `PaymentSubmissionBloc._onSubmit` (`loanId: event.loanId`), teller `PaymentCenterBloc._handleMakePaymentEvent` and `_handleMakeOverduePaymentEvent` (`loanId: loan.id` + explicit `status: PaymentStatus.confirmed` for intent clarity — default was already confirmed, no behavior change).
- **DEFERRED**: the Firestore security rule for *who* may write/confirm payments (borrower may create `pending`; only teller/admin may move to `confirmed`/`rejected`) is still managed in the console, not in repo rules. Close this before relying on the rule for authorization.

---

## Server-side user provisioning — Phase C (frontend) — branch `feat/user-provisioning-frontend` → PR closes finstack #69

Phase C is the Flutter half of moving admin-initiated user creation server-side (Phase A=PR #70 backend, B=PR #72 hosting — both merged + deployed to dev). It fixes finstack #2 properly (an admin adding a user no longer client-side-mints an account / replaces the admin session) and supersedes #69. Spec/plan in `docs/superpowers/`. Delivered in 4 groups (G1–G4), each via implement→spec-review→quality-review.

- **G1 — data layer** (`packages/core/user_repository`): `UserNetworkService`/`UserRepository.createUser({role, user, address, idToken}) → ({uid, inviteSent})` (POST `/api/users/add`) + `sendPasswordSetupLink({email})` (POST `/api/users/password/setup-link`, unauth); dropped the unused `createUserAccess`. New `User.createInvited({required role, ...})` factory (uid-less `NO_ID`, email required, photos optional). Surfaced `invited_by_admin` on `UserEntity` (the server-stamped flag) + regenerated `.g.dart`.
- **G2/G3 — the "admin adds a user" rework** (`RegistrationBloc` + form + entries): new `SubmitInvitedUserEvent` + server-backed `_handleSubmitInvitedUser` (uploads optional photos, `User.createInvited`, calls `userRepository.createUser(role: role.name, ...)`); `registerInvitedUser(data, {role})` replaces the old `registerManagedUser`/managed handler. `RegisterScreenFormUsersWidget` now carries `isAdminCreating` + `isTeamMemberMode` (replacing `isUserCompanyManaged`): email always required; password/facebook/selfie/profile-pic-required only for self-registration; a staff role picker (`UserRole.companyManagedRoles`) in team-member mode. **Two entries:** "Add team member" (users_screen; both company types) routes through the new path; "Add Borrower" (borrowers_screen + layout_widgets) gated on `allowAddClients` (selfManaged only). Added `RegistrationBloc.withDependencies` seam (widens `_companyRepository`/`_addressRepository` to `BaseRepository<T>` — the concrete classes are `final` → unmockable). **Key fix found mid-build:** the old "Add User" entry passed `forCompanyUser: true`, routing to `RegisterScreenFormProvidersWidget`→`registerProvider`→client-side `createUserCredential` (temp pw `Password123!`) — i.e. bug #2 for staff too; flipped to the server path. Self-registration and provider self-signup left untouched.

Three commits on the dead-code/resend-invite/forgot-password slice (G4):

- **C8 — `refactor: remove dead user-creation paths` (89ef8fc)**: deleted the now-unused client-side user-creation paths — `UserBloc.addUser` / `AddUserEvent` / `_handleAddUserEvent`, the `User.createManagedCustomer` factory (shared package `packages/core/user_repository`), and the dead `forCompanyUser` branch + param in `showAddUserWidget` (`dialog_widgets.dart` + `app_widgets.dart`), collapsing it to the `AddUserWidget` path. Removed the now-unused `extensions.dart` / `string_helpers.dart` / `RegisterScreenFormProvidersWidget` imports. Provider self-registration and the `registerCompanyManagedUser` machinery left fully intact (now dead-but-harmless, follow-up).
- **C9 — `feat(users): admin Resend invite action` (d23350b)**: `UserBloc.resendInvite` + `ResendInviteEvent` + handler calling `sendPasswordSetupLink`, emitting `UserState.success("Invite re-sent.")` / `error`. UI: a per-row "Resend invite" `IconButton` on the **Users screen** (`lib/features/users/screens/users_screen.dart`, the compact/medium team-member ListView rows) gated to team managers (`_canResendInvite`) with a non-empty target email, plus a `BlocListener<UserBloc, UserState>` SnackBar. (Chose `users_screen.dart` over `client_detail_action_buttons.dart` — the latter is loan-scoped, not a per-user panel.)
- **C10 — `feat(auth): login Forgot password (set/reset link)` (555dee0)**: `AuthenticationBloc.forgotPassword` + `ForgotPasswordEvent` + handler that calls `sendPasswordSetupLink` and emits the SAME neutral `success` message on both happy + error paths (never leaks whether the account exists). Login screen: small email-prompt `AlertDialog` (`_showForgotPasswordDialog`) dispatches it; the `BlocConsumer` success branch now shows the neutral message **inline as a SnackBar when `AuthenticationService.instance.isLoggedIn == false`** (forgot-password) and only navigates on a real login — preserving normal login-success routing.

### Test-seam pattern note (important)
Added `UserBloc.withDependencies` and `AuthenticationBloc.withDependencies` mirroring `RegistrationBloc.withDependencies`. Gotcha: `AddressRepository`, `CompanyRepository`, `SettingsRepository`, `UserLoanViewRepository` are all `final class` → **cannot be mocked with mocktail** (`invalid_use_of_type_outside_library`). Where the bloc only calls `BaseRepository` methods on one (e.g. `UserLoanViewRepository`, unused in `UserBloc`), the seam types it as `BaseRepository<T>` so it IS mockable. Where the bloc calls a concrete method (`AddressRepository.getByDataType`, or passes the repo into `SessionLoader.loadSession` which needs concrete types), the field stays concrete but the seam makes it an **optional nullable param** (guarded with `!` at the real call sites, which the resend-invite/forgot-password tests never reach). The default `BuildContext` ctors are unchanged → production behavior identical.

- Tests: `test/features/users/user_bloc_resend_invite_test.dart` (success + error), `test/features/authentication/authentication_bloc_forgot_password_test.dart` (success + error-still-neutral). All pass.
- `fvm flutter analyze` (whole app): zero net-new issues vs the pre-work baseline (6224 before == 6224 after, line-number-normalized diff empty).
- Still console-managed before prod: nothing new here, but the password-setup-link backend (Phase A, PR #70) must be deployed for these flows to actually deliver email.

---

## Notification permission no longer blocks startup (branch `fix/notification-permission-blocking-startup`)

Found during the chat dev smoke test (2026-07-09): the deployed dev web app rendered a **blank page indefinitely** because `bootstrap()` did `await requestPermissions()` **before `runApp()`** — the whole app waited on the browser's notification-permission prompt. Additionally, `requestPermissions()` recursed on any non-authorized status; since browsers won't re-show the prompt after an explicit deny, a denial spun a permanent `getNotificationSettings`/`requestPermission` busy-loop.

- Fix in `lib/bootstrap.dart`: `runApp()` first, then `unawaited(requestPermissions())`; the request only fires when `authorizationStatus == notDetermined` (never re-prompts on denial).
- Timing note: on web, FCM `getToken` needs granted permission — and with a restored session, `NotificationService.initializeToken()` (router init, right after `runApp`) can now run while the prompt is still pending. On web the JS SDK's `getToken` awaits the same prompt and REJECTS (`messaging/permission-blocked`) on denial; the `.then` chain had no error handler, so review hardening added a `catchError` that logs instead of surfacing an unhandled async rejection (no token on denial is correct).
- Drive-by in the same file: `print` → `debugPrint` in `showFlutterNotification` (pre-existing `avoid_print` from monorepo-genesis commit `275ad55`).

---

## Chat blocs never received data — dataStream subscribed before loadNext (branch `fix/chat-dead-stream-subscription`)

Caught by the dev smoke test (2026-07-09), right after the startup fix unblocked the UI: the Messages screen body stayed blank forever — the inbox query's results never reached the bloc. (The orphaned query itself still opened a Firestore listener — `addStream` subscribes its source regardless of controller listeners — the data just poured into a controller nobody was listening to.)

- **Cause:** in the chat services, **every** `loadNext` call (the `reset` flag is ignored there) runs `resetStreamController()`, which **replaces** the controller behind `dataStream`. `ConversationsBloc` and `ChatBloc` subscribed to `dataStream` in their constructors and called `loadNext` afterwards — leaving their subscriptions on the old, dead controller. Inbox and chat-room messages could never load. Working blocs (LoansBloc/ProductBloc) don't hit this because they expose `dataStream` as a getter consumed at widget build time; the loans-style services also gate their resets on `switchStream`, not `reset`.
- **Why tests missed it:** the bloc tests mocked the repository with a fixed stream and stubbed `loadNext` — the reset never happens under mocks. Beware of this pattern generally: any bloc that `.listen()`s a repo `dataStream` before calling `loadNext` is broken in production and green under mocktail. **Regression tests now exist** (`_ResettingFakeRepo` / `_ResettingFakeMessages` in the chat bloc tests) — the fakes swap their controller on `loadNext` like the real service.
- **Fix (after adversarial review of the first cut):** in both chat blocs, `_onSubscribe` is fully synchronous — `if (isClosed) return` guard (bloc 8.1.4's default transformer is CONCURRENT and `close()` drains pending events), then cancel-old-sub → `loadNext` → listen, in one turn. Chat services now hold their query subscription (`_querySub`) and cancel it on every `loadNext` + expose `dispose()` (called from `ChatBloc.close()`, since `MessageRepository` is per-room) — the chat-side listener leak is gone. `ConversationsScreen` no longer re-dispatches Subscribe in `initState` (the bloc auto-subscribes). The `/chat/:roomId` route is keyed by `roomId` — go_router reuses the page element on param-only changes (`/chat/A → /chat/B`, exactly what the FCM chat-tap does), which would otherwise keep room A's bloc alive and send messages to the wrong room. Inbox row: "Awaiting" chip moved to the subtitle line (the trailing stack overflowed 28px).
- **Follow-up worth filing:** the same abandon-the-controller-mid-addStream leak exists in the ~20 loans-style services (gated on `switchStream` there). A base-level `pipe()` helper in `BaseFirestoreService` that holds and cancels the source subscription would fix the class; chat services demonstrate the shape.

---

## OTP error surfacing — passthrough narrowed, verifyOtp covered, tests wired to CI (branch `feature/otp-error-surfacing`, finstack #91, 2026-08-12)

The Go OTP endpoints return 400s written for end users; this branch surfaces them instead of a generic "Cannot request OTP". An independent review found the first implementation leaked internals and broke a payment flow:

- **The 4xx window was too wide.** `userMessage` echoed any `400-499` body, but `ValidateRequestV2` runs *before* any OTP logic and emits **401** with raw Go/Firebase SDK text — including `firebase admin initialization error: google: could not find default credentials...` — plus a bare `Unauthorized` for the common expired-token case. All of it rendered verbatim in user snackbars. **Only 400 is passed through now**; 401 maps to a sign-in prompt, everything else to a generic message.
- **`verifyOtp` had the same bug one method away**, still throwing a raw `HttpException` that surfaced as `Cannot verify OTP: HttpException: Verify OTP error: 400 OTP expired`. Both endpoints now share an `OtpApiException` base (`RequestOtpException`, `VerifyOtpException`), exported from `user_repository`.
- **`userMessageOr(fallback)`** lets each flow keep its own wording. The first implementation retired the payment flows' `'Failed to send OTP'` for the auth flow's copy on every HTTP failure, including 5xx.
- **`PaymentCenterStatus.otpError` (new)**: OTP failures previously emitted `PaymentCenterStatus.error`, and `payment_center_screen.dart` pops the topmost **root** route on `error`. During the OTP step that route is the OTP dialog itself (`showDialog(barrierDismissible: false)`, default `useRootNavigator: true`, `initState` dispatches `RequestOtpEvent`), so the dialog was popped, resolved `null`, and the caller abandoned the payment — the actionable message tore down the flow it was explaining how to fix. It also removed a duplicate snackbar, since both listeners reacted to `error`. **Do not route recoverable OTP failures through `error`.** (This was pre-existing on `develop`, not introduced by the branch.)
- Expected 4xx rejections log at `warning`, not `severe`.

### Test seams and CI

- **`PaymentBloc.withDependencies` / `PaymentCenterBloc.withDependencies`** added, mirroring `AuthenticationBloc`/`RegistrationBloc`. Neither bloc could be constructed without a `BuildContext`, so neither had *any* test. `cashPoolRepository`, `productRepository` (final classes — unmockable) and `settingsService` (`SettingsService.instance` throws until app init) are optional and `late`, so a test that reaches a handler needing them fails loudly rather than using a stand-in.
- **No workflow ran `flutter test` before this branch** — the green checks proved only that the web build compiled. `loans-app-development.yml` now gates on package + app tests. See root `MEMORY.md` for the codegen-ordering constraint and the two deleted scaffold tests.

---

## Chat inbox: rooms are labelled with what they are about (2026-08-20)

Three conversations with the same lender rendered identically — counterpart name
plus last-message preview — so a loan enquiry, a product enquiry and a second
product enquiry were indistinguishable.

**The anchor already existed.** Rooms carry `context_type`/`context_id`, set at
all three creation sites (`'product'` + productId from the offer detail,
`'loan'` + loan.id from the borrower loan detail and the staff client detail),
and the anchor is **part of the dedup key** (`roomMatchesAnchor`) — which is why
separate rooms exist per product in the first place. The inbox simply never read
those fields (`conversations_screen.dart` built each row from
`participant.display_name` + `last_message.text` only).

**What changed:**
- New `context_label` on the room: the anchor's `loanType`, denormalized at
  creation so the inbox can name a room without a second fetch. Same snapshot
  trade-off as `participant.display_name` — never refreshed if the product is
  renamed.
- Inbox pill (`contextPillText`): the label when present, else a human name for
  the kind (`Loan`/`Offer`), else no line. Pre-`context_label` rooms therefore
  degrade to the type rather than showing nothing.
- Room screen gained the anchor line under the counterpart name, rendered bare
  (the label already leads with its kind) — spec §8.2 called for this context
  chip and it was silently dropped during planning (absent from both plans'
  coverage checklists AND from the explicit deferred list).

**`context_label` is deliberately NOT in the dedup key.** If `roomMatchesAnchor`
compared it, a renamed product — or any label drift between two clients — would
fork a second room against the same anchor instead of reusing the conversation.
Guarded by a test.

**Backfill on reuse — fire-and-forget, and a surgical write.** `findOrCreate`
returns an existing room without writing, so rooms created before this change
would keep the generic pill *forever*. It now writes the label on the first
reuse. Two constraints, both learned the hard way in review:

- **Never awaited, never allowed to throw** (`unawaited(...).catchError`). This
  sits on the "Message lender"/"Message borrower" hot path, and no call site
  wraps it in a try/catch. Awaiting a rejected write — denied rules, offline —
  made the button do nothing at all, *permanently*: an unwritten label leaves
  the guard true, so every retry re-attempts the same failing write. A missing
  label costs a generic pill; a thrown one costs the conversation.
- **`setContextLabel`, NOT the generic `update()`**, because the inbox orders by
  `updated_at desc` — bumping that timestamp would float every backfilled room
  to the top of every member's inbox. `update()` sets `updatedAt` on every call.

`context_label` was also added to the service's protected-field list, so a
full-entity client `update()` can't erase a stored label with a stale null.

**TRAP — `ChatRoomEntity.toChatRoom()` copies field-by-field.** A new field that
is not added there is written to Firestore correctly and then dropped on the way
to the UI, because rooms reach widgets as `ChatRoom`, never as the entity. This
version of the feature was briefly a silent no-op for exactly that reason, and
every widget test still passed — they build `ChatRoom.create` directly and never
round-trip through Firestore. Same shape as the dead-stream-subscription bug
above: green under test doubles, blank in the running app. Regression test:
`toChatRoom carries context_label`. **When adding a room field, update the
entity, `create`, AND `toChatRoom`** — `toChatRoom` is the one that actually
bites, because rooms reach widgets as `ChatRoom`.

**`props` is inert repo-wide — do not rely on it.** `BaseEntity` *implements*
Equatable rather than extending it (`base_entity.dart:7`) and no entity defines
`operator ==`, so every entity uses Object identity equality and the `props`
list is never consulted. Two consequences: two byte-identical rooms compare
unequal, and `buildWhen: (a, b) => a.room != b.room`
(`chat_room_screen.dart`) is always true, so it suppresses nothing. Keep `props`
updated for consistency, but a `.distinct()` or a `buildWhen` written against
entity equality will silently no-op.

**Codegen is per-checkout, and `.g.dart` is gitignored — so it does NOT follow
you across branches.** Running `packages/build_models.sh` while on a branch
without this field regenerated `chat_room_entity.g.dart` without
`context_label`; switching back to the feature branch left that stale file in
place, and the two round-trip tests failed with the field apparently missing.
Regenerate after ANY branch switch that changes a model, and re-read the
`.g.dart` before believing a serialization failure.

**Constraint worth knowing:** neither `ProductView` nor `Product` has a name or
title field — `loanType` is the best human-readable label available at the
product entry point. It is **free text** (`product_entity.dart:74
`late String loanType`), not an enum: `CommonProducts` only supplies three
suggested labels plus an "others" path. Dev data holds four distinct values
("Business loan", "Open Term Loan", "Personal loan open", "Fix - OneRequirement")
with no collisions, but two products from one company COULD share a label and
their rooms would stay ambiguous. If that shows up, compose the label from
`term`/`interestRate`/`maxLoanableAmount`, which `ProductView` already carries.
**Row layout: the anchor gets its OWN LINE, and do not flex the tags.** The row
is three lines — counterpart, anchor label, preview (with the staff "Awaiting"
tag on the preview line). An earlier cut put the label inline and wrapped the
tags in `Flexible`, which is backwards: **a flexible child is CAPPED at
`spacePerFlex * flex`**, so giving the preview `flex: 3` gave the *preview* more
room and squeezed the label to **17px at 320dp / 34.6px at 390dp against a 140px
natural width** — about one glyph. Nothing overflowed, so nothing failed.

**A "no overflow" test cannot catch that.** With every child `Flexible` a
RenderFlex overflow is impossible by construction, and `find.text()` matches the
widget's `data`, not painted glyphs — so the test passed while the label was
unreadable. Assert **rendered width** instead
(`tester.getSize(find.text(...)).width` against a laid-out `TextPainter`). That
is the test that then caught the label format itself being too long.

Widths worth knowing: the anchor line has ~210px at 390dp, and
`Loan ₱50k · Business loan` needs ~275px, so it ellipsizes — which is why the
**amount precedes the product type**. Truncation must not eat the discriminator
that tells a borrower's several loans apart.

## Search frontend — 8 tasks (branch `docs/amend-search-frontend-plan`, PR #106, 2026-08-31)

Built the query side against the **shipped Go indexer**, not the plan's prose.
The plan predated the backend and had drifted; the spec had drifted further and
was corrected in the same PR (it still described single-pass phone trimming, an
unbounded token rule, and three offer facets where two shipped).

Suite went **104 → 233**. Every guard below was mutation-proven: the mutation was
applied, the named test observed failing, then reverted and the file re-verified
byte-identical. **A guard without a proven-failing test is not a guard.**

**Authorization is the whole feature.** Three places could have leaked client PII
and all three were wrong in the plan:
- `SearchRequest.companyId` came from `AuthenticationService.company`, which
  **throws for `customer` AND `appAdmin`** (it gates on `role.index >
  customer.index`; appAdmin is 0 and customer is 1, so both fail). The throw was
  swallowed into an error state, so borrower search — the borrower's *only*
  scope — would have been permanently and silently broken. The index resolves the
  company itself now, from `UserRole.companyManagedRoles`.
- `/search?scope=clients` minted a `SearchScope` straight from the query param,
  and **`router.dart` has no role gate anywhere**. It is now a *candidate* passed
  to `SearchScopeResolver` as `pinnedScope` and intersected with the role's
  scopes, exactly like a typed prefix.
- `FirestoreSearchIndex` reuses `SearchScopeResolver.scopesFor` rather than
  re-deriving the role check, so the two cannot drift apart.

**Two pre-auth crash guards, same root cause.** `AuthenticationService.user`
throws `Please login` on `/login`, `/register`, `/set-password`. The app-bar field
must stay inside `layout_widgets.dart`'s `if (!showSignUp && !showLogin)` block,
and the `Ctrl/⌘K` wrapper — mounted above the `Router` in `app.dart`, the only
position reaching the twelve out-of-shell routes — must guard on `isLoggedIn`.
`isLoggedIn` is safe there because it reads the nullable `_user` field, never the
throwing getter. Both have regression tests asserting `takeException()` is null
**first**, so the failure names the crash rather than a downstream flag.

**Dart cannot mirror Go's folding without a normalizer.** Go does NFD → strip
every Mn → NFC. Dart core has no normalization, so `unorm_dart` was added. The
plan's 25-char fold table cannot handle `Nguyễn`, `Erdős`, `Ștefan`, `Māori`, and
must NOT fold `Straße`→`strasse` or `Søren`→`soren`, which Go does not. The
golden file cannot prove this: its only non-ASCII case is a **precomposed** `Peña`,
the one character the table already covered.

**Gotchas worth keeping:**
- `load()` carries `lastDocumentSnapshot` across calls — every search needs
  `reset: true` or the second query silently paginates the first.
- `QueryStatement` already supports `arrayContainsAny`, which is what makes the
  last-4 phone search possible with no package change (`0142` canonicalizes to
  `142` and matches nothing, so raw and canonical are both sent).
- `ProductViewRepository` is `final` — it cannot be mocked. The index takes
  injectable loader typedefs instead, which is also what made the authorization
  predicates testable.
- `SearchResults.empty` is pinned to the clients scope; using it on the offers
  scope leaves `results.scope` disagreeing with `state.scope`.
- The interest-rate facet is **deferred to finstack#103**: it is a range filter,
  and `ProductViewFirestoreService` hardcodes `orderBy('updated_at')` before its
  filter loop, so the query is illegal. Removing the chip is not enough — leaving
  `params['interest']` parsed keeps the crash reachable by deep link.
- `LayoutWidgets.defaultAppBar` has exactly ONE caller. A flag added only there
  is unreachable from `home_screen.dart`; it must be plumbed through
  `AppWidgets.defaultAppBar` too.
- `NotificationService.instance` at `layout_widgets.dart:310` is NOT inside the
  `showMessagesButton` block (288-308) — it is a sibling. Reading line order out
  of a grep instead of checking the block structure got this wrong twice.

**Known gaps (deliberate, not oversights):** no company picker, so that facet is
deep-link only (I13 wants the label resolution specified first); tapping a client
result opens the clients list, not the client, because `Paths.clientsAction`
demands a productId and loanId a `users` result does not carry; `/offers/:action`,
`/profile/:action` and `/chat/:roomId` have the shortcut but no visible
affordance; and `reset: true` is verified by reading, not by a test — testing it
needs the Firestore services injectable, a `packages/` change.

### Follow-ups after local verification (same PR, 2026-09-02)

The user ran the app locally before accepting each change (see the
`verify-ui-locally-before-push` memory). Three things that only showed up live:

- **Every way of opening a borrower goes through `BorrowerScreen.openBorrower`** —
  table row, compact list item, search result. It navigates to
  `/?sec=borrowers&id=<id>` in classic UI (the section hosts the dialog) and to
  `/borrowers/:id` full-screen in non-classic, which has no borrower surface. The
  search tile once carried its own copy of the URL and drifted the same day. Closing
  the dialog strips `&id=`, otherwise re-tapping the same row is a no-op. The compact
  list item's `onTap` had been entirely commented out.
- **Scope default is by role, not route.** `/` used to force offers ("the
  marketplace"), so a teller typing a client's name on the home page searched
  products. Now: clients if the role has it, else offers; `/offers/*` still offers.
  Customers cannot reach clients by any route, prefix, or pin — tested adversarially.
- **Prefixes accept aliases.** The only offers keyword was `products:` (from the spec);
  the first admin typed `offer:` and searched clients for "offer: …". Both scopes take
  the plural, singular, and domain word. `SearchScope.prefix` stays the hint keyword.
- Testing seams: `SettingsService.setClassicUIForTest`; `tester.view.physicalSize`
  (not `setSurfaceSize`) is what `MediaQuery`/`getScreenSize` read; providers must sit
  ABOVE `MaterialApp` for a `showDialog` route to see them.

### Code-review fixes, 29 findings (same PR, 2026-09-03)

A ten-angle inline review found 27 issues and missed the worst one; a single independent
reviewer found it. Fixed in three packages by file ownership (search core / search
widgets / routing+borrower screens). What the next session must not undo:

- **`/borrowers/:action` is gated** on `SearchScopeResolver.scopesFor(role).contains(clients)`
  (`BorrowerDetailScreen.permits`), and so is `MainScreen`'s compact deep-link redirect. A
  deep-linkable route must carry the same role gate as the section it exposes — this one
  shipped without it and a customer could read any user's profile and loans. Reuse
  `scopesFor`; never write a second predicate.
- **`SearchClearedEvent` on logout** (`ClearSearchOnLogout` in `app.dart`) and the field
  opens no overlay on an empty controller: the app-lifetime `SearchBloc` otherwise showed
  the previous account's client rows to the next account on the same device.
- **`MainScreen` has a stable key** (`ValueKey(sec ?? 'home')`), not `UniqueKey()`. Query-only
  URL changes update it in place; `BorrowerScreen.didUpdateWidget` opens/closes the dialog
  on `id` changes without re-running `loadNext`. The remount cost was ~1,200 Firestore
  reads per dialog open+close on a 300-borrower company.
- **`openBorrower` rule:** wide classic → `/?sec=borrowers&id=` (dialog over the list);
  compact/medium and non-classic → `goSafe('/borrowers/:id')` (pushed on mobile so back
  works). `BorrowerDetailScreen` now has a real compact body and an exit that pops if it
  can, else goes home. The cash-pool widget stacks its columns below 840 px.
- **Query/refinement split like the indexer:** `SearchTokenizer.wordForms` (joined form +
  parts) is used by both `queryTokens` and `_matchesWords`; a 4-digit phone term matches
  prefix OR tail; everything counts runes. The golden test now asserts
  `queryTokens(input) ⊆ Go's tokens` for every indexed value — the contract production
  depends on — and the indexer-mirror producers live in `test/support/`, not `lib/`.
- **Scope rules:** `_defaultScope` parses the location as a `Uri` (`/offers/*` OR
  `?sec=offers` → offers); `QueryChangedEvent` carries `filters` (field sends empty;
  screen sends its chips) and `candidateLimit` (overlay 10); `SearchScreen.didUpdateWidget`
  re-syncs field/pin/filters on URL change; the shell field is hidden on `/search`;
  `Ctrl/⌘K` does nothing while a modal is up and carries typed text from the field.
- Test facts that cost time: `setSurfaceSize` does not change `MediaQuery` (use
  `tester.view.physicalSize`); providers must sit above `MaterialApp` for a `showDialog`
  route; on Android `await router.goSafe(...)` awaits a push future that completes only on
  pop (a 10-minute hang); `find.text` matches table header columns too.

Known leftover: on `/search`, focus on a chip + `Ctrl K` still reaches the root wrapper and
drops `q`; a pasted `/?sec=borrowers&id=X` on a phone still uses the build-time push.

**Settings/UI-mode facts that cost hours (2026-09-03):** the classic/non-classic layout
comes from a per-user `dev_settings` doc (`user_id ==`); **no doc → non-classic
default on every route**, and a cold load shows the pre-settings paint for 20–40 s while
the session restores. Check the doc (Firestore runQuery on `dev_settings`) BEFORE
diagnosing "the classic layout isn't applying". Separately, `SettingsService.listen()`
used to hand a one-shot default stream to any subscriber that arrived before
`initializeForUser` (the shell's StreamBuilder on a cold load); it is now a live stream,
and the repository subscription is taken AFTER `loadNext(reset: true)` because that call
synchronously replaces the repository's broadcast controller. The app registers a
service worker on every boot: unregister it (or hard-reload) before trusting a rebuilt
bundle in the browser.

### Offers: the URL owns the selection too (same PR, 2026-09-03)

Reported after the review fixes: an offer opened from search landed on `/?sec=offers`
with no id, while a borrower opened as `/?sec=borrowers&id=`. `LoanOffersWidget` now
follows the borrowers rule on wide screens — `initialProductId` from `MainScreen`
(`&id=`), `_sync` on init and on URL change (select by id, with the grid's own view when
it has it; unselect when the id leaves), a card tap and `LoanOffersWidget.openOffer`
(what a search result calls) are URL writes, and the panel/dialog closing strips the id.
Other query params (`maxLoanable`, `maxPeriod`) survive the rewrite. Compact/medium
keep the old flow: the selection drives the navigation to the full-screen route, whose
own URL is the deep link. Admin dialog subtleties: `_dialogFor` tracks the open edit
dialog; `_sync` pops it when the URL moves, and the close path re-syncs to whatever the
URL says by then instead of unselecting (an `unselected` there would strip the newer
id). A deep link before the grid renders selects by id alone — `selectProduct`
already loads the view by `product_id` for that ("to cover dynamic link").
Tests: `test/features/products/loan_offers_widget_test.dart` (9; sync and strip guards
proven by mutation) + a wide case in `search_result_tile_test.dart`. The offer card
overflows its 258px cell under the test font (Ahem, every glyph full-width), so that
test drops overflow reports only — the card itself is untouched.
Independent review of that commit (1 important, 4 minor): `_sync` skipped selecting when
the bloc still held the product from an earlier visit, but a fresh mount paints from the
*state*, whose last value after a selection is `refresh` — a revisit of
`/?sec=offers&id=X` showed nothing until a third tap. Fixed: `_sync` is post-frame,
wide-only (compact/medium leave the id to `MainScreen`'s redirect, as Borrowers does),
and always selects on a mount; the card highlight and panel colour are set from the
`selected` state so deep links and search results get them too. Known and left: a bogus
id in the URL selects nothing and stays in the URL (the bloc's error state is not
handled here); a fast double-click on the same card can leave the panel open with no id.
The admin dialog path (`_dialogFor`) is verified by click-through only, not by a test.

## Penalties definitions — loooans#72 part 2 (2026-09-04)

Branch `feat/penalties-72-definitions` → `develop`. Design: `docs/superpowers/specs/2026-09-04-penalties-design.md`; plan: `docs/superpowers/plans/2026-09-04-penalties-2-definitions-port.md`. Issues live on the OLD tracker: loooans#72 (penalties), loooans#71 (late tagging vs collection date), loooans#78 (allow late payments). Do not confuse with finstack#71/#72.

### What was added
- `Penalty` + `PenaltyFrequency` (once, daily, monthly, per_installment) + `termDaysOf` in `packages/core/loooans_helpers`; `company.default_penalties`; `product.penalties` + `product.allow_late_payments`; loan snapshots both at creation; six schedule-row fields (`collected_at`, `days_late`, `penalty`, `penalties`, `penalty_waived_by`, `penalty_waive_reason`) for part 3. All fields default; old documents load.
- Pure `computePenalties` / `calculateDaysLate` / `previewPenalty` in `packages/loans/loan_schedule_repository` (tests: 19 there, 19 in helpers). Not called by any payment path yet.
- `apps/loans/lib/widgets/penalty_dialog.dart`, `PenaltiesSection` (wizard, after Deductions, with the `allow_late_payments` checkbox), `DefaultPenaltiesSection` (company card, admins), `ProductBloc` penalties state seeded copy-on-create from company defaults, penalties listed as "Penalty if paid late" in every quotation and the PDF, always from the loan snapshot where a loan exists.

### Decisions
- Flutter-only fields → not Class B; no Go PR (spec D10). If a Go trigger ever reads `penalties`, it becomes Class B: backend tolerates the shape first.
- Two loan-math bugs found on the way are NOT in this branch (campaign gate): finstack#107 (stored percentage charges use the running total; `loans_bloc.dart` `Loan.create` folds vs `ChargeCalculator` base) and finstack#108 (campaign D5 in `loan_changes.go`).
- `CompanyState` has no refresh status and is not Equatable, so the defaults section is a StatefulWidget owning its list; the bloc listener is scoped by `CompanyBloc.defaultPenaltiesSavedMessage` / `defaultPenaltiesFailedMessage` because `CompanyBloc` is shared with the edit-profile dialog.

### Independent review (2026-09-11, before merge)
- Verdict: mergeable, no blockers; every new field carries `@JsonKey(defaultValue:)` and the generated files were read to confirm old documents load; Go triggers read none of the new fields.
- Applied: `UpdateDefaultPenaltiesEvent` now registered with a sequential transformer (`events.asyncExpand(mapper)`, Bloc 8 default is concurrent, so two quick chip edits raced the full-list write and the rollback copy); the dialog's `_validateAmount` became `validatePenaltyAmount` (visibleForTesting) with a table test. Suite 353 green.
- Catalogued, not changed: the wizard quotation preview follows the saved `allowLatePayments`, not the unsaved switch (spec 7.6 fallback, owner walked it through); `ProductBloc.unselectProduct` clears penalties but not charges/deductions (no caller can hit it behind an open wizard); `termDaysOf` scales `Nm`/`Nd` beyond its "otherwise 30" doc (only `1m`/`15d` are ever written); a two-line checkbox restyle in `requirements_section.dart` rode along.

### Process lesson
- This feature was first built (14 commits, two draft PRs) against the stale pre-monorepo repos `anatechopc/loooans` and `loooans_cloud_functions`, because the issue link pointed there. Those PRs were closed and the work ported here. Check repo recency before building; the old repos still host the issues.

### Resume state
- Part 3 (`feat/penalties-72-application`): confirmation handler with collection date, waive, red penalty line on `client_detail_schedule_item.dart` and `loan_schedule_widget.dart`, statement-of-account column. Reference plan (old paths) in the loooans worktree `docs/superpowers/plans/2026-09-03-penalties-3-application.md`; `resolveLateness` must pass `termDays: termDaysOf(loan.term)`.
- `sumCharges.upfrontOnly` idea and the quotation-loop unification are deferred with finstack#107.

## Penalties application — loooans#72 part 3 (2026-09-04)

Branch `feat/penalties-72-application` stacked on `feat/penalties-72-definitions` (PR #109). Spec `docs/superpowers/specs/2026-09-04-penalties-design.md` sections 6, 7.4, 7.5, 7.7; plan `docs/superpowers/plans/2026-09-04-penalties-3-application-port.md`.

- One rule: `resolveLateness` (pure, `loan_schedule_repository/penalty_calculator.dart`) → `PaymentConfirmationService.applyLateness` writes `collected_at`, `days_late`, `penalty`, `penalties`, waive fields and returns the status. Called from `PaymentBloc._handlePayLoanScheduleEvent`, `PaymentCenterBloc._handleMakePaymentEvent`, `_handleMakeOverduePaymentEvent` (one date, per-row penalty), and `PaymentConfirmationService.confirm` (default date = `Payment.createdAt`). `scheduleStatusForConfirmation` removed. `paid_late` only when late on a loan with `allow_late_payments == false`.
- Events/methods gained `collectedAt`, `waivePenalty`, `waiveReason`: `PayLoanScheduleEvent`, `MakePaymentEvent`, `MakeOverduePaymentEvent`, `ConfirmSubmissionEvent` and their `makePayment`/`makeOverduePayment`/`confirmSubmission`.
- UI: `lib/widgets/payment_penalty_section.dart` (form keys `collected_at`, `waive_penalty`, `waive_reason`; takes `List<LoanSchedule>`), hosted in `client_detail_dialogs.showMakePaymentDialog`, `payment_center_dialogs.showPaymentCenterPaymentDialog`/`showOverduePaymentDialog`, `client_detail_loan_body._showReviewPaymentDialog`, and — inline, not a dialog — `pending_submission_section._PendingSubmissionCard`: Pending-submission cards are collapsed rows (thumbnail, schedules, paid-to + submitted date, amount incl. running penalty, Reject, Review); PendingSubmissionSection keeps a single open submissionId; the open card shows the screenshot, PaymentPenaltySection, and Confirm inside the card's own FormBuilder, wrapped in a transparent Material for the checkbox's ListTile. Confirm calls `saveAndValidate()` on the card's form key and passes the values straight to `confirmSubmission` (no dialog, no separate `showConfirmSubmissionDialog` — that function was removed). The card's amount is `submission.totalAmount! + penalty` (penalty computed via `previewPenalty` per schedule, "as of now"), with a small "incl. … late penalty" line under it when non-zero. `AppWidgets.defaultFormBuilderDatePicker` gained `initialValue`/`onChanged`. Red lines: `client_detail_schedule_item.dart` (`loan:` param) and `loan_schedule_widget.dart` (`loan:` on widget and `scheduleItem`). `PendingSubmission` carries `loan` and `schedules`. `PaymentPenaltySection` also clears its own `waive_penalty`/`waive_reason` form values through `FormBuilder.of(context)?.removeInternalFieldValue` when the penalty drops to zero, because `form_builder` keeps stale values after unregister. Borrower side: `_nextPayment` and `SubmitPaymentDialog` include `previewPenalty` in the amount (Pay now, Pay in full), with an "incl./Includes … late penalty" line.
- SOA: `SOAEntry.penalty`; `Penalty` header is the LAST column; total penalties appended to `additionalCharges` as `Penalties` (no index arithmetic touched); the deduction and additional-charge rows in statement_of_account_screen.dart index their item from the row number (the old last-column build counters were removed because a lazy TableView never builds the last column in narrow windows).
- Not Class B: `loan_schedule_changes.go` ignores the new fields. Penalties are NOT in `total_collections` (would be Class B). No reporting side effect: the trigger's status gate accepts paid_on_time and paid_late alike, so allow-late loans switching to paid_on_time change nothing there.
- Gate: merge waits for PR #109; Gate 1 waived by the owner on 2026-09-08 (branch touches neither loan_calculation_service.dart nor charge_calculator.dart; golden suite tracked as finstack#112). Tests: `penalty_calculator_test.dart` (resolveLateness), `payment_confirmation_service_test.dart` (applyLateness), `payment_center_confirm_test.dart` (late confirm; `sched()` now sets `isOpenTerm`/`amortization`/`outstandingBalance` because `resolveLateness` reads them), `test/widgets/payment_penalty_section_test.dart`, `test/features/products/loan_schedule_widget_penalty_test.dart` (overdue and waived rows render without overflow).
- **G12 penalties golden set (2026-09-08, branch `test/penalties-golden-g12` stacked on this one; 3 scenarios added 2026-11-13 from the independent review of PR #118):** `test/services/penalty_golden_test.dart`, 11 hand-derived scenarios that run `resolveLateness`/`applyLateness`/`computePenalties`/`termDaysOf` on real `Company`/`Product`/`Loan`/`LoanSchedule` models. The company `defaultPenalties` → product and product → loan copies are made by test helpers that mirror `product_bloc.dart` and `loans_bloc.dart` (`List<Penalty>.of`); those two production call sites are NOT run by this file (`Loan.create` keeps the list it is given, so the loan's independence depends on the call site copying). Pins both owner-required outcomes: defaults imposed → 5 days late on 2,500 charges 225; no company defaults → still `paid_late`, 0, nothing to penalize (and nothing to waive, no reason needed). Also cadence rounding; per installment reading the term from the loan through `resolveLateness` ('15d' → 300, '1m' → 200); the open-term balance base (the loan fixture is 12,000 / 3,000 against a 10,000 / 2,500 row, so a base read from the loan cannot pass); on time → `paid_on_time`; a waive without a reason rejected with the row left as it was; snapshot independence (in-place edits to the company and product lists after the loan exists change nothing, and clearing `loan.penalties` after confirmation leaves the row's copy); and that the ONLY trigger is a collection after the due date (no grace/threshold/cap exists in the code). Dates stay inside Jul 15 – Aug 20, 2026, where no zone changes its clock. Mutation check: `(daysLate / 30).ceil()` → `/ 31` in loooans_helpers' `penalty.dart` fails P5.
- Payment Center search: borrowers are resolved from the company-owned customer list plus the company's user_loan_views (marketplace borrowers have company_id null), each extra id loaded via userRepository.get; PaymentCenterBloc gained userLoanViewRepository (BaseRepository<UserLoanView>, late final, optional in withDependencies). Found in the part-3 walkthrough. The search box (borrower_search_widget.dart, a FormBuilderTypeAhead) had bypassed the bloc via UserBloc.getCustomersByCompany; it now calls PaymentCenterBloc.findBorrowers, which the event handler shares.
- Deferred: collecting the penalty on a borrower submission (recorded as owed only); a bloc-level test for `_handlePayLoanScheduleEvent` (blocked by the unmockable `CashPoolRepository` late field).
- Proof-image viewer: shared lib/widgets/image_viewer_dialog.dart (80% of window, min 320px, PhotoView pinch/trackpad zoom + zoom in/out/reset buttons) replaces the two fixed 400px _showFullImage copies (pending_submission_section.dart, client_detail_loan_body.dart).

### Independent review (2026-09-11, after merging develop dacb540 at 4f11e85)
- Money path verified correct: base = amortization or outstanding balance by `isOpenTerm`; local-calendar `daysLate` floored at 0; `termDays: termDaysOf(loan.term)`; `applyLateness` runs before the balance is reduced on all bloc paths; penalty stays out of principal/interest, cash pool, settlement (G7 intact), and RTDB; SOA counts it once. Hand re-derivation 100×19 + 5000×2%×1 = 2,000 matches the calculator test. Not Class B: no new status or transition; the Go trigger reads status/interest/principal only.
- BLOCKER fixed: `UserLoanViewFirestoreService.load` now orders by `created_at` (for `findBorrowers`, whose company_id shape has that index), but the two pre-existing `loan_id`-filtered callers (`loans_bloc.dart` `_handleSelectLoanEvent`, `_handleGetLoansByUser`) only had `(deleted_at, loan_id, updated_at DESC)`; without a `(deleted_at, loan_id, created_at DESC)` composite, client detail throws FAILED_PRECONDITION. Added that composite to `firestore.indexes.{dev,stg,prod}.json`. Verified live on 2026-09-14 (`firebase firestore:indexes`): none of dev, stg, prod had it. The committed files were also stale against live (console-made indexes never refreshed in: `bank_details` dataId and `chat_rooms` member_ids on all three; stg additionally three `additional_loan_amounts` and two `cash_pool`), so a plain deploy would have prompted to delete live indexes; the three files were reconciled to live + the new composite (same filter as the script's `--refresh`, so the next refresh is a no-op). **Dev deployed 2026-09-14** (`./scripts/deploy-indexes.sh dev`, 43 indexes, nothing deleted; dev now equals the committed file exactly). **Run the script with `stg` and `prod` before promotion**; each creates exactly the one index.
- Should-fix fixed: the pending-submission card previewed the penalty "as of now" while the expanded section and `confirm()` default to `payment.createdAt`; the card now passes `asOf: submission.payments.first.createdAt`.
- Recorded: admins can make payments from client detail (d5ef420, owner-requested in the walkthrough). Design note for later: the borrower path's default collection date is device-written `payment.createdAt`, unvalidated by rules; the teller sees and can override it.
- Catalogued, not changed: bulk overdue / multi-schedule confirm are neither batched nor rolled back on a mid-loop failure (pre-existing shape); `findBorrowers` scans all company views per keystroke (limit null); bloc-level tests of the three writing handlers still blocked by the `CashPoolRepository` late field; one info lint at penalty_calculator_test.dart:319 kept for readability.
