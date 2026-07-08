# Refile list: loooans follow-ups → finstack issues

Ready-to-file bodies for the still-wanted follow-ups from the mobile-verification
work (loooans#13, archive repo `anatechopc/loooans`). Verified 2026-07-07: these
exist on the archive repo — #130 CLOSED (completed), #131–#134 OPEN. Maintainer
policy: refile the still-wanted ones on finstack; the archive issues stay as
historical record (link them, don't move them).

Before filing, re-check nobody has already filed an equivalent:

```bash
gh issue list --repo anatechopc/finstack --state all --search "trusted device"
gh issue list --repo anatechopc/finstack --state all --search "rate limit"
```

Conventions: file on `anatechopc/finstack`; reference the archive issue as
`loooans#NNN` with a full URL in the body (bare `#NNN` would auto-link to the wrong
finstack thread — the two number spaces collide).

---

## 1. loooans#130 — email OTP migration — VERIFY-THEN-SKIP, do not blind-refile

Closed **completed** on the archive repo 2026-05-18, and the code agrees:
`functions/loans/api/users/verify_otp.go` ships the `reasonEmailVerification`
branch (constant at line 35, case at line 107 as of 2026-07-07) that flips Firebase
Auth `emailVerified` via a sentinel field. Remote branches
`feature/email-verification-backend` / `feature/email-verification-otp` carried the
work. The only possibly-still-open scraps from the original body: (a) whether to
retire Firebase's email-link verification entirely or keep it as a fallback, and
(b) whether login should gate on email verification (today the GoRouter redirect
already requires `firebaseUser.emailVerified` — see `apps/loans/lib/app/routing/router.dart`).
**Only file if the maintainer confirms (a) or (b) is still wanted**; if so:

```bash
gh issue create --repo anatechopc/finstack \
  --title "Decide residual email-verification questions (fallback + login gate) [refile of loooans#130 remainder]" \
  --body "The core email-OTP migration from https://github.com/anatechopc/loooans/issues/130 shipped (verify_otp.go reasonEmailVerification branch, closed 2026-05-18). Two design decisions were left open: (1) retire Firebase email-link verification entirely vs keep as fallback; (2) confirm the login gate on emailVerified is the intended long-term behavior. Decide and document; small code change at most."
```

## 2. loooans#131 — trusted device / device binding

```bash
gh issue create --repo anatechopc/finstack \
  --title "Trusted device / device binding for account access [refile of loooans#131]" \
  --body "Refiled from https://github.com/anatechopc/loooans/issues/131 (still wanted, per maintainer 2026-07-07). Link a user account to a specific device so login from a new device requires re-verification (OTP + possibly email). Deferred from the mobile-verification work because it blocks web usage without a web-friendly equivalent (browser fingerprint + cookie) and complicates multi-device users. Design questions: device replacement/loss flow (self-service vs support); what 'trusted' means on web (per-browser, cookie lifetime); interaction with remember-me/silent login; whether mobile OTP verify also establishes device trust. See docs/superpowers/specs/2026-04-19-mobile-verification-design.md."
```

## 3. loooans#132 — SMS OTP rate limiting / abuse prevention

Overlaps open security finding (b) — no rate limits on the unauthenticated
`setPassword` / `sendPasswordSetupLink` endpoints (`TODO(rate-limit)` markers in
`api/users/set_password.go` and `send_password_setup_link.go`). Coordinate with
`finstack-security-hardening` so one rate-limiting design covers both; either file
one combined issue or two cross-linked ones.

```bash
gh issue create --repo anatechopc/finstack \
  --title "OTP + unauthenticated endpoint rate limiting / abuse prevention [refile of loooans#132]" \
  --body "Refiled from https://github.com/anatechopc/loooans/issues/132 (still wanted, per maintainer 2026-07-07). Mobile OTP ships with unlimited resends (4-min cooldown, no daily cap): each SMS costs gateway battery + SIM credit, a looping client could drain it, and the login gate fires an SMS per attempt for unverified users. Candidate limits: per-user and per-phone-number daily caps, per-IP limits on requestOtp, a wrong-OTP attempt cap (invalidate after N failures — today only expiry protects), and growing backoff on consecutive resends. Instrument OTP request volume first to pick thresholds. SCOPE NOTE: fold in the TODO(rate-limit) markers on the unauthenticated setPassword / sendPasswordSetupLink endpoints (open security finding — see .claude/skills/finstack-security-hardening) so one design covers all abuse surfaces."
```

## 4. loooans#133 — self-service mobile change during the 90-day lock

```bash
gh issue create --repo anatechopc/finstack \
  --title "Self-service mobile number change during 90-day lock [refile of loooans#133]" \
  --body "Refiled from https://github.com/anatechopc/loooans/issues/133 (still wanted, per maintainer 2026-07-07). The 90-day mobile-number lock (enforced by console-managed Firestore rules) leaves users who lose their verified number with no in-app path — support contact only. Options explored: support-driven one-time unlock flag; secondary identity proof (email OTP + security question + photo ID); 'change now, freeze account actions until re-verified' escrow; or relaxing the window if legitimate users get stuck often. See docs/superpowers/specs/2026-04-19-mobile-verification-design.md. Note: any rules change goes through the rules-into-source work (.claude/skills/finstack-security-hardening) — do not hand-edit console rules without a repo note."
```

## 5. loooans#134 — AuthenticationBloc testability + bloc tests

The archive issue is scoped to `AuthenticationBloc`; root `MEMORY.md` remembers it
more broadly as "Flutter bloc/widget test infrastructure + rules emulator tests".
Refile the scoped version and link it to the existing test-infra trio
finstack#40/#41/#42 rather than duplicating them.

```bash
gh issue create --repo anatechopc/finstack \
  --title "Make AuthenticationBloc testable + bloc_test coverage for verify/OTP paths [refile of loooans#134]" \
  --body "Refiled from https://github.com/anatechopc/loooans/issues/134 (still wanted, per maintainer 2026-07-07). AuthenticationBloc still takes BuildContext and binds AuthenticationService.instance in its ctor, so the mobile-verification behaviors shipped without bloc_test coverage. Work: add a withDependencies seam (pattern already established on UserBloc/RegistrationBloc — see .claude/skills/finstack-testing-and-validation), then cover: _checkUserVerificationStatus routes to verify when the mobileNumberVerified bit is unset; _handleVerifyOtpEvent calls UserRepository.verifyOtp and refreshes the user on success; error state when backend returns verified=false; _handleRequestOtpEvent emits canResendAt ~4 minutes ahead. Part of the wider test-infra effort: relates finstack#40, finstack#41. Rules-emulator tests (the other half of the old memory note) belong with the rules-into-source campaign (.claude/skills/finstack-security-hardening)."
```

---

After filing: update root `MEMORY.md`'s "Follow-ups: #130–#134" line to point at the
new finstack issue numbers (annotated `finstack#NN`), per the MEMORY-update duty in
`finstack-change-control`.
