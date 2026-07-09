# deploy_functions.sh — Full Anatomy (verified 2026-07-07)

File: `.github/scripts/deploy_functions.sh`. Called by CI (`loans-functions-*.yml`) and runnable by hand. Usage: `-e development|staging|production` `-p <gcloud project>` (both required; env value validated, project NOT validated against env — nothing stops `-e development -p loooans-prod` except you; see unwritten rule 5 in `finstack-change-control`).

## Script flow

1. Parse/validate args; map env → `collectionPrefix` (`dev_` / `stg_` / empty).
2. Define MS Graph constants: `MS_GRAPH_TENANT_ID` and `MS_GRAPH_CLIENT_ID` hardcoded (non-secret by design); `MS_GRAPH_SECRETS="MS_GRAPH_CLIENT_SECRET=ms-graph-client-secret:latest"` (Google Secret Manager; rotate by adding a secret version — no code change).
3. Discover the runtime SA: `gcloud iam service-accounts list --project=$project --filter="email ~ ^firebase-adminsdk-" --limit=1`; **abort if none**. Deployer needs `roles/iam.serviceAccountUser` (actAs) on it. Functions run keyless as this SA (ADC via metadata server — the fix for the 2026-06-11 committed-key incident, `finstack-failure-archaeology`).
4. Launch every `gcloud functions deploy ... &` in the background, recording PID→name.
5. `wait` on each PID; print `Failed functions: ...` and exit 1 if any failed.

## The 17 functions (as of 2026-07-07; branch `feature/chat-messaging` and GitHub `develop`)

Deployed name is always `<entryPoint>_<environment>`; `{p}` = collectionPrefix.

### HTTP (`--trigger-http`)

| Entry point | MS Graph env+secret? | Notes |
|---|---|---|
| `requestOtp` | yes | writes `otp/{hash}` to RTDB; email or SMS-gateway path |
| `verifyOtp` | no (`ENVIRONMENT` only) | reason-driven post-actions |
| `sendEmail` | yes | MS Graph send |
| `addUser` | yes | admin-only provisioning |
| `sendPasswordSetupLink` | yes | deliberately unauthenticated endpoint |
| `setPassword` | no | deliberately unauthenticated; modelled on verifyOtp per script comment |

Common flags: `--runtime go122 --trigger-http --project $project --region asia-east1 --allow-unauthenticated --gen2 --service-account=$serviceAccount --entry-point <name>`.

### Firestore triggers (`--trigger-event-filters`)

Common flags: `--gen2 --service-account=... --runtime=go122 --region=asia-east1 --trigger-location=asia-east1 --source=. --trigger-event-filters=database='(default)' --set-env-vars=ENVIRONMENT=$environment` (userCreated instead gets the full MS Graph env+secret set).

| Entry point | Event type (`google.cloud.firestore.document.v1.*`) | Path pattern |
|---|---|---|
| `userCreated` | created | `{p}users/{uid}` |
| `loanChanges` | **written** | `{p}loans/{uid}` |
| `loanScheduleChanges` | created | `{p}loan_schedules/{uid}` |
| `capitalCreated` | created | `{p}capital/{uid}` |
| `notificationCreated` | created | `{p}notifications/{uid}` |
| `reviewCreated` | created | `{p}reviews/{uid}` |
| `reviewUpdated` | updated | `{p}reviews/{uid}` |
| `paymentCreated` | created | `{p}payments/{uid}` |
| `paymentUpdated` | updated | `{p}payments/{uid}` |
| `userChanges` | updated | `{p}users/{uid}` |
| `messageWritten` | **written** | `{p}chat_rooms/{roomId}/messages/{messageId}` |

The path pattern is fixed **at deploy time** — if the prefix scheme ever changes, redeploying is mandatory (third of the three prefix places, `finstack-config-and-environments`).

## Registered but NOT deployed / disabled

- `sometest` — registered in `init()` (`loooans_cloud_functions.go:30`), intentionally absent from the deploy script. Scratch endpoint.
- `updateUser`, `subscriptionJob` — registration lines commented out in `init()`; `job/` module currently disabled (and contains an expired-but-real OIDC JWT in a comment — open security finding, `finstack-security-hardening`).
- Orphaned Cloud Run services `verifyPaymentOtp_<env>` — predecessor of `verifyOtp` (renamed 2026-04); the script no longer redeploys them and they should be deleted manually from the GCP console after the first successful deploy per env (script comment at line ~86; still listed as pending in `functions/loans/MEMORY.md:149`). A console deletion is a console change → repo note (`finstack-change-control` rule 3).

## Add-a-function checklist

1. Write handler (+ adapter/core split with fakes tests — unwritten rule 4, recipe in `finstack-testing-and-validation`).
2. Register in `functions/loans/loooans_cloud_functions.go` `init()` — `functions.HTTP(...)` or `functions.CloudEvent(...)`.
3. (If you want it locally runnable) also add to `functions/loans/cmd/main.go` — it does NOT pick up the root registration.
4. Add a deploy block to `deploy_functions.sh`:
   - HTTP, no email: copy the `verifyOtp` block.
   - HTTP, sends email via MS Graph: copy the `sendEmail` block (env vars + `--set-secrets`).
   - Firestore trigger: copy a trigger block; set event type + `${collectionPrefix}<collection>/{id}` path pattern.
   - Keep the `pids[$!]="<name>"` line so failures are attributed.
5. Bump BOTH count strings: `"All N functions deploying in parallel"` and `"All N functions deployed successfully"`.
6. `go mod tidy` in the touched sub-module; `go build -v ./...` (macOS test workaround `CGO_ENABLED=0` → `finstack-build-and-env`).
7. Ship backend-first (`finstack-change-control`); after merge to `develop`, confirm with `scripts/check-deploy-status.sh dev`.

Count history (from git): 8 → 10 → 12 → 13 → 15 → 16 → 17. Every new function touches this script — it is the deploy serialization point (14 edits in history).

## Manual-deploy prerequisites

- `gcloud auth login` as an identity with Cloud Functions Admin (or equivalent) + `roles/iam.serviceAccountUser` on `firebase-adminsdk-*@<project>`.
- For email functions: the runtime SA needs `roles/secretmanager.secretAccessor` on `ms-graph-client-secret`. Granted on `loooans-dev-stg`; **still pending on `loooans-prod` as of 2026-07-07** (`functions/loans/MEMORY.md:44`) — the first production deploy will fail on the email functions until granted.
- Run from anywhere; the script `--source=.` for triggers assumes CWD = `functions/loans` when invoked the way CI does (workflow `working-directory` handling). When running by hand: `cd functions/loans && ../../.github/scripts/deploy_functions.sh -e <env> -p <project>` (matches the CI invocation `run: '../../.github/scripts/deploy_functions.sh ...'`).
