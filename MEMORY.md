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
