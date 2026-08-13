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
