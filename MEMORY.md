# MEMORY.md

Generalized memory for the finstack monorepo. Tracks cross-project work, CI/CD changes, and high-level decisions.

For project-specific memory, see:
- **Flutter App**: `apps/loans/MEMORY.md`
- **Go Functions**: `functions/loans/MEMORY.md`

---

## Monorepo Setup

- Restructured from separate repos (`loooans-flutter`, `loooans_cloud_functions`) into the `finstack` monorepo
- Apps live in `apps/`, functions in `functions/`, shared packages in `packages/`

## CI/CD Work

- Added `build_runner` code generation step to app workflows
- Ran code generation concurrently across packages, tuned to 4 concurrent processes
- Cached `build_runner` generated code between runs (per-package caching)
- Increased `build_runner` parallelism and switched to `dart run`
- Enabled parallel deployment of Cloud Functions
- Added `workflow_dispatch` to all workflows for manual testing

## Session: 2026-02-16

- Fixed issue #4 (wrong principal balance for consecutive additional loans) — PR #33
- Three root causes: stale UI after additional loan, double-counted OB in Firestore schedule, wrong sort order of additionalLoanAmounts
- Discussed loooans#66/#68 (borrower remote verification / OTP) — blocked on finding free SMS provider. See `apps/loans/MEMORY.md` for full notes.

## Session: 2026-02-18

