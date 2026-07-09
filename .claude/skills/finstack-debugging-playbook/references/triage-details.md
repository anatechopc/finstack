# Triage details — discriminating experiments per row

Row numbers match the table in `../SKILL.md`. Everything here was verified against
the repo on 2026-07-07 (branch `feature/chat-messaging`, HEAD 3d94ccc).

## Row 1 — `TypeError: Instance of 'Timestamp' is not a subtype of type 'num'`

**Background.** All dates in Firestore and RTDB are int64 millis since epoch (root
`MEMORY.md`, "Date/Timestamp Convention"). The Go Admin SDK serialises a raw
`time.Time` as a Firestore **Timestamp proto**, which the Flutter side cannot cast
to `num`. Two distinct situations produce the same TypeError:

1. **Live producer bug** — some Go code path writes `time.Time` today.
2. **Polluted legacy doc** — the doc was written before the producer fixes of
   2026-05-13 (PRs finstack#48 `verify_otp.go`, finstack#49
   `notification_helpers.go`) and still carries Timestamp fields.

**Discriminate:**

```bash
# 1. Identify the failing doc + field from the Flutter stack trace / feature.
# 2. In Firebase console, open the doc: Timestamp-typed field confirms the data shape.
# 3. Find the Go writer for that field:
grep -rn "field_name" functions/loans/ --include="*.go" | grep -v _test
# 4. In the writer: is the value time.Now() / a time.Time, or .UnixMilli()?
```

- Writer uses `.UnixMilli()` (or `utils.ToInt64` — `functions/loans/utils/math_utils.go`)
  and the doc is old → legacy pollution. The Flutter helpers
  (`packages/core/loooans_helpers/lib/src/data_helpers/constants.dart`) have
  duck-typed Timestamp tolerance since commit de0f7e9 — so a TypeError today means
  the failing code path is casting `as num` directly instead of going through
  `handleDateTimeFromJson` / `handleDateTimeNullableFromJson`. Fix the consumer to
  use the helpers.
- Writer emits `time.Time` → live producer bug. Fix the producer
  (`.UnixMilli()`), then remember the docs it already wrote stay polluted: the
  tolerant helpers absorb them, but any direct `as num` cast will not.

**Do not** "fix" this by migrating prod docs by hand — that violates the
never-touch-prod-data rule (`finstack-change-control`). Chain B narrative:
`finstack-failure-archaeology`.

## Row 2 — Loading overlay stuck / dialog never dismisses

**The Chain A lesson (5 commits, 03-03 → 05-09):** modal loading dialogs live on the
root navigator, so a GoRouter route change does not dismiss them; and on web a
`BlocListener` can process a routing state before the loading-off state if they are
emitted back-to-back (the screen unmounts, the listener detaches, the pop never
happens).

**Check, in order:**

1. Is loading shown with `showDialog(...)`? That is the banned pattern. The house
   pattern is an inline overlay in the widget tree, driven by bloc state:
   `apps/loans/lib/features/authentication/screen/login_screen.dart` (~line 70):
   `Stack` + `if (isLoading) Positioned.fill(ColoredBox + CircularProgressIndicator)`.
   Same pattern in `mobile_verification_screen.dart` and
   `email_verification_screen.dart`.
2. Does the handler emit `loading(false)` immediately followed by a state that
   triggers navigation? Insert a yield so the UI processes loading-off first:
   `apps/loans/lib/features/authentication/bloc/authentication_bloc.dart:192-196`:

   ```dart
   // Without this yield, the route change can race ahead of the listener and
   // the loading state is never cleared on the old screen.
   await Future<void>.delayed(Duration.zero);
   ```

3. Does the bloc reuse one loading status for multiple concurrent operations?
   Commits 053c141 / ed1b5ef exist because OTP flows reused `paymentLoading`;
   dedicated statuses (e.g. `otpLoading`) prevent one operation's completion from
   hiding another's spinner.

**Fix pointer:** replicate the inline-overlay + dedicated-status + yield pattern.
Do not add another "dismiss the dialog defensively" band-aid — that was attempts
1-4 of 5.

## Row 3 — Firestore query silently returns nothing

Three causes, in likelihood order:

1. **Field-name mismatch.** House style is snake_case JSON keys via `@JsonKey`, but
   an entity field WITHOUT `@JsonKey` serialises camelCase. Real case (commit
   e14592a): `BankDetailsEntity.dataId` has no `@JsonKey`, stores as `dataId`; the
   submit dialog queried `data_id` → matched nothing → Send permanently disabled,
   no error anywhere.

   ```bash
   # Check the entity for the field's actual JSON key
   grep -n -B2 "dataId" packages/core/bank_details_repository/lib/src/model/*.dart
   ```

   Then open one real doc in the console and diff exact field names against the
   query string.

