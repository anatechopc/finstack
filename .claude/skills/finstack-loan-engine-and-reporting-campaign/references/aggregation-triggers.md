# RTDB aggregation triggers — defect catalog (verified against source 2026-07-07)

> **Status 2026-09-09:** D1–D8 FIXED on branch `fix/report-triggers-108`
> (spec `docs/superpowers/specs/2026-09-09-report-triggers-rebuild.md`).
> The three writers are adapter + core: `triggers/report_core.go` plans,
> `report_store.go` applies one atomic multi-path update with server-value
> increments after claiming the event id, `report_handlers.go` orchestrates.
> Also fixed: **D13** two data items of one event shared a key (the second
> overwrote the first); **D14** hard deletes on the `written` trigger
> returned an error forever; **D15** the schedule query used
> `{env}_loan_schedules`, which in production named a non-existent
> collection (bad-debt/completed maths ran with zero schedules). The
> line-number evidence below describes the code BEFORE that change; keep it
> as the incident record.

> **Status 2026-11-13 (Phase 4):** the recompute tool is built (branch
> `feat/report-recompute-tool`, PR #132; core `triggers/report_recompute.go`, CLI
> `cmd/recompute_reports/`, spec
> `docs/superpowers/specs/2026-11-13-report-recompute-tool.md`). It rebuilds
> one company's `report_summary` from Firestore through the same planning
> functions the triggers use. No repair has been applied in any environment.
> Building it surfaced **D16–D18** below. The section "Recompute tool" after
> them has the commands.

This is Phase 2 working material for the campaign in `../SKILL.md`. Every
defect below was verified by reading the file at the stated line on
2026-07-07 (branch `feature/chat-messaging`). Line numbers drift — re-grep
the quoted snippet if a number does not land.

Primary file: `functions/loans/triggers/loan_changes.go` (the `loanChanges`
trigger). The same helper functions (`applyToNodeValue`, `addReportDataItem`)
and the same defect patterns are shared by two more report writers:
`triggers/loan_schedule_changes.go` (payment collections) and
`triggers/capital_created.go` (capital additions). Any fix must cover all
three writers.

## Report data flow (who writes / who reads)

- **Writers (Go, RTDB via Admin SDK — bypasses RTDB security rules):**
  - `loanChanges` — deployed on event `google.cloud.firestore.document.v1.written`
    for `{prefix}loans/{uid}` (see the `loanChanges` deploy line in
    `.github/scripts/deploy_functions.sh`). Fires on EVERY create AND update.
  - `loanScheduleChanges` — on `…document.v1.created` for `{prefix}loan_schedules/{uid}`.
  - `capitalCreated` — on `…document.v1.created` for `{prefix}capital/{uid}`.
- **Node layout (RTDB):** base `{dev|stg|""}/companies/{companyId}/report_summary`
  with children `sales`, `products/{productType}`,
  `total_summary/year:Y[:month:M[:week:W[:day:D]]]`, `capital_usage`, and an
  append-only `data/` list (`addReportDataItem`). The RTDB env prefix is
  `dev`/`stg`/`""` from the local `getPathEnv()` in `loan_changes.go` — NOT
  the Firestore `dev_`/`stg_` prefix (see finstack-config-and-environments).
- **Product-type lookup:** `getProductType` reads RTDB node
  `…/companies/{companyId}/loans/{loanId}:product_type`, which the **Flutter
  app** writes in
  `packages/loans/loan_repository/lib/src/data/database/loan_realtime_database_service.dart`
  (`dbRef.child('$loanId:product_type').set(productType)`). If that node was
  never written, the whole trigger returns `cannot get product type` and NO
  report data is written for that loan event.
