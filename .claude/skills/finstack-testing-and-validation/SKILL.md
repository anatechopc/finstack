---
name: finstack-testing-and-validation
description: "Use when adding or changing tests in finstack (Go functions or Flutter app/packages), writing a new Go handler/trigger that needs tests, mocking a final-class repository in a Flutter bloc test, deciding what evidence a fix needs before calling it done, when go test fails on macOS with a dyld/LC_UUID error, when fvm flutter analyze reports ~6000 errors, when address_repository or bank_details_repository package tests fail, or when asked what CI actually gates."
---

# finstack Testing and Validation

What counts as evidence in this repo, and the exact recipes for adding tests on
both sides (Go Cloud Functions and Flutter). All commands verified 2026-07-07.

**When NOT to use this skill:**
- Designing the golden scenario suite or proving loan-computation correctness →
  `finstack-loan-engine-and-reporting-campaign` (it owns proof/analysis recipes).
- Triaging a failure you don't understand yet → `finstack-debugging-playbook`.
- Why the adapter+core pattern exists / incident history → `finstack-failure-archaeology`.
- Change gating, the 5 unwritten rules, MEMORY.md update duty → `finstack-change-control`.
- Toolchain setup (fvm, Go modules, codegen) → `finstack-build-and-env`.
- CI workflow anatomy and deploys → `finstack-run-deploy-operate`.
- Security-rules testing / console rules → `finstack-security-hardening`.

## The evidence bar

A fix or feature claims "done" only with one of:

1. **An automated test** that fails without the change and passes with it
   (preferred; mandatory for new/touched Go code — unwritten rule 4, see
   `finstack-change-control`).
2. **A documented manual verification** — what you ran/clicked, on which env,
   with what result — recorded in the PR body and/or the relevant `MEMORY.md`.

Extra requirements:
- **Loan computation changes** (schedule math, interest, balances) additionally
  require golden scenarios — see `finstack-loan-engine-and-reporting-campaign`.
- **Schema changes** must be validated on both sides (Go writer + Flutter
  reader); a green suite on one side is not evidence for the other.

## What CI actually gates (verified in `.github/workflows/`, 2026-07-07)

| Workflow | Gate | Notes |
|---|---|---|
| `loans-functions-{development,staging,production}.yml` | `go build -v ./...` + `go test -v ./...` | Runs on push AND PRs touching `functions/loans/**`; deploy job needs build and runs only on push. **Go tests block deploys.** |
| `loans-app-{development,staging,production}.yml` | **Nothing test-related** | Build web + deploy hosting only. No `flutter test`, no `flutter analyze` step. |
| `sms-gateway.yml` | `./gradlew testDebugUnitTest` + `assembleDebug` | Build/test only, no deploy. |

Consequence: **Flutter tests and analyze are enforced by discipline, not CI.**
Run them yourself; nothing will catch you if you don't. (Adding Flutter test
steps to CI is open work — see roadmap at the bottom.)

## Go side (functions/loans) — the house discipline

```bash
cd /Users/deibeeed/Projects/AnaheimTechnologies/finstack/functions/loans
go build -v ./...                 # what CI runs
go test -v ./...                  # what CI runs (Linux)
CGO_ENABLED=0 go test ./...       # REQUIRED on macOS — bypasses "dyld: missing LC_UUID"
```

Or `scripts/test-go.sh` in this skill dir (macOS-safe). Suite is green as of
2026-07-07.

**The pattern (unwritten rule 4 — any new or touched Go code follows it):**
a thin **adapter** wires real Firebase into a pure **`*Core`** function that
takes a `*Deps` struct of plain `func` fields. Core holds all business logic
and is unit-tested with in-memory recording fakes from module
`com.loooans.app/test/fakes` (single file `test/fakes/fakes.go` — new fakes are
added there). Tests live under `test/<area>/` in package `<pkg>_test`.

Step-by-step recipe with code skeletons: **`references/go-adapter-core-recipe.md`**.

**Worked example pairs (read these before writing your own):**

| Kind | Core + Deps | Adapter | Test |
|---|---|---|---|
| Firestore trigger | `triggers/message_written_core.go` (`MessageWrittenDeps`, `HandleMessageWrittenCore`, `FixedClock`) | `triggers/message_written.go` (`buildMessageWrittenDeps`) | `test/triggers/message_written_core_test.go` |
| HTTP (core-only test) | `api/users/verify_otp.go` (`VerifyOtpDeps`, `VerifyOtpCore`; adapter `VerifyOtp` in same file) | same file | `test/api/users/verify_otp_test.go` |
| HTTP (adapter tested too) | `api/users/request_otp.go` (`RequestOtpDeps`, `RequestOtpCore`, `RequestOtpDepsBuilder`, `RequestOtpHandler`) | same file | `test/api/users/request_otp_handler_test.go` (httptest harness) |

**Pattern coverage as of 2026-07-07** (verified by grepping for `Core(`/`Deps`):

- Adapter+core WITH tests: HTTP `addUser`, `sendPasswordSetupLink`,
  `setPassword` (separate `*_core.go` files), `requestOtp`, `verifyOtp`;
  triggers `userCreated`, `userChanges`, `reviewCreated`, `reviewUpdated`,
  `paymentCreated`, `paymentUpdated`, `messageWritten`.
- **Monolithic/untested backlog** (no `Deps`, no tests): `notification_created.go`,
  `loan_changes.go`, `capital_created.go`, `loan_schedule_changes.go`
  (plus `notification_helpers.go`). Backfilling these to adapter+core is
  sanctioned hardening work — BUT `loan_changes.go` is the reporting engine
  with known bugs; do not refactor it outside the campaign plan in
  `finstack-loan-engine-and-reporting-campaign`.

