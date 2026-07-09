# Finding 2 — no rate limiting on unauthenticated endpoints

**Severity: High. Open (2026-07-07).** Refile target: **loooans#132** (mobile-verify
follow-up "rate limits / wrong-OTP cap") — still-wanted, to be refiled on finstack
(see `finstack-roadmap-and-frontier`).

## Where (verified)

Two HTTP functions are **intentionally `--allow-unauthenticated`** (their one-time
token / email IS the credential) and both carry a `TODO(rate-limit)`:

| Function | File:line | Why unauth | Abuse without a limit |
|---|---|---|---|
| `setPassword` | `api/users/set_password.go:183` | one-time set-password/reset token in the body is the credential | brute force the token space; hammer the endpoint |
| `sendPasswordSetupLink` | `api/users/send_password_setup_link.go:114` | backs "Resend invite" + "Forgot password"; always 200 (anti-enumeration) | email-bombing any address; enumeration timing probes |

Both are deployed `--allow-unauthenticated` in
`.github/scripts/deploy_functions.sh` (lines 103 and 109). That is correct — the
fix is a rate limit, **not** requiring auth.

The exact TODO text:

```
set_password.go:183          // TODO(rate-limit): unauthenticated — add per-IP rate limiting before prod.
send_password_setup_link.go:114 // TODO(rate-limit): this endpoint is unauthenticated; add per-email/IP rate
                                  //   limiting before production to prevent email-bombing.
```

## Fix menu (ranked)

### Option A (recommended) — shared per-IP + per-account counter in RTDB or Firestore

1. Add a small `utils` helper (adapter+core so it is testable) that, given a key
   (`ip:<addr>` and/or `email:<addr>` / `account:<uid>`), increments a counter with
   a rolling window and returns "allowed / blocked". Store counters in RTDB
   (cheap, TTL-friendly via `expire_at` sweeps) or Firestore.
2. `sendPasswordSetupLink`: rate-limit **per-email AND per-IP**. Keep the always-200
   contract — when blocked, still return 200 and simply do not send. Never turn the
   limit into an existence oracle (a blocked known-account must be indistinguishable
   from a blocked unknown one).
3. `setPassword`: rate-limit **per-IP** and add a **wrong-token / wrong-OTP cap**
   (this dovetails with Finding 1's attempt cap — share the counter helper). After
   N failures from an IP (or against a token), block for a cooldown.
4. Client source IP behind Cloud Functions gen2 / Cloud Run: read
   `X-Forwarded-For` (first hop) — do not trust `RemoteAddr` directly. Verify which
   header the deployed runtime populates before relying on it.

### Option B — Cloud Armor / API gateway in front

Infra-level per-IP throttling without app code. Heavier to stand up, and does not
give you the per-account / wrong-OTP semantics. Consider as defense-in-depth on top
of A, not instead of it.

### Option C — minimum stopgap

If a full counter is out of scope for the current PR, add a per-IP fixed-window
limit on just these two endpoints and file the per-account/wrong-OTP cap as the
refiled loooans#132. Do not ship prod without at least this.

## Verification checklist

- [ ] Core limiter unit-tested with fakes: N requests in the window -> blocked;
      window rolls over -> allowed (adapter+core pattern,
      `finstack-testing-and-validation`).
- [ ] `sendPasswordSetupLink` still returns **200** on the blocked path — assert it
      in a test (invariant #2, `references/security-invariants.md`).
- [ ] `setPassword` wrong-token attempts are capped; success path unaffected.
- [ ] Both functions remain `--allow-unauthenticated` in
      `deploy_functions.sh` (do not "fix" by requiring auth).
- [ ] Counter store + any TTL sweep documented; `functions/loans/MEMORY.md` updated.
- [ ] `scripts/scan-security-regressions.sh` still passes.

Cross-ref: deploy mechanics for these functions and the `--set-secrets` pattern
live in `finstack-run-deploy-operate` / `finstack-config-and-environments`.