- **Reader (Flutter):**
  `packages/loans/reports_repository/lib/src/data/database/reports_realtime_database_service.dart`
  reads `report_summary` and `report_summary/{products,total_summary,capital_usage,sales}`;
  rendered by `apps/loans/lib/features/reports/widgets/` (e.g.
  `report_cards_widget.dart`, whose "Total capital breakdown" carries a TODO
  for loooans#60 — old-repo ticket, refile on finstack if still wanted).

## Defects (all in `functions/loans/triggers/loan_changes.go` unless noted)

### D1 — Non-idempotent re-fire: totals inflate on every loan-doc update
- The trigger is deployed on `written` (create + update), and the report
  branch keys ONLY on the current `status` field — there is no old-vs-new
  comparison. (The notification section at the bottom of `LoanChanges` DOES
  compare `status != oldStatus`; the report section does not.)
- Consequence: any write to a loan document whose status is `approved`
  (adding an additional loan amount, editing amortization, adding a
  co-maker, …) re-adds the full loan `amount` to `total_amount_released`
  across year/month/week/day, product, and sales nodes, and appends another
  `release` data item. Same for re-writes in `bad_debt`/`completed` states.
- This alone makes historical totals untrustworthy (see Phase 4 backfill in
  SKILL.md).
- Status: verified in code; magnitude of prod pollution UNVERIFIED (needs the
  Phase 4 recompute-vs-actual diff).

### D2 — Non-transactional read-modify-write: lost updates under concurrency
- `applyToNodeValue` (~line 462): `ref.Get(ctx, &value)` then
  `ref.Set(ctx, value+applyValue)`. Two concurrent trigger executions on the
  same company read the same value; the slower Set overwrites the faster one.
- Concurrency is real: gen2 functions run concurrent instances; two tellers
  approving loans of the same company, or `loanChanges` +
  `loanScheduleChanges` firing together, race on the same `total_summary`
  nodes.
- Fix direction: `db.Ref.Transaction` (verified available in
  `firebase.google.com/go/v4 v4.13.0`, the version in `triggers/go.mod`).
- Proof: `scripts/race_demo/` (skill-local, transaction variant) — see
  "Discriminating experiment" below. Run 2026-07-07: racy 2/50, txn 50/50.
  Shipped fix (2026-09-09): server-value increments in one multi-path
  update, proven by `functions/loans/cmd/race_demo` (racy 2/50, atomic
  50/50) and `functions/loans/test/triggers/report_store_emulator_test.go`
  (the six-node release plan under 50 concurrent writers: 50/50 on every
  node).

### D3 — Swallowed errors: `dataErrors` reassigned, not accumulated
- Every branch does `dataErrors = applyToNodeValue(...)` repeatedly
  (~lines 111-120, 158-167, 264-295). Only the LAST call's error survives;
  earlier failures are silently dropped, so partial report writes look like
  success (no retry, no log).
- Same pattern in `loan_schedule_changes.go` (~94-160) and
  `capital_created.go` (~89-95).
- Fix direction: `errors.Join(dataErrors, …)` (Go 1.20+; module is on
  go 1.22.12) — but decide retry semantics first: a returned error makes
  Eventarc retry the WHOLE trigger, which without the D1/D2 fixes
  double-counts. Error accumulation is only safe once writes are idempotent.

### D4 — Wrong error wrapped in `applyToNodeValue`
- The Set-failure path returns
  `fmt.Errorf("cannot apply to %s: %w", pathToNodeValue, err)` — but `err`
  is the (nil) Get error; the actual `setErr` is discarded. Any surviving
  message about a failed Set carries no cause.

### D5 — `completed` branch: `additional_charges` both added and subtracted
- `totalLoanAmount` starts at `amount`, then: `+ additional_charges`
  (~190-196), `- deductions` (~198-204), `- additional_charges` AGAIN
  (~206-212, a copy-paste of the deductions block), and
  `- additional_charge_upfront_collection` (~214-220).
- Net effect: `amount - deductions - upfront` — the additional charges
  cancel out. Per the domain formula (`loanAmount = amount +
  additionalCharges - deductions`, see loans-domain-reference) the intended
  value almost certainly keeps `+ additional_charges`; the second
  subtraction block is the bug. Confirm intent against the early-settlement
  formula (golden scenario G7) before fixing.

### D6 — `TODO(deibeeed) complete this for report` at line 171
- The `completed` branch carries this TODO. The branch HAS substantial code
  (collections/interest/principal totals + `refresh_capital`), but it was
  never finished/validated — D5 lives in it, and the maintainer named
  reporting "partially implemented, badly designed". Treat every number this
  branch writes as unvalidated until the Phase 2 tests exist.

### D7 — `%$w` format-verb typos
- Lines ~144 and ~183:
  `fmt.Errorf("cannot get loan schedules for loanId %s: %$w", loanId, collectionErr)`.
  `%$w` is not a verb — the message prints with `%!$…` noise and the cause
  is not wrapped (breaks `errors.Is/As` and log greps).

### D8 — `go vet` lock-copy warnings (2, pre-existing)
- Run: `cd functions/loans/triggers && CGO_ENABLED=0 go vet ./...`
- Output (verified 2026-07-07):
  - `./loan_changes.go:317:87: call of createLoanStatusNotifications copies lock value: … firestoredata.DocumentEventData contains … sync.Mutex`
  - `./loan_changes.go:334:7: createLoanStatusNotifications passes lock by value: …`
- Cause: `data firestoredata.DocumentEventData` (a protobuf message) passed
  by value. Fix: pass `*firestoredata.DocumentEventData`.
- NOTE: older notes describe these as "db.Client lock copies". Reality: vet
  flags the protobuf copies above. Separately, the code DOES pass
  `*dbClient` (a dereferenced `db.Client`) by value into `applyToNodeValue`
  / `addReportDataItem` / `getProductType` — vet does not flag that, but
  change those signatures to `*db.Client` while you are in there.
- Root-module `go vet ./...` from `functions/loans/` is clean — it does NOT
  cover the sub-modules. Vet each sub-module directory.

### D9 (Flutter, CONFIRMED 2026-09-08 → finstack#116) — early-settlement balance sums only the last schedule
- Now `LoanCalculationService.calculateSettlementBalance` in
  `apps/loans/lib/services/loan_calculation_service.dart` (extracted from
  the bloc 2026-09-08; the bloc delegates):

  ```dart
  for (final schedule in paidSchedules) {
    totalLoanPayment = (schedule.isOpenTerm
            ? schedule.interestCharge
            : schedule.interestPayment) +
        schedule.principalPayment +
        schedule.extraPayment;
  }
  ```

  `=` instead of `+=` — with 2+ paid schedules the displayed remaining
  balance ignores all but the last schedule's payments (overstates the
  balance owed).
