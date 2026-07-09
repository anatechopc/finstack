---
name: finstack-security-hardening
description: >-
  Use when working on finstack security: fixing the OTP-derivable-from-token /
  otp-readable-by-any-authed-user weakness, adding rate limiting to
  unauthenticated setPassword / sendPasswordSetupLink, removing the committed
  Google OIDC JWT in subscription_job.go, exporting console-managed Firestore /
  Storage / RTDB security rules into source (the "rules into source" campaign),
  wiring a rules deploy path, codifying the three DEFERRED authorization rules
  (review responses, payment pending->confirmed, lender bank-details writes), or
  before touching anything guarded by ValidateRequestV2, keyless ADC, or the
  --allow-unauthenticated functions.
---

# finstack Security Hardening

Runbook for the open security workstream in the **finstack** monorepo. Every
item below is a **maintainer-confirmed OPEN must-fix** (as of 2026-07-07,
answers file F3) — none is accepted risk. This skill is the primary home for the
three open findings, the rules-into-source export runbook, and the security
invariants that must never regress.

## When to use / when NOT to use

Use this skill when the task matches a `description` trigger above.

Do NOT use it for:

| You want to… | Go to sibling skill |
|---|---|
| Run/deploy functions, deploy indexes/rules mechanics, `deploy_functions.sh` anatomy | `finstack-run-deploy-operate` |
| Understand how a change is classified/gated, the 5 unwritten rules, backend-first PR discipline | `finstack-change-control` |
| Read the full narrative of incident #60 (leaked key) / #71-#74 (auth bypass) | `finstack-failure-archaeology` |
| Env/project/prefix tables, secrets/WIF identities, collection-prefix mechanism | `finstack-config-and-environments` |
| Loan-computation / reporting correctness (the other hardening campaign) | `finstack-loan-engine-and-reporting-campaign` |
| Triage an unknown failure by symptom | `finstack-debugging-playbook` |

CLAUDE.md files load every session — this skill does not restate them. The 5
unwritten discipline rules live in `finstack-change-control`; **rule #3
("console rule changes need a repo note")** governs everything here: no
procedure in this skill may change a Firebase console ruleset without recording
it in the repo.

## The three open findings (2026-07-07)

| # | Severity | Where | One-line | Fix menu |
|---|---|---|---|---|
| 1 | High | `functions/loans/api/service/otp_service.go` + `apps/loans/database.rules*.json` (`otp` node) | OTP is a deterministic pure function of the hash with **no server secret**, and the hash is returned to the caller as `token`/`vid` — a token holder computes the OTP locally; PLUS RTDB `otp .read: auth != null` lets **any** authed user read every OTP entry (plaintext `otp`/`phone`/`userId`). | `references/otp-token-derivation.md` |
| 2 | High | `api/users/set_password.go:183`, `api/users/send_password_setup_link.go:114` | `TODO(rate-limit)` — two **unauthenticated** endpoints with no rate limiting → OTP/token brute force + email-bombing. | `references/rate-limiting.md` |
| 3 | Medium | `functions/loans/job/subscription_job.go:18` | A real (expired) Google OIDC JWT is committed in a code comment (subject `dafduldulao@anaheimtechnologies.com`, `exp` Jan 2024). Function is disabled, token expired — but a live-looking credential sits in source. Echoes finstack#60. | Delete the comment line; see below. |

### Verify the findings still exist (before you fix, and in review)

```bash
cd functions/loans
# Finding 1 — OTP has no server secret; token is returned to the caller:
grep -n 'getOtp\|generateHash\|"token"\|vid=' api/service/otp_service.go api/users/request_otp.go
grep -n '"otp"' ../../apps/loans/database.rules.json          # -> ".read": "auth != null"
# Finding 2 — the two TODO(rate-limit) markers:
grep -rn 'TODO(rate-limit)' api/users/
# Finding 3 — the committed JWT literal (should return exactly one file):
grep -rln 'eyJ[A-Za-z0-9]' . --include='*.go'                 # -> job/subscription_job.go only
```

### Finding 3 — the quick one (do it first)

1. Delete the `// eyJ...` comment line at `job/subscription_job.go:18`. Nothing
   reads it; it is a copy-pasted sample token.
2. Confirm nothing else carries a JWT literal: the `grep eyJ` above must return
   **only** `job/subscription_job.go` before your edit and **nothing** after.
3. This is a source-hygiene fix. It does **not** rotate a credential (the token
   is already expired and the `subscriptionJob` function is commented out of
   `loooans_cloud_functions.go` `init()`). Note in `functions/loans/MEMORY.md`.
4. Cross-ref: finstack#60 was the analogous leak of a **live** service-account
   key — see `finstack-failure-archaeology`. That one required rotation; this one
   does not, but treat both as the same class of defect.

Findings 1 and 2 are larger; each has a ranked fix menu with verification steps
in its `references/` file. Read the menu before writing code — the cheapest safe
fix is not always the first idea.

## Security invariants — never regress these

