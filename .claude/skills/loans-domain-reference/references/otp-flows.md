# OTP flows — step-by-step with file anchors

Companion to `../SKILL.md` §9. Verified 2026-07-07. Paths relative to repo root
`/Users/deibeeed/Projects/AnaheimTechnologies/finstack`.

Security posture of this design (OTP derivable from token; RTDB `otp` readable by any
authed user) is an OPEN finding — home: `finstack-security-hardening`. Do not "fix"
pieces of it ad hoc from this document.

## 0. Shared plumbing

| Piece | Where |
|---|---|
| OTP generation (hash + 6-digit pin derived from hash) | `functions/loans/api/service/otp_service.go` (`GenerateOtp`, `getOtp`) |
| RTDB queue entry | `otp/{hash}` — keyed by hash/token, **never userId** |
| Entry writer | `RequestOtpCore`, `functions/loans/api/users/request_otp.go:87-169` |
| Entry verifier | `VerifyOtpCore`, `functions/loans/api/users/verify_otp.go:65-127` |
| SMS sender | dedicated Android phone, `apps/sms-gateway/` foreground service |
| Gateway filter | `OtpEntry.shouldProcess()` = `objective == "mobile_number" && sms_status == "pending"` (`apps/sms-gateway/app/src/main/java/com/loooans/smsgateway/OtpEntry.kt:18`) |
| Validity | **5 minutes** (`request_otp.go:32`) |
| Flutter HTTP client | `packages/core/user_repository/lib/src/data/network/user_network_service.dart:75-152` (`requestOtp`, `requestOtpForUser`, `verifyOtp`) |

RTDB entry shape written by `RequestOtpCore` (`request_otp.go:114-145`):

```json
{
  "id": "<hash>", "userId": "<target uid>", "otp": "123456",
  "expire_at": 1751871234567, "created_at": ..., "updated_at": ...,
  "objective": "mobile_number" | "email",
  "reason": "mobile_verification" | "email_verification" | "payment",
  "requested_by": "<caller uid>",
  // mobile_number objective only:
  "phone": "+63...", "message": "NEVER SHARE YOUR ONE-TIME PIN...",
  "sms_status": "pending", "sent_at": null, "error": null
}
```

The gateway flips `sms_status` to `"sent"`/`"failed"` after sending. Timestamps are
int64 millis (house convention).

### The two invariants (do not weaken)

1. **`reason` is read from the RTDB entry, never the request body**
   (`verify_otp.go:60-64, 92`). A caller holding a payment OTP cannot turn it into a
   profile mutation by lying in the verify request.
2. `objective` defaults `reason`: `email → email_verification`,
   `mobile_number → mobile_verification`; callers may override reason (that is how
   `payment` rides the `mobile_number` objective) — `request_otp.go:97-104`.

`VerifyOtpCore` outcomes: `ErrOtpNotFound` / `ErrOtpExpired` / `ErrOtpInvalid` → 400s;
success deletes the entry (best-effort, `:87-90`) then runs the reason-driven
post-action.

## 1. Flow (a): first-login mobile verification

Trigger: the GoRouter redirect gate (`apps/loans/lib/app/routing/router.dart:82-92`)
sends any authed user to `Paths.verify` unless BOTH:

- `FirebaseAuth.instance.currentUser.emailVerified` (Firebase Auth owns email), and
- `(user.verificationStatus & UserVerificationStatus.mobileNumberVerified.value) != 0`
  — bitmask, `mobileNumberVerified = 2`
  (`packages/core/user_repository/lib/src/model/user_verification_status.dart`).

Sequence:

1. Verify screen → `AuthenticationBloc.requestOtp(purpose: 'mobile_number')`
   (`apps/loans/lib/features/authentication/bloc/authentication_bloc.dart:90-91, 210-223`).
2. HTTP `requestOtp` (JWT-authed) → `RequestOtpCore` reads the user's `mobile_number`
   from Firestore (400 if missing, `request_otp.go:127-138`), writes the RTDB entry
   with `sms_status: pending`, returns `{token, expire_at, redirect_url}`.
