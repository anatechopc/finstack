---
name: finstack-run-deploy-operate
description: Use when running the loans Flutter app or the Go cloud functions locally; when deploying anything (cloud functions, web hosting, Firestore indexes, RTDB rules); when editing or debugging the GitHub Actions workflows; when adding a new cloud function to the deploy script; when bumping the app version; when checking whether the SMS gateway phone is alive or OTP SMS are stuck at "pending"; when you need to know where a function's logs or outputs (RTDB reports, notification docs, FCM) land; or before running ANY `firebase deploy` command in this repo.
---

# finstack — Run, Deploy, Operate

How to run and ship everything in the finstack monorepo, and where the output lands. Repo root: `/Users/deibeeed/Projects/AnaheimTechnologies/finstack`. All facts verified against the repo on 2026-07-07 (branch `feature/chat-messaging`, HEAD `3d94ccc`), plus live GitHub checks via `gh` where noted.

## When NOT to use this skill

| You want to... | Use instead |
|---|---|
| Look up env/project/prefix tables, `ENVIRONMENT` mechanics, secrets, WIF identities | `finstack-config-and-environments` |
| Set up a dev machine (fvm, Go modules, Gradle, codegen, ADC login traps) | `finstack-build-and-env` |
| Know what changes are allowed and how they're gated (branch policy, the 5 rules) | `finstack-change-control` |
| Triage a runtime failure | `finstack-debugging-playbook` |
| Security-rules content, console-rules export runbook, open security findings | `finstack-security-hardening` |
| Write tests / know what counts as evidence | `finstack-testing-and-validation` |

## 1. Running the Flutter app

From `apps/loans/` (always `fvm flutter`, never bare):

```bash
fvm flutter run --flavor development --target lib/main_development.dart --dart-define=ENVIRONMENT=development
fvm flutter run --flavor staging     --target lib/main_staging.dart     --dart-define=ENVIRONMENT=staging
fvm flutter run --flavor production  --target lib/main_production.dart  --dart-define=ENVIRONMENT=production
```

What each flavor connects to (project, prefix, RTDB node): the table in `finstack-config-and-environments`.

**TRAP — the `--dart-define` is NOT optional** (the shorter commands in `apps/loans/CLAUDE.md` omit it). The `--target` file only selects the Firebase options (which *project* you hit); the collection prefix comes from compile-time `String.fromEnvironment('ENVIRONMENT')`, which **falls back to `dev_` when unset** (`packages/core/loooans_helpers/lib/src/data_helpers/database/base_firestore_service.dart`). Verified consequences of omitting it:
- `--flavor staging` without the define → connects to `loooans-dev-stg` but reads/writes `dev_*` collections (you are silently on dev data).
- `--flavor production` without the define → connects to `loooans-prod` but looks for `dev_*` collections that don't exist there (empty app, and any write pollutes prod with `dev_` collections — violates unwritten rule 1/5, `finstack-change-control`).

The three VS Code launch configs in `apps/loans/.vscode/launch.json` already pass the define correctly — prefer them. iOS is not buildable on this box; platform gotchas → `finstack-build-and-env`.

## 2. Running Go functions locally

The deployed entry point `functions/loans/loooans_cloud_functions.go` is a *library* package whose `init()` registers all functions and starts the server — you can't `go run` it. The local runner is **`functions/loans/cmd/main.go`**, which registers its own, **stale subset** (as of 2026-07-07: HTTP `requestOtp`, `sendEmail`, `sometest`; triggers `userCreated`, `loanChanges`, `loanScheduleChanges`, `capitalCreated`, `notificationCreated`). To exercise anything else locally, temporarily add its registration line to `cmd/main.go` — do not commit that edit.

```bash
cd functions/loans
gcloud auth application-default login   # once; ADC required — Admin SDK has no embedded key
ENVIRONMENT=development go run ./cmd
```