Full statements, rationale, and one-line re-checks are in
`references/security-invariants.md`. Summary:

1. **Reason/objective is read from the RTDB OTP entry, never the request body**
   (`VerifyOtpCore`) — a payment OTP cannot be escalated into a profile mutation.
2. **`sendPasswordSetupLink` always returns 200** (anti-enumeration) — never leak
   whether an account exists.
3. **`ValidateRequestV2` does full verification only** (`VerifyIDToken`). Never
   reintroduce `jwt.ParseUnverified` (finstack#71/#74). The only remaining mention
   is a *comment* in `triggers/user_created.go` explaining why it was removed —
   that is fine; a real `ParseUnverified(` call is not.
4. **Keyless ADC only** — `firebase.NewApp(ctx, conf)` with no credentials file;
   runtime identity comes from the function's service account (finstack#60). Never
   commit or reference a key file.
5. **`--allow-unauthenticated` functions rely on in-code JWT checks.** Only
   `setPassword` and `sendPasswordSetupLink` are *intentionally* public (their
   one-time token / email IS the credential). Every other HTTP function must call
   `ValidateRequestV2` first. Inventory in `references/security-invariants.md`.

`scripts/scan-security-regressions.sh` checks 3, 4, and finding 3 in one pass —
run it before any security-adjacent PR.

## The rules-into-source campaign

The systemic root cause behind findings and the recurring "DEFERRED" theme:
**the real Firestore and Storage authorization rules live only in the Firebase
console, and the repo files are stale placeholders.**

The authoritative file-by-file deploy reality — which repo rules file is a stale
stub vs. real, which is wired into `firebase.json`, and why bare `firebase deploy`
is unsafe — is owned by **`finstack-run-deploy-operate` §7** ("Rules deploy
reality"). Read that table before any rules deploy; it is not restated here so the
two can't drift. What this skill owns is the security angle: turning that console
state into source of truth and codifying the deferred rules.

- Three shipped features deferred their Firestore authorization to the console:
  **review responses**, **borrower payment `pending`->`confirmed` transition**,
  **lender bank-details writes**. Their intended rules are documented in
  `apps/loans/MEMORY.md` (and chat rules in `apps/loans/firestore.rules.chat.reference`
  / `storage.rules.chat.reference`).

The campaign turns console rules into source of truth, wires a deploy path, gates
it under change control, then codifies the three deferred rules. Full runbook —
exact export commands (firebase MCP + CLI + REST fallback), diff-against-expectations,
commit, wire `firebase.json`, deploy-with-gating, codify — is in
`references/rules-into-source-campaign.md`. `scripts/export-live-rules.sh`
automates the export step.

Deploy *mechanics* (how `firebase deploy` / `deploy-indexes.sh` actually run,
where output lands) are the primary home of `finstack-run-deploy-operate`; this
skill covers the security-specific export, gating, and codification.

## Scripts

| Script | What it does | Notes |
|---|---|---|
| `scripts/export-live-rules.sh` | Exports live Firestore + Storage + RTDB rules from a given project into a directory so you can diff console-vs-repo. | Read-only. Needs `firebase` CLI logged in; prints the exact commands it runs. |
| `scripts/scan-security-regressions.sh` | Greps the Go tree for `jwt.ParseUnverified(` usage, committed key/JWT literals, and unauth HTTP handlers missing `ValidateRequestV2`. | Read-only. Exit non-zero if a regression is found. |

## Provenance and maintenance

- **Authored:** 2026-07-07 from direct read-only repo inspection on branch
  `feature/chat-messaging` (finstack monorepo). Every file:line, flag, and CLI
  command below was executed or `stat`'d, not recalled.
- **Verified tooling:** `firebase` CLI `14.27.0` at
  `/Users/deibeeed/.nvm/versions/node/v24.11.1/bin/firebase`; firebase MCP
  `firebase_get_security_rules` tool present (read-only).
- **UNVERIFIED (cannot be checked from the repo):** the *actual live content* of
  the console-managed Firestore and Storage rules in both projects, and the
  **90-day mobile-number change lock** (maintainer says it is enforced in console
  Firestore rules — root `MEMORY.md:54` — but the repo `firestore.rules` is
  the stale stub, so it cannot be confirmed here). Resolve by running
  `scripts/export-live-rules.sh` against each project.
- **Re-verify the findings still open:** run the four `grep` commands under
  "Verify the findings still exist" above. If any returns empty, the finding may
  have been fixed — update this skill and cross-check the relevant `MEMORY.md`.
- **Re-verify invariants:** `bash scripts/scan-security-regressions.sh` from the
  repo root.
- **Ticket convention:** annotate every ticket with its repo of origin —
  `finstack#60`, `finstack#71`/`#74` are on the current repo. Rate-limit follow-up
  is **loooans#132** (mobile-verify follow-ups on the old `loooans` archive) and is
  a **still-wanted item to be refiled on finstack** — see
  `finstack-roadmap-and-frontier`.
