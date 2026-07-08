---
name: finstack-config-and-environments
description: Use when you need to know which Firebase project, collection prefix, RTDB path, Flutter flavor, entrypoint, or Git branch an environment uses; when data shows up in the wrong collection or seems missing (suspect a prefix mismatch); when adding an environment-sensitive path, feature flag, or new config axis; when wiring the ENVIRONMENT variable for a build, test, deploy, or local run; or when looking up service accounts, WIF identities, or secret names used by CI.
---

# finstack Config and Environments

Catalog of every configuration axis in the finstack monorepo: environments, projects, prefixes, flags, secrets, identities. All paths relative to repo root `/Users/deibeeed/Projects/AnaheimTechnologies/finstack` unless absolute.

**When NOT to use this skill:**
- Deploying or running things (workflow anatomy, `deploy_functions.sh` internals, sms-gateway operations) -> `finstack-run-deploy-operate`
- Change gating, the 5 unwritten rules, branch/PR discipline -> `finstack-change-control`
- Setting up a dev machine (fvm, Gradle, codegen) -> `finstack-build-and-env`
- Security rules content, console-rules export, open security findings -> `finstack-security-hardening`
- "Why is this broken" triage -> `finstack-debugging-playbook`

## THE TABLE (memorize this)

| Axis | Development | Staging | Production |
|---|---|---|---|
| Firebase project | `loooans-dev-stg` | `loooans-dev-stg` (SAME project) | `loooans-prod` |
| Project number | 565409367468 | 565409367468 | 444559784514 |
| Flutter flavor | `development` | `staging` | `production` |
| Flutter entrypoint | `lib/main_development.dart` | `lib/main_staging.dart` | `lib/main_production.dart` |
| Firebase options file | `lib/firebase_options_dev.dart` | `lib/firebase_options_stg.dart` | `lib/firebase_options.dart` |
| Android appId suffix | `.dev` | `.stg` | (none) — base `com.loooans.app` |
| Go deploy branch | `develop` | `release/**` (`release/v*` for app) | `master` |
| `ENVIRONMENT` value | `development` | `staging` | `production` |
| Firestore collection prefix | `dev_` | `stg_` | (none) |
| RTDB env node | `dev/` | `stg/` | (none — root) |
| Hosting target / site | `develop` / `loooans-dev-stg` | `staging` / `loooans-stg` | `production` / `loooans-prod` |
| Web URL subdomain | `dev.` (`dev.loooans.com`) | `stg.` | (none) |
| Function suffix | `_development` | `_staging` | `_production` |

Dev and staging are separated ONLY by prefixes inside the shared `loooans-dev-stg` project. Prod is a separate project with no prefixes anywhere. Branch->env mapping policy and its non-negotiables: `finstack-change-control`.

## What dev and stg actually SHARE (same project — easy to forget)

Because dev + stg live in one Firebase project, these are NOT separated between them:
- **Auth users** — one user pool. A dev account is a stg account.
- **Cloud Storage** — upload paths carry no env prefix (verified callers pass e.g. `users/{uid}/loans/{loanId}`, `packages/core/storage_repository/lib/src/firebase_storage_service.dart:24`). Dev and stg files share one bucket namespace; prod is a different bucket.
- **Global RTDB nodes** — `otp/{hash}`, `gateway_status/{deviceId}`, `app/sessions/{uid}` are unprefixed (see RTDB section). One sms-gateway phone serves BOTH dev and stg OTP traffic.
- **Secret Manager, IAM, WIF pool** — one of each per project.

Only Firestore collections (`dev_`/`stg_`) and env-scoped RTDB subtrees (`dev/`, `stg/`) are separated. Rule cross-ref: dev/staging builds must never point at prod (`finstack-change-control`, unwritten rule 5).

## The ENVIRONMENT variable — two different carriers

Same name, two mechanisms. Do not confuse them:

| Side | Mechanism | Set where | Unset behavior |
|---|---|---|---|
| Flutter | **compile-time** `--dart-define=ENVIRONMENT=...` (`String.fromEnvironment`) | `.vscode/launch.json` (all 3 configs, `apps/loans/.vscode/launch.json`); CI `flutter build web` steps in `.github/workflows/loans-app-*.yml` | **Falls back to development** (`dev_` prefix, `dev/` RTDB node) |
| Go functions | **runtime env var** | `deploy_functions.sh` passes `ENVIRONMENT=$environment` to every function via `--set-env-vars` | **Fatal** — `start()` in `functions/loans/loooans_cloud_functions.go` calls `log.Fatal` + `os.Exit(1)` if `ENVIRONMENT` is empty |