- `ENVIRONMENT` is **required** — the process calls `log.Fatal` if unset (`loooans_cloud_functions.go:62` and `cmd/main.go:46`). Always use `development` locally; anything unrecognized silently maps to **prod** collection paths in Go (`finstack-config-and-environments`).
- Port: 8080, override with `PORT`.
- Routing (functions-framework-go v1.8.1, verified in module source): with no `FUNCTION_TARGET`, every registered function is served at `http://localhost:8080/<name>`; with `FUNCTION_TARGET=<name>`, that single function is served at `/`.
- Smoke test: `curl http://localhost:8080/sometest` (a scratch endpoint, registered but never deployed).
- Firestore triggers are CloudEvent handlers — exercising them locally means hand-crafting CloudEvent POSTs; in practice, test trigger *logic* via the adapter+core fakes pattern (`finstack-testing-and-validation`) and test wiring on the dev environment.
- ADC account drift (CLI account ≠ ADC account) is a known local trap → `finstack-build-and-env`.

## 3. CI workflow inventory

Seven workflows in `.github/workflows/` (verified 2026-07-07):

| Workflow | Trigger branches | Path filter | Does |
|---|---|---|---|
| `loans-app-development.yml` | PR + push `develop`; dispatch | `apps/loans/**`, `packages/**`, `loans-app-*.yml` | PR: build web + hosting **preview channel**. Push: version bump commit, build web, deploy hosting `develop` target (live) |
| `loans-app-staging.yml` | push/PR/create `release/v*`; dispatch | same | bump `staging`, build web staging, deploy hosting `staging` target |
| `loans-app-production.yml` | push/create `master`; dispatch | same | bump `production` (parses merge-commit source branch for `release/v*` / `hotfix/*`), build web prod, deploy hosting `production` target |
| `loans-functions-development.yml` | PR + push `develop`; dispatch | `functions/loans/**`, `loans-functions-*.yml` | build+test Go; **deploy only on push** via WIF → `deploy_functions.sh -e development -p loooans-dev-stg` |
| `loans-functions-staging.yml` | PR + push `release/**`; dispatch | same | same, `-e staging -p loooans-dev-stg` |
| `loans-functions-production.yml` | PR + push `master`; dispatch | same | same, `-e production -p loooans-prod` (WIF project 444559784514; pins `setup-go@v4` vs `@v5` elsewhere) |
| `sms-gateway.yml` | push `develop`/`feat/sms-gateway*`, PR; dispatch | `apps/sms-gateway/**` | **build + unit-test ONLY — no deploy** (device is manually provisioned, §7) |

Key operational facts:

- **Triplicate hazard (known, recurring):** the three `loans-app-*.yml` are near-identical (~200 lines of shared codegen-cache logic) and the three `loans-functions-*.yml` likewise. There is no reusable workflow — **any change to shared steps must be edited in all three files**. Sanity-check after editing: `diff .github/workflows/loans-app-development.yml .github/workflows/loans-app-staging.yml` and eyeball that only env-specific lines differ.
- **Flutter upgrades need no workflow edits:** every app workflow extracts the version from `apps/loans/.fvmrc` (job `get_flutter_version`).
- **PRs never deploy functions** (`if: github.event_name == 'push'` on the deploy job). App PRs deploy a hosting *preview channel*, not live.
- **Keyless deploys:** OIDC workload identity federation; no SA keys in secrets. Identities per env: `finstack-config-and-environments`.
- **CI builds web only.** No workflow builds an APK/AAB or iOS artifact for the loans app — Android/iOS binaries are built and distributed manually.
- **Branch reality as of 2026-07-07 (verified via `gh api .../branches`): only `develop` + feature branches exist. There is NO `master` and NO `release/*` branch** — the staging and production workflows have *never fired* from this repo. Before the first `master` functions deploy: `roles/secretmanager.secretAccessor` on `ms-graph-client-secret` is still pending on `loooans-prod` (`functions/loans/MEMORY.md:44`), and orphaned `verifyPaymentOtp_<env>` Cloud Run services need manual console deletion (`functions/loans/MEMORY.md:149`).