- Status 2026-09-08: CONFIRMED and pinned — G7
  (`test/services/loan_calculation_settlement_test.dart`) shows
  10200 - 1400 = 8800. The independent review of PR #115 found the formula
  wrong in four ways, so finstack#116 is a design decision, not `+=`:
  1. assigns instead of accumulating — and because the bloc's list comes
     back newest-first (`loan_schedule_firestore_service.dart` orders
     `updated_at` DESC) production credits the LEAST recently updated row;
  2. `+=` would be wrong too: released − Σ payments subtracts interest from
     principal (an interest-only open-term loan trends to zero);
  3. the rows come from `payment_id != null`, which includes borrower
     submissions not yet confirmed (`payment_submission_bloc.dart`);
  4. open-term rows credit the computed `interestCharge`, not the recorded
     `interestPayment`; approved top-ups (`loan.additionalLoanAmounts`) are
     not part of the released amount.
  Direction: settlement = last row's outstanding balance (top-ups included)
  + accrued interest, over confirmed rows only. Flip G7 with the fix.

### D10 (Flutter, CONFIRMED 2026-09-08 → finstack#117) — top-up interest copied onto the next row
- `calculateOpenTerm` (`apps/loans/lib/services/loan_calculation_service.dart`,
  the `lastLoanSchedule..outstandingBalance = ... ..interestCharge = ...`
  mutation after inserting the placeholder) copies the placeholder's
  prorated interest onto the adjacent computed schedule and never
  recomputes its amortization. G9 pins it: next row shows 83.33 on 12100
  where 12100 × 5% × 25/30 = 504.17 is due (owner decision).