Trap: Go's `GetCollectionPrefix()` returns `""` (= PROD paths) for any value other than `development`/`staging`. The only thing standing between a typo'd `ENVIRONMENT` and prod collection paths is the `start()` fatal-if-unset guard — which checks empty, not validity. When running Go code locally or in tests, always set `ENVIRONMENT=development` explicitly.

## Collection prefix mechanism — THREE places that must agree (Firestore)

The Firestore prefix (`dev_`/`stg_`/``) is computed independently in three places. A change to the scheme must touch all three; disagreement = triggers watching collections nobody writes, or the app reading collections nobody populates.

1. **Flutter reader/writer:** `packages/core/loooans_helpers/lib/src/data_helpers/database/base_firestore_service.dart` — `collectionPrefix` getter (staging -> `stg_`, production -> ``, **anything else -> `dev_`**). Every repository path is `$collectionPrefix$collectionName`.
2. **Go reader/writer:** `functions/loans/utils/environment_utils.go` — `GetCollectionPrefix()` (development -> `dev_`, staging -> `stg_`, **anything else -> ``**). Note the fallback direction is OPPOSITE to Flutter's.
3. **Trigger deploy wiring:** `.github/scripts/deploy_functions.sh` — computes `collectionPrefix` from `-e` and bakes it into every `--trigger-event-filters-path-pattern=document="${collectionPrefix}<collection>/{id}"`. A trigger's watched path is fixed at deploy time; runtime Go prefix only affects what the handler then reads/writes. (Script anatomy: `finstack-run-deploy-operate`.)

Never hardcode `dev_`/`stg_` in feature code (root `CLAUDE.md` rule). Sibling env helpers in `environment_utils.go`: `GetSubdomain()` (`dev.`/`stg.`/``, used to build `https://{sub}loooans.com/...` links, `functions/loans/api/users/invite_email.go:57`) and `GetMinifiedEnv()` (`dev`/`stg`/``, RTDB).

## RTDB path style — the exception

RTDB does NOT use the `dev_` underscore prefix. Env-scoped data lives under bare child nodes `dev/...` and `stg/...`; prod is unprefixed at root. Four independent implementations (as of 2026-07-07):

| Where | File | Style |
|---|---|---|
| Go reports writer | `functions/loans/triggers/loan_changes.go` — local `getPathEnv()` (~line 504; also called from `loan_schedule_changes.go:109`, same package) | `dev`/`stg`/`` + `"/companies/"+companyId` |
| Go capital writer | `functions/loans/triggers/capital_created.go:81` — uses `utils.GetMinifiedEnv()` | same values |
| Flutter RTDB base | `packages/core/loooans_helpers/lib/src/data_helpers/database/base_realtime_database_service.dart` — `dbRef` getter | `dev/`/`stg/`/`` + basePath; **fallback = dev** |
| Flutter chat typing | `packages/core/chat_repository/lib/src/data/database/typing_service.dart` — private `_prefix` | `dev/`/`stg/`/``; fallback = dev |

Global (NOT env-scoped, shared by dev+stg within a project): `otp/{hash}`, `gateway_status/{deviceId}`, `app/sessions/{uid}`, and — in prod rules only — `companies/{id}/...`. Full path catalog with writers/readers/rules anchors: [references/rtdb-paths-and-flags.md](references/rtdb-paths-and-flags.md).

**Known source-level mismatch (open, as of 2026-07-07):** Flutter listens to `companies/{companyId}/authentication/force_logout` at ROOT (`packages/core/authentication_repository/lib/src/data/authentication_database.dart:6`), but the dev-stg rules file (`apps/loans/database.rules.json`) defines `force_logout` only under the `dev/` and `stg/` nodes; only the prod file defines it at root. On dev/stg, the source rules would deny that read. Deployed console rules may differ (unverifiable from repo). Cross-ref `finstack-debugging-playbook` before "fixing" either side.

## Config file inventory (`apps/loans/` unless noted)

