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
- `triggers/report_handlers.go` — `HandleLoanChangeCore` / `HandleScheduleCreatedCore` / `HandleCapitalCreatedCore(ctx, pathEnv, event, deps)` orchestrate: parse → plan → (product type) → **claim event id** → **apply atomically** → release the claim on failure. `ReportDeps` injects `ReportStore`, `LoadSchedules`, `Now`, logging.
- `triggers/report_store.go` — the RTDB adapter (`*db.Client`): `ClaimEvent` (transaction on `report_summary/applied_events/{eventId}`: absent → set true, present → not claimed), `ReleaseEvent`, `ProductType`, `Apply` (one multi-path `Update` on `report_summary` using RTDB server-value increments `{".sv": {"increment": delta}}` for counters plus the data items).
- The three trigger files become thin adapters: proto → event struct → core. `loan_changes.go` keeps the notification section, now receiving `*firestoredata.DocumentEventData` (D8), and runs it only when the report step applied or was skipped for a non-transition (a redelivered, already-applied event sends no duplicate notification).
- The in-memory `ReportStore` fake lives with the tests (`test/triggers/report_fakes_test.go`).

### 3.2 Defect by defect

| ID | Fix |
|---|---|
| D1 re-fire | Loan plan acts only on a **status transition** into `approved` / `bad_debt` / `completed` (`status != old status`); same-status writes are no-ops. Redelivery of the *same* event is caught by the event-id claim. Documented limitation: a loan that leaves and re-enters `approved` is counted again (a new release). |
| D2 lost updates | Counters are applied with RTDB server-value increments inside **one atomic multi-path update**, so concurrent writers never read-modify-write. Proven on the emulator (race test + `cmd/race_demo`). Fallback if the emulator rejects `.sv increment`: per-node `Ref.Transaction`. |
| D3 swallowed errors | The apply is a single call; the remaining multi-error site (apply failed AND release failed) uses `errors.Join`, and the trigger returns the error. With `--retry`, a returned error re-delivers the event; the claim is released first so the retry re-applies. |
| D4 wrong error wrapped | Rewritten; every error wraps its own cause. |
| D5 charges added then subtracted | Formula per §2. |
| D6 unvalidated `completed` branch | Formula per §2; table tests pin released amount, remaining principal, capital return and data items. |
| D7 `%$w` | Gone with the rewrite. |
| D8 vet lock copies | `*firestoredata.DocumentEventData` and `*db.Client` everywhere; `go vet ./...` prints nothing. |
| D13 (new) data-item overwrite | Two items in one event shared the same key (same timestamp), so the second `Set` overwrote the first (`refresh_capital` lost under `collection`). Keys are made unique within a plan by suffixing `:n`; the Flutter reader keys on `created_at`, not on the key. |
| D14 (new) delete events | `loanChanges` is deployed on `written`; a hard delete arrives with no value and today returns an error (with retries it would loop). It now returns nil. |

Semantics deliberately **kept** (not this PR's decision): `payment_submitted` rows count as collections at creation (before confirmation); bad debt = `amount − Σ principal_payment`; the product-type node must exist or the event errors (and, with retries, is retried).

### 3.3 Idempotency and failure windows

Order: transition check → product type → schedules → claim → apply → (on apply failure) release → return error. The only unrecoverable window is a crash between claim and apply (the event is lost, never double counted); the recompute tool covers it. Claims live under `report_summary/applied_events/{eventId}` (tiny booleans; unbounded).

## 4. Proofs (Phase 2 obligations)

- **Idempotency:** the same event delivered twice through the core with the fake store yields one apply and unchanged totals; the same through the real store against the emulator (`emulator` build tag).
- **Concurrency:** against the emulator, 50 goroutines × increment lands exactly 50 with the atomic path; `cmd/race_demo` shows the old Get/Set losing updates next to it. Both refuse to run without `FIREBASE_DATABASE_EMULATOR_HOST`.
- **Numbers:** table tests per branch with hand-derived expectations (approved, bad debt, completed per §2, schedule collection, capital, key de-duplication).

## 5. Rollout

Backend PR to `develop` (auto-deploys dev functions). Observe `dev/companies/*/report_summary` under app usage; then `release/**`, then `master`. Deploy script change: `--retry` on the three writers. `functions/loans/MEMORY.md` records the Phase 3 decision (option (a) in full, recompute deferred) and the proof outputs.

## 6. Out of scope

Recompute/backfill (Phase 4), the Flutter reader, the `capital_usage` semantics on release, D9–D12 (Flutter engine, tracked as finstack#116/#117/#120).
