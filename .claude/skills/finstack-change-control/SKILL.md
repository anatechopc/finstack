---
name: finstack-change-control
description: "Use when planning, committing, merging, or deploying any finstack change — choosing a target branch (develop / release/** / master), splitting a full-stack change into PRs, writing commit messages or PR descriptions, changing Firestore document shapes, changing Firebase console rules or indexes, doing anything that touches production (loooans-prod) or its data, handling credentials/secrets, modifying loan-computation or JWT-validation code, or wrapping up a session (MEMORY.md duty)."
---

# finstack Change Control

How a change gets from idea to production in this monorepo, and the rules that
gate it. Every rule here has an incident behind it or a maintainer mandate;
none are style preferences.

**When NOT to use this skill:**
- Diagnosing a failure → `finstack-debugging-playbook`
- Full incident history / why a rule exists in depth → `finstack-failure-archaeology`
- Writing the actual tests a change needs → `finstack-testing-and-validation`
- Running/deploying mechanics (deploy_functions.sh anatomy, CI workflow internals) → `finstack-run-deploy-operate`
- Env/prefix/flags/secrets details → `finstack-config-and-environments`
- Security fix menus and the rules-into-source campaign → `finstack-security-hardening`
- Loan-math changes: this skill tells you the gate exists; the recipes live in `finstack-loan-engine-and-reporting-campaign`

## The non-negotiables (memorize these)

1. **Never hand-edit production data** (loooans-prod Firestore/RTDB/Storage). No exceptions via console, scripts run ad hoc, or "just this one field".
2. **Doc-shape changes ship both sides (Go + Flutter), backend first**, as two PRs.
3. **Firebase console changes (rules, indexes) require a repo note** in the same time window as the change.
4. **New or touched Go handlers use the adapter+core pattern with fakes-based tests** (recipe: `finstack-testing-and-validation`).
5. **Dev/staging builds never point at prod** unless genuinely needed and deliberate.
6. **Never commit credentials, keys, or tokens** — incident finstack#60 (see below).
7. **Never weaken JWT validation** in `functions/loans/utils/validate_request_v2.go` — incident finstack#71.
8. **Loan-computation changes require golden verification** before merge — PR finstack#33 history; recipes in `finstack-loan-engine-and-reporting-campaign`.
9. **Never push `master` directly** — it deploys the Go backend and the app to production (root CLAUDE.md rule).

Rules 1–5 are the maintainer's five unwritten discipline rules (confirmed
2026-07-07), now written. Details and incident evidence below.

## Branch → environment → deploy mapping

Push deploys. PRs never deploy to a live channel. Verified in
`.github/workflows/` (all deploy jobs are gated `if: github.event_name == 'push'`;
the app dev workflow additionally requires `github.ref == 'refs/heads/develop'`).

| Branch | Environment | Firebase project | Firestore prefix | What deploys on push |
|---|---|---|---|---|
| `develop` (default) | development | `loooans-dev-stg` | `dev_` | Go functions + web app to `develop` hosting target |
| `release/**` (functions) / `release/v*` (app) | staging | `loooans-dev-stg` | `stg_` | Go functions + web app to `staging` hosting target |
| `master` | production | `loooans-prod` | none | Go functions + web app to `production` hosting target |

- On PR: functions workflows run build+test only; app workflows build web and
  deploy a **Firebase Hosting preview channel** (temporary URL posted on the
  PR) — that is a preview, not an environment deploy.
- On push to `develop`: a bot job commits `chore(version): bump to 1.0.2-dev.N+<epoch>`
  before the live deploy. Don't be surprised by bot commits on develop.
- Workflows are path-filtered: functions workflows fire on `functions/loans/**`,
  app workflows on `apps/loans/**` + `packages/**`. A packages-only change
  redeploys the app, not the functions.
- **Release-branch naming trap:** functions staging matches `release/**` but the
  app staging workflow matches `release/v*`. Name release branches
  `release/vX.Y.Z` so both sides deploy. (Verified in
  `loans-functions-staging.yml` vs `loans-app-staging.yml`.)