| File | Axis it controls | Notes |
|---|---|---|
| `.fvmrc` | Flutter toolchain | `3.44.0` — always `fvm flutter` (see `apps/loans/CLAUDE.md`) |
| `.firebaserc` | Project aliases + hosting targets | `default`=`loooans-dev-stg`, `production`=`loooans-prod`; targets develop/staging/production -> sites |
| `firebase.json` | Many: flutterfire options generation, hosting (3 targets, each with `/api/*` rewrites to Cloud Run per-env services), emulator ports, `database.rules`, `storage.rules`, `firestore.indexes` | **No `firestore.rules` key** — Firestore rules are console-managed, never shipped by `firebase deploy` (`finstack-security-hardening`). Only `database.rules.json` (dev-stg) is wired; `database.rules.prod.json` has NO deploy wiring — prod RTDB rules are a manual step (`finstack-run-deploy-operate`). |
| `lib/firebase_options.dart`, `_dev`, `_stg` | Per-flavor Firebase app config | **Generated by flutterfire (config in `firebase.json` `flutter.platforms.dart`) — never hand-edit** |
| `.vscode/launch.json` | Local run: flavor + target + `--dart-define ENVIRONMENT` | The canonical example of a correct triple |
| `android/app/build.gradle` | `productFlavors` development/staging/production, appId suffixes | |
| `firestore.indexes{,.dev,.stg,.prod}.json` + `scripts/deploy-indexes.sh` | Per-env composite indexes (prefix-filtered from live) | `firestore.indexes.json` is an overwritten scratch artifact; the `dev` branch of the script has a known bash bug — details in `finstack-run-deploy-operate` |
| `firestore.rules.chat.reference`, `storage.rules.chat.reference` | Nothing — reference-only chat rules snippets, never deployed | Console rules are the live state; export runbook in `finstack-security-hardening` |
| `functions/loans/utils/initialize_firebase.go` | RTDB instance URLs | **Hardcoded**: `loooans-dev-stg-default-rtdb` vs `loooans-prod-default-rtdb`, both `asia-southeast1` (functions themselves deploy to `asia-east1`) — selected by `ENVIRONMENT == "production"` |
| `apps/sms-gateway/app/` | Gateway device config | Needs untracked `google-services.json` (picks the project = which env's OTP queue it serves) + `local.properties` `gateway.email`/`gateway.password` -> `BuildConfig` fields. Debug build appId suffix `.dev`. |

## Feature flags inventory

There is **no central flag system**. Everything is scattered (as of 2026-07-07); full anchors in [references/rtdb-paths-and-flags.md](references/rtdb-paths-and-flags.md):

| Flag | Kind | Status |
|---|---|---|
| `SettingsService.forcePaymentConfirmation` | Per-user Firestore `{prefix}settings` doc | Production-active (gates borrower payment confirmation flow) |
| `SettingsService.appUseClassicUI` | Per-user Firestore `{prefix}settings` doc | Production-active (routes classic vs new home UI) |
| `SettingsService.enableProductAddOns` | Per-user Firestore `{prefix}settings` doc | Production-active (gates add-ons UI) |
| Product bools: `forceCollect` (copied onto loans as `isForceCollect`), `allowAddOns`, `allowRequestMaxLoanAmountExtension` | Per-product Firestore fields | Production-active |
| `AuthenticationService.allowAddClients` | Derived: `company.managementType == selfManaged` | Production-active (not stored) |
| AutoCollect / UnionBank | Commented-out UI + TODOs | **DORMANT** — do not resurrect without product decision (`finstack-roadmap-and-frontier`) |

## Secrets and identity (summary)

Full table with rotation notes: [references/identity-and-secrets.md](references/identity-and-secrets.md).

- **Keyless everywhere in Go**: `InitializeFirebase` uses Application Default Credentials (ADC) — no key files, ever. This is the finstack#60 lesson (exposed SA key auto-disabled by Google; incident narrative in `finstack-failure-archaeology`). Local Go runs: `gcloud auth application-default login`.
- **CI -> GCP**: OIDC workload identity federation (WIF), per-project providers + `github@<project>.iam.gserviceaccount.com` deployer SAs (functions workflows). Hosting deploys still use SA-key GitHub secrets (`FIREBASE_SERVICE_ACCOUNT_LOOOANS_DEV_STG` / `_PROD`).
- **Runtime SA**: every function runs as the project's `firebase-adminsdk-*` SA (discovered dynamically by the deploy script).
- **The one Secret Manager secret**: `ms-graph-client-secret:latest`, mounted via `--set-secrets`. MS Graph tenant/client IDs are hardcoded non-secrets in `deploy_functions.sh`.
- **sms-gateway**: signs in as Auth user `sms-gateway@loooans.com` (RTDB rules key on this email); password lives only in the device build's `local.properties`.

## CHECKLIST — adding an environment-sensitive path or config axis

New **Firestore collection** (app-only): use a repository extending `BaseFirestoreService` — prefix is automatic. Never concatenate `dev_` yourself.

New **Firestore collection watched by a Go trigger** — touch ALL of:
1. Go handler uses `utils.GetCollectionPrefix()` for every path it reads/writes.
2. Register in `functions/loans/loooans_cloud_functions.go` `init()`.
3. Add a deploy block in `.github/scripts/deploy_functions.sh` with `${collectionPrefix}` in the path pattern, and bump BOTH hardcoded "All N functions" counts (17 as of 2026-07-07).
4. Composite indexes, if any, must be created per prefix (`dev_x`, `stg_x`, `x`) — see index deploy reality in `finstack-run-deploy-operate`.
5. Schema is shared Go<->Flutter: coordinate both sides, backend first (`finstack-change-control`).

New **RTDB env-scoped path** — touch ALL of:
1. Flutter: extend `BaseRealtimeDatabaseService` (or replicate its 3-way prefix exactly — see `typing_service.dart` for the precedent).
2. Go (if written server-side): use `utils.GetMinifiedEnv()`, not a new local switch.
3. Rules: add the node under BOTH `dev` and `stg` in `apps/loans/database.rules.json` AND at root in `apps/loans/database.rules.prod.json` — they do not share source, and the prod file deploys manually.
4. If it must be global instead (like `otp/`), say so explicitly in the PR — global means dev+stg share it.

New **HTTP function**: deploy block in `deploy_functions.sh` (+ counts) + a rewrite entry in EACH of the 3 hosting targets in `apps/loans/firebase.json` (serviceId `<lowercasename>-<environment>`) if it should be reachable via `/api/...`.

New **env-dependent value** (URL, id, etc.): add a case to `functions/loans/utils/environment_utils.go` beside its siblings (Go) and/or a helper in `packages/core/loooans_helpers` keyed on `Environments` (`packages/core/loooans_helpers/lib/src/environments.dart`) — never a raw string compare scattered in feature code.

New **flag**: prefer a field on the existing per-user `settings` doc (`packages/loans/settings_repository`) or a per-product field, matching the inventory above. Note it in this skill's references when you add it.

Any change here that alters console state (rules, indexes) requires a repo note — `finstack-change-control`, unwritten rule 3.

## Re-verification

Run `scripts/verify_env_axes.sh` (in this skill dir) to print all prefix implementations side by side for drift-checking. Individual one-liners are in the Provenance section.

## Provenance and maintenance

Authored 2026-07-07 from direct repo inspection on branch `feature/chat-messaging` (local checkout; chat backend PR finstack#83 merged on GitHub, frontend finstack#84 open — local refs stale). Volatile facts (function count 17, flag inventory, WIF provider paths) are date-stamped above.

Re-verify before trusting:
- THE TABLE projects/aliases: `cat apps/loans/.firebaserc`
- Flutter prefix: `grep -n -A9 "collectionPrefix" packages/core/loooans_helpers/lib/src/data_helpers/database/base_firestore_service.dart`
- Go prefix + siblings: `cat functions/loans/utils/environment_utils.go`
- Deploy-script prefix + path patterns: `grep -n "collectionPrefix" .github/scripts/deploy_functions.sh`
- RTDB env nodes (Flutter): `sed -n 7,19p packages/core/loooans_helpers/lib/src/data_helpers/database/base_realtime_database_service.dart`
- RTDB env nodes (Go): `grep -n -A12 "func getPathEnv" functions/loans/triggers/loan_changes.go`
- RTDB URLs: `grep -n "firebasedatabase.app" functions/loans/utils/initialize_firebase.go`
- ENVIRONMENT fatal guard: `grep -n -A4 "Runtime environment not defined" functions/loans/loooans_cloud_functions.go`
- Function count: `grep -c "gcloud functions deploy" .github/scripts/deploy_functions.sh`
- WIF identities: `grep -n "workload_identity_provider\|service_account:" .github/workflows/loans-functions-*.yml`
- Secret mount: `grep -n "ms-graph-client-secret" .github/scripts/deploy_functions.sh`
- Flags: `grep -rn "forcePaymentConfirmation\|appUseClassicUI" apps/loans/lib/services/settings_service.dart`
