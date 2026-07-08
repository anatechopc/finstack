# Finding 1 — OTP derivable from token + OTP readable by any authed user

**Severity: High. Open (2026-07-07).** Two defects that compound each other.

## What the code actually does (verified)

`functions/loans/api/service/otp_service.go`:

- `generateHash()` builds an HMAC-SHA256 over `time.Now()+salt` keyed by a
  **hardcoded** string (`"Loooans! app the greatest application in the universe!"`).
  The result is a 64-char hex string used as the RTDB key.
- `getOtp(hashStr)` derives the 6-digit OTP **purely from the hash**: takes the
  last hex nibble as an offset, slices 8 hex chars, parses to int, takes the last
  6 digits. **No server secret, no per-user salt, no state.**
- `GenerateOtp()` returns `(hashStr, otp)`. `VerifyOtp(hashStr, receivedOtp)` just
  recomputes `getOtp(hashStr)` and compares.

`functions/loans/api/users/request_otp.go`:

- Writes the entry to RTDB `otp/{hash}` including the plaintext `otp`, `userId`,
  and (mobile path) `phone` + the full SMS `message` text.
- **Returns the hash to the caller** as `"token"` in the JSON response
  (`request_otp.go:279`) and embeds it in `RedirectURL` as `?vid=<hash>`
  (`request_otp.go:167`).

`apps/loans/database.rules.json` and `database.rules.prod.json`, `otp` node:

```json
"otp": {
  ".read": "auth != null",
  "$hash": { ".write": "auth != null && auth.token.email == 'sms-gateway@loooans.com'" }
}
```

## Why this is exploitable

1. **Token holder computes the OTP locally.** Because `otp = getOtp(hash)` and the
   API hands `hash` back as `token`/`vid`, whoever receives the response can
   compute the valid OTP without ever receiving the SMS/email. This defeats the
   entire point of an out-of-band second factor: the "secret" the user is supposed
   to prove they received is derivable from data the client already has.
2. **Any authenticated user reads every OTP.** `.read: auth != null` is at the
   `otp` collection node, so any signed-in account can read the whole `otp/` tree —
   including other users' plaintext `otp`, `phone`, and `userId`. The per-`$hash`
   write restriction does not restrict reads.

The two combine: an attacker does not even need the token flow — they can read
live OTP entries directly from RTDB.

## What still protects you (do not remove)

- Entries carry `expire_at` (5 min, `otpValidityDuration` in `request_otp.go:32`)
  and `VerifyOtpCore` enforces it (`ErrOtpExpired`, `verify_otp.go`).
- On success the entry is deleted (`DeleteOtp`).
- Functions write via the Admin SDK, which **bypasses** RTDB rules, so tightening
  `.read`/`.write` does not break the server or the SMS gateway (the gateway
  authenticates as `sms-gateway@loooans.com` and only needs `$hash` write to set
  `sms_status`, per `apps/sms-gateway/.../SmsGatewayService.kt`).
- **No attempt cap today.** `VerifyOtpCore` has no wrong-guess counter — worth
  adding alongside (see Finding 2 / `references/rate-limiting.md`).

## Fix menu (ranked — read all before choosing)

### Option A (recommended) — HMAC with a server-side secret, stop returning the OTP-deriving material

Make the OTP a function of a secret the client never sees, so possession of the
token proves nothing.

1. Add a secret to Secret Manager (both projects), delivered exactly like the
   existing `ms-graph-client-secret` via `--set-secrets` in
   `.github/scripts/deploy_functions.sh` (that file is the primary home of
   `finstack-run-deploy-operate` — coordinate there). e.g. `otp-hmac-secret:latest`.
2. Change generation so the OTP is `HMAC(secret, nonce)` truncated to 6 digits,
   where `nonce` is random and stored **server-side only** in the RTDB entry. The
   RTDB key (`hash`) stays a random opaque id but is **no longer sufficient** to
   compute the OTP.
3. Verify by recomputing from the stored `nonce` + secret — never from the key.
4. **Stop returning anything the client can derive the OTP from.** The response
   may keep an opaque `token`/`vid` used only to look up the entry server-side; it
   must not be the OTP seed.
5. Verification steps:
   - `getOtp` (or its replacement) takes the secret as an argument and is unit
     tested with the adapter+core + fakes pattern (see
     `finstack-testing-and-validation`). A test proves: given only the returned
     `token`, the OTP cannot be recomputed.
   - `grep -n '"otp"' functions/loans/api/users/request_otp.go` — the plaintext
     `otp` field should remain only for the SMS-gateway delivery path; confirm no
     read rule exposes it (Option C).

### Option B — keep a derived OTP but never expose the deriving key

Lower effort, weaker. Keep `getOtp(hash)` but return an opaque lookup id to the
client that is **not** the hash, and store the real hash server-side. Still relies
on the hardcoded key and is brute-forceable if the hash ever leaks; only choose if
A is blocked. Must still be paired with Option C + an attempt cap.

### Option C (do this regardless of A/B) — per-entry read rules + TTL + attempt cap

1. **Tighten the RTDB read rule.** Change `otp .read: auth != null` so a caller can
   read only their own entry, or remove client read entirely (the server reads via
   Admin SDK and does not need the rule). Because functions bypass rules, the safe
   default is `".read": false` at `otp` unless a client genuinely needs it —
   confirm no Dart/Kotlin client reads `otp/` directly first:
   ```bash
   grep -rn '"otp"\|child("otp")\|/otp/' apps/loans/lib packages \
     apps/sms-gateway/app/src/main --include='*.dart' --include='*.kt'
   ```
   As of 2026-07-07 the only readers are the **gateway** (needs read to process
   the queue) and the **Go functions** (Admin SDK). The Flutter app talks to the
   HTTP endpoints (`/users/request/otp`, `/users/verify/otp`), **not** RTDB `otp/`
   directly (verified: `packages/core/user_repository/.../user_network_service.dart`).
   So a rule that grants read only to `sms-gateway@loooans.com` is viable.
2. **TTL** already exists (5 min) — keep it; consider shortening.
3. **Attempt cap:** add a per-entry wrong-guess counter in `VerifyOtpCore`; delete
   or lock the entry after N failures. This closes online brute force of the
   6-digit space and overlaps with Finding 2's rate limiting.
4. Deploy the tightened RTDB rules through the rules-into-source path — **prod uses
   `database.rules.prod.json`, which nothing auto-deploys** (see
   `references/rules-into-source-campaign.md`). Record the console/rule change per
   unwritten rule #3.

## Verification checklist for the fix PR

- [ ] `scripts/scan-security-regressions.sh` passes.
- [ ] Adapter+core test proves OTP is not derivable from the returned token.
- [ ] `otp .read` no longer grants blanket `auth != null`; gateway + server paths
      still work (gateway sends SMS; `verifyOtp` succeeds end to end).
- [ ] Attempt cap unit-tested (N wrong guesses -> locked/deleted).
- [ ] Secret wired via `--set-secrets` in `deploy_functions.sh` for **both**
      projects; no secret literal in source.
- [ ] `functions/loans/MEMORY.md` + repo note for the console rule change.
- [ ] Backend PR before any Flutter PR (backend-first discipline —
      `finstack-change-control`).

Cross-ref: the invariant "reason from RTDB entry, never request body" must be
preserved through this refactor (`references/security-invariants.md`).
