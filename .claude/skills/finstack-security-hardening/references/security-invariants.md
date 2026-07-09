# Security invariants — never regress

These are incident-derived. Regressing one re-opens a closed vulnerability. Each
has a one-line re-check. Full incident narratives live in
`finstack-failure-archaeology`; the 5 unwritten discipline rules live in
`finstack-change-control` (this file does not restate them).

## 1. Reason/objective is read from the RTDB OTP entry, never the request body

**Why:** otherwise a caller could take a `payment` OTP and claim
`reason=mobile_verification` to trigger a profile mutation they were not
authorized for. Established with mobile verification (backend PR finstack#44).

**Where:** `functions/loans/api/users/verify_otp.go` — `VerifyOtpCore` does
`reason, _ := otpData["reason"].(string)` from the persisted entry and switches on
it; the request body only carries the token + received OTP. The doc comment above
`VerifyOtpCore` states this explicitly.

**Re-check:** the `reason` used for the post-verify side effect must come from
`otpData`, not the parsed request body.
```bash
grep -n 'reason' functions/loans/api/users/verify_otp.go
```

## 2. `sendPasswordSetupLink` always returns 200 (anti-enumeration)

**Why:** the endpoint backs both "Resend invite" and "Forgot password" and is
unauthenticated. If it returned different responses/status/timing for
existing vs non-existing accounts, it becomes an account-existence oracle.

**Where:** `functions/loans/api/users/send_password_setup_link.go` — doc comment:
"intentionally UNAUTHENTICATED and always responds 200 — it never reveals whether
an account exists." Preserve this even when adding rate limiting (Finding 2): the
blocked path must also be 200-and-silent.

**Re-check:** no code path returns a non-200 that depends on account existence.

## 3. `ValidateRequestV2` does full verification only — never `ParseUnverified`

**Why:** finstack#71/#74. `ValidateRequestV2` used to fall back to
`jwt.ParseUnverified`, which accepts a **forged** token for any admin uid on every
HTTP function. The fallback was removed.

**Where:** `functions/loans/utils/validate_request_v2.go` uses
`authClient.VerifyIDToken(ctx, idToken)` and returns the verified UID or `""`. The
only remaining mention of `ParseUnverified` is a **comment** in
`triggers/user_created.go` explaining why the last caller relying on it was
removed — that comment is fine; a real `jwt.ParseUnverified(` call is a regression.

**Re-check:**
```bash
grep -rn 'ParseUnverified(' functions/loans --include='*.go'   # expect: no call sites
grep -rn 'VerifyIDToken' functions/loans/utils/validate_request_v2.go  # expect: present
```

## 4. Keyless ADC only — never a key file

**Why:** finstack#60. A service-account **private key** was committed to
`initialize_firebase.go`; Google auto-disabled it, breaking all Admin SDK calls
(first seen as `requestOtp` 500s). Fixed by switching to Application Default
Credentials — the function's runtime service account, no key material in source.

**Where:** `functions/loans/utils/initialize_firebase.go` calls
`firebase.NewApp(ctx, conf)` with a config that sets only `DatabaseURL` (no
`option.WithCredentialsFile` / no embedded key). The deploy script assigns each
function a `firebase-adminsdk-*` service account via `--service-account`
(`deploy_functions.sh`). Local runs use `gcloud auth application-default login`.

**Re-check:**
```bash
grep -rn 'WithCredentialsFile\|WithCredentialsJSON\|BEGIN PRIVATE KEY\|private_key' \
  functions/loans --include='*.go'   # expect: nothing
```
(Finding 3 — the committed expired JWT comment in `job/subscription_job.go` — is
the same *class* of defect: no live credentials in source.)

## 5. `--allow-unauthenticated` functions rely on in-code JWT checks

Every deployed HTTP function is `--allow-unauthenticated` at the Cloud Run layer
(`deploy_functions.sh`). Authorization is enforced **in code**, not by the
platform. Two are *intentionally* public; the rest MUST validate.

| Function | Public? | Auth mechanism |
|---|---|---|
| `setPassword` | **Intentionally public** | one-time set-password token in body IS the credential |
| `sendPasswordSetupLink` | **Intentionally public** | unauth by design; always 200 |
| `addUser` | Gated | `ValidateRequestV2` + server-side role matrix |
| `requestOtp` | Gated | `ValidateRequestV2` |
| `verifyOtp` | Gated | `ValidateRequestV2` |
| `sendEmail` | Gated | `ValidateRequestV2` |
| `sometest` | Registered but NOT deployed | scratch endpoint (`sometest` excluded from deploy script) |

**Re-check** — every gated HTTP handler calls `ValidateRequestV2`:
```bash
grep -rn 'ValidateRequestV2' functions/loans/api functions/loans/utils --include='*.go' \
  | grep -v validate_request_v2.go
```
Verified callers (2026-07-07): `add_user.go:202`, `request_otp.go:356`,
`verify_otp.go:154`, `utils/send_email_http.go:33`. If you add a new HTTP function
that is not intentionally public, it must appear here.

## Also worth knowing

- The **90-day mobile-number change lock** is enforced (per maintainer) in the
  console Firestore rules and mirrored in the Flutter UX. It **cannot be verified
  from the repo** because `apps/loans/firestore.rules` is the stale stub — resolve
  via the export runbook (`references/rules-into-source-campaign.md`). Labeled
  UNVERIFIED in SKILL.md provenance.
- RTDB rules deny by default (`.read/.write: false` at root) and functions bypass
  rules via the Admin SDK — so tightening client-facing read rules (Finding 1,
  Option C) does not break the server or the SMS gateway.