Full per-workflow anatomy (jobs, conditions, codegen cache, version-bump logic, the Node 24 / Happy-Eyeballs fix): [references/ci-workflows.md](references/ci-workflows.md).

## 4. Deploying Go functions

Normal path: merge to `develop` (backend-first discipline → `finstack-change-control`); the workflow runs `.github/scripts/deploy_functions.sh`.

Manual deploy (same script CI runs; needs `gcloud auth login` with an identity holding deployer perms + `roles/iam.serviceAccountUser` on the runtime SA):

```bash
.github/scripts/deploy_functions.sh -e development -p loooans-dev-stg
# -e: development | staging | production   -p: loooans-dev-stg | loooans-prod
```

Anatomy (one line each; full flag-by-flag breakdown in [references/deploy-functions-anatomy.md](references/deploy-functions-anatomy.md)):

- Deploys **17 functions** (6 HTTP + 11 Firestore triggers) **in parallel** as background `gcloud functions deploy` jobs, then waits and reports failures. Count is date-stamped: 17 as of 2026-07-07 on `feature/chat-messaging` AND on GitHub `develop` (verified live via `gh api`; local `origin/develop` ref is stale at 16 — last fetch 2026-06-30).
- All gen2, runtime `go122`, region `asia-east1`, `--allow-unauthenticated` **by design** — HTTP auth is JWT validation in-code (`utils/validate_request_v2.go`); two endpoints are deliberately public (`finstack-security-hardening`).
- Runtime identity: the project's `firebase-adminsdk-*` SA, discovered by `gcloud iam service-accounts list` at the top of the script; script aborts if not found.
- Email-sending functions (`requestOtp`, `sendEmail`, `addUser`, `sendPasswordSetupLink`, `userCreated`) additionally get MS Graph env vars + `--set-secrets MS_GRAPH_CLIENT_SECRET=ms-graph-client-secret:latest`.
- Trigger path patterns are **baked at deploy time** with the env's collection prefix (`dev_`/`stg_`/none) — the third of the three places that must agree (`finstack-config-and-environments`).
- `sometest` is registered in `init()` but intentionally absent from the script — never deployed.

**Adding a function = two files, minimum** (checklist in [references/deploy-functions-anatomy.md](references/deploy-functions-anatomy.md)): register in `loooans_cloud_functions.go` `init()` AND add a deploy block to `deploy_functions.sh` (plus bump the two "All N functions" echo strings). Forgetting the script = function builds green but never ships — this exact serialization point was touched 14 times in history.

## 5. Version bumping (app)

`apps/loans/scripts/bump_version.sh [dev|staging|production]` (default `dev`). CI runs it automatically on merge/push (see §3) — run it manually only for out-of-band bumps. Modes: `dev` → `X.Y.Z-dev.N`; `staging` → `-pre.N`; `production` → strips `-pre` (or `-fix.N` for hotfixes). Build number is **`date +%s` seconds — never milliseconds**: millis overflow Android's 32-bit `versionCode` (the Flutter 3.44 upgrade headline failure → `finstack-failure-archaeology`). Seconds stay valid until ~2038-01-19.

## 6. Deploying Firestore indexes

```bash
cd apps/loans
./scripts/deploy-indexes.sh [dev|stg|prod]   # needs firebase-cli (logged in) + jq
```

Mechanism: pulls **live** indexes (`firebase firestore:indexes`), filters by collection prefix into `firestore.indexes.<env>.json`, copies that over `firestore.indexes.json`, then `firebase deploy --only firestore:indexes`.

