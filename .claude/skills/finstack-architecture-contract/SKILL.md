---
name: finstack-architecture-contract
description: "Use when you need to know why finstack is built the way it is before changing it: adding a package, repository, BLoC, or Go trigger; changing a Firestore document shape; writing dates to Firestore/RTDB; touching collection prefixes or environment wiring; syncing denormalized fields; answering 'who writes X / where does X live / can I change Y safely'; or when a change spans both Flutter and Go. Also load before working near known-weak areas: RTDB report aggregation (loan_changes.go), multi-payment writes, or the Go module layout."
---

# finstack Architecture Contract

Load-bearing design decisions, the invariants every change must preserve, and the
known-weak points — for the **finstack** monorepo (Loooans loans marketplace:
Flutter app + Go Cloud Functions + Firebase).

The root `CLAUDE.md` already gives you the repo table, environment table, and
quick commands — this skill does NOT repeat it. This is the *contract*: what must
stay true, where each rule is enforced in code, and what breaks if you violate it.

**When NOT to use this skill:**

| You want... | Use instead |
|---|---|
| The non-negotiable process rules, PR/branch discipline | `finstack-change-control` |
| Triage for a live failure or error message | `finstack-debugging-playbook` |
| The full story behind an incident or re-fix chain | `finstack-failure-archaeology` |
| Loan lifecycle / schedule math / domain terms | `loans-domain-reference` |
| Env/prefix/flag/secret tables, add-a-config-axis | `finstack-config-and-environments` |
| Setting up a dev machine, codegen, toolchain | `finstack-build-and-env` |
| Deploying, CI workflows, sms-gateway ops | `finstack-run-deploy-operate` |
| Writing tests (Go adapter+core recipe, Flutter seams) | `finstack-testing-and-validation` |
| Fixing loan computation / rebuilding reporting | `finstack-loan-engine-and-reporting-campaign` |
| Security findings, rules-into-source runbook | `finstack-security-hardening` |

## 1. Monorepo map — what root CLAUDE.md omits

Verified on disk as of 2026-07-07:

- `apps/sms-gateway/` — Kotlin/Jetpack Compose Android app (absent from the root
  CLAUDE.md table). Runs as a foreground service on a dedicated phone; drains the
  RTDB `otp/` queue and sends SMS. Operations: `finstack-run-deploy-operate`.
- `packages/core/` — **9 packages** (loooans_helpers, authentication, user,
  company, address, bank_details, notification, storage, chat).
- `packages/loans/` — **14 packages**, of which **3 are on disk but NOT wired
  into the app** (not in `apps/loans/pubspec.yaml`, no imports in `apps/loans/lib`):
  `karma_transaction_repository`, `transaction_repository`,
  `transaction_view_repository`. Treat as dormant, not load-bearing — do not
  "helpfully" wire them in; see `finstack-roadmap-and-frontier` for disposition.
- `functions/loans/` — Go, **multi-module**: root module `com.loooans.app` plus
  sub-modules `api/`, `triggers/`, `utils/`, `types/`, `job/`, `test/fakes/`,
  each with its own `go.mod`, stitched together by `replace` directives in the
  root `go.mod` (lines 65–75). Toolchain details: `finstack-build-and-env`.

