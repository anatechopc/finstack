# Report recompute tool — campaign Phase 4

Date: 2026-11-13. Branch `feat/report-recompute-tool` → `develop`. Backend only.

## 1. Goal

Rebuild one company's Realtime Database `report_summary` from its Firestore documents. The triggers were fixed on 2026-09-09 (PR #121), but the totals written before that date are wrong (campaign D1/D2) and the triggers cannot repair them. Report totals are never edited by hand; this tool is the repair path, and every apply is recorded.

Scope: one company per run, a command-line tool, no scheduling, no UI. Decisions already taken by the owner and not reopened here: a completed loan books its remaining principal only; only paid rows (`paid_on_time`, `paid_late`, `payment_submitted`) count as returned principal; amounts floor at 0; malformed documents are logged and dropped.

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
- **P**, paid rows: `{prefix}loan_schedules` where `company_id == company`; `deleted_at` unset; `status` is `paid_on_time`, `paid_late` or `payment_submitted`; `loan_id`, `interest_payment`, `principal_payment` present; a product type exists for `loan_id`.
- **K**, capital: `{prefix}capital` where `provider_id == company`; `deleted_at` unset; `id`, `amount`, `created_at` present.

The product type of a loan is the Realtime Database node `{company}/loans/{loanId}:product_type`, the same node the triggers read.

For a loan `l`, `paid(l)` is its rows in a paid status. For `status == completed`, `remaining(l) = max(amount + additional_charges − deductions − additional_charge_upfront_collection − Σ paid(l) (principal_payment + extra_payment), 0)`. For `status == bad_debt`, `baddebt(l) = max(amount − Σ paid(l) principal_payment, 0)`.

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

Every number comes from the trigger's own planning functions (`PlanLoanReport`, `PlanScheduleReport`, `PlanCapitalReport`). Recompute calls them once per document with a document date in place of the event time, and sums the plans.

## 4. Where recompute cannot equal the live value, and the rule chosen

1. **Bucket date of a release.** The loan document has no approval date. Rule: `created_at`, the only loan date that never changes. A loan approved days after the application lands in an earlier day (sometimes an earlier month) than the trigger put it. All-time totals are unaffected.
2. **Bucket date of a settlement or bad debt.** No completion date exists. Rule: `updated_at`; the move to a final status is normally the last write to the loan. A later edit of the loan moves the booking.
3. **Bucket date of a collection.** Rule: `collected_at` (when the money was received, set at confirmation since the penalties work), else `paid_at` (when the row was marked paid), else `created_at`. For rows the trigger booked this is the creation time or close to it, unless a teller back-dated the collection; then recompute uses the back-dated day.
4. **Rows updated into a paid status.** `loanScheduleChanges` runs on document creation only. A planned row that is paid later by update (the first row persisted at approval) is never booked by the trigger. Recompute counts it, following the owner's rule that paid rows count.
5. **Submissions rejected later.** The trigger books a `payment_submitted` row at creation and never reverses it. Recompute reads the final status, so a rejected row does not count.
6. **A loan that leaves `approved` and returns.** The trigger books a second release (documented in the triggers spec). Recompute books one.
7. **Deleted documents.** A hard-deleted document is absent from Firestore and from the recompute; rows with `deleted_at` set are left out, as in the app's own queries. The trigger's bookings for them remain in the live node.
8. **Values edited after the event.** Recompute reads the final `amount` and the final rows; the trigger used the values at event time.
9. **Data items in the same millisecond.** Two live events in the same millisecond share a key and the later item overwrites the earlier. Recompute keeps both.

Items 4 and 5, 9, and 1 and 2 are catalogued as D16, D17 and D18 in the campaign reference (`.claude/skills/finstack-loan-engine-and-reporting-campaign/references/aggregation-triggers.md`). The unit test `TestRecompute_DiffersFromTheTriggers_OnlyInTheNamedWays` demonstrates 1, 4, 5, 6 and 9; `TestRecompute_EqualsReplayingTheHistoryThroughTheTriggers` shows that without them a replayed history and the recompute give identical totals and items.

Consequence: straight after an apply, live equals the recompute exactly. Once triggers book new events, differences of kinds 1 to 5 return in the period buckets (and, for 4 and 5, in the all-time totals) without any new defect. The all-time totals (`sales`, `products`, `capital_usage`) are the pollution measure; the tool prints them separately from the period buckets.

## 5. Design

- **Core** — `functions/loans/triggers/report_recompute.go`. `RecomputeReport(RecomputeInput) RecomputeResult` is pure: raw documents and the product-type map in; the summed `ReportPlan`, counts and the list of dropped documents out. `ReportPlan.SummaryNode()` turns the plan into the `report_summary` node. Bookings are summed in a fixed order (date, then document id), so the result depends only on the set of documents. The trigger's schedule loader and recompute share one function for reading a row's amounts.
- **Adapters** — `functions/loans/cmd/recompute_reports/adapters.go`. Firestore reader: three equality queries on the prefixed collections. Realtime Database: read `report_summary` with its ETag, read `report_events` and the product-type nodes, write `report_summary` conditionally, write the run marker. `-env` sets `ENVIRONMENT`, and prefixes, database root and URL come from `utils`, as for the triggers.
- **CLI** — `functions/loans/cmd/recompute_reports/main.go`. Flags: `-company <id>` and `-env dev|stg|prod` (required), `-apply`, `-confirm-prod <id>`, `-by <who>` (default `user@host`).