- **VERIFIED BUG — the `dev` branch is broken.** Line 38 reads `if ["$ENV" == "dev"]; then` (missing spaces inside brackets) → the condition always errors/false → the script generates the **stg** file, then `cp`s the **stale committed** `firestore.indexes.dev.json` and deploys *that*. `stg` and `prod` paths are correct. Workaround until fixed: for dev, either fix the brackets locally (`if [ "$ENV" == "dev" ]; then`) or run the `jq` dev filter by hand before the deploy step.
- `apps/loans/firestore.indexes.json` is an **overwritten scratch artifact** (whatever env deployed last, currently unprefixed/chat state) — never treat it as the source of truth; the per-env `.dev/.stg/.prod` files are the committed snapshots.
- New composite indexes must exist per prefix (`dev_x`, `stg_x`, `x`) — a trigger/query needing a missing index retry-loops (`finstack-debugging-playbook`).

## 7. Rules deploy reality — READ BEFORE ANY `firebase deploy`

`apps/loans/firebase.json` wires: `hosting` (3 targets), `firestore.indexes` → `firestore.indexes.json`, `database.rules` → `database.rules.json`, `storage.rules` → `storage.rules`. **There is NO `firestore.rules` key.** Verified state of each source file:

| File | State | If you deployed it |
|---|---|---|
| `firestore.rules` | STALE VGV template, expired 2024-06-22 (= deny-all) | Can't via `firebase deploy` (not wired). Real Firestore rules are **console-managed** |
| `storage.rules` | `allow read, write: if false` — deny-all, **and it IS wired** | Would **deny-all Cloud Storage** → breaks every upload (requirements, payment proofs, chat images). Real Storage rules are console-managed |
| `database.rules.json` | REAL dev-stg RTDB rules (env-scoped `dev`/`stg` nodes + global `otp`, `gateway_status`, `app/sessions`) | Safe **only** against `loooans-dev-stg` |
| `database.rules.prod.json` | REAL prod RTDB rules (unprefixed) — **nothing deploys it**; no firebase.json wiring, no CI | Prod RTDB rules are a **manual console step** (history: commit `96057c6`). Deploying `--only database` with `--project loooans-prod` would ship the WRONG (dev-stg) file |

Consequences — treat as hard rules:
1. **NEVER run bare `firebase deploy`** from `apps/loans/` — it would push deny-all Storage rules and dev-stg RTDB rules to the active project. The only safe deploy target here is `--only firestore:indexes` (and `--only hosting` if deploying web by hand, which CI normally owns).
2. `firestore.rules.chat.reference` / `storage.rules.chat.reference` are **reference-only** files for the chat feature — not deployed by anything; the corresponding real rules are a pending console change (in-flight state → `finstack-roadmap-and-frontier`).
3. Every console rules change requires a repo note — unwritten rule 3 (`finstack-change-control`). Rules content, export-to-source runbook, and the campaign to end this situation: `finstack-security-hardening`.

## 8. SMS gateway operations

The SMS gateway is a **dedicated physical Android phone** running `apps/sms-gateway` (Kotlin foreground service) that delivers OTP SMS — it watches RTDB `/otp/` and sends via the phone's SIM (`SmsGatewayService.kt`). It is a **single point of failure with no alerting** (open risk, accepted for now). One device serves BOTH dev and stg (shared project, unprefixed `/otp/`).

**Is the gateway alive?** It heartbeats to `/gateway_status/{deviceId}` every 30s (`SmsGatewayService.kt:181`, fields `last_heartbeat` int64-millis, `device_name`, `status`). Check:

```bash
.claude/skills/finstack-run-deploy-operate/scripts/check-deploy-status.sh dev --gateway
# or raw (uses your gcloud CLI account's token — needs RTDB read on the project):
curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://loooans-dev-stg-default-rtdb.asia-southeast1.firebasedatabase.app/gateway_status.json"
```

`last_heartbeat` older than ~90s ⇒ gateway down. Symptom downstream: OTP entries stuck at `sms_status: "pending"`, users never receive SMS (`finstack-debugging-playbook`).