**Reality check (as of 2026-07-07):** the GitHub remote has **no `master` and no
`release/*` branches** — the staging and production CI lanes have never fired
from this repo. A branch `main` exists but is a dead vestige of the monorepo
genesis, frozen at `e8574e4` (2026-02-12); never target it. The first
`release/**` or `master` push will be a first-time event with known open
prerequisites — prod RTDB rules and prod console Firestore rules are
undeployed, and MEMORY notes flag a still-pending prod Secret Manager accessor
grant (UNVERIFIED against live IAM; check before deploying) — see
`finstack-run-deploy-operate` and `finstack-security-hardening`. Do not create
`master` casually; when
production goes live, `master` should be created from a reviewed release state,
never by direct push of work-in-progress.

## Change classification — what process does my change need?

| Class | Examples | Process |
|---|---|---|
| **A. Single-side code change** | Flutter UI fix, one Go handler fix, test-only, docs | One feature branch → one PR into `develop`. Merge commit (not squash). |
| **B. Doc-shape / cross-side change** | New Firestore field, renamed key, new collection, anything both Go and Flutter parse | **Two PRs, backend first** (see next section). |
| **C. Console-side change** | Firestore/Storage security rules, console-managed indexes | Make the console change AND land a repo note (see "Console changes"). |
| **D. Prod-touching** | First prod deploy, prod data correction, prod rules | Everything above **plus**: no hand edits (rule 1), fix data via the producer or a reviewed, committed migration, record in MEMORY.md. Treat as an event, not a task. |
| **E. Loan-math / reporting** | `loan_calculation_service.dart`, schedule math, `triggers/loan_changes.go` | Class A/B process **plus** the golden-verification gate — `finstack-loan-engine-and-reporting-campaign`. |
| **F. Security-sensitive** | `validate_request_v2.go`, OTP flow, rules, anything credential-adjacent | Class A/B process **plus** review against `finstack-security-hardening` invariants. |

## Backend-first PR discipline (Class B)

Never ship a Firestore document-shape change in Go or Flutter alone. Split into
two PRs and land the **backend (Go) PR first**, let it deploy to the target
environment, then land the frontend (Flutter) PR. Rationale: deployed triggers
must already tolerate the new shape before any client writes it, and clients
must never write shapes the deployed triggers can't read. The producer/consumer
drift that motivates this is the Timestamp saga (PRs finstack#47/#48/#49 —
full story in `finstack-failure-archaeology`).

Verified precedent (merge order from `git log`):

| Backend PR (first) | Frontend PR (second) | Feature |
|---|---|---|
| finstack#44 (2026-05-06) | finstack#45 (2026-05-11) | Mobile verification |
| finstack#66 (2026-06-17) | finstack#65 (2026-06-18) | Borrower payment submission |
| finstack#70, #72 (2026-06-19+) | finstack#73 (2026-06-30) | User provisioning |
| finstack#83 (merged 2026-07-03) | finstack#84 (open as of 2026-07-07) | Chat |

Convention: title the pair like PR finstack#83/#84 —
`feat(chat): backend — … (1/2, deploy first)` / `feat(chat): frontend — … (2/2)`.
A monolithic full-stack PR is a known dead end: PR finstack#43 was closed
unmerged and re-split into #44/#45.

Step-by-step runbook (branch names, deploy confirmation, anti-patterns):
`references/class-b-walkthrough.md` in this skill.

## Console changes require a repo note (Class C)

Ground truth (verified 2026-07-07): `apps/loans/firestore.rules` is the stale
VGV template (expired 2024-06-22, untouched since the genesis commit `275ad55`),
`apps/loans/storage.rules` is deny-all, and `apps/loans/firebase.json` has **no
`firestore.rules` key** — real Firestore/Storage rules live only in the Firebase
console. Deploying the in-repo files as-is would break the app. Until the
rules-into-source campaign lands (`finstack-security-hardening`), every console
rule or index change MUST leave a repo trace, or the authorization model is
unrecoverable by the next engineer. Acceptable traces, in order of preference:

1. A `.reference` rules file capturing the exact rules text — precedent:
   `apps/loans/firestore.rules.chat.reference`, `storage.rules.chat.reference`
   (commit `3d94ccc`).
2. A MEMORY.md entry stating what changed, in which project(s)
   (`loooans-dev-stg`, `loooans-prod`), and why — precedent: the mobile-verification
   90-day-lock notes in root `MEMORY.md`.
3. A README/docs note with deploy instructions — precedent: commit `96057c6`
   (split RTDB rules into `database.rules.json` + `database.rules.prod.json`).

