---
name: finstack-roadmap-and-frontier
description: Use when deciding what to work on next in finstack, resuming work after time away, answering "what is in flight / what is pending / what happened to X", judging whether an asset (package, flag, endpoint, test scaffold) is dormant or live, filing or refiling follow-up issues, assessing production-deploy readiness, weighing the sms-gateway's future, or evaluating platform expansion (budgeting/HRIS on packages/core).
---

# finstack roadmap and frontier

> **THIS IS THE MOST VOLATILE SKILL IN THE LIBRARY.** Everything here was true on
> **2026-07-07** and decays fastest of all twelve skills. Before acting on any "state"
> claim below, re-verify it — run `scripts/check_roadmap_state.sh` (read-only) or the
> one-liners in "Provenance and maintenance". A merged PR or a single deploy can
> invalidate half this file.

**Jargon used below** (defined once): *dev-stg* = Firebase project `loooans-dev-stg`
(hosts both development and staging, separated by `dev_`/`stg_` Firestore collection
prefixes); *prod* = Firebase project `loooans-prod`; *RTDB* = Firebase Realtime
Database; *console-managed rules* = Firebase security rules edited in the web console
and NOT deployed from repo source; *archive repos* = the pre-monorepo GitHub repos
`anatechopc/loooans` (Flutter) and `anatechopc/loooans_cloud_functions` (Go), read-only
history since 2026-02.

## When NOT to use this skill

| You want to... | Use instead |
|---|---|
| Actually execute the loan-math / reporting rebuild | `finstack-loan-engine-and-reporting-campaign` |
| Fix the open security findings or move rules into source | `finstack-security-hardening` |
| Understand why something is the way it is (incidents, sagas) | `finstack-failure-archaeology` |
| Deploy, run, or operate anything | `finstack-run-deploy-operate` |
| Know the change-gating rules before touching code | `finstack-change-control` |
| Add tests | `finstack-testing-and-validation` |

## Ticket annotation rule (applies to every reference below)

