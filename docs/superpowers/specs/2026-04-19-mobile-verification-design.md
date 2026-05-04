# Mobile Number Verification — Design

- **Issue**: [#13](https://github.com/anatechopc/loooans/issues/13) — Verify user mobile number
- **Date**: 2026-04-19
- **Follow-ups tracked in**: [#130](https://github.com/anatechopc/loooans/issues/130), [#131](https://github.com/anatechopc/loooans/issues/131), [#132](https://github.com/anatechopc/loooans/issues/132), [#133](https://github.com/anatechopc/loooans/issues/133)

## Goal

Require users to verify their mobile number via SMS OTP before they can access the app. Verification status is enforced at login, exposed in the profile, and re-triggered when the mobile number changes. After a successful verification, the mobile number is locked for 90 days to reduce number-hopping abuse.

## Scope

**In scope**
- Login-time gate that blocks entry when the mobile number is unverified.
- Dedicated verification screen (reused by login gate and profile re-verify).
- Editable mobile number on the verify screen while unverified.
- "Verify" button + "Verified" badge in the profile.
- 90-day lock on mobile number changes after successful verification.
- Generalize the existing `verifyPaymentOtp` backend endpoint into a single `verifyOtp` with reason-driven post-actions (removing the old endpoint outright).
- Firestore security rules enforcing the 90-day lock and preventing client writes to verification fields.
- Documentation updates (security rules doc, project README).

**Out of scope** (tracked separately)
- Email verification changes — see #130.
- Trusted device / device binding — see #131.
- SMS rate limits beyond the 4-minute cooldown; wrong-OTP attempt cap — see #132.
- Self-service mobile-number change during the 90-day lock — see #133.

## Key decisions

| Decision | Choice | Reason |
|---|---|---|
| Login gate | Hard block | Verification is a real identity gate; soft banners get ignored. |
| Verify UI | Dedicated screen (route), not dialog | Reused by gate and profile; deep-linkable; less cramped than a dialog. |
| Edit mobile on gate | Allowed (user is unverified) | Escape hatch for wrong numbers without needing support. |
| 90-day lock enforcement | Client UX + Firestore security rules | Client disables the field; rules are authoritative against direct SDK access. |
| OTP expiry | 5 minutes (unchanged) | Existing backend behavior. |
| Resend cooldown | 4 minutes | Throttles SMS cost while still leaving a 1-minute window before expiry. |
| Resend cap | None | MVP — monitor and revisit (see #132). |
| Wrong-OTP cap | None (rely on 5-min expiry) | MVP — see #132. |
| Backend structure | Single `VerifyOtp` handler, switch on `reason` read from RTDB | One source of truth; RTDB-sourced `reason` prevents client switching attacks. |
| Old `verifyPaymentOtp` endpoint | Removed outright | App isn't in prod at scale; coordinate single atomic deploy. |
| Profile re-verify after edit | Auto-route to verify screen on successful save | User just made an identity-relevant change; immediate verify matches intent. |

## Architecture

### Data model

**`packages/core/user_repository/lib/src/model/user_entity.dart`** — add a new field:

```dart
@JsonKey(
  name: 'mobile_verified_at',
  toJson: handleDateTimeToJson,
  fromJson: handleDateTimeNullableFromJson,
)
DateTime? mobileVerifiedAt;
```

Surface on `User` model (+ `toEntity`/`fromEntity`/`update`), regen via `../../packages/build_models.sh`. Field is nullable — legacy users with the `mobileNumberVerified` bit set but no timestamp are treated as "verified, no lock".

### Backend (Go) — `functions/loans/`

**Adapter + core pattern** — to make the new code unit-testable without Firebase emulators, every handler/trigger we add or rename in this feature splits into two layers:

- **Adapter**: thin wrapper that owns HTTP/CloudEvent wiring, parses inputs, instantiates real Firebase clients, and calls the core. Untested by automation.
- **Core**: pure function that takes a `deps` struct of collaborator function fields (e.g., `readOtp`, `deleteOtp`, `updateUser`). Holds all branching logic. Tested with in-memory fakes.

This pattern is established here for the touched files only — no backfill of existing untested code. Future PRs adopt the same pattern as they go.

**`api/users/verify_otp.go`** (rename from `verify_payment_otp.go`):
- Adapter `VerifyOtp(w, r)` parses `token` + `otp`, wires real RTDB + Firestore clients into `verifyOtpDeps`, calls `verifyOtpCore`, encodes response.
- Core `verifyOtpCore(ctx, token, receivedOtp, deps) (verified bool, err error)`:
  - Reads OTP entry via `deps.readOtp(token)`, pulls `reason` from the stored entry (never from the request body).
  - Checks expiry, runs `service.VerifyOtp`, on success calls `deps.deleteOtp(token)` and dispatches via `switch reason`:
    - `case "mobile_verification"`: `deps.updateUser(uid, {verificationStatus: |= 2, mobile_verified_at: now})`.
    - `case "payment"`: no-op (current behavior, preserves the existing payment-acknowledgement flow).
    - Unknown reason: log + return verified=true without side effects.

**`loooans_cloud_functions.go`**:
- Remove `functions.HTTP("verifyPaymentOtp", users.VerifyPaymentOtp)`.
- Add `functions.HTTP("verifyOtp", users.VerifyOtp)`.

**`triggers/user_mobile_number_changed.go`** (new):
- Adapter unmarshals the Firestore CloudEvent, wires real Firestore client, calls core.
- Core `handleUserMobileChanged(ctx, before, after, deps) error`:
  - If `before.mobile_number == after.mobile_number`: no-op.
  - Else: `deps.updateUser(uid, {verificationStatus: &= ~2, mobile_verified_at: nil})`.
- Register in `loooans_cloud_functions.go` as a CloudEvent handler on the users collection.

**`service/otp_service.go`**: no changes.

**`api/users/request_otp.go`**: no changes. Already writes `reason` into the RTDB entry.

**`test/fakes/`** (new): in-memory fakes implementing the collaborator function signatures used by `verifyOtpDeps` and the trigger's deps. Reusable by future tests.

**Stub cleanup**: delete `test/api/users/add_user_test.go` (logs only, unrelated to this feature, dead).

### Hosting routing — `apps/loans/firebase.json`

For all three target blocks (`develop`, `staging`, `production`):
- Remove the rewrite mapping `/api/users/verify/payment-otp` → `verifypaymentotp-{env-suffix}`.
- Add a rewrite mapping `/api/users/verify/otp` → `verifyotp-{env-suffix}` (suffixes `-development`, `-staging`, `-production` preserving existing CI/CD naming convention).

### Firestore security rules

Current rules file needs update (confirm `firestore.rules` path during implementation — also referenced by `firestore.indexes.json` in `apps/loans/firebase.json`).

Add two rules for the users collection:

1. **Mobile-number change lock**: reject updates that modify `mobile_number` when the old `mobile_verified_at` is within 90 days.

   ```
   // pseudo-code
   allow update: if (
     request.resource.data.mobile_number == resource.data.mobile_number ||
     resource.data.mobile_verified_at == null ||
     duration.value(request.time - resource.data.mobile_verified_at.toMillis(), 'd') >= 90
   );
   ```

2. **Backend-only fields**: reject client writes that modify `verificationStatus` or `mobile_verified_at`. Admin SDK writes (from `VerifyOtp` and the user-update trigger) bypass rules.

   ```
   allow update: if (
     request.resource.data.verificationStatus == resource.data.verificationStatus &&
     request.resource.data.mobile_verified_at == resource.data.mobile_verified_at
   );
   ```

Both rules compose with existing user-update rules.

### Flutter — `apps/loans/`

**New route + screen**

- `lib/app/routing/paths.dart`: add `mobileVerification`.
- `lib/app/routing/router.dart`: register the route.
- New file: `lib/features/authentication/screen/mobile_verification_screen.dart`.
  - Reused by login gate **and** post-profile-edit re-verify.
  - UI: editable mobile number, OTP input, "Send OTP" / "Resend in X:XX" button (4-min cooldown timer), "Verify" button, "Log out" action.
  - Dispatches `RequestOtpEvent` on mount; dispatches it again on "Resend" (after cooldown elapses) and on mobile-number edit save.

**`AuthenticationBloc`** — `lib/features/authentication/bloc/authentication_bloc.dart`:
- `_checkUserVerificationStatus()`: actually check `(user.verificationStatus & mobileNumberVerified.value) == 0`. If unset, emit `AuthenticationState.verify(verifyStatus: mobileNumberVerified)`. Else, emit success.
- `_handleVerifyOtpEvent`: swap client-side RTDB compare for `UserNetworkService.verifyOtp(token, otp)` backend call. On success, refresh `authService.user` from the updated Firestore doc (the backend has already set the bit and timestamp).
- `_handleRequestOtpEvent`: add tracking state for cooldown (`canResendAt` timestamp) so the screen can render the countdown. Existing event + state schema extended, not replaced.

**`LoginScreen`** — `lib/features/authentication/screen/login_screen.dart`:
- Remove the dormant `aiVerified` and `mobileNumberVerified` dialog branches. Replace with a single listener: on `AuthenticationStateStatus.verify`, `GoRouter.go(Paths.mobileVerification)`.
- Remove the `requestOtp` status dialog (the verify screen owns that UI now).

**Profile & update-profile**

- `lib/features/users/widget/profile_widget.dart`: show "✓ Verified" badge next to mobile when bit set; show "Verify" button when unset (routes to `Paths.mobileVerification`).
- `lib/features/users/widget/update_profile/update_profile_primary_details.dart` and `update_profile_portrait_personal_fields.dart`: disable the `mobile_number` field when verified AND `now - mobileVerifiedAt < 90d`. Show helper text "Editable in N days" with days remaining.
- After a successful profile save where `mobile_number` changed: navigate to `Paths.mobileVerification`. The bloc dispatches `RequestOtpEvent` on mount.

**Network service** — `packages/core/user_repository/lib/src/data/network/user_network_service.dart`:
- Rename `verifyPaymentOtp` → `verifyOtp`, POST target `/api/users/verify/otp`. Callers:
  - `_handleVerifyOtpEvent` in `AuthenticationBloc` (mobile flow).
  - Payment flows in `features/loans/bloc/payment_bloc.dart`, `features/payment_center/bloc/payment_center_bloc.dart`, `features/users/widget/client_detail/payment_otp_dialog.dart`.

**Dead code cleanup**

- Delete `packages/core/user_repository/lib/src/data/database/user_otp_realtime_database_service.dart` and `UserRepository.getTokenDetails` — client-side RTDB compare is obsolete once the backend `VerifyOtp` is wired.

## Data flow

### Login gate (happy path)

1. User logs in → `_handleLoginEvent` loads session.
2. `_checkUserVerificationStatus()` sees the `mobileNumberVerified` bit unset → emits `verify` state.
3. `LoginScreen` listener routes to `Paths.mobileVerification`.
4. `MobileVerificationScreen` mounts → auto-dispatches `RequestOtpEvent` (`purpose=mobile_number`, `reason=mobile_verification`).
5. Backend `RequestOtp` writes an OTP entry to RTDB with `reason=mobile_verification`, `sms_status=pending`, `phone=userDoc.mobile_number`, `message` text.
6. SMS gateway device picks up the RTDB entry, sends the SMS, updates status.
7. User enters OTP → `VerifyOtpEvent` → `UserNetworkService.verifyOtp` → backend `VerifyOtp` verifies, deletes the entry, updates the user doc.
8. Bloc refreshes `authService.user` from Firestore → emits success → router goes to home/dashboard.

### Profile re-verify after mobile change (happy path)

1. User opens profile, 90-day lock has expired (`mobileVerifiedAt` is null or > 90d old).
2. User edits mobile, submits → Firestore write succeeds (security rule permits).
3. Firestore user-update trigger fires on the write → detects `mobile_number` changed → clears `verificationStatus & ~2`, sets `mobile_verified_at = null`.
4. Bloc detects the change → routes to `Paths.mobileVerification`.
5. Screen auto-dispatches `RequestOtpEvent` → same pipeline as login gate from step 4.

## Error handling

| Case | Behavior |
|---|---|
| OTP expired at verify | Backend returns `400 OTP expired`; screen shows error and enables "Resend" immediately (bypass cooldown for expired case). |
| Wrong OTP | Backend returns `400 { verified: false, message: "Invalid OTP" }`; screen shows error; OTP input remains; user can retry until expiry. |
| SMS gateway stalls (pending > N minutes) | No backend change in this feature. User waits 4 minutes, hits "Resend". If still no SMS, "Log out" escape + support-contact message in error state. |
| RTDB OTP entry missing | 400 "OTP not found"; screen treats as expired and offers resend. |
| 90-day lock violation at profile write | Firestore rules reject with permission error; client catches and shows "Cannot change mobile until {date}". |
| Network failure during verify | Standard error banner; OTP still valid in RTDB; user retries. |
| User logs out on gate | Normal sign-out flow; returns to landing; next login re-runs the gate. |
| Missing mobile number on user doc | Should not happen (registration requires it, max 10 digits), but if encountered: error state with support escape. |

## Security

- `reason` is read from the RTDB OTP entry (written by `RequestOtp`), never from the `VerifyOtp` request body. Prevents a client from requesting a `reason=payment` OTP and claiming `reason=mobile_verification` at verify time to trigger unintended user-doc side effects.
- `verificationStatus` and `mobile_verified_at` are writable only via Admin SDK — client writes rejected by Firestore rules.
- 90-day mobile-number lock enforced in rules, not just client — can't be bypassed by direct SDK access.
- Firestore user-update trigger clears verification state on mobile-number change, so a client that manages to bypass the client-side routing cannot retain "verified" status with a different number.

## Testing

**Backend testing baseline**: the Go codebase currently has no real test coverage — only a single stub file (`test/api/users/add_user_test.go`) that logs. CI (`.github/workflows/loans-functions-*.yml`) already runs `go test ./...`, so newly-added tests run automatically. This feature establishes the unit-test pattern for the codebase via the adapter+core split (see Architecture). Future Go PRs adopt the same pattern incrementally; no backfill of existing handlers is in scope.

| Layer | Tests | Style |
|---|---|---|
| `verifyOtpCore` (Go) | Table-driven unit tests in `test/api/users/verify_otp_test.go` covering: `mobile_verification` reason → `updateUser` called with `(verificationStatus \|= 2, mobile_verified_at = now)`; `payment` reason → `updateUser` NOT called; unknown reason → no-op + verified true; wrong OTP → no `deleteOtp` / `updateUser`, returns error; expired OTP → returns error; missing OTP entry → error; **`reason` sourced from RTDB entry, request body `reason` ignored** (security invariant). | Pure unit, in-memory fakes from `test/fakes/`. No Firebase. |
| `VerifyOtp` adapter (Go) | Not directly tested; thin HTTP wiring exercised manually via dev-stg deploy. | Manual / smoke. |
| `handleUserMobileChanged` core (Go) | Table-driven unit tests in `test/triggers/user_mobile_changed_test.go`: mobile changed → `updateUser` called clearing bit + nulling timestamp; mobile unchanged → no `updateUser`; missing fields → error returned without crash. | Pure unit, in-memory fakes. |
| User-update trigger adapter (Go) | Not directly tested; CloudEvent unmarshal + Firebase wiring exercised manually. | Manual / smoke. |
| `service/otp_service.go` (Go) | Unchanged. No new tests added (out of feature scope; would be a sensible follow-up). | — |
| Firestore rules | Emulator-based tests: (a) reject `mobile_number` change within 90d, (b) permit after 90d, (c) reject client writes to `verificationStatus` / `mobile_verified_at`, (d) Admin SDK writes bypass. | Firebase rules-unit-testing emulator. |
| `AuthenticationBloc` (Dart) | `bloc_test`: `_checkUserVerificationStatus` routes to verify state when bit unset; `_handleVerifyOtpEvent` calls backend + emits success on verified; error on wrong OTP / expired; cooldown state tracked. | `bloc_test` + `mocktail`. |
| `MobileVerificationScreen` (Dart) | Widget: resend disabled for 4 min after a send; "Log out" works; editing mobile triggers resend; error states render. | `flutter_test`. |
| Profile & update-profile (Dart) | Widget: badge when bit set, button when unset; mobile field disabled + helper text inside 90d window; enabled past window. | `flutter_test`. |

SMS gateway Android app: **no changes required**. It reads `phone` + `message` from the RTDB entry; the new `reason` value is transparent to it.

## Legacy users & registration

- **Registration flow is unchanged.** After signup the user has `verificationStatus=0` and `mobile_verified_at=null`. The existing "check your email" screen and Firebase email-link remain. On next login, the new mobile gate catches them.
- **Legacy users with `mobileNumberVerified` bit set but `mobile_verified_at` null**: treated as verified, no lock. They won't be re-gated. If they later edit their mobile number, the bit clears (via trigger), which re-gates them on next login — organic migration, no backfill needed.
- **Legacy users without the bit**: login gate kicks in on next login. Effectively every existing user, since the mobile verify flow was dormant. Coordinate external communication before ship.

## Documentation updates

- `README.md` (root) or `apps/loans/README.md`: add "Mobile number verification" to the feature list.
- New `docs/security-rules.md` (or append to an existing docs dir): document the `users/{uid}` rules — 90-day mobile lock and backend-only fields. Note the rule interacts with the Firestore user-update trigger.
- `MEMORY.md` at root, `apps/loans/MEMORY.md`, `functions/loans/MEMORY.md`: entries summarizing what shipped and any gotchas, per the CLAUDE.md convention.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Users stuck on gate with wrong mobile and no edit-save flow | Edit-and-save flow is part of v1. Log-out + support is the fallback. |
| SMS gateway outage blocks all logins | Degraded state — users see error with "Log out" + support message. We own the gateway; monitor. |
| Security rules too strict accidentally breaking existing writes | Stage rules in dev-stg first; emulator tests before prod push. |
| Trigger race: client edits mobile + client reads user doc before trigger clears verified state | Bloc routes to verify after save regardless of doc state; trigger's role is backstop against rogue clients. |
| Old `verifyPaymentOtp` consumers during deploy window | Ship backend + Flutter app together. Small user base, minimal risk. |
