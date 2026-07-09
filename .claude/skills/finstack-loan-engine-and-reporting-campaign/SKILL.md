---
name: finstack-loan-engine-and-reporting-campaign
description: "Use when touching loan computation (loan_calculation_service.dart, open-term or fixed-term schedules, additional loans/top-ups, early settlement, charges) or the RTDB report aggregation (loanChanges / loanScheduleChanges / capitalCreated triggers, report_summary totals); when report totals look inflated, missing, or irreproducible; when loan schedules show wrong outstanding balances or interest; or when planning, reviewing, or resuming the loan-math/reporting-rebuild campaign work."
---

# Loan engine + reporting rebuild campaign

The maintainer named this finstack's hardest live problem (2026-07-07): loan
creation/computation/updates — especially **open-term loans** — and a
reporting system that is "partially implemented, badly designed". This skill
is the executable campaign to fix it. It is decision-gated: each phase has an
entry gate and a falsifiable exit; do not skip gates.

**Goal (measurable, never eyeballed):**
1. Loan math is provably correct — a golden scenario suite whose expected
   numbers were derived BY HAND from the formulas, green in CI.
2. Reporting is rebuilt on sound foundations — idempotent, concurrency-safe,
   error-visible writers, plus a sanctioned recompute path that makes
   historical totals reproducible from Firestore source data.

## When NOT to use this skill

- Formula/domain questions (what is open-term, how charges compose, term
  string grammar) → **loans-domain-reference**.
- Test mechanics (fakes, bloc seams, adapter+core recipe, coverage reality)
  → **finstack-testing-and-validation**.
- A reporting/loan bug you are triaging cold → **finstack-debugging-playbook**
  first; come here once the fix touches math or aggregation.