### D11 (Flutter, CANDIDATE) — open-term day math is not DST-safe
- jiffy 6.4.4 `add(days:)` is a `Duration` add and `diff(unit: Unit.day)`
  floors microseconds; across a fall-back a due date lands at 23:00 the
  previous day (a calendar day early once read as a date) and across a
  spring-forward a proration is one day short. Product is Asia/Manila
  (no DST) today, so no user is affected; the golden suite states the
  assumption and CI pins `TZ=UTC`. Confirmed by running the suite under
  America/New_York, Europe/London and Australia/Sydney (review of PR #115).

### D12 (Flutter, CONFIRMED 2026-09-08 → finstack#120) — overdue open-term row bills one month while the charge grows
- `calculateOpenTermSchedules` sets
  `amortization = min(min(monthlyAmortization, OB + interestCharge), interestCharge)`
  with `monthlyAmortization = OB × rate`, so once the past-due clamp makes
  the prorated charge exceed one month the amount due stays at the month
  (G4c: interestCharge 633.33, amortization 500). Owner decides whether an
  overdue row bills full accrual; flip G4c with the fix.

### D16 (Go, CANDIDATE 2026-11-13, not fixed) — `loanScheduleChanges` books created rows only
- The trigger is deployed on `…document.v1.created`. The app also changes
  rows by update: the planned row persisted at approval is later paid with
  `loanScheduleRepository.update` (`payment_bloc.dart`,
  `payment_center_bloc.dart`, `payment_submission_bloc.dart` when
  `schedule.id != NO_ID`), and `PaymentConfirmationService.reject` reverts a
  `payment_submitted` row to `not_paid`.
- Consequence: a row paid by update is never booked as a collection; a
  rejected submission stays booked. Recompute reads the final status, so it
  counts the first and not the second
  (`TestRecompute_DiffersFromTheTriggers_OnlyInTheNamedWays`).
- Fix direction: deploy on `written` with a status-transition guard like the
  loan trigger's (book on entering a paid status, reverse on leaving it).
  Magnitude in real data UNVERIFIED.

### D17 (Go, CANDIDATE 2026-11-13, not fixed) — data items of two events in the same millisecond share a key
- `dataItemKey` is built from the handling time to the millisecond. D13 made
  keys unique within one event; two different events handled in the same
  millisecond still write the same `data/{key}` and the later item replaces
  the earlier. Totals are unaffected (increments). Recompute suffixes `:2`,
  `:3` across the whole summary.

### D18 (schema, OPEN 2026-11-13) — the loan document records no approval or completion date
- Loans carry `created_at` and `updated_at` only. The triggers bucket a
  release, settlement or bad debt on the time they handled the event, which
  no document records, so recompute cannot reproduce those buckets exactly:
  it uses `created_at` for the release and `updated_at` for settlement and
  bad debt (spec §4, owner decisions 1 and 2). Exact buckets need
  `approved_at` / `completed_at` / `bad_debt_at` written by the app (schema
  change, both sides).

## Recompute tool (Phase 4, 2026-11-13)

```bash
cd functions/loans
# dry run: reads Firestore and the live node, prints recomputed vs live, writes nothing
go run ./cmd/recompute_reports -env dev -company <companyId>
# apply: one conditional write of report_summary + a run marker under report_recomputes/
go run ./cmd/recompute_reports -env dev -company <companyId> -apply
# production needs the company id twice
go run ./cmd/recompute_reports -env prod -company <id> -apply -confirm-prod <id>

# proofs against the emulators (Firestore needs Java)
cd apps/loans && firebase emulators:start --only database,firestore --project demo-finstack
cd functions/loans && FIRESTORE_EMULATOR_HOST=localhost:8081 \
  FIREBASE_DATABASE_EMULATOR_HOST='localhost:9000?ns=demo-finstack' \
  go test -tags emulator ./cmd/recompute_reports/ -run Emulator -v
```

- Source and formula per total, bucket dates, the race with triggers and the
  operator procedure: the spec. Per-run evidence: the run log in
  `functions/loans/MEMORY.md`.
- With both emulator variables set the CLI talks to the emulators only
  (project `demo-finstack`); with one of them set it refuses to run.
- An apply is refused while an event is claimed and not applied under
  `report_events` (younger than 7 days), when no document is found for the
  company, and when a trigger wrote to the summary during the run.

## Untested-code reality

- None of the three report writers has any test:
  `functions/loans/test/triggers/` covers message/payment/review/user
  triggers only (verified by listing the directory).
- They are pre-adapter+core monoliths. Unwritten rule 4: touched Go code
  must be refactored to adapter+core with fakes-based tests — so ANY fix
  here starts with that extraction (recipe in finstack-testing-and-validation;
  fake conventions in `functions/loans/test/fakes/fakes.go`).

## Discriminating experiment for D2 (race proof)

> 2026-09-09: the shipped implementation uses server-value increments, not
> `Ref.Transaction`. The proof for the shipped path is
> `cd functions/loans && FIREBASE_DATABASE_EMULATOR_HOST='localhost:9000?ns=demo-finstack' go run ./cmd/race_demo -n 50`
> (both modes in one run; `apps/loans/firebase.json` already configures the
> emulator on port 9000, start it with
> `cd apps/loans && firebase emulators:start --only database --project demo-finstack`).
> The block below is the original transaction demo, kept as the record.

Run `scripts/race_demo/` (it refuses to start unless
`FIREBASE_DATABASE_EMULATOR_HOST` is set — emulator only, honoring the
never-touch-prod rule):

```bash
# terminal 1 — any directory with a firebase.json works; simplest is a temp dir:
mkdir -p /tmp/race-emu && cd /tmp/race-emu
printf '{"database":{"rules":"database.rules.json"},"emulators":{"database":{"port":9000}}}' > firebase.json
printf '{"rules":{".read":true,".write":true}}' > database.rules.json
firebase emulators:start --only database --project demo-race

# terminal 2
cd .claude/skills/finstack-loan-engine-and-reporting-campaign/scripts/race_demo
CGO_ENABLED=0 FIREBASE_DATABASE_EMULATOR_HOST=localhost:9000 go run . -n 50        # racy: expect << 50, exit 1
CGO_ENABLED=0 FIREBASE_DATABASE_EMULATOR_HOST=localhost:9000 go run . -n 50 -txn   # fixed: exactly 50, exit 0
```

(`CGO_ENABLED=0` is the standard macOS `dyld: missing LC_UUID` workaround —
see finstack-build-and-env.)

The racy mode is a line-for-line mirror of `applyToNodeValue`; `-txn` is the
`Ref.Transaction` replacement. Exit code 1 on lost updates makes it usable
as a CI-able proof once the fix lands. Observed 2026-07-07: racy 2/50,
txn 50/50.

## Fix-ordering constraint (matters!)

D1 (idempotency) must be fixed BEFORE or WITH D3 (error accumulation).
Returning accumulated errors triggers Eventarc redelivery; redelivered
events re-run the whole handler, and without idempotency every retry
inflates totals further. Safe order: idempotency guard (status-transition
check using `data.GetOldValue()`) → transactions (D2) → error accumulation
(D3/D4/D7) → completed-branch math (D5/D6) — each step behind the Phase 2
tests described in SKILL.md.
