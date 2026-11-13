# Report recompute tool — campaign Phase 4

Date: 2026-11-13. Branch `feat/report-recompute-tool` → `develop` (PR #132). Backend only. Revised the same day after the independent review of head `4c54d8a`.

## 1. Goal

Rebuild one company's Realtime Database `report_summary` from its Firestore documents. The triggers were fixed on 2026-09-09 (PR #121), but the totals written before that date are wrong (campaign D1/D2) and the triggers cannot repair them. Report totals are never edited by hand; this tool is the repair path, and every apply is recorded and can be undone.

Scope: one company per run, a command-line tool, no scheduling, no UI. Decisions already taken by the owner and not reopened here: a completed loan books its remaining principal only; amounts floor at 0; malformed documents are logged and dropped.

**Status: usable as a dry-run measurement tool. No apply may run in any hosted environment until §8 is satisfied.**

## 2. What the triggers write

Under `{dev|stg|""}/companies/{companyId}/report_summary`:

| Node | Fields |
|---|---|
| `sales` | `total_amount_released`, `total_collections`, `total_interest_payments`, `total_principal_payments` |
| `products/{productType}` | the four above and `total_bad_debts` |
| `total_summary/{bucket}` | the same five. Buckets: `year:Y`, `year:Y:month:M`, `year:Y:month:M:week:W`, `year:Y:month:M:week:W:day:D`, in UTC, `W` = ISO week |
| `capital_usage` | `total_capital`, `total_bad_debts` |
| `data/{key}` | one item per booking (`release`, `collection`, `refresh_capital`, `bad_debt`, `add_capital`) |

The triggers write nothing else there. Event claims live beside it, under `{company}/report_events`.

## 3. Source and formula per total

Firestore collections carry the environment prefix (`dev_`, `stg_`, none). Three sets:

- **L**, released loans: `{prefix}loans` where `company_id == company`; `deleted_at` unset; `id`, `status`, `amount` present; `status` neither `pending` nor `declined`; a product type exists for the loan; `created_at` readable. After approval the app sets a loan's status to that of its latest schedule (`payment_confirmation_service.dart`), so every status except `pending` and `declined` is reached through approval.
- **P**, confirmed rows: `{prefix}loan_schedules` where `loan_id` is one of the company's loans (the query of the trigger's schedule loader; a row's own `company_id` is not used to find it, and a row whose `company_id` is empty or another company's is counted and listed); `deleted_at` unset; `status` is `paid_on_time` or `paid_late`; `loan_id`, `interest_payment`, `principal_payment` present; a product type exists for the loan. A `payment_submitted` row is a borrower's claim that no teller has confirmed: it is not counted and is listed as a pending submission (§4.3).
- **K**, capital: `{prefix}capital` where `provider_id == company`; `deleted_at` unset; `id`, `amount`, `created_at` present.

The product type of a loan is the Realtime Database node `{company}/loans/{loanId}:product_type`, the same node the triggers read.

For a loan `l`, `paid(l)` is its rows in P. For `status == completed`, `remaining(l) = max(amount + additional_charges − deductions − additional_charge_upfront_collection − Σ paid(l) (principal_payment + extra_payment), 0)`. For `status == bad_debt`, `baddebt(l) = max(amount − Σ paid(l) principal_payment, 0)`.

| Total | Formula | Written to | Bucket date in recompute | Date the live trigger uses |
|---|---|---|---|---|
| `total_amount_released` | Σ L `amount` | `total_summary`, `products`, `sales` | loan `created_at` | time the trigger handled the write that moved the status to `approved` |
| `total_bad_debts` | Σ `baddebt(l)` | `total_summary`, `products`, `capital_usage` | loan `updated_at` | time it handled the move to `bad_debt` |
| `total_collections` | Σ P (`principal_payment + interest_payment`) + Σ `remaining(l)` | `total_summary`, `products`, `sales` | row: `collected_at`, else `paid_at`, else `created_at`. Settlement: loan `updated_at` | row: time it handled the row's creation. Settlement: time it handled the move to `completed` |
| `total_interest_payments` | Σ P `interest_payment` | same | row date as above | as above |
| `total_principal_payments` | Σ P `principal_payment` + Σ `remaining(l)` | same | as `total_collections` | as above |
| `capital_usage/total_capital` | Σ K `amount` + Σ P `principal_payment` + Σ `remaining(l)` | `capital_usage` | no bucket | — |
| `capital_usage/total_bad_debts` | Σ `baddebt(l)` | `capital_usage` | no bucket | — |

"Time the trigger handled" is `time.Now().UTC()` inside the function: normally seconds after the write, later after a retry. No document records it.