- Full incident narratives (finstack#33 story, Chain B timestamps) →
  **finstack-failure-archaeology**.
- Branch/deploy/PR rules the campaign must obey → **finstack-change-control**.
- The RTDB/Firestore rules exposure of `report_summary` →
  **finstack-security-hardening**.

## Terrain map (verified paths)

| Artifact | Path |
|---|---|
| Math core (Flutter, static methods) | `apps/loans/lib/services/loan_calculation_service.dart` |
| Amortization formula | `apps/loans/lib/utils/extensions.dart` (`calculateMonthlyPayment`) |
| Charges math | `apps/loans/lib/services/charge_calculator.dart` |
| Early settlement (inline formula, no seam) | `apps/loans/lib/features/loans/bloc/loan_settlement_bloc.dart` |
| Math call sites | `loans_functions.dart`, `payment_center_bloc.dart`, `reports_bloc_extension_soa.dart`, (`additional_loan_bloc.dart` historically) |
| Report writers (Go) | `functions/loans/triggers/loan_changes.go`, `loan_schedule_changes.go`, `capital_created.go` |
| Report reader (Flutter) | `packages/loans/reports_repository/.../reports_realtime_database_service.dart` + `apps/loans/lib/features/reports/` |
| Existing math test (1 test) | `apps/loans/test/services/loan_calculation_service_test.dart` |
| Campaign references | `references/golden-scenarios.md`, `references/aggregation-triggers.md` |
| Race proof tool (emulator-only) | `scripts/race_demo/` |

Standing constraints (see finstack-change-control for the full set): never
touch prod data by hand; schema changes ship both sides, backend first;
console rule changes need a repo note; touched Go code becomes adapter+core
with fakes tests; update MEMORY.md when you land campaign work.

## PHASE 0 — Baseline (run before changing anything)

Record what exists and passes TODAY so every later claim is a diff, not an
impression.

```bash
# Flutter app suite
cd apps/loans
fvm flutter test --test-randomize-ordering-seed random

# Just the math-core tests
fvm flutter test test/services/

# Go functions suite (CGO_ENABLED=0 is the macOS dyld workaround)
cd ../../functions/loans
CGO_ENABLED=0 go test ./...

# Vet the triggers sub-module (root `go vet ./...` does NOT cover sub-modules)
cd triggers && CGO_ENABLED=0 go vet ./...
```

Expected observations — actuals recorded 2026-07-07 (branch
`feature/chat-messaging`); re-run and update if they drift:

- App suite: **76 tests, all pass** (~coverage concentrated in newest
  features; the math core has exactly **1 test** — the `calculateFixedTerm`
  paid-schedules contract).
- Go: `ok` for `test/api/users`, `test/triggers`, `test/utils` — **159 test
  cases incl. subtests** (`go test ./test/... -count=1 -v | grep -c "^=== RUN"`).
  **Zero tests** for the three report writers.
- `go vet` (triggers module): **2 lock-copy warnings** in `loan_changes.go`
  (lines ~317/~334, protobuf `DocumentEventData` by value) — pre-existing.
- Separately known: 2 package scaffold tests fail pre-existing
  (`address_repository`, `bank_details_repository`; `apps/loans/MEMORY.md`
  ~line 343) — unrelated to this campaign, do not chase.

Also inventory current behavior you will later have to preserve or
deliberately change: read `references/golden-scenarios.md` "Clock coupling"
(the math core reads the wall clock — affects test design) and note the
open-term `totalLoanPayment == double.infinity` sentinel.

**Gate 0 → 1:** baseline numbers recorded (in your working notes/PR
description), no unexplained failures.

## PHASE 1 — Golden scenario suite for the math core

Full scenario table, fixture recipes, and the worked-derivation template are
in **`references/golden-scenarios.md`**. Summary:

- G1/G2: fixed-term amortization (`'1m'`, `'15d'`) vs hand-computed tables.
- G3: resume-from-paid-schedules contract (exists — keep).
- G4a/G4b: open-term 30-day and 15-day proration + interest-only invariants
  + the `double.infinity` sentinel.
- G5/G5b: `'D1,D2'` salary-day term parsing (comma grammar, day ordering).
- G6: proration across a month boundary (1 month = 30 days convention).
- G7: early settlement remaining balance (requires extracting the formula
  from `LoanSettlementBloc` to a pure helper first — behavior-preserving).
- G8: charges trio (`additionalCharges` / `deductions` / upfront) through
  `ChargeCalculator`.
- G9/G10 (+G11): the three root causes of **finstack#33** (consecutive
  open-term additional loans, closed issue finstack#4) encoded as regression
  cases.

Method rule ("prove it, don't just install it"): every expected number is
derived on paper from the formulas BEFORE the test is written, using the
template derivation in the reference. If a test fails, you re-derive by hand
before touching code — the double derivation is the proof.

**Gate 1 → any math change:** `fvm flutter test test/services/` green with
G1-G10 present, plus the mutation check (locally change `/ 30` to `/ 31` in
`loan_calculation_service.dart` → at least one test fails → revert). **No
change to loan math semantics may merge before this suite exists and is
green.** That is the finstack#33 lesson: three interacting root causes were
only separable because each got its own oracle.

## PHASE 2 — Reporting defect catalog + proofs

The verified defect catalog (D1-D9, with file/line evidence and fix
directions) is **`references/aggregation-triggers.md`**. Headlines:

| ID | Defect | Where |
|---|---|---|
| D1 | Non-idempotent re-fire: trigger on `written` + no old/new status check → totals inflate on every loan-doc update | `loan_changes.go` |
| D2 | Non-transactional Get→Set (`applyToNodeValue`) → lost updates under concurrency | all 3 writers |
| D3 | `dataErrors` reassigned (`=`) not accumulated → errors swallowed | all 3 writers |
| D4 | Set-failure wraps the wrong (nil) error | `applyToNodeValue` |
| D5 | `completed` branch adds AND subtracts `additional_charges` (nets to zero) | `loan_changes.go` ~190-212 |
| D6 | `TODO(deibeeed) complete this for report` — completed branch unfinished/unvalidated | `loan_changes.go:171` |
| D7 | `%$w` format typos (unwrapped errors) | `loan_changes.go` ~144/~183 |
| D8 | 2 `go vet` lock-copy warnings (protobuf by value) | `loan_changes.go` ~317/~334 |
| D9 | CANDIDATE: settlement balance sums only last schedule (`=` vs `+=`) | `loan_settlement_bloc.dart` ~104 |

Required proofs in this phase (before choosing a solution):

1. **Race proof (D2):** run `scripts/race_demo/` against the RTDB emulator —
   exact commands in the reference. Verified run 2026-07-07: racy mode
   landed 2/50 increments; transaction mode 50/50. The tool refuses to run
   without `FIREBASE_DATABASE_EMULATOR_HOST` set (never-touch-prod).
2. **Idempotency demonstration (D1):** deliver the same `approved` loan
   event twice through the extracted core (or emulator) and show
   `total_amount_released` doubles. This becomes the regression test.
3. Read the **fix-ordering constraint** in the reference: error accumulation
   (D3) before idempotency (D1) makes retries AMPLIFY corruption. Order is
   D1 → D2 → D3/D4/D7 → D5/D6, each behind tests.

**Gate 2 → 3:** every defect either reproduced by a test/experiment or
explicitly marked not-reproducible-with-reason in your notes.

## PHASE 3 — Solution menu (ranked) and decision gate

**(a) Fix-in-place** — keep the trigger-fan-in design; make it correct.
Idempotency guard via `data.GetOldValue()` status comparison; `Ref.Transaction`
per node; `errors.Join` accumulation; adapter+core extraction with fakes
tests for all three writers (unwritten rule 4 makes this mandatory anyway).
*Theory obligations:* prove idempotency (double-delivery test) AND
concurrency safety (transaction race test) — both as repeatable tests, not
arguments. Accept that historical pollution remains (Phase 4 must still
repair data).

**(b) Redesign aggregation** — demote RTDB totals to a cache; make Firestore
(`loans`, `loan_schedules`, `capital`) the declared source of truth with a
single writer: either a scheduled recompute job (see the disabled `job/`
module pattern) or on-demand recompute per company.
*Theory obligations:* write down the source-of-truth definition per total
(which Firestore query produces `total_amount_released` for a period);
implement **recompute-from-scratch** for one company node and prove
recompute(recompute(x)) == recompute(x); define staleness budget (reports
stop being real-time — confirm acceptable with the maintainer); migration
cutover plan.

**(c) Hybrid (default recommendation)** — (a) now to stop active corruption,
then (b)'s recompute function built as the Phase 4 backfill tool and kept as
the permanent repair/verification path. Obligations of both, but the
recompute tool is built once and reused.

**Decision gate — choose using these criteria, record the decision + date in
`functions/loans/MEMORY.md`:**
- Phase 4 pre-check shows material prod pollution → recompute capability is
  mandatory → (c) or (b). (Given D1 fires on every loan update, expect this.)
- Reporting UI needs new dimensions/back-dated corrections → (b)/(c); pure
  (a) cannot repair the past.
- Tight effort budget → minimum acceptable bar is (a) in FULL. Shipping D3
  error accumulation without the D1 idempotency guard is forbidden (retry
  amplification).
- Whatever is chosen: the three writers ship together, backend-first, tests
  first (change-control rules).

## WRONG PATHS — fenced off (do not do these)

1. **Hand-editing RTDB report totals** in the console (any env, and NEVER
   prod — unwritten rule 1). Repair goes through a sanctioned recompute
   function with its run recorded in MEMORY.md.
2. **Masking bad totals in the Flutter reader** (clamping negatives, hiding
   suspicious spikes in `reports_realtime_database_service.dart` /
   `report_cards_widget.dart`). Chain B (Timestamp saga) already taught
   this: consumer tolerance hides producer bugs and polluted data persists.
3. **Adding more denormalized totals** (new nodes, new counters) without a
   single-writer or transaction guarantee. Every new total inherits D1/D2
   until those are fixed.
4. **Changing math without the golden suite** — no edit to
   `loan_calculation_service.dart` / `charge_calculator.dart` semantics
   before Gate 1 passes (finstack#33 lesson).
5. **Routing around branch flow** — no direct pushes to `master`, no
   dev/staging builds pointed at prod "to check the totals" (unwritten
   rule 5); promotion is develop → release/** → master only.
6. **Fixing producers and declaring victory** — Chain B lesson: fixing the
   writer does NOT fix already-polluted data. Phase 4's data repair is a
   deliverable, not an afterthought.

## PHASE 4 — Validation, promotion, and data repair

1. **All gates green:** golden suite (Gate 1), writer tests + race +
   double-delivery proofs (Gate 2/3 obligations), `go vet` clean in
   `triggers/`, full `CGO_ENABLED=0 go test ./...` and
   `fvm flutter test` green.
2. **Staged rollout through normal branch flow** (finstack-change-control):
   backend PR first (`develop` → auto-deploys dev functions), observe dev
   RTDB `dev/companies/*/report_summary` under real app usage; then
   `release/**` (stg); then `master` (prod). Flutter-side changes (G7
   extraction, any reader changes) ride separate frontend PRs, after the
   backend, per the backend-first discipline.
3. **Backfill / recompute plan (explicit deliverable):** historical totals
   are polluted by D1/D2 regardless of producer fixes.
   - Build the recompute tool (Phase 3 (b)/(c)): read Firestore
     source collections, rebuild one company's `report_summary` node.
   - Dry-run in dev: diff recomputed vs live totals; the diff size IS the
     pollution measurement — record it.
   - Repair dev → verify app reports render sanely → stg → prod. The prod
     run is executed by the sanctioned function/tool (Admin SDK), never by
     console edits, and is logged in `functions/loans/MEMORY.md` with date,
     scope, and before/after evidence.
4. **MEMORY.md updates** (CLAUDE.md standing duty): summarize what shipped,
   decisions (Phase 3 choice), and the repair evidence in
   `functions/loans/MEMORY.md` (+ `apps/loans/MEMORY.md` for Flutter-side
   changes).

## You are done when (all falsifiable)

- `cd apps/loans && fvm flutter test test/services/` is green with G1-G10,
  and the `/30 → /31` mutation check fails at least one test.
- `cd functions/loans && CGO_ENABLED=0 go test ./...` is green and includes
  core tests for all three report writers, among them a double-delivery test
  asserting totals unchanged on redelivery.
- `scripts/race_demo` `-txn` mode (or the CI equivalent emulator test) exits
  0; the racy mode is retired to documentation.
- `cd functions/loans/triggers && CGO_ENABLED=0 go vet ./...` prints nothing.
- `grep -rn '%\$w' functions/loans/` returns nothing; `grep -n 'TODO(deibeeed)'
  functions/loans/triggers/loan_changes.go` returns nothing (D5/D6 resolved,
  completed-branch numbers covered by tests).
- For at least one real company per env, recompute-from-Firestore equals the
  live `report_summary` totals within a written tolerance, and the repair
  run is recorded in `functions/loans/MEMORY.md`.
- The Phase 3 decision (a/b/c) is recorded with rationale and date in
  `functions/loans/MEMORY.md`.

## Provenance and maintenance

Authored 2026-07-07 from direct repo inspection on branch
`feature/chat-messaging` (local checkout; chat backend PR finstack#83 merged
on GitHub, frontend finstack#84 open — local refs stale). All file paths,
line numbers, commands, and baseline counts verified by execution or reading
on that date. Ticket annotations: `finstack#NN` = current repo
(`anatechopc/finstack`); `loooans#NN` = archived repos (in-code TODOs still
link `anatechopc/loooans` issues #47/#58/#60 — old universe; refile
follow-ups on finstack).

Re-verify before trusting drift-prone facts:

```bash
# Baselines
cd apps/loans && fvm flutter test --test-randomize-ordering-seed random   # 76 pass @2026-07-07
cd functions/loans && CGO_ENABLED=0 go test ./...                          # all ok @2026-07-07
cd functions/loans/triggers && CGO_ENABLED=0 go vet ./...                  # 2 warnings @2026-07-07

# Defects still present?
grep -n 'dataErrors =' functions/loans/triggers/loan_changes.go            # D3 (many hits)
grep -n '%\$w' functions/loans/triggers/loan_changes.go                    # D7 (2 hits)
grep -n 'TODO(deibeeed)' functions/loans/triggers/loan_changes.go          # D6 (1 hit)
grep -n 'document.v1.written' .github/scripts/deploy_functions.sh          # D1 precondition (loanChanges + messageWritten)
grep -n 'totalLoanPayment =' apps/loans/lib/features/loans/bloc/loan_settlement_bloc.dart  # D9

# Math-core test inventory
ls apps/loans/test/services/
```

If a re-verification line stops matching, the corresponding phase item is
either done (celebrate, update this skill) or the code moved (re-locate,
update line refs here and in `references/aggregation-triggers.md`).