2. **Missing/wrong collection prefix.** Querying `users` where the data lives in
   `dev_users` (or vice versa). Flutter gets the prefix from
   `base_firestore_service.dart` (compile-time `ENVIRONMENT`); Go from
   `utils.GetCollectionPrefix()`. If you built the app with the wrong flavor/target
   pair you are reading the wrong environment's collections. See
   `finstack-config-and-environments`.

3. **Missing composite index** — but that usually fails loudly
   (FAILED_PRECONDITION with an index-creation link), not silently. If a *trigger*
   does the query, the error may only appear in function logs (see the logs
   runbook) — and beware commit 18adc31's lesson: an index error inside a trigger
   makes the trigger retry-loop.

## Row 4 — Blank page ONLY in release/prod build

**Mechanism (commit d84b628):** `Expanded` is a ParentDataWidget that writes
`FlexParentData` and asserts an ancestor Flex. Under a non-Flex parent
(`ConstrainedBox` in the real case), debug builds trip an assertion Flutter
catches and recovers from — the panel still renders. Profile/release builds strip
assertions, so the `child.parentData as FlexParentData` cast throws
`TypeError: Instance of 'ParentData' is not a subtype of ... 'FlexParentData'`
and blanks the whole panel.

**Repro locally (always dev flavor/env, never prod):**

```bash
cd apps/loans
# Web (where the real bug shipped — hosting builds are release):
fvm flutter run -d chrome --release --target lib/main_development.dart
# Android:
fvm flutter run --flavor development --target lib/main_development.dart --release
```

Open the browser dev console: the TypeError appears there even though the UI just
looks empty.

**Hunt:** look for `Expanded` / `Flexible` (need a `Row`/`Column`/`Flex` parent) or
`Positioned` (needs a `Stack` parent) whose *direct* parent is something else.
`fvm flutter analyze` does NOT catch this — it is a runtime parent-data check.

**Status:** finstack#31 ("Page does not load on production AND/OR on release
build") is still OPEN as of 2026-07-07 — d84b628 fixed one instance; treat any new
release-only blank as possibly another instance of the same class.

## Row 9 — `requestOtp` 500 / Admin SDK `Unauthenticated`