New function? Registration in `loooans_cloud_functions.go` `init()` and the
deploy-script entry are covered by `functions/loans/CLAUDE.md` and
`finstack-run-deploy-operate` respectively.

## Flutter side (apps/loans + packages)

```bash
cd /Users/deibeeed/Projects/AnaheimTechnologies/finstack/apps/loans
fvm flutter test --coverage --test-randomize-ordering-seed random   # canonical (CLAUDE.md)
fvm flutter test test/features/reviews/bloc/reviews_bloc_test.dart  # single file

# Package tests: run from the package dir
cd ../../packages/loans/review_repository && fvm flutter test
```

App suite green as of 2026-07-07 (76 tests, ~5 s). Ordering is randomized by
the canonical command — never write order-dependent tests.

**Idioms** (full detail + worked examples: **`references/flutter-test-idioms.md`**):
- `bloc_test` (^9.1.6) + `mocktail` (^1.0.3). `blocTest<Bloc, State>` with
  `setUp`/`build`/`act`/`expect`/`verify`; `registerFallbackValue` in `setUpAll`;
  `captureAny(named: ...)` to assert query statements.
- **The `.withDependencies(...)` seam**: concrete repositories are `final class`
  → mocktail cannot mock them. Blocs expose a test constructor typing deps as
  `BaseRepository<T>` (mockable) or optional-nullable concrete. The default
  `BuildContext` constructor is the production path — never bypass it in app
  code. Seams exist in 8 blocs (authentication, bank_details, chat,
  conversations, payment_submission, registration, reviews, user). Canonical
  example: `lib/features/reviews/bloc/reviews_bloc.dart` +
  `test/features/reviews/bloc/reviews_bloc_test.dart`.
- Widget tests use `tester.pumpApp(widget)` (`test/helpers/pump_app.dart`) —
  wraps `MaterialApp` with the app's localization delegates.

**Known pre-existing failures — NOT your regression, do not chase:**
`packages/core/address_repository` and `packages/core/bank_details_repository`
scaffold tests instantiate Firestore-backed repos without
`Firebase.initializeApp()` and fail (documented `apps/loans/MEMORY.md:344`).
The two package-test invariants:
1. Exactly those two packages fail, with that Firebase-init failure mode.
2. Every other package's tests pass.
A third failing package — or a different failure in those two — IS your regression.

**Coverage reality (as of 2026-07-07):** app tests concentrate in
chat, reviews, payments/payment_center, bank_details, set_password,
registration, users, plus two service tests (`loan_calculation_service_test.dart`,
`payment_confirmation_service_test.dart`). `loans_bloc`, `product_bloc`, and
most screens/widgets are untested. **Zero golden tests** (`matchesGoldenFile`
count: 0). The VGV counter scaffold is still present and tested
(`test/counter/`, `test/app/view/app_test.dart`) — harmless, ignore it.
Package coverage: `chat_repository` 12 test files, `user_repository` 4,
`review_repository`/`payment_repository`/`loooans_helpers` 2 each, the rest one
VGV scaffold test each.

`--coverage` writes `coverage/lcov.info`; render with
`genhtml coverage/lcov.info -o coverage/` (per `apps/loans/README.md`).
`coverage_badge.svg` is committed; no automation updates it (no CI step found).

## The analyzer baseline (read before panicking)

`apps/loans/CLAUDE.md` requires `fvm flutter analyze` after changes, but the
raw output is misleading. Measured 2026-07-07:

- Raw total: **6228 issues** — of which **6082 (incl. all 5860 "errors") come
  from `build/ios/SourcePackages/checkouts/**`** (Swift-Package-Manager
  checkouts of flutterfire examples inside `build/`, present after an iOS build).
- Source-only baseline (excluding `build/`): **146 issues — 0 errors,
  10 warnings, 136 infos** (deprecations etc., intentionally tolerated).

Your gate: **0 errors outside `build/`**, and no NEW warnings/infos from your
diff. Use `scripts/analyze-source-only.sh` in this skill dir — it filters the
`build/` noise and fails only on real source errors.

## Test-infra roadmap (open work, as of 2026-07-07)

- finstack#40 "Implement Unit testing" — OPEN
- finstack#41 "Implement Widget testing" — OPEN
- finstack#42 "Implement Patrol" (e2e) — OPEN
- loooans#134 (Flutter bloc/widget test infra; rules emulator tests) — phantom
  reference from the old loooans archive repos; **does not exist on GitHub;
  still-wanted, to be refiled on finstack**. See `finstack-roadmap-and-frontier`.

Backfilling the four monolithic Go triggers (above) and adding a Flutter
test/analyze gate to `loans-app-*.yml` are sanctioned hardening tasks.

## Provenance and maintenance

Authored 2026-07-07 from direct repo inspection on branch
`feature/chat-messaging` (commands executed, files read; dossier claims
spot-verified). Re-verify volatile facts:

```bash
# Go suite still green (macOS)
cd functions/loans && CGO_ENABLED=0 go test ./...
# Flutter app suite still green
cd apps/loans && fvm flutter test
# Which Go trigger files still lack the pattern (expect the 4 triggers + notification_helpers.go)
grep -L "Deps" functions/loans/triggers/*.go
# CI still doesn't run Flutter tests (expect 0 for each file)
grep -c "flutter test\|flutter analyze" .github/workflows/loans-app-*.yml
# Analyzer source-only baseline
.claude/skills/finstack-testing-and-validation/scripts/analyze-source-only.sh
# Seam inventory (expect 8 bloc files)
grep -rln "withDependencies" apps/loans/lib
# Roadmap tickets still open
for i in 40 41 42; do gh issue view $i --json number,state -q '.number,.state'; done
```