Data items: one `release` per loan in L (date as its bucket), one `bad_debt` per bad debt, a `refresh_capital` and a `collection` per row in P and per settlement, one `add_capital` per document in K (`created_at`). Keys use the trigger's format from the same date; items that share a millisecond get the suffix `:2`, `:3`.

The arithmetic of a release, a collection, a settlement, a bad debt and a capital addition is the trigger's own (`PlanLoanReport`, `PlanScheduleReport`, `PlanCapitalReport`): recompute calls those functions once per document with a document date in place of the event time, and sums the plans. What recompute decides for itself is which documents to feed them, from each document's final state. §4 lists every case where that gives another number than the triggers booked.

## 4. Where recompute and the triggers give different numbers

"Right" means: agrees with what the documents say today.

### 4.1 Dates (period buckets only; all-time totals agree)

1. **Release.** The loan document has no approval date (D18). Recompute uses `created_at`, the only loan date that never changes. A loan approved days after the application lands in an earlier day, sometimes an earlier month, than the trigger put it. Neither side is exact; the trigger is closer.
2. **Settlement and bad debt.** No completion date exists. Recompute uses `updated_at`; a later edit of the loan moves the booking. The trigger is closer.
3. **Collection.** Recompute uses `collected_at` (when the money was received, set at confirmation since the penalties work), else `paid_at`, else `created_at`. The trigger uses the time it handled the row's creation. They differ when a teller back-dates a collection; then recompute is right.

### 4.2 Histories the final documents do not show (the triggers booked each event; recompute sees the end state)

| History | Triggers | Recompute | Right |
|---|---|---|---|
| Loan leaves `approved` and returns | release booked twice | once | recompute |
| Loan marked `bad_debt` (10,000), then a payment arrives and the app moves it to `paid_on_time` | bad debt 10,000 stays | 0 | recompute: the loan is not a bad debt today. The trigger never reverses a write-off. |
| Loan `completed`, leaves that status, `completed` again | remainder booked twice (20,000) | once (10,000) | recompute |
| Row paid after settlement (remainder 10,000 booked, then a row of 4,000) | 14,000 collected | 10,000 (remainder 6,000 + row 4,000) | recompute: collections cannot exceed the loan |
| `amount` or a row edited after its event | value at event time | final value | depends on the edit; recompute follows the documents |
| Document hard-deleted, or `deleted_at` set | booking remains | absent | recompute, by the source-of-truth rule |

### 4.3 Rows: which ones count (D16, filed as #133)

`loanScheduleChanges` runs on document creation only, and its planner (`PlanScheduleReport`, `isCollectionStatus`) treats `payment_submitted` as a payment. The app also changes rows by update:

- Approval in an app-managed company persists the first row as `approved` (`loans_bloc.dart`; for an open-term loan its `principal_payment` is the whole `amount`). Tellers cannot pay that row: the teller flows require a self-managed company (`payment_bloc.dart:127`), which persists no row at approval. The borrower's "Pay now" flow can: it updates the row's status to `payment_submitted` (`payment_submission_bloc.dart`), and a teller's confirmation updates it to `paid_on_time` / `paid_late`. A rejection updates it back to `not_paid`.

| Case | Triggers | Recompute | Right |
|---|---|---|---|
| Row **created** as `payment_submitted` (open-term runtime row) | booked as a collection at creation, and counted as returned principal at settlement / bad debt | not counted; listed as a pending submission | recompute: unconfirmed cash is not a collection. **This is a deliberate difference from the trigger planner, decided in review; the trigger is not changed in this PR.** |
| Planned row moved to `payment_submitted` by "Pay now" | not booked (update) | not counted; listed | both agree. Counting it would book the whole principal of an open-term loan (10,000 on a 10,000 loan). |
| That row then confirmed (`paid_on_time`) | never booked | counted | recompute: the trigger misses a real payment |
| Row created as `payment_submitted`, then confirmed | booked at submission | counted once confirmed, on `collected_at` (by default the submission time) | both count it |
| Submission rejected (`not_paid`) | booking remains | not counted | recompute |

### 4.4 Shared formula known to be wrong (#134, D19 in the campaign reference)

The settlement remainder subtracts `principal_payment + extra_payment` (`report_core.go`, `collectedPrincipal(…, true)`), and the teller flows store the extra in both fields (`payment_bloc.dart:213-225`: `principal_payment = payment`, `extra_payment = payment − scheduled principal`). The extra is subtracted twice, so the remainder of a settled loan with extra payments is too low. Recompute calls the same function, so **an apply restates this under-count**; it does not fix it. Fixing the trigger core is #134 and is a precondition for an apply (§8).

### 4.5 Other

- **Data items in the same millisecond (D17).** Two live events in one millisecond share a key and the later item overwrites the earlier. Recompute keeps both.
- **Top-ups** (`additional_loan_amounts`) are in neither side's `total_amount_released`.

