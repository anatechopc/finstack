# RTDB aggregation triggers — defect catalog (verified against source 2026-07-07)

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
- Proof: `scripts/race_demo/` — see "Discriminating experiment" below. Run
  2026-07-07: racy mode landed 2/50 increments (48 lost); txn mode 50/50.

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

### D9 (Flutter, CANDIDATE) — early-settlement balance sums only the last schedule
- `apps/loans/lib/features/loans/bloc/loan_settlement_bloc.dart` ~104-110:

  ```dart
  for (final schedule in loanSchedules) {
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
- Status: CANDIDATE — the pattern is almost certainly a bug, but pin the
  intended semantics with golden scenario G7 before changing it. The bloc
  has no test seam (constructor takes `BuildContext`); extract the formula
  into a pure helper first (see golden-scenarios.md, G7).

## Untested-code reality

- None of the three report writers has any test:
  `functions/loans/test/triggers/` covers message/payment/review/user
  triggers only (verified by listing the directory).
- They are pre-adapter+core monoliths. Unwritten rule 4: touched Go code
  must be refactored to adapter+core with fakes-based tests — so ANY fix
  here starts with that extraction (recipe in finstack-testing-and-validation;
  fake conventions in `functions/loans/test/fakes/fakes.go`).

## Discriminating experiment for D2 (race proof)

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
