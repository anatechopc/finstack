# Report triggers rebuild — campaign Phase 2/3, option (a) in full

Date: 2026-09-09. Branch `fix/report-triggers-108` → `develop`. Owner decisions taken in session on 2026-09-09.

## 1. Goal

Make the three RTDB report writers (`loanChanges`, `loanScheduleChanges`, `capitalCreated` in `functions/loans/triggers/`) **idempotent, concurrency-safe and error-visible**, fix the catalogued defects D1–D8 (`.claude/skills/finstack-loan-engine-and-reporting-campaign/references/aggregation-triggers.md`), and put every number they write behind tests. Historical pollution is NOT repaired here: the recompute/backfill tool is the next PR (owner decision).

## 2. Owner decisions (2026-09-09)

| Decision | Choice |
|---|---|
| `completed` branch (D5/D6) | Books the **remaining principal**: `(amount + additional_charges − deductions − upfront) − Σ principal_payment − Σ extra_payment` as a collection and as returned capital. No interest is booked at completion; the Σ-of-all-schedules re-add that double counted every schedule payment is dropped. |
| Retries | `--retry` is enabled on the three report triggers in `.github/scripts/deploy_functions.sh`, safe because of the claim + atomic apply below. |
| Recompute tool | Separate PR (Phase 4). |

## 3. Design

### 3.1 Adapter + core (unwritten rule 4)

- `triggers/report_core.go` — pure planning. `PlanLoanReport`, `PlanScheduleReport`, `PlanCapitalReport` turn parsed event data into a `ReportPlan{Increments map[relPath]float64, Items []ReportDataItem}` relative to `{env}/companies/{companyId}/report_summary`. No I/O, no clock reads (the caller passes `Now`). Table-tested.
- `triggers/report_handlers.go` — `HandleLoanChangeCore` / `HandleScheduleCreatedCore` / `HandleCapitalCreatedCore(ctx, pathEnv, event, deps)` orchestrate: transition check → product type → schedules → plan → **claim the event id** → **apply atomically together with the applied marker**. `ReportDeps` injects `ReportStore`, `LoadSchedules`, `Now`, logging. `DecideClaim` is the one claim rule, shared by the RTDB transaction and the test fake.
- `triggers/report_store.go` — the RTDB adapter (`*db.Client`): `ClaimEvent` (transaction on `{company}/report_events/{eventId}`, a **sibling** of `report_summary` so the client, which streams `report_summary` in full, never downloads claims; the key is sanitised for RTDB), `ProductType`, `Apply` (one multi-path `Update` on the company node: counters as server-value increments `{".sv": {"increment": delta}}`, the data items, and `report_events/{eventId} = {applied: true}` in the same write).
- The three trigger files become thin adapters: proto → event struct → core. A document that fails to parse is logged and **dropped** (retrying cannot fix it); a missing product-type node is returned as an error and retried, because the app writes that node after the loan document. `loan_changes.go` keeps the notification section, now receiving `*firestoredata.DocumentEventData` (D8), and runs it only when the report step applied or was skipped for a non-transition (an already-applied redelivery sends no duplicate notification).
- Only rows that are payments (`paid_on_time`, `paid_late`, `payment_submitted`) contribute principal to the bad-debt and settlement sums: the app also persists planned rows (the first schedule at approval carries status `approved` and, for open-term loans, `principal_payment = amount`).
- The in-memory `ReportStore` fake lives with the tests (`test/triggers/report_fakes_test.go`).

### 3.2 Defect by defect