RTDB rules ARE source-controlled (`apps/loans/database.rules.json` dev-stg,
`database.rules.prod.json` prod) — change those in the repo, not the console;
note that nothing auto-deploys the prod file (see `finstack-run-deploy-operate`).

## The five unwritten rules — rationale and incidents

**1. Never hand-edit prod data.** Manual writes bypass every invariant the code
enforces (dates as int64 millis, self-ID convention, denormalized fields) and
they FIRE TRIGGERS: a hand-edited loan doc runs `loanChanges` and mutates RTDB
report aggregates, which are non-transactional read-modify-write and cannot be
trivially recomputed. The Timestamp saga proved bad docs linger: contaminated
user docs forced permanent defensive parsing in the Flutter client even after
the producers were fixed (root `MEMORY.md`, "Date/Timestamp Convention"). If
prod data is wrong: fix the producer, then correct data via a reviewed,
committed migration/script, and record it in MEMORY.md.

**2. Doc-shape changes ship both sides, backend first.** See the section above.

**3. Console rule changes require a repo note.** See the section above.

**4. New/touched Go handlers use adapter+core with fakes.** Established on PR
finstack#44 and used by every Go PR since (`VerifyOtpCore`,
`HandleUserChangedCore`, `HandleMessageWrittenCore`, …). Pre-pattern monolithic
triggers get converted when touched, not in bulk. Recipe and fakes module:
`finstack-testing-and-validation`.

**5. Dev/staging builds never point at prod unless genuinely needed.** Dev and
staging share `loooans-dev-stg`; prod is a separate project. Cross-pointing a
build invites accidental prod writes (a rule-1 violation by accident) and
identity drift — the keyless-ADC fix (`ae0789d`) also fixed a latent bug where
**prod functions were using the dev-stg key**. If you genuinely must point a
local build at prod (e.g., verifying a prod-only incident read-only), say so in
the session record and use the production flavor deliberately:
`--flavor production --target lib/main_production.dart`.

## Incident-derived non-negotiables

**Never commit credentials — finstack#60 (2026-06-11, commit `ae0789d`).** A
service-account private key was hardcoded in `initialize_firebase.go`. Google's
scanner detected and disabled it (`SERVICE_ACCOUNT_KEY_DISABLE_REASON_EXPOSED`);
every Admin SDK call started failing `Unauthenticated`. Fix: keyless ADC —
`firebase.NewApp(ctx, conf)` with no credentials option; functions run as their
runtime service account. Consequences for you: never re-embed or re-enable a
key; local Go runs authenticate out-of-band via
`gcloud auth application-default login`; anything key-shaped in a diff is a
merge-blocker. (A related open finding — an expired-but-real OIDC JWT in a
comment at `job/subscription_job.go:18` — is tracked in
`finstack-security-hardening`.)

**Never weaken JWT validation — finstack#71, fixed by PR finstack#74 (commit
`84d3c82`).** `ValidateRequestV2` used to fall back to `jwt.ParseUnverified` on
verification failure — an attacker could forge a token claiming any admin's uid
and pass auth on every HTTP function. The fallback is gone: on `VerifyIDToken`
error → log, 401, return. Any diff touching `utils/validate_request_v2.go` or
adding a "tolerant" auth path is security-critical and needs explicit
justification against this incident.