Dry run (the default) reads and prints: document counts, dropped documents, the claims summary, every all-time total as recomputed, live and live minus recomputed, the period totals that differ by 0.005 or more, the number of data items on each side, and whether live equals the recompute. Totals and document ids only; no names or contact data.

Refusals: `-apply -env prod` without `-confirm-prod` equal to the company; `ENVIRONMENT` already set to another environment; one emulator variable set without the other; an apply when no document was found for the company (a wrong id would delete the live node); an apply while a claim is unapplied and younger than 7 days (§6).

## 6. Apply, the race with triggers, and verification

An apply does three things:

1. Reads `report_summary` and its ETag before reading Firestore.
2. Replaces the whole node with one conditional write (`If-Match` on that ETag). The node is replaced completely or not at all. If any trigger wrote to the summary after step 1, the write is refused and nothing changes; the operator runs again.
3. Records the run at `{company}/report_recomputes/{yyyymmddThhmmssZ}`: `at`, `by`, document counts, how many totals differed, and the totals before and after (the `data` list is not copied). The marker is a second write. If it fails, the tool exits with an error that says the summary was replaced and the marker was not.

If live already equals the recompute, an apply writes nothing.

What the conditional write does not cover:

- **An event whose document was read but whose trigger had not applied yet.** The recompute counts the document; the trigger then adds it again. Events normally apply within seconds.
- **An event claimed and not applied** (`report_events/{id}` without `applied`). The delivery failed between claim and apply, and the platform may redeliver it for up to 7 days (the default retry window in Google's "Retry event-driven functions" guide, read 2026-11-13; the window configured on these three triggers was not inspected). The tool reads the claims, prints the counts and refuses to apply while any unapplied claim is younger than 7 days. Older ones are no longer redelivered; the recompute covers their documents.
- **An event that fails before claiming** (no product-type node yet). Recompute drops that loan for the same reason, so both sides agree when the node appears and the trigger books it.

Operator procedure:

1. Dry run. Record the all-time differences: this is the pollution measurement.
2. Apply when the company is not transacting.
3. Wait a minute, then dry run again. It must print `live equals the recomputed summary: zero difference`. If it does not, an event landed in between: apply again. Recompute is a function of the documents, so repeating it is safe.
4. Record the run in `functions/loans/MEMORY.md`: date, environment, company, before and after totals (the marker holds them).

## 7. Open decisions for the owner

The tool is built on the defaults.

| # | Question | Default built | Alternative |
|---|---|---|---|
| 1 | Bucket date of a release | loan `created_at` | Store `approved_at` on the loan at approval (app change, both sides) and use it when present. Recommended as a follow-up; it is the only exact fix. |
| 2 | Bucket date of settlement and bad debt | loan `updated_at` | Store `completed_at` / `bad_debt_at` with the same follow-up. |
| 3 | Bucket date of a collection | `collected_at`, else `paid_at`, else `created_at` | `paid_at` first (when it was recorded, not when the money arrived). |
| 4 | Rows updated into a paid status | counted | Leave them out to match the trigger. Not recommended: the trigger is the side that is incomplete. Follow-up: run `loanScheduleChanges` on `written` with a status-transition guard. |
| 5 | Submissions rejected later | not counted | — (same follow-up as 4 makes the trigger reverse them). |
| 6 | Documents with `deleted_at` set | left out | Count them. The app does not soft-delete loans, schedules or capital today. |
| 7 | Loan without a product-type node | dropped and listed, as the trigger cannot book it either | Fall back to the product document's `loan_type`. |
| 8 | Unapplied claim younger than 7 days | apply refused | Mark such claims applied in the same write, so a redelivery becomes a no-op; or read the real retry window of the triggers and use it. |
| 9 | Run marker | `{company}/report_recomputes/{runId}`, totals before and after without the `data` list | Also keep the previous `data` list (doubles the node on every apply). |
| 10 | Smallest reported difference | 0.005 (half a centavo) | — |
| 11 | Top-ups (`additional_loan_amounts`) | not part of `total_amount_released`, as in the triggers | Count them; needs the same change in the triggers. |

## 8. Tests

- **Unit** (`test/triggers/report_recompute_test.go`, `cmd/recompute_reports/main_test.go`): hand-derived totals for a five-loan company; the collection date rule; dropped and skipped documents; the same documents in another order give the same node; replay-versus-recompute equivalence and the named differences; option checks; a dry run writes nothing; an apply writes the recompute and the marker once, then a second dry run shows zero difference and a second apply writes nothing; the refusals.
- **Integration** (`cmd/recompute_reports/emulator_test.go`, build tag `emulator`, Firestore and Realtime Database emulators, real adapters): a dry run leaves the whole company node untouched; an apply leaves `report_summary` equal to the recompute of the seeded documents, other nodes unchanged and one marker; another company's documents are not read; a trigger write during the run makes the conditional write fail.
- **Manual**: the built binary against the emulators, then one dry run against dev. Outputs are in the pull request.

## 9. Out of scope

Repairing dev, staging or production (each apply is a separate, recorded step); scheduling; a UI; changes to the triggers (follow-ups 1, 2 and 4 above); the Flutter reader.