Tests: `TestRecompute_EqualsReplayingTheHistoryThroughTheTriggers` shows that a history with none of the above gives identical totals and items on both sides; `TestRecompute_DiffersFromTheTriggers_OnlyInTheNamedWays` pins ten of the cases above with their numbers.

Consequence: straight after an apply, live equals the recompute exactly. Once triggers book new events, the differences above return without any new defect. The all-time totals (`sales`, `products`, `capital_usage`) are the pollution measure; the tool prints them separately from the period buckets.

## 5. Design

- **Core** — `functions/loans/triggers/report_recompute.go`. `RecomputeReport(RecomputeInput) RecomputeResult` is pure: raw documents and the product-type map in; the summed `ReportPlan`, counts, one line per loan, and three lists out (dropped documents, pending submissions, rows with a foreign `company_id`). `ReportPlan.SummaryNode()` turns the plan into the `report_summary` node. Bookings are summed in a fixed order (date, then document id), so the result depends only on the set of documents. The trigger's schedule loader and recompute share one function for reading a row's amounts.
- **Adapters** — `functions/loans/cmd/recompute_reports/adapters.go`. Firestore reader: loans and capital by company, rows by `loan_id` per loan. Realtime Database: read `report_summary` with its ETag, read `report_events` and the product-type nodes, write `report_summary` conditionally, read and write run records. `-env` sets `ENVIRONMENT`, and prefixes, database root and URL come from `utils`, as for the triggers.
- **CLI** — `functions/loans/cmd/recompute_reports/main.go`. Flags: `-company <id>` and `-env dev|stg|prod` (required), `-loans`, `-apply`, `-confirm-prod <id>`, `-restore <runId>`, `-by <who>` (default `user@host`).

Dry run (the default) reads and prints: document counts; every dropped document, pending submission and foreign-company row; the claims summary; every all-time total as recomputed, live and live minus recomputed; the period totals that differ by 0.005 or more; the number of data items on each side; whether live equals the recompute; and why an apply would be refused. `-loans` adds one line per loan: id, status, amount, released, the releases the live `data` list holds for it, paid principal, interest, settlement remainder, bad debt, and why it was dropped or not released; then one line per live release whose loan Firestore no longer has. Ids, statuses and amounts only; no names or contact data.

An apply is refused when: `-env prod` lacks `-confirm-prod` equal to the company; `ENVIRONMENT` is already set to another environment; one emulator variable is set without the other; **the recompute is empty** (it would delete the live node); **any document was dropped** (the recompute is incomplete; the documents are listed); a claim is unapplied and younger than 7 days (§6); the previous node cannot be saved; a trigger wrote to the summary during the run.

## 6. Apply, rollback, the race with triggers, and verification

An apply does this, in order:

1. Reads `report_summary` and its ETag before reading Firestore.
2. Writes the run record `{company}/report_recomputes/{yyyymmddThhmmssZ}`: `at`, `by`, `applied: false`, document counts, how many totals differ, the totals after, and **`previous`: the complete node as read in step 1, `data` list included**. If this write fails, nothing else is written.
3. Replaces the whole node with one conditional write (`If-Match` on that ETag). The node is replaced completely or not at all. If any trigger wrote to the summary after step 1, the write is refused; the record is marked `outcome: not applied…` and the operator runs again.
4. Marks the record `applied: true`.

If live already equals the recompute, an apply writes nothing.

**Rollback.** `-restore <runId>` uses the `previous` node of that run in place of a recompute. Without `-apply` it prints saved versus live; with `-apply` it goes through steps 1 to 4 (so the restore is itself recorded, holds the node it replaced, and can be undone):

```bash
go run ./cmd/recompute_reports -env dev -company <id> -restore <runId>          # compare
go run ./cmd/recompute_reports -env dev -company <id> -restore <runId> -apply   # write it back
```

A restore puts back the node as it was before that run. Increments the triggers added after the run are not in it; restore soon after the apply, or expect to recompute again.

What the conditional write does not cover:

