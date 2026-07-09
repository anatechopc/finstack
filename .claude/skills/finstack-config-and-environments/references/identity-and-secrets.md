# Identity and secrets catalog

Companion to `../SKILL.md`. Verified against the repo 2026-07-07. Paths relative to repo root `/Users/deibeeed/Projects/AnaheimTechnologies/finstack`.

Definitions:
- **WIF** = Workload Identity Federation: GitHub Actions exchanges its OIDC token for short-lived GCP credentials — no stored key.
- **SA** = service account. **ADC** = Application Default Credentials (ambient credentials: metadata server on GCP, `gcloud auth application-default login` locally).

## 1. CI deployer identities — Go functions (keyless, WIF)

From `.github/workflows/loans-functions-{development,staging,production}.yml` (the `google-github-actions/auth` step, line ~54 in each):

| Env | WIF provider | Deployer SA |
|---|---|---|
| development | `projects/565409367468/locations/global/workloadIdentityPools/github-actions/providers/github-actions` | `github@loooans-dev-stg.iam.gserviceaccount.com` |
| staging | same as development (same project) | same |
| production | `projects/444559784514/locations/global/workloadIdentityPools/github/providers/github-actions` | `github@loooans-prod.iam.gserviceaccount.com` |

Gotcha: the prod WIF **pool** is named `github` while dev-stg's is `github-actions` — do not copy the dev provider path into a prod workflow.

The deployer SA needs `roles/iam.serviceAccountUser` (actAs) on the runtime SA (below) — stated in `.github/scripts/deploy_functions.sh:65-68`.

## 2. Runtime identity — Go functions

Every function runs as the project's Firebase Admin SDK SA, matched dynamically at deploy time (`deploy_functions.sh:69-70`):

```bash
gcloud iam service-accounts list --project="$project" \
  --filter="email ~ ^firebase-adminsdk-" --format="value(email)" --limit=1
```

At runtime, `functions/loans/utils/initialize_firebase.go` calls `firebase.NewApp(ctx, conf)` with NO credentials option — ADC resolves the runtime SA via the metadata server. **Never re-embed a key file**: a hardcoded SA key was committed and auto-disabled by Google on 2026-06-11 (finstack#60; narrative in `finstack-failure-archaeology`, rule rationale in `finstack-change-control`). The disabled key stays disabled.

Local Go runs / integration pokes: `gcloud auth application-default login` (or `GOOGLE_APPLICATION_CREDENTIALS`) first, plus `ENVIRONMENT=development`.

## 3. CI deployer identities — Flutter hosting (still key-based)

`FirebaseExtended/action-hosting-deploy@v0` authenticates with SA JSON keys stored as GitHub repository secrets — the one remaining key-based CI identity:

| GitHub secret | Used by |
|---|---|
| `FIREBASE_SERVICE_ACCOUNT_LOOOANS_DEV_STG` | `loans-app-development.yml:148,298`, `loans-app-staging.yml` |
| `FIREBASE_SERVICE_ACCOUNT_LOOOANS_PROD` | `loans-app-production.yml:216` |

No `secrets.*` besides `GITHUB_TOKEN` appear in the functions or sms-gateway workflows. Migrating hosting deploys to WIF is an open candidate (not planned anywhere in-repo as of 2026-07-07).

## 4. Secret Manager

Exactly one managed secret, per project: **`ms-graph-client-secret`** (Microsoft Graph client secret for sending mail). Mounted at deploy time (`deploy_functions.sh:63`):

```
--set-secrets "MS_GRAPH_CLIENT_SECRET=ms-graph-client-secret:latest"
```

Attached only to email-sending functions: `requestOtp`, `sendEmail`, `addUser`, `sendPasswordSetupLink`, `userCreated`. All other functions get `ENVIRONMENT` only.

Rotation: add a new secret **version** in Secret Manager; `:latest` picks it up on next cold start / deploy — no code change (`deploy_functions.sh:55-59`).

Hardcoded NON-secrets beside it (`deploy_functions.sh:60-61`) — do not "fix" by moving to Secret Manager, they are public identifiers:

```
MS_GRAPH_TENANT_ID="9df89475-8709-4ec5-82f0-4cb73ebdc92b"
MS_GRAPH_CLIENT_ID="d5b456ce-6c94-47e9-a904-f071382fb4f6"
```

Open (UNVERIFIED console state, as of 2026-07-07): whether the prod runtime SA's `secretmanager.secretAccessor` grant on `ms-graph-client-secret` in `loooans-prod` was completed — root `MEMORY.md` listed it as a pending manual step. Verify: `gcloud secrets get-iam-policy ms-graph-client-secret --project=loooans-prod`.

## 5. sms-gateway device identity

The gateway phone signs in as Firebase Auth user **`sms-gateway@loooans.com`** (`apps/sms-gateway/app/src/main/java/com/loooans/smsgateway/FirebaseConfig.kt:16`). RTDB rules key on exactly this email for `otp/{hash}` and `gateway_status` writes (both `database.rules*.json`).

Credentials are injected at build time, never committed: `apps/sms-gateway/local.properties` (untracked) provides `gateway.email` / `gateway.password` → `BuildConfig.GATEWAY_EMAIL/GATEWAY_PASSWORD` (`app/build.gradle.kts:34-41`). Which project the device serves = which `app/google-services.json` (untracked) it was built with.

## 6. Known bad artifacts (do not imitate)

- `functions/loans/job/subscription_job.go:18` — a real (expired 2024) Google OIDC JWT sits in a comment. Open security finding; disposition in `finstack-security-hardening`.
- `apps/loans/lib/features/authentication/screen/login_screen.dart:141-147` — dev-flavor login autofill with committed real-looking credentials (compiled only into development builds; still a smell).

## Re-verification one-liners

```bash
grep -n "workload_identity_provider\|service_account:" .github/workflows/loans-functions-*.yml
grep -rn "firebaseServiceAccount" .github/workflows/loans-app-*.yml
grep -n "ms-graph-client-secret\|MS_GRAPH_TENANT_ID\|MS_GRAPH_CLIENT_ID" .github/scripts/deploy_functions.sh
grep -n "firebase-adminsdk" .github/scripts/deploy_functions.sh
grep -rn "sms-gateway@loooans.com" apps/loans/database.rules.json apps/loans/database.rules.prod.json
grep -n "GATEWAY_EMAIL\|GATEWAY_PASSWORD" apps/sms-gateway/app/build.gradle.kts
```
