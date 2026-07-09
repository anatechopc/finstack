---
name: finstack-failure-archaeology
description: Use for the incident, history, and reasoning behind a finstack pattern rather than a live fix — the postmortem chronicle of the repo's sagas, re-fix chains, and dead ends. Triggers — a ticket number in MEMORY.md or a commit message does not match what gh shows (the loooans#NN vs finstack#NN numbering-universe collision); git blame leads to a weird-looking guard, convention, or invariant and you need the incident behind it before changing it; refiling old follow-up tickets; writing a postmortem; or you already triaged a live symptom in finstack-debugging-playbook and now need the full incident story behind it. For live symptom-to-fix triage (Timestamp TypeError, stuck loading dialog, blank-in-release, Unauthenticated, CI "Premature close", etc.), go to finstack-debugging-playbook.
---

# finstack Failure Archaeology

The chronicle of every saga, re-fix chain, dead end, and incident in the finstack
repo (`anatechopc/finstack`), each as symptom -> root cause -> evidence -> status.
Commit bodies in this repo are themselves detailed postmortems — this skill is the
index into them.

Definitions used below:
- **Saga**: a named incident with a story worth knowing before touching the area.
- **Re-fix chain**: a sequence of fix-the-fix commits on one symptom (there are
  ZERO true `git revert` commits in this repo — instability always shows as chains).
- **Dead end**: a closed-unmerged PR whose approach was replaced, not reverted.

**When NOT to use this skill:**
- Live triage of a current bug -> `finstack-debugging-playbook` (it points back here per trap).
- The rules these incidents produced (never touch prod data, backend-first, etc.) -> `finstack-change-control`.
- Open security findings and their fix menus -> `finstack-security-hardening`.
- The loan-computation/reporting campaign (the hardest live problem) -> `finstack-loan-engine-and-reporting-campaign`.
- Invariants as forward-looking contracts (date-as-millis, prefixes) -> `finstack-architecture-contract`.

---

## 1. THE TICKET-NUMBERING UNIVERSES (read before trusting any #NN)

There are TWO GitHub numbering universes, and MEMORY.md files freely cite the old one:

| Universe | Repo | Role |
|---|---|---|
| `loooans#NN` | `anatechopc/loooans` (Flutter; root MEMORY.md calls it "loooans-flutter" — that repo name does not exist on GitHub) | Historical archive + old issue tracker. Consult for pre-2026-02 investigations. |
| `loooans_cloud_functions#NN` | `anatechopc/loooans_cloud_functions` (Go) | Historical archive (only 7 issues; rarely cited). |
| `finstack#NN` | `anatechopc/finstack` | Current repo. **All future tickets are filed here** (maintainer policy, 2026-07-07). |

`gh` shares one integer space for issues+PRs per repo, so old-universe citations
collide with unrelated finstack items. Verified mapping (2026-07-07):

| Cited in MEMORY.md as | Actually means (anatechopc/loooans) | Collides with in finstack |
|---|---|---|
| issue #13 (mobile verification) | loooans#13 "Verify user mobile number" (CLOSED) | finstack issue #13 "advance dates on SOA" (OPEN) |
| issue #47 (reviews) | loooans#47 "implement reviews functionality" (CLOSED) | finstack PR #47 Timestamp login fix (MERGED) |
| issue #61 (chat spec) | loooans#61 "Enable messaging" (OPEN) | finstack PR #61 CI codegen-cache fix (MERGED) |
| issue #66 (SMS OTP) | loooans#66 "Borrower acknowledgement" (CLOSED) | finstack PR #66 payment confirm/reject notifications (MERGED) |
| issue #68 (remote verification) | loooans#68 "Implement remote verification" (OPEN) | finstack PR #68 user_loan_views rename sync (MERGED) |
| #130–#134 (mobile-verify follow-ups) | loooans#130–#134 — **exist on the loooans repo** (see below) | nothing — finstack numbers don't reach that high (max 84 as of 2026-07-07) |