**History (finstack#60, commit ae0789d):** an SA private key was committed; Google's
scanner disabled it; every Admin SDK call started failing
`rpc error: code = Unauthenticated`, first observed as a 500 from `requestOtp`
during mobile-number verification. The fix made all Firebase init keyless ADC
(`firebase.NewApp(ctx, conf)` with no credentials option —
`functions/loans/utils/initialize_firebase.go`). **Never re-embed or re-enable a
key** (see `finstack-security-hardening`).

**Local triage (running functions on your machine):**

```bash
# ADC missing or stale:
gcloud auth application-default login

# ADC DRIFT TRAP: the gcloud CLI account and the ADC account are separate.
# `gcloud auth list` showing the right account does NOT mean ADC uses it.
gcloud auth list                                   # CLI account
gcloud auth application-default print-access-token >/dev/null && echo "ADC ok"
# Inspect which identity ADC actually holds:
cat ~/.config/gcloud/application_default_credentials.json 2>/dev/null | head -5
```

If Admin SDK calls fail with permission errors while `gcloud` CLI commands work,
suspect ADC drift first.

**Cloud triage (deployed function):**

```bash
# Runtime SA must be the project's firebase-adminsdk-* account
gcloud functions describe requestOtp_development \
  --region=asia-east1 --project=loooans-dev-stg \
  --format='value(serviceConfig.serviceAccountEmail)'
# Then read its logs (see cloud-functions-logs.md)
```

The deploy script (`.github/scripts/deploy_functions.sh`) discovers and pins that
SA with `--service-account=`; a function deployed without it runs as the default
compute SA and may lack Firestore/RTDB/Auth access.

## Row 10 — FCM push not arriving

Two distinct pipelines:

**Pipeline A (everything except chat):** business trigger (loanChanges,
paymentCreated, reviewCreated, ...) → `createNotification`
(`functions/loans/triggers/notification_helpers.go`) writes a
`{prefix}notifications` doc → `notificationCreated` trigger
(`triggers/notification_created.go`) reads `{prefix}users/{recipientId}/devices`,
collects each doc's `token` field, `SendEachForMulticast`.

Walk it in order:

1. **Notification doc created?** Console → `{prefix}notifications`, filter by
   recipient/time. Missing → the *business* trigger failed; read ITS logs
   (e.g. `paymentCreated_development`).
2. **`notificationCreated_<env>` logs** — `scripts/fn-logs.sh notificationCreated development`.
   Look for "failed to get devices" or FCM batch errors.
3. **Device tokens present?** Console → `{prefix}users/{id}/devices` — docs must
   have a non-empty string `token`. No docs → the app never registered the token
   (Flutter `NotificationService` owns token management).
4. **Device side** — notification permissions, token staleness, app foreground
   handling.

**Pipeline B (chat):** `messageWritten`
(`functions/loans/triggers/message_written.go`) pushes DIRECTLY via `sendChatPush`
— no notifications doc is ever created, so step 1 above will "fail" by design for
chat. Check `messageWritten_<env>` logs instead. Two silent-failure traps verified
in `sendChatPush`: per-recipient device-fetch errors are skipped (`continue`), and
zero tokens returns `nil` (success) — so an empty `devices` subcollection produces
no error anywhere.

## Row 11 — RTDB report totals wrong

Reports live in RTDB at `{dev|stg}/companies/{companyId}/report_summary/...` (prod:
no env node), written solely by `functions/loans/triggers/loan_changes.go`. Known
defects, all verified present on 2026-07-07:

- `applyToNodeValue` is a non-transactional Get→Set read-modify-write; concurrent
  loan writes race and lose increments.
- `dataErrors = applyToNodeValue(...)` reassigns on every call — only the last
  error survives; earlier failures are silently dropped.
- Format typos `%$w` (two occurrences, "cannot get loan schedules" messages) print
  literally instead of wrapping the error.
- `completed` branch adds then subtracts `additional_charges` (copy-paste), netting
  zero; branch is explicitly incomplete (`TODO(deibeeed) complete this for report`,
  ~line 171).
- The `bad_debt`/`completed` branches build the Firestore collection as
  `pathEnv+"_loan_schedules"` — `dev_loan_schedules`/`stg_loan_schedules` are
  correct, but in prod `pathEnv` is empty so the query targets `_loan_schedules`
  (leading underscore, wrong collection). Observed in source; not separately
  confirmed against prod behavior.
- `go vet` reports pre-existing lock-copy warnings (passing `db.Client` by value).

**Consequence for triage:** wrong totals are EXPECTED with this code under
concurrency and for completed/bad-debt loans. Do not hand-patch RTDB values (prod
data is hands-off — `finstack-change-control`), and do not spot-fix the trigger:
the rebuild is the campaign in `finstack-loan-engine-and-reporting-campaign`,
which owns the recompute-by-hand and race-proof recipes.

## Row 12 — Stale `origin/*` refs

`gh` queries GitHub live; `git rev-parse origin/develop` reads the local ref from
the last fetch. Real incident: on 2026-07-04 local `origin/develop` predated the
PR finstack#83 merge (2026-07-03), making merged chat-backend work look unmerged.

```bash
git ls-remote origin develop          # live remote SHA (read-only)
git rev-parse origin/develop          # local snapshot
git fetch origin                      # reconcile
gh pr view 84 -R anatechopc/finstack  # PR state is always live via gh
```

Rule of thumb: for "is X merged/deployed?" questions, trust `gh` and CI run
history, never local refs.

## Row 13 — Pre-existing package test failures

`packages/core/address_repository` and `packages/core/bank_details_repository`
ship VGV scaffold tests that construct Firestore-backed repositories without
`Firebase.initializeApp()`. Documented as pre-existing on `develop` in
`apps/loans/MEMORY.md` (Flutter 3.44 section, "2 package tests fail"). Before
blaming your change:

```bash
git stash && cd packages/core/address_repository && fvm flutter test; cd - && git stash pop
```

Same failure without your change → baseline. The proper fix (test seams / fakes)
belongs to `finstack-testing-and-validation`.

## Row 14 — `Runtime environment not defined`

Two entry points fatal with `log.Fatal("Runtime environment not defined")` when
`ENVIRONMENT` is unset — the container never serves:

- `functions/loans/loooans_cloud_functions.go:63` (`start()`) — the **deployed**
  entry point. Note its package is `loooans_cloud_functions`, not `main` (the
  GCF Go buildpack supplies the main); you cannot `go run .` it.
- `functions/loans/cmd/main.go:47` — a local runner. **WARNING: stale subset** —
  it registers only `requestOtp`, `sendEmail`, `sometest` and 5 old triggers
  (userCreated, loanChanges, loanScheduleChanges, capitalCreated,
  notificationCreated). Do not treat its behavior as representative of the
  deployed 17.

Valid values: `development`, `staging`, `production` — full words (they drive
`GetCollectionPrefix`, RTDB paths, subdomains —
`functions/loans/utils/environment_utils.go`).

Deployed: every entry in `.github/scripts/deploy_functions.sh` passes
`--set-env-vars ENVIRONMENT=$environment` (or the MS-Graph superset that
includes it) — a manually deployed function without it dies exactly this way.
See `finstack-run-deploy-operate`.

Local run (only if you accept the stale-subset caveat):

```bash
cd functions/loans
ENVIRONMENT=development go run ./cmd    # funcframework server on :8080
```
