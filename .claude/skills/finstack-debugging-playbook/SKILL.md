---
name: finstack-debugging-playbook
description: "Use when something in finstack is broken and you need to triage: TypeError 'Instance of Timestamp' is not a subtype of type 'num'; a loading overlay/dialog that never dismisses; a Firestore query silently returning nothing; a page blank only in release/prod builds; Go tests failing on macOS with dyld LC_UUID; Gradle OOM; iOS/SPM path errors; CI hosting deploy 'Premature close'; requestOtp 500 or Admin SDK Unauthenticated; FCM push not arriving; OTP SMS marked sent but never delivered; RTDB report totals wrong; stale origin/* refs; pre-existing package test failures; functions dying at startup with 'Runtime environment not defined'; or when you need to read Cloud Functions logs."
---

# finstack Debugging Playbook

Symptom-first triage for the finstack monorepo (Flutter app `apps/loans/`, Go Cloud
Functions `functions/loans/`, SMS gateway `apps/sms-gateway/`). Find your symptom in
the table, run the discriminating experiment, follow the fix pointer. Deep
experiments live in `references/triage-details.md`; log-reading in
`references/cloud-functions-logs.md`.

**When NOT to use this skill:**
- Full incident narratives / why a bug happened historically → `finstack-failure-archaeology`
- Loan-computation correctness or the reporting rebuild (fixing, not just diagnosing) → `finstack-loan-engine-and-reporting-campaign`
- Setting up a dev environment that never worked → `finstack-build-and-env`
- Deploying, CI workflow anatomy, index/rules deploys → `finstack-run-deploy-operate`
- Env/project/prefix mechanics → `finstack-config-and-environments`
- Security findings and rules-into-source work → `finstack-security-hardening`
- Change gating before you ship a fix → `finstack-change-control`

Jargon used below (defined once):
- **Prefix** — Firestore collection prefix per environment: `dev_` / `stg_` / none
  (prod). Go: `utils.GetCollectionPrefix()`. RTDB uses bare `dev` / `stg` nodes
  instead (`getPathEnv()` in `triggers/loan_changes.go`). Details: `finstack-config-and-environments`.
- **ADC** — Application Default Credentials; the Go functions use keyless ADC (runtime
  service account), never embedded keys.
- **Ticket universes** — `loooans#NN` = old archive repos (loooans-flutter,
  loooans_cloud_functions); `finstack#NN` = current repo. Same integers, different
  meanings. Full map: `finstack-failure-archaeology`.

## Triage table