⚠️ **Module-name landmine:** `functions/loans/triggers/go.mod` declares
`module com.looans.app/triggers` (**two** o's) while everything else is
`com.loooans.app` (three o's). It builds only because the root `replace
com.loooans.app/triggers => ./triggers` resolves the import by directory,
ignoring the inner module line. Removing that `replace`, or adding a package
inside `triggers/` that imports another `triggers/` package by module path,
will break the build. If you touch `triggers/go.mod`, fix the typo in the same
PR — do not perpetuate it.

## 2. Layering contract — Flutter side

```
UI (BlocBuilder/BlocListener)
  → BLoC (flutter_bloc, event/state, Equatable)
    → Repository (implements BaseRepository<T>)
      → Service (BaseFirestoreService / BaseRealtimeDatabaseService / BaseCacheService)
        → Firebase SDKs
```

- **`BaseRepository<T>`** (`packages/core/loooans_helpers/lib/src/data_helpers/base_repository.dart`)
  is the abstract CRUD+load+stream interface every repository implements. BLoCs
  should depend on it (or the concrete repo) via injection — it is also the
  mocking seam for tests (`finstack-testing-and-validation`).
- **`BaseFirestoreService`** (`.../data_helpers/database/base_firestore_service.dart`)
  owns the environment collection prefix (invariant I2) and the `root` collection
  ref. Every Firestore-backed service extends it; never build a collection path
  by hand in a BLoC or screen.
- **Entity/Model split** (canonical example:
  `packages/loans/loan_repository/lib/src/model/loan_entity.dart` +
  `loan.dart`): the `*Entity` is the `@JsonSerializable` persistence shape
  (JSON keys, date `@JsonKey` converters, extends `BaseEntity`); the `Model`
  extends the entity, implements `BaseModel<Entity>`, and carries domain getters
  plus a `.create(...)` factory that seeds `id = NO_ID` and timestamps. New
  packages must follow this split — Go triggers parse the *entity* field names,
  so entity JSON keys are a cross-language API (invariant I8).

**DI reality (as of 2026-07-07)** — `apps/loans/lib/app/di/`:
- `repository_providers.dart`: **20** `RepositoryProvider`s (19 concrete + 1
  bound as `BaseRepository<BankDetails>`; includes `ChatRoomRepository` and
  `TypingService`).
- `bloc_providers.dart`: **16** app-level BLoCs. (`apps/loans/CLAUDE.md:99` and
  `apps/loans/ARCHITECTURE.md:18` say "9 BLoCs" — stale; trust the DI files.)
- **Singleton injection is PARTIAL.** Repositories are injected via
  `context.read<>()` everywhere. For services there are two tiers (verified
  2026-07-07):
  - *Seamed (the target pattern):* registration, payment_submission,
    bank_details, chat, conversations, user, authentication, reviews BLoCs —
    the default `BuildContext` constructor delegates to a
    `.withDependencies(...)` factory, passing `AuthenticationService.instance`
    only as the production default at the composition edge; logic uses the
    injected field.
  - *Un-seamed debt (7 files):* `loans_bloc.dart:31`, `payment_bloc.dart:28-29`
    (binds `SettingsService.instance` too), plus `capital_bloc`, `product_bloc`,
    `payment_center_bloc`, `company_bloc`, `reports_bloc` — these bind
    `.instance` directly in the constructor with NO `.withDependencies` seam.
  `apps/loans/CLAUDE.md` forbids raw `.instance` use in BLoCs; finishing this
  refactor was deferred as **loooans#134 — a phantom ticket that does not exist
  on GitHub; still-wanted work to be refiled on finstack** (see
  `finstack-roadmap-and-frontier`). Until then: new BLoCs must use the
  `.withDependencies` pattern; don't add new un-seamed `.instance` bindings
  (test seams: `finstack-testing-and-validation`).

## 3. Layering contract — Go side

- Single entry point `functions/loans/loooans_cloud_functions.go`: every
  function is registered in `init()` (`functions.HTTP` / `functions.CloudEvent`).
  Registered ≠ deployed: `sometest` is registered but absent from the deploy
  script; the deploy script (17 functions) is the source of truth for what runs
  (`finstack-run-deploy-operate`).
- **Adapter + core pattern (house style for all new/touched Go code — unwritten
  rule #4):** a thin adapter parses the CloudEvent/HTTP request and wires real
  Firebase clients into a pure `*Core` function that takes a `Deps` struct of
  injected func fields; the core is unit-tested with in-memory fakes from
  `com.loooans.app/test/fakes`. Canonical examples: `VerifyOtpCore`
  (`api/users/verify_otp.go`), `HandleMessageWrittenCore`
  (`triggers/message_written_core.go` + adapter `message_written.go`).
  WHY: Cloud Functions are untestable end-to-end locally; the core/Deps split is
  the only reliable test seam. Recipe: `finstack-testing-and-validation`.
  Older triggers (`loan_changes.go`, `notification_created.go`,
  `capital_created.go`, `loan_schedule_changes.go`) predate the pattern and are
  monolithic/untested — that is debt, not license.

## 4. Data-flow ownership — who writes what

| Data | Owner (writer) | Notes |
|---|---|---|
| Firestore domain docs (loans, payments, reviews, users, chat messages…) | **Flutter app** | Go triggers react; they do not create domain docs |
| `notifications/{id}` docs | **Go triggers only** (`createNotification` in `triggers/notification_helpers.go`) | Flutter `NotificationService` only manages FCM tokens + display |
| FCM push (standard path) | `notificationCreated` trigger fans out to `users/{id}/devices/*.token` | one push per notification doc |
| FCM push (chat) | `messageWritten` trigger pushes **directly** via `sendChatPush` (`triggers/message_written.go:172`) — bypasses the notifications collection | Deliberate: chat design decision #13 locks "Direct FCM data-push… **No persistent notification-list entries**" (`docs/superpowers/specs/2026-07-01-chat-messaging-design.md`) — a per-message notification doc would double-write state the message doc + seq/reads model already carries |
| RTDB report aggregates (`{dev|stg}/companies/{id}/report_summary/...`) | **Go** `loanChanges` trigger | known-weak, see §6 |
| RTDB `otp/{hash}` queue | Go `requestOtp` writes; sms-gateway app consumes + writes back status | |
| Message `seq` + `chat_rooms.last_seq` | **Go** `messageWritten` only, in a Firestore transaction | invariant I7; client writes messages with no `seq` |

So there are **two FCM paths** on purpose. If you add a new notifying feature,
default to the notifications-doc path; only bypass it if, like chat, the feature
has its own persisted unread model and you record the decision.

## 5. The invariants (the contract)

Violating any of these has already caused, or will cause, a production incident.
Evidence excerpts and verify commands: `references/evidence.md`.
Drift check: `scripts/verify-contract.sh`.

- **I1 — Dates are int64 millis-since-epoch everywhere** (Firestore + RTDB, both
  languages). Go writers MUST use `.UnixMilli()` — never store a raw
  `time.Time` (the Admin SDK serializes it as a Firestore Timestamp proto,
  which crashes Flutter's `as num` casts; the web login outage of finstack
  PRs #47/#48/#49, Chain B in `finstack-failure-archaeology`; docs written
  before the fix are permanently polluted, which is why Flutter's
  `handleDateTime*FromJson` in `loooans_helpers/.../constants.dart` also
  tolerates Timestamps on read). Flutter entities use the `handleDateTime*`
  `@JsonKey` converters — never hand-roll date serialization.
- **I2 — The Firestore collection prefix (`dev_` / `stg_` / `''`) is computed in
  THREE places that must agree:**
  1. Flutter: `base_firestore_service.dart:27-36` (compile-time `ENVIRONMENT`),
  2. Go: `functions/loans/utils/environment_utils.go` `GetCollectionPrefix()`
     (runtime `ENVIRONMENT` env var),
  3. Deploy script: `.github/scripts/deploy_functions.sh:39-47` (bakes the
     prefix into trigger path patterns like `${collectionPrefix}loans/{uid}`).
  Change the mapping in one place and the others silently read/trigger on the
  wrong collections. **RTDB is different:** it uses bare `dev`/`stg` path roots
  (Go `GetMinifiedEnv()` in `environment_utils.go`, plus a local duplicate
  `getPathEnv()` in `triggers/loan_changes.go:504`). Full env axis:
  `finstack-config-and-environments`.
- **I3 — OTP `reason`/`objective` is read server-side from the persisted RTDB
  entry, NEVER from the request body** (`api/users/verify_otp.go:60-64` states
  it: a caller must not be able to escalate a payment OTP into a profile
  mutation). Any new OTP-driven action must key off the stored entry. Business
  flows: `loans-domain-reference`; OTP security findings:
  `finstack-security-hardening`.
- **I4 — `NO_ID` sentinel** (`const NO_ID = 'no-id'`,
  `loooans_helpers/.../constants.dart:3`) marks not-yet-persisted or
  not-applicable references — e.g. open-term payments start with
  `loan_schedule_id = NO_ID`. Never `update()` a doc whose id is `NO_ID`
  (past bug: `finstack-failure-archaeology`). Go code must treat `no-id` as
  absent, not as a key.
- **I5 — Doc self-ID:** every Firestore doc body carries its own `id` field;
  the service `add()` pattern is `final doc = root.doc(); data..id = doc.id;
  doc.set(...)` (see `loan_firestore_service.dart:19-25`). Go triggers depend
  on `fields["id"]` (e.g. `loan_changes.go:75-79` errors without it). Omitting
  `id` in a new writer breaks triggers downstream.
- **I6 — Denormalizations that must stay synced** (if you add a writer, you own
  the sync):
  - `user_loan_views.user_full_name` ← cascaded by the `userChanges` trigger on
    profile-name change (`triggers/user_changes.go:41-48,146-161`).
  - Payment→loan attribution: payment docs carry `loan_schedule_id`;
    `paymentCreated` resolves `loan_id` (explicit `loan_id` honored for
    legacy/teller docs) — `triggers/payment_created.go:47-91`.
  - `submission_id` groups the N payments of a pay-in-full submission; only the
    first sibling notifies (`payment_created.go:63-73`).
- **I7 — Chat `seq` is allocated ONLY inside a Firestore transaction that bumps
  `chat_rooms.last_seq`** (`triggers/message_written.go:137-157`). Clients
  write messages without `seq`; the whole unread/receipt/team-inbox model
  assumes `seq` is dense and monotonic per room. Never write `seq` or
  `last_seq` from Flutter.
- **I8 — Firestore doc schemas are a shared Go/Flutter API.** Entity JSON keys
  (snake_case) in Dart and `fields["..."]` reads in Go must move together,
  backend first — process in `finstack-change-control` (unwritten rule #2).
- **I9 — Notification creation is server-side only** (root `CLAUDE.md`); the
  chat direct-push is the single sanctioned exception (§4).

## 6. Known-weak points (all OPEN as of 2026-07-07)

Stated plainly so you don't rediscover them. Do not build on top of these
without reading the cross-referenced skill first.

| Where | Defect | Cross-ref |
|---|---|---|
| `triggers/loan_changes.go:462-480` (`applyToNodeValue`) | Non-transactional RTDB read-modify-write (Get then Set) — concurrent loan writes race and lose report increments | `finstack-loan-engine-and-reporting-campaign` |
| `triggers/loan_changes.go:108+` | `dataErrors` is *reassigned* (`=`) on every call, never accumulated — all but the last error silently dropped | same campaign |
| `triggers/loan_changes.go:190-212` (`completed` branch) | `additional_charges` added (L190-196) then subtracted (L206-212) — copy-paste that nets to zero; branch also carries `TODO(deibeeed)` at L171 | same campaign |
| `triggers/loan_changes.go:141,180` | Firestore query built as `pathEnv+"_loan_schedules"`; in production `pathEnv==""` → queries collection `_loan_schedules` (leading underscore). [Inference: query silently returns empty in prod → bad-debt/completed report figures computed from zero payments] | same campaign |
| `triggers/loan_changes.go:144,183` | `%$w` format typos — errors print literally instead of wrapping | trivial; fix when touching file |
| `apps/loans/.../payment_center_bloc.dart:1174,1224`; `payments/bloc/payment_submission_bloc.dart:69` | Multi-payment confirm/reject/pay-in-full loops are non-atomic (no `WriteBatch`) — partial failure leaves earlier schedules mutated; TODOs in code acknowledge it | `finstack-loan-engine-and-reporting-campaign` (correctness), `finstack-debugging-playbook` (symptoms) |
| `functions/loans/triggers/go.mod` | Two-o module typo held together by root `replace` (§1) | fix alongside any triggers/go.mod change |
| `go vet ./...` in `triggers/` | 2 pre-existing lock-copy warnings (`loan_changes.go:317,334`): `createLoanStatusNotifications` takes `firestoredata.DocumentEventData` **by value** (contains a `sync.Mutex`). Style cousin: `db.Client` is also passed by value into `applyToNodeValue`/`addReportDataItem`/`getProductType` | don't add new by-value passes of clients/protos |
| Firestore + Storage rules | Not in source — repo files are stale placeholders; real rules console-managed | `finstack-security-hardening` (rules-into-source campaign) |
| 3 open security findings (OTP derivable from token; no rate limits on unauthenticated `setPassword`/`sendPasswordSetupLink`; committed JWT in `job/subscription_job.go`) | All confirmed must-fix by the maintainer, none accepted | `finstack-security-hardening` |
| `packages/loans/*/` stub RTDB services (`loan_realtime_database_service.dart`, reports) | `// TODO: implement` bodies — by design: Go writes reports, Flutter only reads | leave as-is |

## 7. Provenance and maintenance

Authored 2026-07-07 from direct repo inspection on branch `feature/chat-messaging`
(chat backend merged as finstack PR #83; frontend finstack PR #84 open at time of
writing — re-check with `gh pr view 84 -R anatechopc/finstack`). Dossier claims
were re-verified against source; counts and line numbers below will drift.

Re-verification one-liners (run from repo root):

```bash
# Full drift check (prefix triple, module typo, DI counts, NO_ID, unwired pkgs)
.claude/skills/finstack-architecture-contract/scripts/verify-contract.sh

# DI counts (expect 20 / 16 as of 2026-07-07; anchored so MultiXxxProvider lines don't inflate)
grep -cE "^\s+RepositoryProvider[(<]" apps/loans/lib/app/di/repository_providers.dart
grep -cE "^\s+BlocProvider[(<]" apps/loans/lib/app/di/bloc_providers.dart

# Prefix triple agreement
grep -n "dev_\|stg_" packages/core/loooans_helpers/lib/src/data_helpers/database/base_firestore_service.dart functions/loans/utils/environment_utils.go .github/scripts/deploy_functions.sh

# Module typo still present?
head -1 functions/loans/triggers/go.mod   # 'com.looans.app/triggers' = typo lives

# Weak-point TODOs still open?
grep -n "TODO(payments)" apps/loans/lib/features/payment_center/bloc/payment_center_bloc.dart apps/loans/lib/features/payments/bloc/payment_submission_bloc.dart
grep -n "TODO(deibeeed)" functions/loans/triggers/loan_changes.go

# Unwired packages still unwired?
grep -c "karma_transaction\|transaction_repository\|transaction_view" apps/loans/pubspec.yaml  # expect 0
```

Line-number citations were exact at authoring time; if a cited line has moved,
trust the symbol name (function/field) over the number and update this file.