`finstack#N` = github.com/anatechopc/finstack. `loooans#N` = the archive repo
github.com/anatechopc/loooans. The two number spaces collide (e.g. finstack#13 is an
SOA feature; loooans#13 is mobile verification). MEMORY.md files cite bare loooans
numbers — full collision table lives in `finstack-failure-archaeology`. **All future
tickets are filed on finstack.**

## Priority order (maintainer-confirmed 2026-07-07)

Near-term ambition is **production hardening**, not features. Order:

0. **Finish what is in flight** — chat feature (below). Never leave a 10.9k-line PR
   rotting.
1. **Rules into source** + apply the three deferred console rules (review responses,
   borrower payment `pending→confirmed`, lender `bank_details` writes) —
   procedure and rule inventory: `finstack-security-hardening`.
2. **The three open security fixes** (OTP derivable from token; no rate limits on
   unauthenticated endpoints; committed JWT in `job/subscription_job.go`) — fix menus:
   `finstack-security-hardening`.
3. **Loan-engine correctness + reporting rebuild** — the maintainer-named hardest
   live problem. Decision-gated campaign: `finstack-loan-engine-and-reporting-campaign`.
4. **Flutter test infrastructure** — finstack#40 (unit), #41 (widget), #42 (Patrol),
   plus the refiled loooans#134 (below). Recipes: `finstack-testing-and-validation`.

Platform expansion (budgeting/HRIS) is the frontier — see the last section. It comes
after, not instead of, the above.

## In flight: chat feature (state as of 2026-07-07)

| Item | State (2026-07-07) | Evidence |
|---|---|---|
| Backend (`messageWritten` Go trigger) | **MERGED** to develop — finstack PR #83, 2026-07-03 | `gh pr view 83` |
| Backend deployed to development env | **YES** — develop deploy workflow succeeded 2026-07-03 after the #83 merge; deploy script on develop has 17 functions incl. `messageWritten` | `gh run list --workflow loans-functions-development.yml` |
| Frontend + infra (finstack PR #84) | **OPEN**, +10,926/−41, `feat/chat-frontend` → develop, last update 2026-07-04 | `gh pr view 84` |
| Rules/index source in PR #84 | Carries `database.rules.json`, `database.rules.prod.json` (chat `typing` paths), `firestore.indexes.json` (chat_rooms inbox index), and the two `.reference` rule files | `gh pr diff 84 --name-only` |
| Local branch `feature/chat-messaging` | Was the monolithic dev branch (HEAD `3d94ccc`, 2026-07-02); superseded by the #83/#84 split. Do not develop on it further | `git log -1 feature/chat-messaging` |

**TRAP: local git refs are stale.** As of 2026-07-07 local `origin/develop` =
`5e74d69` (2026-06-30), which predates the #83 merge. `git fetch origin` first;
when local and `gh` disagree, **trust `gh`**.

**Remaining chat work** (in order, backend-first discipline per
`finstack-change-control`):

1. Review + merge finstack#84.
2. Apply chat Firestore/Storage rules in the **console** for dev-stg (and later prod),
   from `apps/loans/firestore.rules.chat.reference` and
   `apps/loans/storage.rules.chat.reference` — with a repo note, per the console-rules
   rule in `finstack-change-control`; export runbook in `finstack-security-hardening`.
3. Deploy chat RTDB rules: dev-stg via the normal `database.rules.json` path; **prod
   RTDB rules are a manual deploy** (`database.rules.prod.json` — nothing in CI ships
   it). Commands: `finstack-run-deploy-operate`.
4. Prod function deploy — blocked on the larger prod-readiness item below.

## Production deploy readiness (state as of 2026-07-07)

**The finstack repo has never deployed Go functions to prod.** Verified 2026-07-07:
the remote has **no `master` branch and no `release/**` branches** — only `develop`
(default) and feature branches — and the production workflow
(`.github/workflows/loans-functions-production.yml`, deploy gated on `master` pushes)
has **zero recorded runs** (`gh run list --workflow loans-functions-production.yml`
returns empty). Whatever runs on `loooans-prod` today predates the monorepo
(deployed from the archive `loooans_cloud_functions` repo) — exact live prod state is
UNVERIFIED from the repo; check the GCP console for `loooans-prod`.

Known prerequisites before the first prod deploy (from `functions/loans/MEMORY.md`):

- [ ] Grant `roles/secretmanager.secretAccessor` on `ms-graph-client-secret` to the
      prod runtime SA in `loooans-prod` (pending as of the provisioning work, 2026-06-19).
- [ ] Deploy `apps/loans/database.rules.prod.json` to prod RTDB (manual; includes the
      chat `typing` rules once #84 merges).
- [ ] Recreate prod Firestore + Storage rules story (console-managed today) — see
      `finstack-security-hardening` before trusting any prod authorization.
- [ ] Delete orphaned `verifyPaymentOtp_<env>` Cloud Run services after first deploy.
- [ ] Create `master` (and `release/**` for staging) per the branch→env mapping in
      `finstack-change-control` — never push to `master` casually; it deploys prod.

## Refile list — loooans follow-ups to re-open on finstack

**Ground truth correction (verified 2026-07-07):** loooans#130–#134 DO exist — on the
archive repo `anatechopc/loooans`, not on finstack (root `MEMORY.md` cites them as
bare `#130–#134`, which resolve to nothing meaningful on finstack). Maintainer policy
(2026-07-07): these are still-wanted work, to be refiled on finstack. States on the
archive repo as of 2026-07-07:

| Archive issue | Title (actual) | State | Refile? |
|---|---|---|---|
| loooans#130 | Migrate email verification to OTP path | **CLOSED (completed 2026-05-18)** | **Verify-then-skip** — `verify_otp.go` ships a `reasonEmailVerification` branch, so the core migration landed. Only refile the residual open decisions (replace Firebase email-link entirely? gate login on it?) if the maintainer still wants them. |
| loooans#131 | Trusted device / device binding | OPEN | Yes |
| loooans#132 | SMS OTP rate limiting / abuse prevention | OPEN | Yes — overlaps open security finding (b) (unauthenticated-endpoint rate limits); coordinate with `finstack-security-hardening` so one fix closes both |
| loooans#133 | Self-service mobile change during 90-day lock | OPEN | Yes |
| loooans#134 | Bloc test pattern for AuthenticationBloc | OPEN | Yes — root MEMORY.md describes it more broadly ("Flutter bloc/widget test infra + rules emulator tests"); refile scoped, linked to finstack#40/#41 |

Ready-to-file titles + bodies + `gh issue create` commands:
`references/refile-issues.md`.

## Open issue digest (finstack, verified via `gh` 2026-07-07)

14 open issues. Ages matter: everything ≤ #32 predates the monorepo (2024–2025
creation dates, carried over) and needs a "still wanted?" pass before work starts.

| # | Title (abridged) | Created | Note |
|---|---|---|---|
| #6 | Additional loan amount notification | 2025-05 | Backend notification trigger work; see `finstack-architecture-contract` for notification ownership |
| #9 | "implement functionalities" | 2025-03 | Too vague to act on — ask maintainer or close |
| #10 | Figma design for unified tellers view | 2025-03 | Design task; Payment Center (2026-03) may have superseded it |
| #13 | Advance dates on SOA calculation | 2025-03 | **NOT** mobile verification (that's loooans#13) |
| #14 | Advance Statement of Account calculations | 2025-03 | Parent story of #13; touches loan math — route through the campaign skill |
| #21 | Cash pool mass upload options | 2025-03 | Idea stage |
| #28 | Update `load()` on all Firestore services | 2025-02 | Cross-cutting packages change; architecture-contract territory |
| #30 | Client app remote confirmation | 2025-02 | Story; partially overlapped by borrower payment submission (finstack#64, delivered) |
| #31 | Page does not load on prod/release build | 2025-02 | Likely fixed by `d84b628` (2026-06-16, release-only `Expanded` blank-screen fix — see `finstack-failure-archaeology`). Verify on a release build, then close |
| #32 | Setup domains | 2024-05 | Oldest open item; infra/ops |
| #40 | Implement Unit testing | 2026-03 | Test-infra trio — priority 4 above |
| #41 | Implement Widget testing | 2026-03 | Test-infra trio |
| #42 | Implement Patrol | 2026-03 | Test-infra trio (integration tests) |
| #63 | Borrower payment submission | 2026-06 | **Delivered** via finstack PRs #64/#65 + follow-ups; verify and close as duplicate |

## Dormant assets — decide-then-act (never silently delete)

Every item below is a candidate for removal or revival. The rule: open a finstack
issue or PR stating the decision; do not quietly delete (change control applies).
All paths verified present 2026-07-07.

| Asset | Evidence | Options |
|---|---|---|
| 3 unwired packages: `packages/loans/karma_transaction_repository`, `transaction_repository`, `transaction_view_repository` | On disk; zero references in `apps/loans/pubspec.yaml` or `lib/app/di/repository_providers.dart` | Wire in (if a transactions feature is planned) or remove via PR. Ask maintainer intent first |
| AutoCollect / UnionBank feature | Commented gate `apps/loans/lib/features/users/widget/profile_widget.dart:44` (+ marketing copy ~:307); layout TODO `apps/loans/lib/widgets/profile_widgets.dart:50` | Dormant integration awaiting UnionBank setup. Keep commented until a real decision; do not "clean up" without asking |
| `updateUser` + `subscriptionJob` functions | Commented out in `functions/loans/loooans_cloud_functions.go:26,33`; `job/subscription_job.go` also holds a committed (expired) JWT — security finding (c), see `finstack-security-hardening` | Revive with adapter+core tests, or delete `job/`. The JWT comment must be scrubbed regardless |
| `sometest` HTTP endpoint | Registered at `loooans_cloud_functions.go:30`, absent from `deploy_functions.sh` (never deployed) | Scratch endpoint — delete when convenient |
| VGV counter scaffold | `apps/loans/test/counter/{cubit,view}/` exist with **fully commented-out** bodies; `lib/counter/` already deleted; `lib/l10n/arb/app_en.arb` is 4 keys of mostly counter strings (l10n effectively unused — UI strings are hardcoded) | Delete the dead tests; decide whether l10n is a real goal before touching ARB files |
| 681 MB heap dump `apps/sms-gateway/java_pid7112.hprof` | **Local-disk only** — git-ignored via `apps/sms-gateway/.gitignore:5` (`*.hprof`), NOT committed | Safe to delete locally, no PR needed |
| Stale merged branches | Nearly every merged feature branch still exists local + remote (no pruning has ever happened) | Archaeological record — prune only with maintainer sign-off; see `finstack-failure-archaeology` before assuming a branch is live |

## sms-gateway: open operational risk (decision pending)

SMS OTP delivery = one physical Android phone running a foreground service
(`apps/sms-gateway/`). It heartbeats to RTDB `/gateway_status/{ANDROID_ID}` every 30s
(`SmsGatewayService.kt`), but **nothing watches the heartbeat** — if the phone dies,
OTP SMS silently stop (login/mobile-verify and payment-ack flows degrade). No CI, no
monitoring, manual APK install. It exists to avoid telco/SMS-provider registration
(history: `finstack-failure-archaeology`, SMS OTP saga).

Options on the table (no decision as of 2026-07-07):

1. **Keep + alert**: add staleness alerting on `gateway_status` (e.g. a scheduled Go
   function or an admin-UI banner when `last_heartbeat` > N minutes). Cheapest;
   respects the no-telco constraint. Operations detail: `finstack-run-deploy-operate`.
2. **Migrate to an SMS provider** when volume justifies registration cost. Removes the
   single point of failure; revisit alongside loooans#132 rate-limiting (refile list).

## Frontier: packages/core as the platform layer

Root `CLAUDE.md` names the direction: `packages/core/` packages "can be shared by
future apps (budgeting, HRIS, etc.)". This is **documented direction, not present
work** — nothing may start here while hardening items 1–4 are open. To keep the
frontier honest, treat these as **falsifiable milestones** (each has a yes/no check):

| # | Milestone | Falsifiable check |
|---|---|---|
| M1 | Security rules deploy from source in CI, both projects | `firebase.json` gains a `firestore.rules` key; CI logs show rules deploy for dev-stg AND prod; console diff vs repo is empty (`finstack-security-hardening`) |
| M2 | Golden loan-math suite green in CI | The campaign's golden scenario suite exists and runs in a required CI check (`finstack-loan-engine-and-reporting-campaign`) |
| M3 | Report totals recomputable from scratch | A recompute job/tool regenerates RTDB `report_summary` from Firestore loans and matches (or intentionally corrects) live values (campaign skill) |
| M4 | Core is actually app-agnostic | A second app consumes `packages/core/*` with **zero imports from `packages/loans/*`**. Known blockers today: `user_repository → user_loan_view_repository` and `company_repository → product_view_repository` cross-boundary deps (see `finstack-architecture-contract`), and the loans-branded `loooans_helpers` name |
| M5 | Flutter test infra exists | finstack#40/#41 closed; new features land with bloc + widget tests by default (`finstack-testing-and-validation`) |

If someone proposes starting the budgeting or HRIS app before M1–M3 are green, the
correct answer is "not yet" — expanding on top of unverified loan math and
console-only security rules multiplies both risks.

## Provenance and maintenance

Authored 2026-07-07 from repo inspection on branch `feature/chat-messaging` plus live
`gh` queries (local refs were stale; every PR/issue/branch state above came from
`gh`). Volatile by design — re-verify before trusting:

```bash
# One-shot re-check of everything volatile in this skill (read-only):
.claude/skills/finstack-roadmap-and-frontier/scripts/check_roadmap_state.sh

# Or piecemeal:
gh pr view 84 --repo anatechopc/finstack --json state          # chat frontend still open?
gh issue list --repo anatechopc/finstack --state open          # issue digest drift
gh api "repos/anatechopc/finstack/branches?per_page=100" -q '.[].name' | grep -E '^(master|release/)'  # prod branches exist yet?
git fetch origin && git log -1 --format='%h %ad' origin/develop # cure stale-ref trap
grep -c "gcloud functions deploy" .github/scripts/deploy_functions.sh  # 17 on develop as of 2026-07-07
ls packages/loans | grep -E '^(karma_)?transaction'            # dormant packages still present?
for n in 131 132 133 134; do gh issue view $n --repo anatechopc/loooans --json state -q .state; done  # refile sources
```

When any of these disagree with this file, the repo/`gh` wins — update this skill in
the same session (and the relevant `MEMORY.md`, per `finstack-change-control`).