- Implemented Borrower Acknowledgement via SMS OTP (Issue #66) — full stack across Go backend, Flutter app, and new Android gateway app
- SMS delivery uses a dedicated Android device as SMS gateway (avoids telco registration), Firebase RTDB as message queue
- **Go backend:** Modified `requestOtp` to key by hash (not userId), added `target_user_id`/`reason` fields, replaced TransmitSMS with RTDB queue. Created `verifyPaymentOtp` endpoint.
- **Flutter app:** Extended PaymentBloc with OTP events/states, created PaymentOtpDialog, wired up "thru Mobile OTP" button. Updated AuthenticationBloc to use token instead of userId for OTP lookup.
- **Android gateway:** New Kotlin app at `apps/sms-gateway/` — foreground service listens to RTDB, sends SMS via SmsManager, updates status
- **RTDB rules:** Updated to allow gateway user read/write on `/otp/` and `/gateway_status/`
- **Deploy script:** Added `requestOtp` and `verifyPaymentOtp` to parallel deploy (8→10 functions)

## Cross-Project Decisions

- Notification creation is server-side only (Go triggers), not in the Flutter app
- Firestore collection paths use environment-based prefixes (`dev_`, `stg_`, none for prod)
- Dev and staging share Firebase project `loooans-dev-stg`; production uses `loooans-prod`

---

## Mobile Number Verification (issue #13)

- Login gate now blocks entry when `verificationStatus & 2 == 0` and routes to a dedicated `MobileVerificationScreen` at `Paths.mobileVerification`.
- Backend `verifyPaymentOtp` was generalized into `verifyOtp` with reason-driven post-actions; `reason` is read from the RTDB OTP entry, never the request body (security invariant).
- New `userChanges` Firestore trigger clears verification fields when `mobile_number` changes — see `functions/loans/triggers/user_changes.go`.
- 90-day lock enforced via Firestore security rules (now source-controlled at `apps/loans/firestore.rules` — manual export from console required before next deploy). Client UX mirrors the lock by disabling the field with "Editable in N days" helper text.
- Established the Go adapter+core test pattern on the touched handlers (`verifyOtpCore`, `handleUserChangedCore`); future Go PRs adopt the same pattern incrementally. New module `com.loooans.app/test/fakes` provides reusable fakes.
- Local Go test workaround on macOS 26.x: `CGO_ENABLED=0 go test ./...` to bypass a `dyld: missing LC_UUID` issue. CI on Linux unaffected.
- Follow-ups: #130 (email OTP migration), #131 (trusted device), #132 (rate limits / wrong-OTP cap), #133 (self-service mobile change during lock), #134 (Flutter bloc/widget test infrastructure + rules emulator tests).

---

## Date/Timestamp Convention (must follow when touching date fields)

- **Store dates as int64 milliseconds since epoch everywhere.** Both Firestore documents and Realtime Database entries use this single representation across the codebase.
- **Flutter side**: `loooans_helpers/data_helpers/constants.dart` exposes `handleDateTimeToJson` / `handleDateTimeFromJson` / `handleDateTimeNullableFromJson`. Entities use these via `@JsonKey(toJson: ..., fromJson: ...)`. `handleDateTimeToJson(DateTime?)` returns `millisecondsSinceEpoch` (a `num`). After PR #47, the `fromJson` variants also tolerate Firestore `Timestamp` values as a defensive measure for any rogue producer — but new code MUST still write millis.
- **Go side**: NEVER write a Go `time.Time` directly into a Firestore document or RTDB entry — the Firebase Admin SDK serialises `time.Time` as a Firestore **Timestamp** protocol object (not millis), which breaks Flutter's `num`-shaped deserialization. Always convert with `.UnixMilli()` before writing. Pattern from `request_otp.go`:
  ```go
  otpData := map[string]any{
      "created_at": time.Now().UnixMilli(),
      "updated_at": time.Now().UnixMilli(),
      "expire_at":  expireAt, // already int64 millis
  }
  ```
- **Why this matters**: PR #47 + PR #48 chased a `TypeError: Instance of 'Timestamp' is not a subtype of type 'num'` login failure caused by `verify_otp.go` writing `time.Time` for `updated_at` and `mobile_verified_at`. Existing user docs got contaminated and couldn't be read by the Flutter client until the helpers were made permissive. Avoid the round trip by writing millis from the start.

---

## Flutter 3.38.4 → 3.44.0 upgrade (issue #46, 2026-05-25)

Full details in `apps/loans/MEMORY.md`. Cross-project notes:

- **CI**: no workflow edits needed — `loans-app-{development,staging,production}.yml` already extract the Flutter version from `apps/loans/.fvmrc`.
- **Pre-existing latent bug fixed**: `apps/loans/scripts/bump_version.sh` used millis as the Android `versionCode`, overflowing `Integer.MAX_VALUE`. Old AGP truncated silently; new toolchain rejects. Now uses seconds (`date +%s`) — valid until ~2038.
- **Toolchain floor raised on Android**: AGP 8.11.1, Kotlin 2.2.20, Gradle 8.14.3, compileSdk/targetSdk 36, Java 17. Required by plugin dependencies Flutter 3.44 brings.
- **iOS Podfile.lock will need a refresh on a Mac** (plugin versions changed) — not verified locally because no CocoaPods on dev box.
- The `org.gradle.jvmargs=-Xmx2048M` rule (from "Build / Test gotchas") needed to go higher: **4096M** at this toolchain. Update the rule accordingly when next touched.

---

## OTP SMS non-delivery — independent review + fixes (2026-08-12, PRs #89/#90/#91)

Three PRs (backend #89, sms-gateway #90, Flutter #91) fixing OTP SMS non-delivery were declared "ready to merge, zero Critical/Important" by an in-run subagent review. An **independent multi-agent `/code-review` at xhigh later found 41 issues, including one that inverted an entire PR.** All blocking findings are fixed; the PRs are green and mergeable but **not yet merged**.

### Process lesson (the important part)

The in-run reviewers only ever read the diff and the implementer's own report — they never executed the code or consulted platform/SDK source, so they validated the work against the same assumptions that produced it. Do **not** treat an in-run review as a merge gate. Before calling a PR mergeable:

1. Run a review that was **not** part of the implementation loop.
2. **Execute** the code on real inputs rather than reasoning from the diff. (Two #89 bugs were only provable by running `NormalizePhoneE164`; #90's fatal bug was only provable from the android-35 `IntentFilter` source.)
3. Check which workflow **actually runs** the tests instead of trusting a green check — see the CI section below.
4. Design manual tests that distinguish "works" from "fails the same way as the bug". The planned airplane-mode gateway test expected `failed`, and the bug made *everything* `failed`, so it would have passed.
5. Beware that **one review round's own fix can be the next round's bug**: pinning `phonenumbers` to v1.1.8 (to hold the `go 1.22` directive) was itself the source of a client-triggerable panic.

### CI: `flutter test` never ran

**No workflow ran `flutter test` at all.** Green checks only ever proved the web build compiled. `loans-app-development.yml` now runs package tests and app tests before the build, gating the PR.

- The test step **must stay after the `Generate code` step**: `*.g.dart` is gitignored repo-wide and generated per build, so testing first asserts against stale or absent generated code.
- That trap produced a wrong diagnosis mid-session: `review_repository` appeared to have "JSON round-trip bugs" when the local `*.g.dart` was simply stale (generated 16 Jun; the model gained four `response*` fields 19 Jun). After regeneration it passes 9/9. **When a package test fails locally, regenerate before believing it.**
- `address_repository` and `bank_details_repository` each held one Very Good CLI scaffold test — `expect(SomeRepository(), isNotNull)` — which asserts nothing and can never pass, because constructing the repository builds `FirebaseFirestore.instance` and throws `[core/no-app]`. Both deleted; those packages now have no `test/` dir. The gate is unconditional — **keep it that way.**

### SMS gateway (`apps/sms-gateway`, PR #90) — has no MEMORY.md of its own

- **Fatal bug**: the sent-intents carried `setData("loooans-sms://<hash>/<i>")` to make each PendingIntent unique, but the receiver's `IntentFilter(ACTION_SMS_SENT)` declares no data scheme. Per `IntentFilter.matchData` (android-35 source, line 1739), a filter with null types **and** null schemes returns `NO_MATCH_DATA` for any intent carrying data. **The receiver could never fire**, so `markSent` was unreachable and every *delivered* OTP was written `failed: "timeout waiting for send result"`. PendingIntent uniqueness now lives in the `requestCode` (`sendRequestCode(sendId, partIndex)`); **never reintroduce `setData` on these intents.**
- A per-attempt **send id** in the extras lets a late result from a timed-out attempt be recognised and ignored instead of credited to its successor.
- Expired entries now write a terminal `failed` status instead of returning silently — returning silently left them `pending` forever and poisoned the "are OTP SMS stuck at pending?" health check.
- `onDestroy` gives in-flight sends a terminal status before cancelling `serviceScope`.
- **Pre-existing bug fixed**: the `gateway_status` "offline" write was launched into `serviceScope` and cancelled by `serviceScope.cancel()` on the very next line, so devices never went offline — the likely cause of the stale Pixel 10 / PJE110 entries.

### Resume state (as of 2026-08-12)

All three PRs are **pushed, mergeable, CI-green, and unmerged**. Merging auto-deploys, so it is a deliberate call.

- **#89** `feature/otp-phone-normalization` — merge **first** (backend-first).
- **#90** `feature/sms-gateway-delivery-status` — needs a manual APK build + `adb install` on the gateway phone (SM-S908E) after merge. **Re-test must include the happy path**: confirm a real send writes `sms_status: "sent"` with a non-null `sent_at`, *then* do the airplane-mode run and confirm `RESULT_ERROR_RADIO_OFF (2)` rather than `timeout waiting for send result`.
- **#91** `feature/otp-error-surfacing` — also carries the CI test gate.

Deliberately **not** fixed, needing a decision rather than a patch:
- The payment-acknowledgement OTP path still inherits the borrower address/country precondition — a product call about whether payments should be gated on address completeness.
- The backend-first gap: #89's new 400s reach production before an app release can display them.
- `phonenumbers` adds a global-metadata load to every function's cold start in the shared binary (measure before restructuring).
- `review_repository`'s tests pass, but its `response*` fields depend on codegen freshness — worth confirming the feature works end to end.

**Withdrawn finding** (recorded so nobody re-chases it): "12 live PH prefixes rejected as invalid" was wrong. v1.8.1 rejects `0900-0904, 0913, 0940, 0941, 0980, 0982, 0984, 0990` identically, so it is not stale metadata and there is no evidence those prefixes are allocated.

---

## GCF retired `go122` — the backend deploy pipeline was broken (2026-08-14)

**PR #89 is merged (`4a598a7`) but did not deploy.** Google removed `go122` from
Cloud Functions 2nd gen, so `gcloud functions deploy` now rejects every function:

```
ERROR: (gcloud.functions.deploy) Invalid value for [--runtime]:
go122 is not a supported runtime on GCF 2nd gen
Failed functions: userChanges messageWritten verifyOtp requestOtp
loanScheduleChanges paymentCreated reviewUpdated reviewCreated
notificationCreated capitalCreated paymentUpdated sendPasswordSetupLink
setPassword sendEmail addUser loanChanges userCreated
```

The **last successful functions deploy was 2026-07-09.** The dev backend sat
frozen at that build for five weeks without anyone noticing, because *the Build
and Test job stayed green the whole time* — only the deploy step failed, and
nothing merged in between. It surfaced when the docs-only merge of PR #92
(2026-08-13) happened to trigger a deploy.

**Watch the deploy job, not just the PR check.** A merged PR with a green check
is not a shipped change; on this repo the deploy runs *after* the merge, on
`develop`, and its failure is invisible from the PR.

Staging and production run the same `deploy_functions.sh`, so the first
`release/*` or `master` deploy would have failed identically.

Fix and verification details (flag spellings, `GOTOOLCHAIN` recipe, runtime
availability): `functions/loans/MEMORY.md`. Summary: 17 `--runtime` flags moved
to `go126`; the three `loans-functions-*.yml` workflows moved from
`go-version: '1.22'` to `'1.26'` so CI compiles on the toolchain that builds the
deploy; `go.mod` left at `go 1.22.12` deliberately.

### OTP PR resume state (supersedes the 2026-08-12 table above)

- **#89 `feature/otp-phone-normalization` — MERGED 2026-08-14** (`4a598a7`),
  **not yet live**; it deploys on the first successful run after the runtime fix.
- **#90 `feature/sms-gateway-delivery-status`** — open, mergeable, unaffected by
  the runtime problem (Android APK, separate pipeline). Still needs the manual
  APK build + `adb install` on the gateway phone, happy path asserted first.
- **#91 `feature/otp-error-surfacing`** — open, mergeable. Surfaces the 400s that
  #89 produces, so it is only meaningful once #89 is actually deployed.

---

## Flutter pin moved 3.44.0 → 3.44.9, and the drift that hid it (2026-08-20)

`apps/loans/.fvmrc` pinned **3.44.0, which was not installed on the dev machine**,
while the fvm **global default was 3.44.9**. fvm resolves per-directory, so:

- `packages/**` (no `.fvmrc`, uses the global default) worked normally.
- **Every `fvm flutter` command in `apps/loans` silently blocked forever** on an
  interactive prompt — `? Would you like to install it now? (y/n)` — with no TTY
  to answer it. One `flutter test` sat 85 minutes before anyone checked `etime`.

The prompt is invisible if you pipe the command into `tail`/`head`, which buffers
until exit. **Redirect to a file and tail the file** when a build command seems
slow; you see partial output immediately.

**All three `loans-app-*.yml` workflows read the version out of `.fvmrc`**
(`get_flutter_version` → `flutter-version:`), so `.fvmrc` IS the CI pin — editing
it changes every build. There is no hardcoded Flutter version in the workflows.

Verified on 3.44.9 before merging: `flutter --version` resolves, `pub get` exits 0,
**87/87 app tests pass in 10s**.

Second trap hit on the way: 26 test files failed to load with
`Error when reading '..._entity.g.dart': No such file or directory`. That is the
gitignored-codegen trap, not a toolchain fault — `packages/build_models.sh`
regenerates all 21 packages (CI does this in its "Generate code" step). A fresh
clone cannot run `apps/loans` tests until it runs.

---

## 2026-08-25 — Search: spec, plans, and the backend half (finstack#56)

Brainstormed → spec → two plans → executed the backend. Branch
`worktree-search-design-spec`, 15 commits, merge-ready. Backend and frontend are
deliberately **separate PRs, backend first**, per the standing preference.

- Spec: `docs/superpowers/specs/2026-08-24-search-design.md` (binding)
- Plans: `docs/superpowers/plans/2026-08-24-search-{backend,frontend}.md`
- Backend detail and traps: `functions/loans/MEMORY.md`
- **Frontend plan is NOT ready to execute** — see the defect below.

**Cross-cutting decision:** search is Firestore `array-contains` over server-written
`search_tokens`, not BigQuery. BigQuery is right for *reporting* (#98) and wrong for
high-QPS point lookups. The reusable idea is to share the **CDC pipeline**, not the query
store.

**Frontend plan defect, must be fixed before executing it:** `OfferFilters.maxInterestRate`
is a range filter, and Firestore requires the first `orderBy` to be the inequality field —
but `ProductViewFirestoreService.load()` hardcodes `orderBy('updated_at', descending)` after
applying filters. That query throws at runtime and **no index can fix it**; it needs a
dedicated query path. Tracked as **#103**.

**Process note that paid for itself.** Every task was implemented by one subagent and
reviewed by an independent one, with findings adjudicated and verified by mutation rather
than by re-reading. Reviewers/implementers caught **four** errors in my own rulings —
including one (`tag_line` is a company field, not a product field) that would have silently
dropped ~a third of every offer's search tokens. The Critical in the final review was that
the *golden-vector file itself* could not express the contract it existed to enforce: a Dart
implementation with the exact phone bug Go once had would have passed it. Independent review
+ mutation testing found things no amount of careful reading did.

### Correction (2026-08-25): Firestore indexes live in per-env files

Recorded because I got it wrong twice in one session. `apps/loans/firestore.indexes.json`
is a **scratch artifact** — `apps/loans/scripts/deploy-indexes.sh` `cp`s the chosen
environment's file over it right before deploying, so anything committed there is
discarded. The real snapshots are `firestore.indexes.{dev,stg,prod}.json`
(`dev_*` / `stg_*` / unprefixed). Fixed in `5b14006`.

**The repo's own skill library documented all of this** — `finstack-run-deploy-operate` §6
covers the file layout, the scratch-artifact trap, and the `["$ENV" == "dev"]` bracket bug.
`CLAUDE.md` says to load the relevant skill before non-trivial work and I did not. Loading
it would have prevented three wrong commits and a wrong claim to the user. **Load the skill
first — especially for anything deploy- or environment-shaped.**