**loooans#130–#134 ground truth (verified 2026-07-07):** they exist on
`anatechopc/loooans`, NOT on finstack: #130 email-OTP migration (CLOSED),
#131 trusted device (OPEN), #132 SMS OTP rate limits (OPEN), #133 self-service
mobile change during 90-day lock (OPEN), #134 AuthenticationBloc test pattern
(OPEN). Maintainer disposition: still-wanted work, **to be refiled on finstack**
(tracked in `finstack-roadmap-and-frontier`'s refile list). Note the loooans
tracker kept receiving issues even after the code moved (loooans#135 creds
rotation CLOSED, #136 KYC OPEN, #138 chat-deferred backlog OPEN) — when an
unfamiliar reference doesn't resolve on finstack, check the loooans tracker too:

```bash
gh issue view NN -R anatechopc/finstack   # current universe
gh issue view NN -R anatechopc/loooans    # old universe
```

**Rule for anything you write:** annotate every historical ticket reference with
its repo of origin — `loooans#66` vs `finstack#66`. Never bare `#66`.

---

## 2. Era timeline (2026-02-10 -> chat era)

All dates 2026. One human author (`deibeeed`, renders as "I am" in git), every
substantive commit Claude-co-authored. Strict Conventional Commits with
postmortem-quality bodies. Merge commits, not squash.

| Era | Dates | What happened | Anchors |
|---|---|---|---|
| Monorepo genesis | 02-10 | `anatechopc/loooans` + `loooans_cloud_functions` merged into `apps/`, `functions/`, `packages/` | `275ad55` |
| CI/CD hardening | 02-10..12 | build_runner caching/parallelism, parallel function deploy, workflow_dispatch | root MEMORY.md |
| First real fix | 02-16 | principal-balance bug (Saga 1) | `3facda9`, PR finstack#33 |
| SMS OTP campaign | 02-23..03-11 | Android sms-gateway app + RTDB queue + payment OTP | PRs finstack#34/#35/#36; fixes #37/#38 |
| Payment Center | 03-21..04-14 | teller payment center; sparse months (9 commits Mar, 4 Apr) | PR finstack#39 |
| Mobile verification + adapter/core | 05-05..18 | backend-testability inflection; Go adapter+core pattern born | PRs finstack#44/#45..#55 |
| Timestamp firefight | 05-12..14 | Saga 3 | PRs finstack#47/#48/#49 |
| Flutter 3.44 upgrade | 05-25..27 | Saga 12 | PR finstack#56, `b0953b7` |
| Reviews/Payments/Provisioning | 06-02..30 | peak era (108 commits): reviews #57/#58, SA-key incident #60, borrower payments #63..#68, provisioning #69->#70/#72/#73, set-password #76->#77-#80, auth bypass #71/#74, int64 hardening #81, CI #82 | |
| Chat era | 07-01.. | spec `6cd1c25` (loooans#61) + 4 plans in `docs/superpowers/plans/2026-07-01-*`; backend PR finstack#83 MERGED 07-03 (merge `f95eb6e`, GitHub-only — see §5); frontend PR finstack#84 OPEN as of 07-07 | |

---

## 3. The sagas (symptom -> root cause -> evidence -> status)

Full commit-body evidence and per-saga verification commands:
`references/saga-evidence.md`. Verify all citations at once:
`scripts/verify-citations.sh`.

### S1 — Principal balance wrong on consecutive additional loans (finstack#33)
- **Symptom:** adding two+ additional loans to an open-term loan produced wrong principal balance.
- **Root cause — THREE compounding bugs:** (1) AdditionalLoanBloc success handler never called `selectLoan()` -> UI/next loan used stale data; (2) `_handleAddLoanAmountEvent` mutated the last schedule's outstandingBalance while `calculateOpenTerm` ALSO added the amount -> double count; (3) `additionalLoanAmounts` iterated newest-first -> older loans grabbed inflated OB and overwrote schedules.
- **Evidence:** `3facda9` (2026-02-16), PR finstack#33, fixes finstack issue #4. Fix: add `selectLoan()`, delete the OB-mutating microtask, sort by `createdAt` ascending (comment survives at `apps/loans/lib/services/loan_calculation_service.dart`).
- **Status:** FIXED. But loan computation remains the hardest live problem — see `finstack-loan-engine-and-reporting-campaign` before touching this area. Domain math: `loans-domain-reference`.

### S2 — Chain A: the 5-fix loading-dialog whack-a-mole (67 days)
- **Symptom (recurring):** OTP/login/verify loading dialog stuck, never dismissed, or missed states — mostly on web.
- **The chain:** `c4bacd1` (03-03, PR finstack#37: listener mounted after fast API response -> dispatch moved to `initState`) -> `053c141` (03-31: `paymentLoading` status reuse triggered an alien listener's dialog -> dedicated `otpLoading`) -> `ed1b5ef` (04-03: same fix for verify path) -> `27b9695` (05-06: `loading(false)` and route-changing state emitted back-to-back; listener unmounted on route change before popping the dialog, which lives on the ROOT navigator) -> **root fix** `2f4d0b4` (05-06) + `5c80c25` (05-09): abandoned modal dialogs entirely for an inline overlay (ColoredBox + spinner) inside the screen's own Scaffold — no navigator routes, no race with route changes.
- **Root cause (of the whole chain):** dialog-based loading on the root navigator racing GoRouter route changes, compounded by status-enum reuse across listeners.
- **Status:** FIXED by pattern change. The standing rule (inline overlay, never modal loading dialog) lives in `finstack-debugging-playbook` / `finstack-architecture-contract`.

### S3 — Chain B: Timestamp contamination (finstack#47/#48/#49 + #81)
- **Symptom:** web login fails: `TypeError: Instance of 'Timestamp' is not a subtype of type 'num'`.
- **Root cause:** producer/consumer schema drift. Go Admin SDK serializes `time.Time` as a Firestore Timestamp proto; Flutter's generated `fromJson` casts `as num?`. `verify_otp.go` wrote `updated_at`/`mobile_verified_at` as `time.Time`; `notification_helpers.go` did the same for EVERY notification doc.
- **The chain:** `de0f7e9` (05-12, PR finstack#47: client-side tolerance — helpers accept num OR Timestamp) -> `46c7f39` (05-13, PR finstack#48: fix producer `verify_otp.go` -> `.UnixMilli()`) -> `8a983e8` (05-13, PR finstack#49: fix producer `notification_helpers.go`) -> `4e2b36a` (06-24, merged 06-30 in PR finstack#81: consolidate coercion into `utils.ToInt64`, fails closed on Timestamp).
- **Status:** producers FIXED; **client tolerance is PERMANENT** because pre-fix documents were contaminated with real Timestamp values and never backfilled — removing the tolerance re-breaks login on old docs. The forward invariant (all dates int64 millis; Go always `.UnixMilli()`) is owned by `finstack-architecture-contract`.

### S4 — OTP payment silently creates no payment document (finstack#38)
- **Symptom:** teller runs an OTP-verified payoff; everything looks fine; no payment document exists.
- **Root cause:** `Payment.create()` throws when `bypassPaymentProof` is false and no photo/signature is provided; the OTP path passed `false` and the throw surfaced nowhere in the flow.
- **Evidence:** `2fa151e` (03-11, PR finstack#38). Fix: `bypassPaymentProof: event.force || event.otpVerified` — still live at `apps/loans/lib/features/loans/bloc/payment_bloc.dart:161` and `payment_center_bloc.dart:658/865` (guard at `packages/loans/payment_repository/lib/src/model/payment.dart:23`). Same commit also added the first real RTDB rules.
- **Status:** FIXED. Trap generalizes: repository factories that throw inside bloc handlers can fail silently — see `finstack-debugging-playbook`.

### S5 — SECURITY: committed SA private key -> total backend outage (finstack#60)
- **Symptom (2026-06-11):** `requestOtp` returns 500 ("verify mobile number" fails); ALL Admin SDK calls fail `rpc error: code = Unauthenticated`.
- **Root cause:** a service-account private key was hardcoded in `functions/loans/utils/initialize_firebase.go`; Google's secret scanner detected it and auto-disabled the key (`SERVICE_ACCOUNT_KEY_DISABLE_REASON_EXPOSED`), killing every function in every environment at once.
- **Evidence:** `ae0789d`, PR finstack#60. Fix: keyless ADC — `firebase.NewApp(ctx, conf)` with no credentials option (runtime SA via metadata server); `deploy_functions.sh` deploys each function with the discovered `firebase-adminsdk-*` `--service-account`. Also fixed a latent bug: prod had been using the dev-stg key.
- **Status:** FIXED; the key stays disabled (never rotated back). Related still-open finding (real expired OIDC JWT in a comment in `job/subscription_job.go`) -> `finstack-security-hardening`.

### S6 — SECURITY: auth bypass via ParseUnverified fallback (finstack#71 -> PR #74)
- **Symptom:** none observed — found by reading. Every HTTP function (requestOtp, verifyOtp, addUser, sendEmail) would accept a forged token.
- **Root cause:** `ValidateRequestV2` verified the Firebase ID token but on failure fell back to `jwt.ParseUnverified`, accepting any unsigned JWT whose `aud` matched the IdentityToolkit constant — an attacker could claim any admin's uid.
- **Evidence:** `84d3c82` (06-22), finstack issue #71 (CLOSED), PR finstack#74. Fix: remove the fallback (401 on verify error); refactor the sole dependent caller (userCreated self-call) to send email in-process; delete dead v1 `ValidateRequest` + `CustomTokenClaims`.
- **Status:** FIXED. Security invariants derived from S5+S6 -> `finstack-security-hardening`.

### S7 — Bank-details query matched nothing: `data_id` vs `dataId` (no ticket)
- **Symptom:** borrower payment-submit dialog: lender bank details never load; Send button permanently disabled. No error anywhere.
- **Root cause:** `BankDetailsEntity.dataId` has no `@JsonKey`, so it serializes camelCase (`dataId`) while sibling fields are snake_case; the dialog queried `data_id` — a Firestore query on a nonexistent field silently returns empty.
- **Evidence:** `e14592a` (06-17, part of the finstack#64 payment campaign).
- **Status:** FIXED. Trap: never assume snake_case — check the entity's generated `.g.dart` for the actual stored field name.

### S8 — Open-term NO_ID update + composite-index retry loop (no ticket)
Two adjacent landmines from the borrower-payment campaign (both 06-17):
- **`832eaf4`:** open-term payments start with `loan_schedule_id = NO_ID`; code called `update()` on a nonexistent schedule doc (throws). Fix: replicate teller add-then-backfill persistence so the payment links a real schedule id.
- **`18adc31`:** `paymentCreated`'s de-dup query used `submission_id + created_at` ordering -> needs a composite index; missing index = `FAILED_PRECONDITION` which **retry-loops a Firestore trigger forever**. Fix: equality-only query (auto single-field index), compute earliest in code. Same commit: lender-only guard on confirm/reject.
- **Status:** both FIXED. Standing traps (NO_ID lifecycle, trigger queries must not need composite indexes unless the index ships first) -> `finstack-debugging-playbook`; index deploy reality -> `finstack-run-deploy-operate`.

### S9 — Blank loan detail in RELEASE builds only (PR finstack#62; relates OPEN finstack#31)
- **Symptom:** loan-detail panel renders in local debug, blank on web hosting (release) builds.
- **Root cause:** `Expanded` inside a `ConstrainedBox` (not a Flex). Debug builds catch the ParentDataWidget assertion and recover; release strips assertions, so RenderFlex's `parentData as FlexParentData` cast throws and blanks the panel.
- **Evidence:** `d84b628` (06-16), PR finstack#62.
- **Status:** that instance FIXED. finstack issue #31 "Page does not load on production AND/OR on release build" is still OPEN (as of 2026-07-07) — release-only blanks are a recurring class; triage recipe in `finstack-debugging-playbook`.

### S10 — Login crash on legacy user docs (no ticket)
- **Symptom:** some users crash during login deserialization: `$enumDecode` on null `sex` ("Supported values: male, female") or `EmploymentDetails.fromJson(null)`.
- **Root cause:** old/incomplete user documents predate these fields; the two fields were the only nested ones without null guards.
- **Evidence:** `dfba3e6` (06-10), PR finstack#59. Fix: `Sex.other` default via `@JsonKey(defaultValue/unknownEnumValue)`; null-guard EmploymentDetails.
- **Status:** FIXED. Trap: prod data is older than the schema — every new required field needs a legacy-doc story (see `finstack-change-control` rule 2, schema changes both sides).

### S11 — CI hosting deploys redden: 'Premature close' (PR finstack#82)
- **Symptom (06-2x):** Firebase Hosting deploy jobs fail after the ubuntu-24.04 runner image bump; the deploy actually LANDED (the failing release POST returns "is the current active version").
- **Root cause:** Node 20+ Happy-Eyeballs (`autoSelectFamily`) IPv6/IPv4 race on a runner with a broken IPv6 path to Google; every first request premature-closes; the one non-idempotent POST can't retry.
- **Evidence:** `5b91797` (06-30), the sole commit of PR finstack#82. Fix: `NODE_OPTIONS=--no-network-family-autoselection` on each hosting deploy step; Node 24 + latest firebase-tools.
- **Status:** FIXED. If it recurs, check the runner-image changelog first — `finstack-run-deploy-operate` owns workflow anatomy.

### S12 — Flutter 3.38.4 -> 3.44.0 upgrade fallout (PR finstack#56)
- **Headline trap — versionCode overflow:** `scripts/bump_version.sh` used millis-since-epoch (13 digits) as Android versionCode, > `Integer.MAX_VALUE`. Old AGP silently truncated; AGP 8.11.1 rejects ("For input string: ..."). Fix: `date +%s` seconds (valid until 2038). **Never switch it back to millis.**
- **Second trap — SPM vs path with a space:** Flutter 3.44 auto-enables Swift Package Manager, which broke on the old checkout path `.../Anaheim Technologies/...` (`%20`) -> **the repo was relocated to `/Users/deibeeed/Projects/AnaheimTechnologies/finstack`**. Keep it on a space-free path.
- **Also:** AGP 8.11.1 / Kotlin 2.2.20 / Gradle 8.14.3 / SDK 36 / Java 17 / jvmargs 4096M; impossible `>=2.18.0 <3.0.0` Dart constraint widened; 54 `withOpacity` -> `withValues`.
- **Evidence:** `b0953b7` (05-25), PR finstack#56.
- **Status:** DONE. Residuals still open as of 2026-07-07: iOS unverified locally (no CocoaPods on the dev box, Podfile.lock needs a Mac refresh); 5 plugins on KGP; 3 iOS plugins not on SPM -> tracked in `finstack-roadmap-and-frontier`. Toolchain setup -> `finstack-build-and-env`.

---

## 4. Dead ends (closed-unmerged PRs — approaches replaced, never reverted)

| Closed PR | Was | Superseded by | Lesson |
|---|---|---|---|
| finstack#43 | monolithic mobile-verification (full-stack in one PR) | finstack#44 (backend) + #45 (frontend) | birth of the backend-first split discipline (`finstack-change-control`) |
| finstack#69 | client-side fix for finstack issue #2 (creating a user replaced the admin's session — client `createUserWithEmailAndPassword` swaps the auth session) | finstack#70/#72 (server-side `addUser` + hosting rewrites) + #73 (frontend) | fix identity problems server-side |
| finstack#76 | branded Firebase **hosted** auth-action page (branch deleted) | finstack#77/#78/#79/#80 self-hosted `/set-password` (token store + endpoint + rewrite + page) | own the auth UX end-to-end |
| finstack issue #63 | OPEN duplicate of CLOSED issue #64 (borrower payment submission — shipped via PRs #65/#66/#67/#68) | — | housekeeping candidate: close #63 as dup |

Related branch archaeology: merged branches are never pruned (local or remote) —
the branch list is a historical record, NOT live work. `backup/review-responses-combined`
is a local-only safety backup from splitting reviews into finstack#57/#58.
`.worktrees/` and `.claude/worktrees/` contain STALE duplicate MEMORY/CLAUDE
copies — canonical files live at root, `apps/loans/`, `functions/loans/`.

---

## 5. Digging further (and the stale-refs trap)

**Local `origin/*` refs lag GitHub.** As of 2026-07-07 the local clone's
`origin/develop` (`5e74d69`) predates the finstack#83 merge (`f95eb6e`, GitHub-only).
Before trusting refs: `git fetch origin`. For PR/issue state, prefer `gh` (live)
over local refs.

```bash
cd /Users/deibeeed/Projects/AnaheimTechnologies/finstack
git log --all --oneline --grep='<keyword>'         # find incidents by keyword
git log -1 --format='%B' <hash>                    # commit bodies ARE the postmortems
git log --follow --oneline -- <path>               # churn history of a file
gh pr list -R anatechopc/finstack --state all --limit 100
gh issue list -R anatechopc/finstack --state all --limit 100
```

Old-universe deep dives (pre-2026-02 code questions): clone or browse
`anatechopc/loooans` / `anatechopc/loooans_cloud_functions` read-only.

---

## 6. Lessons index (where each standing rule now lives)

| Saga | Standing rule | Primary home |
|---|---|---|
| S1 | additional loans sorted by `createdAt` asc; recompute-by-hand before trusting schedule math | `loans-domain-reference`, `finstack-loan-engine-and-reporting-campaign` |
| S2 | inline loading overlays, never modal dialogs on the root navigator | `finstack-debugging-playbook` |
| S3 | all dates int64 millis; Go writes `.UnixMilli()` only; client tolerance stays | `finstack-architecture-contract` |
| S4/S7/S8 | silent-failure traps (swallowed throws, wrong field names, NO_ID, trigger index needs) | `finstack-debugging-playbook` |
| S5/S6 | keyless ADC only; no secrets in source; verify-or-401 | `finstack-security-hardening` |
| S9 | release-only rendering failures triage | `finstack-debugging-playbook` (finstack#31 OPEN) |
| S10 | schema changes both sides + legacy-doc tolerance | `finstack-change-control` |
| S11/S12 | CI/toolchain trap details | `finstack-run-deploy-operate`, `finstack-build-and-env` |
| #43/#69/#76 | backend-first PR splits; server-side fixes for identity | `finstack-change-control` |

---

## Provenance and maintenance

Authored 2026-07-07 from direct repo inspection: every commit hash confirmed via
`git log`, every PR/issue number and state confirmed via `gh` against
`anatechopc/finstack` and `anatechopc/loooans`, code anchors grepped on branch
`feature/chat-messaging`. Historical narratives (fixed sagas) are stable; the
items below drift.

Re-verify volatile facts:

```bash
# all cited hashes still resolve + PR/issue states still match this skill
bash /Users/deibeeed/Projects/AnaheimTechnologies/finstack/.claude/skills/finstack-failure-archaeology/scripts/verify-citations.sh

# chat era: is frontend PR still open?
gh pr view 84 -R anatechopc/finstack --json state,mergedAt

# S9 recurrence class: is finstack#31 still open?
gh issue view 31 -R anatechopc/finstack --json state

# refile list: are loooans#131-#134 still open / not yet refiled on finstack?
for n in 131 132 133 134; do gh issue view $n -R anatechopc/loooans --json number,state --template '{{.number}} {{.state}}{{"\n"}}'; done

# stale-refs caveat still true? (compare local develop tip vs GitHub)
git -C /Users/deibeeed/Projects/AnaheimTechnologies/finstack log -1 --format=%h origin/develop; gh pr view 83 -R anatechopc/finstack --json mergeCommit --template '{{.mergeCommit.oid}}'
```

If a saga gets a sequel (new commit on the same symptom), append it to the
saga's chain here — do not start a parallel story in a sibling skill.
