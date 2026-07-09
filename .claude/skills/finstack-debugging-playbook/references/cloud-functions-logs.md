# Reading Cloud Functions logs — full runbook

Everything here verified 2026-07-07 against `.github/scripts/deploy_functions.sh`,
`functions/loans/utils/initialize_logger.go`, `apps/loans/firebase.json`, and
gcloud SDK 549.

## Name resolution (know what you are querying)

Every function is deployed gen2, runtime `go122`, region **asia-east1**, named
`<entryPoint>_<environment>`:

| You know | Deployed function name | Underlying Cloud Run service |
|---|---|---|
| entry point `notificationCreated`, env development | `notificationCreated_development` | `notificationcreated-development` |
| entry point `verifyOtp`, env production | `verifyOtp_production` | `verifyotp-production` |

- Entry points are registered in `functions/loans/loooans_cloud_functions.go`
  `init()`; the deploy list (17 functions as of 2026-07-07) is in
  `.github/scripts/deploy_functions.sh`.
- Gen2 functions run on Cloud Run; the service name is the function name
  lowercased with `_` → `-` (visible in the `firebase.json` hosting rewrites,
  e.g. `"serviceId": "verifyotp-development"`).
- Environment values are the full words `development` / `staging` / `production`
  (the deploy script's `-e` argument), never `dev`/`stg`.

| Environment | GCP project |
|---|---|
| development, staging | `loooans-dev-stg` |
| production | `loooans-prod` |

## Quick read: `gcloud functions logs read`

```bash
gcloud functions logs read notificationCreated_development \
  --region=asia-east1 --project=loooans-dev-stg --limit=50 --gen2
```

Or use the wrapper (maps env → project for you):

```bash
.claude/skills/finstack-debugging-playbook/scripts/fn-logs.sh notificationCreated development 50
```

Useful extra flags (all verified in SDK 549):

```bash
--min-log-level=error                 # only >= ERROR
--start-time=2026-07-07T00:00:00Z     # window start (see: gcloud topic datetimes)
--end-time=2026-07-07T12:00:00Z
--execution-id=<id>                   # one invocation's logs
```

## Deep read: `gcloud logging read` (when the quick read is not enough)

`gcloud functions logs read` truncates long lines and misses some
platform/system entries. For full payloads, query the Cloud Run revision logs
directly (lowercase service name):

```bash
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="notificationcreated-development"' \
  --project=loooans-dev-stg --limit=50 --freshness=1d --order=desc
```

Add `severity>=ERROR` or a text match to the filter:

```bash
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="loanchanges-development" AND textPayload:"cannot get"' \
  --project=loooans-dev-stg --limit=20 --freshness=7d
```

## Console

- **Logs Explorer**: https://console.cloud.google.com/logs/query?project=loooans-dev-stg
  (swap project for prod). Paste the same `resource.type="cloud_run_revision" AND
  resource.labels.service_name="..."` filter.
- **Per-function**: Cloud Functions → region asia-east1 → click the function →
  Logs tab. Slower but pre-filtered.

## Log format quirks (what you will actually see)

- Handlers log via zap, named per handler: `utils.InitializeLogger("functionName")`
  (`functions/loans/utils/initialize_logger.go`). The logger name appears in each
  line — useful when one container hosts shared `init()` output.
- **Quirk (source-verified 2026-07-07):** `InitializeLogger` switches on
  `os.Getenv("environment")` — lowercase — while deploys set `ENVIRONMENT`
  (uppercase). The `production` branch therefore never matches, and every
  environment uses zap's *development* console encoder (tab-separated
  `TIMESTAMP  LEVEL  name  caller  message  {fields}`), not production JSON.
  Do not expect `jsonPayload` fields from handler logs; match on `textPayload`.
- Cold-start lines: `init`, `added cloud functions`, `Running on <env> Environment`,
  `Listening to port: {port}` come from `loooans_cloud_functions.go` on every
  instance start. Seeing them repeatedly = instances churning, not necessarily a bug.

## Known log signatures → triage rows (SKILL.md table)

| Log text | Meaning | Row |
|---|---|---|
| `Runtime environment not defined` (then container exits) | `ENVIRONMENT` unset | 14 |
| `rpc error: code = Unauthenticated` | Admin SDK credential problem (runtime SA / ADC) | 9 |
| `failed to get devices for user <id>` | FCM fan-out could not read the devices subcollection | 10 |
| `cannot get loan schedules for loanId <id>: %$w` (literal `%$w`) | `loan_changes.go` format typo — the wrapped error is NOT printed; the schedules query failed (the literal `%$w` is itself a verified grep target) | 11 |
| `FAILED_PRECONDITION` + an index-creation URL | Missing composite Firestore index; inside a trigger this can re-invoke persistently (the 18adc31 near-miss) | 3 |

## Trigger re-invocation

If the same document event appears over and over for a trigger, the handler is
returning an error persistently (e.g. a missing index). Correlate invocations
with `--execution-id`, find the first failure, and fix the underlying error —
the repetition is a symptom, not the disease. (Observed behavior in this repo's
history — commit 18adc31 was specifically shaped to avoid a deploy-time
FAILED_PRECONDITION "that would retry-loop the trigger".)

## Prerequisites / gotchas

- You need `roles/logging.viewer` (or broader) on the project. If `gcloud` errors
  with permission denied while the console works, remember the ADC drift trap
  (CLI account vs ADC account — `references/triage-details.md` Row 9); note
  `gcloud logging read` uses the **CLI** account, so drift shows up as CLI-works /
  SDK-fails or vice versa.
- Functions are in asia-east1 but RTDB is asia-southeast1 — RTDB has no logs
  here; only function-side errors about RTDB appear.
- Do not confuse the environments: `dev_` prefixed collections fire
  `*_development` functions; `stg_` fire `*_staging` — both in the SAME project
  `loooans-dev-stg`. Reading the wrong function's logs for the environment you
  tested in is the most common dead end.