| # | Symptom | Likely cause | Discriminating experiment | Fix pointer |
|---|---------|--------------|---------------------------|-------------|
| 1 | `TypeError: Instance of 'Timestamp' is not a subtype of type 'num'` (often breaks web login) | A Go producer wrote `time.Time` into Firestore (Admin SDK serialises it as a Timestamp proto), OR a legacy doc polluted before PRs finstack#48/#49 | Open the failing doc in Firebase console: is the field a Timestamp type? Then grep the Go writer for that field — does it use `.UnixMilli()`? Clean producer + Timestamp doc = legacy pollution | Producer: convert with `.UnixMilli()` (never write `time.Time`). Consumer: route dates through `handleDateTimeFromJson` helpers (Timestamp-tolerant since finstack#47). Story: Chain B in `finstack-failure-archaeology` |
| 2 | Loading overlay/dialog stuck, never dismisses (esp. web, around login/OTP) | Modal-dialog loading racing a GoRouter route change; or loading-off emitted back-to-back with a routing state so the listener unmounts first | Is loading shown via `showDialog`? Does the bloc emit `loading(false)` immediately before a state that triggers navigation, with no yield between? | Never use modal dialogs for loading — use the inline `Positioned.fill` overlay pattern (`login_screen.dart` ~line 70) and yield `await Future<void>.delayed(Duration.zero)` before routing emits (`authentication_bloc.dart:192-196`). Story: Chain A (5 fixes, 67 days) in `finstack-failure-archaeology` |
| 3 | Firestore query silently returns nothing (no error, feature just dead) | Field-name mismatch: house style is snake_case, but entity fields WITHOUT `@JsonKey` serialise camelCase (e.g. `bank_details.dataId`); or missing/wrong collection prefix | Read one real doc (console) and diff its exact field names against the query string; check the entity for `@JsonKey` on that field; confirm the collection name includes the right prefix | Query the stored name (commit e14592a: `'dataId'` not `'data_id'`). Prefix mechanics: `finstack-config-and-environments` |
| 4 | Page/panel blank ONLY in release or prod build (fine in debug) | ParentDataWidget misuse (`Expanded`/`Flexible`/`Positioned` under a non-matching parent): debug recovers from the assertion; release strips it and the cast throws | Repro locally in release: `fvm flutter run -d chrome --release --target lib/main_development.dart`; browser console shows `TypeError: Instance of 'ParentData' is not a subtype of ... 'FlexParentData'` | Remove the misplaced ParentDataWidget (commit d84b628 removed `Expanded` inside a `ConstrainedBox`). finstack#31 still OPEN as of 2026-07-07 — class of bug may have more instances |
| 5 | Go tests fail on macOS: `dyld: missing LC_UUID` | macOS 26.x + cgo linking issue | Run `CGO_ENABLED=0 go test ./...` in `functions/loans/` — passes? Then it's this | Always use `CGO_ENABLED=0` locally; CI (Linux) unaffected |
| 6 | Android build OOM / dex transform failures | Gradle heap too small for this toolchain | Check `apps/loans/android/gradle.properties`: `org.gradle.jvmargs=-Xmx4096M` present? | 4096M is the verified floor at Flutter 3.44 / AGP 8.11 (2048M was not enough). If missing, restore it |
| 7 | iOS/SPM build fails resolving `pubspec.yaml` / `%20` in paths | Flutter 3.44 auto-enables SPM, which URL-encodes the project path — breaks on paths with spaces | Does the repo path contain a space? (`pwd`) | Keep the repo at a no-space path — that is why it lives at `.../AnaheimTechnologies/finstack`. See `apps/loans/MEMORY.md` "SPM is enabled" |
| 8 | CI hosting deploy red with `Premature close` (deploy actually landed) | Node 20+ Happy-Eyeballs IPv6/IPv4 race on GitHub runners vs googleapis.com | Check the job log: requests fail at ~74ms, succeed on retry; check `NODE_OPTIONS: --no-network-family-autoselection` still on the hosting deploy steps in `loans-app-*.yml` | Fix already in place (commit 5b91797, 4 steps across 3 workflows). If it recurs, verify the env var survived workflow edits. Check whether the release actually landed before re-running |
| 9 | `requestOtp` 500, or any function logging `rpc error: code = Unauthenticated` from Admin SDK | Credentials problem: locally, missing/wrong ADC; in cloud, wrong runtime SA (or a disabled key — the finstack#60 incident) | Local: `gcloud auth application-default login`, and beware ADC drift (CLI account ≠ ADC account — see details ref). Cloud: `gcloud functions describe <fn>_<env> --region=asia-east1 --project=<project> --format='value(serviceConfig.serviceAccountEmail)'` — must be the `firebase-adminsdk-*` SA | Keyless ADC is the design (commit ae0789d); NEVER embed or re-enable a key. Story + invariant: `finstack-failure-archaeology` / `finstack-security-hardening` |
| 10 | FCM push not arriving | Break anywhere in the chain: business trigger → `notifications` doc → `notificationCreated` → device tokens → device | Walk the chain in order (see details ref): (a) was a `{prefix}notifications` doc created? (b) `notificationCreated_<env>` logs; (c) `users/{id}/devices` docs have non-empty `token`; (d) device-side. **Chat is different**: `messageWritten` pushes directly via `sendChatPush`, bypassing the notifications collection — check `messageWritten_<env>` logs instead | `triggers/notification_created.go`, `triggers/message_written.go` |
| 11 | RTDB report totals wrong (`{dev\|stg}/companies/{id}/report_summary/...`) | Known `triggers/loan_changes.go` defects: non-transactional read-modify-write races, swallowed errors, double-count, incomplete `completed` branch | Don't experiment on live data. Recompute expected totals from Firestore loans/schedules and diff (recipe: `finstack-loan-engine-and-reporting-campaign`) | Do NOT hand-patch RTDB totals (rule: never touch prod data by hand — `finstack-change-control`). Fixing this is the campaign skill's job |
| 12 | Local `origin/*` refs disagree with GitHub (PR "merged" but branch looks unmerged) | `gh` is live; local `origin/*` refs are as-of-last-fetch | `git ls-remote origin develop` (live SHA) vs `git rev-parse origin/develop` (local ref) | `git fetch origin`. Bit the chat work on 2026-07-04: local `origin/develop` lacked the PR finstack#83 merge |
| 13 | Package tests fail in `address_repository` / `bank_details_repository` | Pre-existing scaffold tests constructing Firestore-backed repos without `Firebase.initializeApp()` | Confirmed pre-existing on `develop` (see `apps/loans/MEMORY.md`, Flutter 3.44 section) — did YOUR change touch these packages? If not, not your regression | Known baseline failure. Test seams and known-failures list: `finstack-testing-and-validation` |
| 14 | Function crashes at startup: `Runtime environment not defined` | `ENVIRONMENT` env var unset (fatal in `loooans_cloud_functions.go:62-63`) | Running locally without `ENVIRONMENT=development`? Deployed without `--set-env-vars ENVIRONMENT=...`? | Set `ENVIRONMENT` (`development`/`staging`/`production`). Deploy script sets it per env — `finstack-run-deploy-operate` |
| 15 | OTP SMS never arrives (RTDB entry says `sms_status: "sent"`) | "sent" only means the radio accepted it — the gateway passes `deliveryIntent = null`, so a carrier-dropped message is indistinguishable from a delivered one. Two known causes: a destination that is not E.164, and any link-like token in the body (PH carriers filter link-bearing P2P SMS) | (a) is `phone` in the entry `+639XXXXXXXXX` (13 chars)? a bare 10-digit is silently discarded by the SMSC; (b) does the body contain an email address, URL, or domain? (c) is the gateway alive — `/gateway_status/{id}.last_heartbeat` under ~90s old? (d) bisect content: send a plain `test` through the gateway, then the real body — if plain arrives and the real one does not, it is content filtering, not the route | `functions/loans/MEMORY.md` "OTP SMS was carrier-filtered on the support address (2026-08-20)". Guarded by `TestRequestOtpCore_MobileObjective_SmsBodyIsCarrierSafe`. Gateway ops: `finstack-run-deploy-operate` §8 |

## Reading Cloud Functions logs (quick version)

All functions are gen2, region `asia-east1`, named `<entryPoint>_<environment>`
(e.g. `loanChanges_development`). Projects: dev+stg → `loooans-dev-stg`,
prod → `loooans-prod`.

```bash
# Wrapper (this skill): function name + env, optional limit
.claude/skills/finstack-debugging-playbook/scripts/fn-logs.sh notificationCreated development 50

# Raw command it runs
gcloud functions logs read notificationCreated_development \
  --region=asia-east1 --project=loooans-dev-stg --limit=50 --gen2
```

Full runbook (Logs Explorer queries, gen2 Cloud Run service names, time windows,
structured-log fields): `references/cloud-functions-logs.md`.

## Triage discipline

1. **Reproduce before fixing.** For release-only bugs that means an actual
   `--release` run; for backend bugs that means the dev environment
   (`loooans-dev-stg`, `dev_` prefix), never prod.
2. **Discriminate before patching.** Most entries above have two candidate causes;
   the experiment column tells them apart. A fix for the wrong cause re-enters a
   re-fix chain (Chain A took 5 attempts — `finstack-failure-archaeology`).
3. **Check the archaeology before "fixing" something odd.** If a behavior looks
   wrong but old, it may be a known open defect (e.g. every `loan_changes.go` item
   in row 11) with a planned campaign — don't spot-patch it.
4. **Never touch prod data by hand, never console-change rules without a repo
   note.** Gating and the full rule list: `finstack-change-control`.
5. **Found and fixed something new?** Update the relevant `MEMORY.md`
   (root CLAUDE.md mandate) and consider adding a row here.

## Trap stories in one line each

Full narratives with commit evidence: `finstack-failure-archaeology`.

- **Chain A (loading dialogs):** 5 fixes over 67 days (c4bacd1 → 5c80c25) until the
  root fix: abandon modal loading dialogs entirely for inline state-driven overlays.
- **Chain B (Timestamp pollution):** client tolerance (de0f7e9) was needed even
  after both producers were fixed (46c7f39, 8a983e8) because existing docs stayed
  polluted; hardened fail-closed in 4e2b36a.
- **e14592a (dataId):** one camelCase field among snake_case siblings kept the
  borrower Send button disabled for weeks — silently.
- **d84b628 (Expanded):** debug builds recover from ParentData misuse; release
  builds blank the whole panel. Demo-day discovery (finstack#31, still OPEN).
- **ae0789d (finstack#60):** committed SA key → Google auto-disabled it → every
  Admin SDK call `Unauthenticated`, first seen as a `requestOtp` 500.
- **2fa151e (loooans#66-era):** OTP payments silently created no payment doc — an
  exception swallowed inside the payment path (`bypassPaymentProof` not set).
- **5b91797:** a runner-image bump made hosting deploys red while deploys actually
  succeeded — infrastructure flakes can look like app regressions.

## Provenance and maintenance

Authored 2026-07-07 from direct repo inspection on branch `feature/chat-messaging`
(HEAD 3d94ccc); all commits, paths, line numbers, and flags verified against the
working tree and `git log` on that date. Line numbers drift — treat them as anchors,
re-grep if they miss.

Re-verification one-liners (run from the repo root):

```bash
# Commits cited exist
git -C /Users/deibeeed/Projects/AnaheimTechnologies/finstack log --oneline -1 e14592a
# ENVIRONMENT fatal still at entry point
grep -n "Runtime environment not defined" functions/loans/loooans_cloud_functions.go
# Timestamp-tolerant date helpers still in place
grep -n "Timestamp" packages/core/loooans_helpers/lib/src/data_helpers/constants.dart
# Inline overlay pattern still in login screen
grep -n "Positioned.fill" apps/loans/lib/features/authentication/screen/login_screen.dart
# Emit-order yield still in auth bloc
grep -n "Future<void>.delayed(Duration.zero)" apps/loans/lib/features/authentication/bloc/authentication_bloc.dart
# Happy-Eyeballs fix still in workflows
grep -rn "no-network-family-autoselection" .github/workflows/
# Gradle heap floor
grep jvmargs apps/loans/android/gradle.properties
# Deploy region/runtime and function name pattern
grep -m1 "gcloud functions deploy" .github/scripts/deploy_functions.sh
# finstack#31 still open?
gh issue view 31 -R anatechopc/finstack --json state
```

Volatile facts: finstack#31 OPEN; `loan_changes.go` defects unfixed; package test
failures pre-existing — all as of 2026-07-07. If the reporting campaign
(`finstack-loan-engine-and-reporting-campaign`) lands, row 11 and its story change.