| ID | Fix |
|---|---|
| D1 re-fire | Loan plan acts only on a **status transition** into `approved` / `bad_debt` / `completed` (`status != old status`); same-status writes are no-ops. Redelivery of the *same* event is caught by the event-id claim (lease, §3.3). Documented limitation: a loan that leaves and re-enters `approved` is counted again (a new release). |
| D2 lost updates | Counters are applied with RTDB server-value increments inside **one atomic multi-path update**, so concurrent writers never read-modify-write. Proven on the emulator with the full six-node release plan under 50 concurrent writers (`-tags emulator`) and by `cmd/race_demo`. |
| D3 swallowed errors | The apply is a single call and its error is returned; with `--retry` a returned error re-delivers the event. Malformed documents are logged and dropped instead (retrying cannot fix them). |
| D4 wrong error wrapped | Rewritten; every error wraps its own cause. |
| D5 charges added then subtracted | Formula per §2. |
| D6 unvalidated `completed` branch | Formula per §2; table tests pin released amount, remaining principal, capital return and data items. |
| D7 `%$w` | Gone with the rewrite. |
| D8 vet lock copies | `*firestoredata.DocumentEventData` and `*db.Client` everywhere; `go vet ./...` prints nothing. |
| D13 (new) data-item overwrite | Two items in one event shared the same key (same timestamp), so the second `Set` overwrote the first (`refresh_capital` lost under `collection`). Keys are made unique within a plan by suffixing `:n`; the Flutter reader keys on `created_at`, not on the key. |
| D14 (new) delete events | `loanChanges` is deployed on `written`; a hard delete arrives with no value and today returns an error (with retries it would loop). It now returns nil. |

Semantics deliberately **kept** (not this PR's decision): `payment_submitted` rows count as collections at creation (before confirmation), and the same set of statuses counts as returned principal at settlement / bad debt; bad debt = `amount − Σ principal_payment` of paid rows, floored at zero (as is the settlement remainder: an overpaid loan is not a negative amount); the product-type node must exist or the event errors and is retried.

Small changes beyond the catalogue, listed so they are deliberate: whole-number `principal_payment` values stored as integers (the web app writes those) now count toward bad debt, where the old code only read doubles; non-report status transitions (`pending`, `declined`) are not claimed, so a platform redelivery of one of those can send its notifications twice (pre-existing at-least-once behaviour; notification failures are logged, not returned, so `--retry` only adds the case of a delivery that timed out mid-way); bad debt counts `principal_payment` only while settlement also counts `extra_payment` as returned principal (kept: bad debt keeps its historical definition).

### 3.3 Idempotency and failure windows

Order: transition check → product type → schedules → plan → claim → apply (increments + data items + applied marker in one write) → return. The claim is a **lease**: `DecideClaim` wins when nothing is recorded or the previous claim is older than 10 minutes and not applied; returns *applied* when the marker is set; otherwise *in progress*, which the handler surfaces as an error so the platform retries later. The claim is never released. Outcomes of every failure:

| Failure | Result |
|---|---|
| Crash between claim and apply | lease expires, the retry (or next redelivery) re-applies once |
| Apply committed on the server but the client saw an error | the marker landed with the increments; the retry sees *applied* and does nothing |
| Apply genuinely failed | no marker; the retry waits out the lease, then re-applies once |
| Two deliveries at the same time | one wins, the other is told to retry later |

An event is never counted twice. The only way an event is lost is a delivery that fails permanently for the whole retry window; the recompute tool (next PR) covers that. Claims live under `{company}/report_events/{eventId}` (tiny records; unbounded).

## 4. Proofs (Phase 2 obligations)

- **Idempotency:** the same event delivered twice through the core with the fake store yields one apply and unchanged totals; the same through the real store against the emulator (`emulator` build tag); an apply that committed while the client saw an error is a no-op on retry; a genuine failure waits out the lease then applies once; twenty concurrent deliveries of one event apply once.
- **Concurrency:** against the emulator, 50 concurrent applies of the full six-node release plan land exactly 50 on every node; `cmd/race_demo` shows the old Get/Set losing updates next to it. Both refuse to run without `FIREBASE_DATABASE_EMULATOR_HOST`.
- **Numbers:** table tests per branch with hand-derived expectations (approved, bad debt and completed per §2 with the planned rows the app really persists, settlement before any payment, overpayment floor, schedule collection, capital, key de-duplication, ISO-week year boundary) plus internal tests of the proto parsing (integer and double values, missing optionals, create vs update, delete).

## 5. Rollout

Backend PR to `develop` (auto-deploys dev functions). Observe `dev/companies/*/report_summary` under app usage; then `release/**`, then `master`. Deploy script change: `--retry` on the three writers. `functions/loans/MEMORY.md` records the Phase 3 decision (option (a) in full, recompute deferred) and the proof outputs.

## 6. Out of scope

Recompute/backfill (Phase 4), the Flutter reader, the `capital_usage` semantics on release, D9–D12 (Flutter engine, tracked as finstack#116/#117/#120).