- **An event whose document was read but whose trigger had not applied yet.** The recompute counts the document; the trigger then adds it again. Events normally apply within seconds.
- **An event claimed and not applied** (`report_events/{id}` without `applied`). The delivery failed between claim and apply, and the platform may redeliver it for up to 7 days (the default retry window in Google's "Retry event-driven functions" guide, read 2026-11-13; the window configured on these three triggers was not inspected). The tool reads the claims, prints the counts and refuses to apply while any unapplied claim is younger than 7 days. Older ones are no longer redelivered; the recompute covers their documents.
- **An event that fails before claiming** (no product-type node yet). Recompute drops that loan for the same reason and therefore refuses to apply.

Operator procedure:

1. Dry run with `-loans`. Record the all-time differences: this is the pollution measurement. Resolve every dropped document.
2. Apply when the company is not transacting.
3. Wait a minute, then dry run again. It must print `live equals the recomputed summary: zero difference`. If it does not, an event landed in between: apply again. Recompute is a function of the documents, so repeating it is safe.
4. Record the run in `functions/loans/MEMORY.md`: date, environment, company, run id, before and after totals.

## 7. Open decisions for the owner

The tool is built on the defaults.

| # | Question | Default built | Alternative |
|---|---|---|---|
| 1 | Bucket date of a release | loan `created_at` | Store `approved_at` on the loan at approval (app change, both sides) and use it when present. Recommended as a follow-up; it is the only exact fix. |
| 2 | Bucket date of settlement and bad debt | loan `updated_at` | Store `completed_at` / `bad_debt_at` with the same follow-up. |
| 3 | Bucket date of a collection | `collected_at`, else `paid_at`, else `created_at` | `paid_at` first (when it was recorded, not when the money arrived). |
| 4 | Planned rows confirmed by update (#133) | counted | Leave them out to match the trigger. Not recommended: the trigger is the side that is incomplete. |
| 5 | Submissions rejected later (#133) | not counted | — |
| 6 | Documents with `deleted_at` set | left out | Count them. The app does not soft-delete loans, schedules or capital today. |
| 7 | Loan without a product-type node | dropped and listed; blocks an apply | Fall back to the product document's `loan_type`. |
| 8 | Unapplied claim younger than 7 days | apply refused | Mark such claims applied in the same write, so a redelivery becomes a no-op; or read the real retry window of the triggers and use it. |
| 9 | Run record | `{company}/report_recomputes/{runId}` with the complete previous node | Keep the copy elsewhere (it grows by one full node per apply). |
| 10 | Smallest reported difference | 0.005 (half a centavo) | — |
| 11 | Top-ups (`additional_loan_amounts`) | not part of `total_amount_released`, as in the triggers | Count them; needs the same change in the triggers. |
| 12 | `payment_submitted` rows | not counted until confirmed (review decision; differs from the trigger planner and from the earlier rule that listed them as paid) | Count them as the triggers do. Then "Pay now" on an open-term planned row books the whole principal. |
| 13 | A dropped document | blocks every apply for that company | An explicit flag that names the documents the operator accepts losing. |

## 8. Before any apply

None of this is done by merging the PR.

- [x] An apply cannot delete or shrink the live node silently: empty recompute and dropped documents are refused (review fix 1).
- [x] The complete previous node is saved before the write, and `-restore` writes it back (review fix 2).
- [x] Unconfirmed submissions are not counted (review fix 3).
- [ ] #133 (the schedule trigger books created rows only) resolved, or accepted in writing with its effect on the company measured by a `-loans` dry run.
- [ ] #134 (extra payment subtracted twice in the settlement remainder) fixed in the trigger core, or accepted in writing; until then an apply restates the under-count.
- [ ] Owner decisions 1, 2, 4, 5, 7, 9 (and 12, which the review introduced) taken.
- [ ] Dev first: apply, check that the app's reports render, record the run; then stg; then prod.

## 9. Tests

- **Unit** (`test/triggers/report_recompute_test.go`, `cmd/recompute_reports/main_test.go`; run by CI): hand-derived totals and loan lines for a five-loan company; every `LoanStatus` value released or not; the collection date rule; dropped and skipped documents; foreign-company rows; the same documents in another order give the same node; replay-versus-recompute equivalence and ten named differences; option checks; the names each `-env` uses; a dry run writes nothing; an apply saves the previous node, then writes, then a second dry run shows zero difference and a second apply writes nothing; restore; every refusal, including claims at one hour and at almost seven days.
- **Integration** (`cmd/recompute_reports/emulator_test.go`, build tag `emulator`, Firestore and Realtime Database emulators, real adapters; **not run by CI**, which starts no emulators): under the dev, stg and prod names, a dry run leaves the whole company node untouched; an apply leaves `report_summary` equal to the recompute of the seeded documents, saves a copy equal to the node as it was, and leaves other nodes unchanged; rows are found by loan and foreign documents are not read; a restore puts the saved node back; the review's probe (one approved loan, no product type) is refused with nothing changed; a trigger write during the run makes the conditional write fail.
- **Manual**: the built binary against the emulators, and read-only dry runs against dev. Outputs are in the pull request.

## 10. Out of scope

Repairing dev, staging or production (each apply is a separate, recorded step); scheduling; a UI; changes to the triggers (#133, #134, D17, D18); the Flutter reader.