3. Gateway phone sends the SMS; user types the 6-digit code into
   `MobileVerificationScreen`.
4. `verifyOtp(token, otp)` → `VerifyOtpCore`, reason `mobile_verification` →
   in a Firestore transaction: `verificationStatus |= 2`, `mobile_verified_at` and
   `updated_at` written as **UnixMilli** (`verify_otp.go:96-106, 246-269` — the
   Timestamp-contamination lesson, see `finstack-failure-archaeology`).
5. Router gate now passes; user proceeds.

Email verification has a parallel OTP path (`objective: 'email'` — OTP emailed via
MS Graph, reason `email_verification` flips Firebase Auth `EmailVerified` via Admin
SDK sentinel `firebase_email_verified`, `verify_otp.go:107-121, 227-235`).

### The 90-day change lock

- Client: `computeMobileLock` (`apps/loans/lib/utils/mobile_lock.dart:13-22`) —
  locked while `now − mobileVerifiedAt < 90 days`; profile UI disables the field and
  shows days remaining.
- Authoritative enforcement: **console-managed Firestore rules** (not in repo —
  `apps/loans/firestore.rules` is a stale placeholder). Spec with the intended rule:
  `docs/superpowers/specs/2026-04-19-mobile-verification-design.md:111-118`.
  Status/verification → `finstack-security-hardening`.
- Changing `mobile_number` (when a previous number existed) clears bit 2 and
  `mobile_verified_at` via the Go `userChanges` trigger
  (`functions/loans/triggers/user_changes.go:52-66`), forcing re-verification.
  First-time set does NOT clear (`:57-60`).

## 2. Flow (b): payment acknowledgement (teller-side)

Purpose: let a borrower authorize a teller-recorded payment without photo+signature
proof. UI lives in the teller's payment dialog; bloc =
`apps/loans/lib/features/loans/bloc/payment_bloc.dart`.

1. Teller taps "Request OTP" → `RequestPaymentOtpEvent` →
   `userRepository.requestOtpForUser(targetUserId: borrowerId)` which posts
   `{purpose: 'mobile_number', target_user_id: borrower, reason: 'payment'}`
   (`user_network_service.dart:99-125`). The SMS goes to the **borrower's** phone;
   `requested_by` records the teller.
2. Bloc emits `otpRequested(token, expireAt)` (`payment_bloc.dart:289-311`); UI shows
   the OTP input + countdown.
3. Borrower reads the code to the teller → `VerifyPaymentOtpEvent` →
   `userRepository.verifyOtp(token, otp)` (`payment_bloc.dart:313-336`).
   Server-side, reason `payment` runs **no post-action** (`verify_otp.go:94-95`) —
   the consent is consumed client-side.
4. On `otpVerified` state, the teller records the payment with `otpVerified: true` →
   `Payment.create(bypassPaymentProof: force || otpVerified)`
   (`payment_bloc.dart:161`) plus an audit `comment` naming borrower, teller,
   timestamp, and "verification_method: SMS OTP" (`:105-114`).
   `bypassPaymentProof: false` on this path was the silently-swallowed-payment bug —
   PR finstack#38 (`finstack-failure-archaeology`).

Still-wanted follow-up (refile on finstack; old loooans-era note): extend OTP
acknowledgement to the **additional-loan** flow.

## 3. Debugging quick checks

Symptom-first triage lives in `finstack-debugging-playbook`; these are the
domain-level sanity checks:

- OTP never arrives → is the entry in RTDB `otp/` with `sms_status: pending`? Is the
  gateway phone heartbeating at `gateway_status/{deviceId}` (30s interval)?
  Gateway ops → `finstack-run-deploy-operate`.
- "OTP expired" instantly → check `expire_at` is millis and device clocks; validity
  is 5 min from request.
- Verified but router still blocks → the gate needs BOTH email and mobile bits;
  check `verificationStatus` (camelCase field, no snake_case rename) and Firebase
  Auth `emailVerified` after a user reload.
- Mobile bit mysteriously cleared → borrower (or admin) changed `mobile_number`;
  that is the `userChanges` trigger working as designed.