**Provision / redeploy the device (fully manual — CI only builds/tests):**
1. `apps/sms-gateway/app/` needs `google-services.json` (from Firebase console; CI drops dummies in `app/src/debug/` + `app/src/release/` — either location works).
2. Root `apps/sms-gateway/local.properties`: `gateway.email` / `gateway.password` (injected as `BuildConfig` fields via `app/build.gradle.kts:34-41`; the README's "update FirebaseConfig.kt" step is stale). The gateway signs in as this Firebase Auth user — RTDB rules key its write access to `auth.token.email == 'sms-gateway@loooans.com'`.
3. `./gradlew assembleDebug` (debug appId suffix `.dev`) or `assembleRelease`.
4. `adb install` the APK on the designated device, open the app, start the service (foreground notification "Loooans SMS Gateway" appears). Needs SEND_SMS + notification permission granted on-device.

Processing contract (verified `OtpEntry.kt`): sends only entries with `objective == "mobile_number"` && `sms_status == "pending"`; re-sends when an entry's `sms_status` flips back to `pending`; writes back `sent`+`sent_at` or `failed`+`error`.

## 9. Where outputs land

- **Function logs:** `gcloud functions logs read <name>_<env> --project <project> --region asia-east1 --gen2 --limit 50` (e.g. `requestOtp_development --project loooans-dev-stg`).
- **Deployed form:** each function is a Cloud Run service, lowercased (`requestotp-development`); hosting rewrites `/api/...` paths to them per env (`apps/loans/firebase.json` rewrites blocks).
- **Web hosting:** CI builds to `build/web/<env>` → hosting targets `develop`/`staging`/`production` → sites `loooans-dev-stg` / `loooans-stg` / `loooans-prod` (`.firebaserc`).
- **RTDB reports** (written by `loanChanges`): `{dev|stg|<none>}/companies/{companyId}/report_summary/` → `sales`, `products`, `total_summary`, `capital_usage`, `data/` (per-item entries) — path builders at `triggers/loan_changes.go:504-537`. NOTE the RTDB env node style (`dev/`, not `dev_`). This writer has known correctness bugs and is the reporting-rebuild campaign target → `finstack-loan-engine-and-reporting-campaign`.
- **Notifications:** Go triggers write `{prefix}notifications/{uid}` docs → `notificationCreated` fans out FCM to `users/{id}/devices/*.token`. Exception: chat (`messageWritten`) pushes FCM **directly**, bypassing the notifications collection. Ownership rationale → `finstack-architecture-contract`.

## 10. Status-check script

`scripts/check-deploy-status.sh [dev|stg|prod] [--gateway]` (in this skill dir, read-only): lists deployed functions for the env's project/suffix via `gcloud functions list`, diffs them against the entry points parsed from `deploy_functions.sh` on your current branch, and with `--gateway` prints SMS-gateway heartbeat age. Requires `gcloud auth login` (uses CLI credentials, not ADC).

## Provenance and maintenance

Authored 2026-07-07 from repo inspection on branch `feature/chat-messaging` (`3d94ccc`) + live `gh`/`gcloud --help` checks. Volatile facts and how to re-verify:

- Function count / roster (17): `grep -c "gcloud functions deploy" .github/scripts/deploy_functions.sh`
- Branch reality (no master/release yet): `gh api repos/anatechopc/finstack/branches --jq '.[].name'`
- Workflow inventory: `ls .github/workflows/`
- `deploy-indexes.sh` dev bug still present: `sed -n 38p apps/loans/scripts/deploy-indexes.sh` (broken if no spaces inside `[...]`)
- firebase.json still has no `firestore.rules` key: `jq 'has("firestore") and (.firestore|has("rules"))' apps/loans/firebase.json` (expect `false`)
- `cmd/main.go` local-runner subset: `grep "functions\." functions/loans/cmd/main.go`
- Heartbeat interval: `grep -n "delay(" apps/sms-gateway/app/src/main/java/com/loooans/smsgateway/SmsGatewayService.kt`
- Prod-deploy prerequisites still pending: `grep -n "pending" functions/loans/MEMORY.md`