**Loan-computation changes require golden verification — finstack PR #33
history.** The first real bug fix in this repo (issue finstack#4) had THREE
independent root causes in open-term additional-loan math, invisible without
recomputing schedules by hand. Loan math is the declared hardest live problem.
Before merging any change to schedule/interest/balance computation, run the
golden-scenario verification described in
`finstack-loan-engine-and-reporting-campaign`; "tests pass" alone is not
evidence (coverage there is thin).

## Commit and PR conventions (verified from history)

- **Conventional Commits**: `type(scope): summary`. Observed types (frequency
  order): `feat`, `fix`, `chore`, `docs`, `ci`, `refactor`, `test`, `style`.
  Observed scopes: `functions`, `app`, `loans`, `chat`, `hosting`, `version`.
- **Body = symptom → cause → fix narrative.** Exemplars worth imitating:
  `ae0789d`, `84d3c82`, `4e2b36a`. State what the user saw, the mechanism, and
  what the change does — future archaeology depends on this.
- **Co-author trailer** when Claude co-authors:
  `Co-Authored-By: Claude <model name> <noreply@anthropic.com>` (present on
  every substantive commit in history).
- **Merge commits, NOT squash.** PRs merge into `develop` with a merge commit;
  feature-branch commits are preserved. Do not squash-merge — the per-commit
  bodies are the project's archaeology.
- PRs target `develop` (the default branch). No PR/issue templates exist
  (verified: none under `.github/`).
- **Commit only when asked; push only when asked** (`apps/loans/CLAUDE.md`).
- **Ticket references must name the repo of origin**: `finstack#NN` for this
  repo, `loooans#NN` for the pre-2026-02 archive repos (`loooans-flutter`,
  `loooans_cloud_functions`). The two numbering universes collide (e.g. "#47"
  is a loooans reviews issue AND finstack's Timestamp PR) — collision table in
  `finstack-failure-archaeology`. All future tickets are filed on finstack.
  loooans#130–#134 do not exist on GitHub; they are still-wanted follow-ups to
  be refiled on finstack (`finstack-roadmap-and-frontier`).

## MEMORY.md update duty

The root `CLAUDE.md` ("Session Memory") defines the three files and their
scopes — root for cross-project/CI/decisions, `apps/loans/MEMORY.md` for app
work, `functions/loans/MEMORY.md` for backend work — and mandates updating the
relevant one(s) **before ending a session**. Change-control additions:

- The MEMORY.md update rides in the same branch/PR as the change it records.
- Annotate every ticket number with its repo (`finstack#NN` / `loooans#NN`) —
  existing entries predate this rule and are ambiguous.
- MEMORY files go stale; trust the repo over the memory (known stale claims as
  of 2026-07-07: Flutter "3.38.4", "9 app-level BLoCs", and root
  `MEMORY.md`'s claim that firestore.rules is "now source-controlled" — the
  file has never been updated since genesis; only the export intent was real).
- Ignore MEMORY/CLAUDE copies under `.worktrees/` and `.claude/worktrees/` —
  canonical files live at root, `apps/loans/`, `functions/loans/`.

## Pre-merge gate (run before opening/merging any PR)

```bash
# From the repo root — read-only preflight (branch, secrets scan, reminders):
.claude/skills/finstack-change-control/scripts/preflight.sh
```

Then, per side touched:
- **Go** (`functions/loans/`): `go build -v ./...` and `go test -v ./...`
  (macOS: prefix `CGO_ENABLED=0` — see `finstack-build-and-env`). New handler?
  Adapter+core + fakes (rule 4). Registered in `loooans_cloud_functions.go`
  `init()` AND added to `.github/scripts/deploy_functions.sh`? (Both required —
  the script is a hand-maintained list; `sometest` is registered but
  deliberately not deployed.)
- **Flutter** (`apps/loans/`, `packages/`): `fvm flutter analyze` on touched
  paths; `fvm flutter test` (two pre-existing package-test failures are known —
  `finstack-testing-and-validation`).
- **Doc shape touched?** → Class B: is this the backend PR, and does the
  frontend PR exist as a follow-up? Dates written as int64 millis
  (`.UnixMilli()` in Go)?
- **Rules/indexes touched in console?** → repo note landed (Class C)?
- **Loan math touched?** → golden verification done (Class E)?
- **MEMORY.md updated** in the same branch?

## Provenance and maintenance

Authored 2026-07-07 from direct repo inspection (workflows, deploy script,
git history, live `gh` queries) plus the maintainer's confirmed discipline
rules. Volatile facts are date-stamped. Re-verify with:

```bash
# Branch → env mapping and push-only deploy gates
grep -n -A2 "branches:" .github/workflows/loans-functions-*.yml | head -30
grep -n "if: github.event_name" .github/workflows/*.yml

# Remote branch reality (does master / release/* exist yet?)
gh api "repos/anatechopc/finstack/branches?per_page=100" --paginate --jq '.[].name'

# Chat frontend PR state (open as of 2026-07-07)
gh pr view 84 --json state,mergedAt

# Merge-commit (not squash) convention still holding
git log --merges --oneline -5 origin/develop

# firestore.rules still the untouched genesis placeholder?
git log --oneline -- apps/loans/firestore.rules

# Backend-first precedent (merge order)
git log --all --format="%h %ad %s" --date=short --grep="pull request #44\|pull request #45"
```
