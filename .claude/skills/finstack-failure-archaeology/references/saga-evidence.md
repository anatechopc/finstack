# Saga evidence — verified commit-body excerpts and verification commands

Companion to `../SKILL.md` §3. Every excerpt below was read from `git log` in
`/Users/deibeeed/Projects/AnaheimTechnologies/finstack` on 2026-07-07; every
excerpt is quotable in postmortems. To re-read any body:

```bash
git -C /Users/deibeeed/Projects/AnaheimTechnologies/finstack log -1 --format='%B' <hash>
```

---

## S1 — finstack#33 principal balance (`3facda9`, 2026-02-16, fixes finstack issue #4)

Commit body (the three root causes, verbatim):

> 1. The AdditionalLoanBloc success handler did not refresh loan data via
>    selectLoan(), so the UI showed stale schedules and subsequent
>    additional loans used outdated loan data.
> 2. _handleAddLoanAmountEvent mutated the last Firestore schedule's
>    outstandingBalance, which caused double-counting when calculateOpenTerm
>    also adds the amount in its additionalLoanAmounts loop.
> 3. additionalLoanAmounts were processed in array order (newest first),
>    causing older loans to use inflated OB values from newer loans and
>    overwrite their schedules via the lastLoanSchedule mutation.

Anchor today: sort-ascending fix survives in
`apps/loans/lib/services/loan_calculation_service.dart` (search `createdAt`).

---

## S2 — Chain A loading-dialog whack-a-mole

| Commit | Date | Fix attempt |
|---|---|---|
| `c4bacd1` | 03-03 | "Move RequestPaymentOtpEvent dispatch ... into the PaymentOtpDialog's initState (via addPostFrameCallback). This ensures the BlocListener is mounted before the request fires" — dialog missed `otpRequested` when the API responded fast (Firebase Hosting). PR finstack#37. |
| `053c141` | 03-31 | "The OTP request handler was reusing paymentLoading status, which triggered the screen's BlocListener to show a loading dialog that was never dismissed." -> dedicated `otpLoading`. |
| `ed1b5ef` | 04-03 | same `otpLoading` fix for the OTP **verify** path. |
| `27b9695` | 05-06 | "loading(false) immediately followed by the verify state. On web the BlocListener could process the verify state first (route change -> LoginScreen unmounts -> listener detaches), missing the dialog pop. The dialog persisted across the route change because it lives on the root navigator." -> `Future.delayed` yield between emits. |
| `2f4d0b4` | 05-06 | ROOT FIX: "Switched to an inline ColoredBox + CircularProgressIndicator overlay inside the screen's Scaffold body. No navigator routes, no dialog stacking, no race with route changes." |
| `5c80c25` | 05-09 | extends the inline overlay to login + verify screens (full-screen, green spinner). |

Note `2f4d0b4` also records honest uncertainty: "Possibly an interaction with an
unrelated unhandled error in notification_repository (Timestamp deserialization)
blowing up the frame" — i.e., Chain A and Chain B overlapped in time and
symptoms. If you see a stuck overlay AND a Timestamp TypeError, treat them as
two bugs.

---

## S3 — Chain B Timestamp contamination

| Commit | PR | Side | Fix |
|---|---|---|---|
| `de0f7e9` (05-12) | finstack#47 | consumer (Flutter) | `handleDateTimeFromJson`/`handleDateTimeNullableFromJson` accept `dynamic`: num millis OR Firestore Timestamp. Band-aid, now permanent. |
| `46c7f39` (05-13) | finstack#48 | producer (Go) | `verify_otp.go` wrote `updated_at`/`mobile_verified_at` as raw `time.Time` -> `.UnixMilli()`. |
| `8a983e8` (05-13) | finstack#49 | producer (Go) | `buildAndCreateNotification` in `notification_helpers.go` wrote both timestamps as `time.Time` — EVERY notification doc contaminated. |
| `4e2b36a` (06-24, merged 06-30) | finstack#81 | hardening (Go) | one canonical `utils.ToInt64(any) (int64, bool)`; "a Firestore Timestamp fails closed". Replaced dupes in `payment_created.go` + `VerifyOtpCore`. |

Key sentence from `de0f7e9` explaining WHY tolerance stays:

> Existing user docs got contaminated and couldn't be read by the Flutter
> client until the helpers were made permissive.

(That paraphrase is from root `MEMORY.md` §"DateTime fields"; the commit body
itself documents the cast failure:
`handleDateTimeNullableFromJson(json['x'] as num?)` throws on a Timestamp.)
No backfill of contaminated documents was ever run (none found in history as of
2026-07-07), so the permissive read path is load-bearing forever.

Canonical write-side rule + current anchors: `functions/loans/MEMORY.md`
("write timestamps as int64 millis") and `finstack-architecture-contract`.

---

## S4 — finstack#38 silent OTP payment (`2fa151e`, 03-11)

> The Payment.create() factory threw when bypassPaymentProof was false
> and no photo/signature was provided. OTP-verified payments now bypass
> proof validation since the OTP itself serves as borrower confirmation.

Current anchors (grepped 2026-07-07):
- `packages/loans/payment_repository/lib/src/model/payment.dart:16,23` — `bypassPaymentProof = false` default; throw guard.
- `apps/loans/lib/features/loans/bloc/payment_bloc.dart:161` — `bypassPaymentProof: event.force || event.otpVerified`.
- `apps/loans/lib/features/payment_center/bloc/payment_center_bloc.dart:658,865` — same expression.

Same commit also: OTP audit comment logs the borrower (teller as
`processed_by`); first real RTDB security rules wired into `firebase.json`.
Sibling commit `96057c6` (03-11) split prod RTDB rules into
`database.rules.prod.json` (still manually deployed — see
`finstack-run-deploy-operate`).

---

## S5 — finstack#60 committed SA key (`ae0789d`, 06-11)

> A service-account private key was hardcoded in initialize_firebase.go and
> committed to the repo. Google's secret scanner detected it and disabled
> the key (SERVICE_ACCOUNT_KEY_DISABLE_REASON_EXPOSED), so every Admin SDK
> call started failing with `rpc error: code = Unauthenticated` — seen as a
> 500 from requestOtp ("verify mobile number") and affecting all
> functions/triggers that init Firebase.

Fix details from the body: `firebase.NewApp(ctx, conf)` with no credentials
option -> ADC via metadata server; deleted now-unused `types.FirebaseOptions`;
`deploy_functions.sh` discovers the project's `firebase-adminsdk-*` SA and
deploys every function with `--service-account=<it>`; deployer identity needs
`roles/iam.serviceAccountUser` on that SA. "Also fixes a latent bug where prod
used the dev-stg key."

---

## S6 — finstack#71/#74 ParseUnverified fallback (`84d3c82`, 06-22)

> ValidateRequestV2 verified the Firebase ID token but, on failure, fell back
> to jwt.ParseUnverified — accepting an unsigned, unverified JWT as long as
> its `aud` matched the IdentityToolkit constant and `uid` was non-empty. An
> attacker could forge a token claiming any admin's uid and pass auth on every
> HTTP function (requestOtp, verifyOtp, addUser, sendEmail).

Fix: remove fallback (log + 401 + return ""); userCreated self-call refactored
to send its email in-process; deleted `types/custom_token_claims.go` and
`utils/validate_request.go` (v1); `go mod tidy` dropped golang-jwt from
utils/types. Current anchor: `functions/loans/utils/validate_request_v2.go`.

---

## S7 — dataId field-name mismatch (`e14592a`, 06-17)

> BankDetailsEntity.dataId has no @JsonKey, so it serialises to 'dataId'
> (camelCase) while its siblings are snake_case. The submit dialog queried
> 'data_id', which never matched — so lender bank details were never found and
> Send stayed disabled. Query the real field name.

Generalized check: read the entity's generated `*.g.dart` for the true stored
key before writing any Firestore query.

---

## S8 — NO_ID persistence + composite-index retry loop (06-17)

`832eaf4` — open-term (NO_ID) schedules:

> replicate the teller add-then-backfill persistence for open-term (NO_ID)
> schedules so update() is never called on a non-existent doc and the payment
> links to the real schedule id; thread the real loanId through the event

`18adc31` — trigger-side de-dup:

> paymentCreated de-dup uses an equality-only submission_id query (served by the
> automatic single-field index) and computes the earliest payment in code, so no
> composite submission_id+created_at index is needed — avoids a deploy-time
> FAILED_PRECONDITION that would retry-loop the trigger

Plus: `_handleConfirmSubmission`/`_handleRejectSubmission` gated by the same
`CompanyManagementType.selfManaged` check as other teller write-handlers.

---

## S9 — release-only blank panel (`d84b628`, 06-16, PR finstack#62)

> `Expanded` is a ParentDataWidget that writes FlexParentData to its
> child, asserting an ancestor Flex (Row/Column). Here the child's parent
> is the ConstrainedBox, not a Flex. In debug this trips an assertion that
> Flutter catches and recovers from (panel still renders), but in
> profile/release builds assertions are stripped, so RenderFlex's
> `child.parentData as FlexParentData` cast throws:
>     TypeError: Instance of 'ParentData' is not a subtype of 'FlexParentData'

Recurrence class tracked as OPEN finstack issue #31 ("Page does not load on
production AND/OR on release build").

---

## S10 — legacy-doc login crash (`dfba3e6`, 06-10, PR finstack#59)

Two crash shapes on old/incomplete user documents:
- `"A value must be provided. Supported values: male, female"` — `$enumDecode` on null `sex` (required enum, no default).
- `"type 'Null' is not a subtype of type 'Map<String, dynamic>'"` — `EmploymentDetails.fromJson(null)`.

Fix: `Sex.other` + `@JsonKey(defaultValue: Sex.other, unknownEnumValue:
Sex.other)` (side effect: "Other" became selectable in the UI); null-guard for
employment details. "Every other nested field was already null-guarded; only
these two weren't."

---

## S11 — CI Happy-Eyeballs flake (`5b91797`, 06-30, sole commit of PR finstack#82)

> Full debug logs show every request to googleapis.com 'premature close'-ing on
> its first attempt (~74ms) and succeeding only on the retry WITHOUT keep-alive
> — the signature of the Node 20+ 'autoSelectFamily' (Happy Eyeballs) IPv6/IPv4
> race against a runner whose IPv6 path to Google is broken. firebase-tools
> recovers every call except the non-idempotent hosting release POST, which then
> returns a benign 400 ('is the current active version') and reds the job even
> though the deploy landed.

Fix: `NODE_OPTIONS=--no-network-family-autoselection` on each hosting deploy
step; Node 24; latest firebase-tools. Trigger was the ubuntu-24.04 runner-image
bump 20260615 -> 20260622, NOT a repo change.

---

## S12 — Flutter 3.44 upgrade (`b0953b7`, 05-25, PR finstack#56)

versionCode overflow (verbatim):

> scripts/bump_version.sh used millis-since-epoch as the Android
> versionCode source (13 digits, ~1.78e12). Overflowed Integer.MAX_VALUE;
> the new AGP rejects it ("For input string: ..."). Switched to
> date +%s (seconds, ~10 digits, valid until 2038).

Also in the body: AGP 8.7.2->8.11.1, Kotlin 1.9.20->2.2.20, Gradle 8.9->8.14.3,
compile/targetSdk 34->36, Java 8->17, jvmargs 1536M->4096M (Jetifier OOM);
`storage_repository` impossible Dart constraint `>=2.18.0 <3.0.0` widened;
54 `withOpacity`->`withValues`; iOS not verified locally (no CocoaPods,
Podfile.lock needs a Mac); 2 package tests fail pre-existing
(`address_repository`, `bank_details_repository` — construct Firestore repos
without `Firebase.initializeApp()`).

The SPM path-with-space failure (`Anaheim Technologies` -> `%20` -> repo
relocated to `AnaheimTechnologies`) is recorded in `apps/loans/MEMORY.md`'s
3.44 notes rather than this commit body.

---

## Chat era references (state as of 2026-07-07 — volatile)

- Design spec: `6cd1c25` (07-01) "docs(chat): add chat/messaging design spec (issue #61)" — that `#61` is **loooans#61 "Enable messaging"** (finstack PR #61 is a CI fix).
- Plans: `docs/superpowers/plans/2026-07-01-*` (4 files).
- PR finstack#83 (backend, `feat/chat-backend`) MERGED 2026-07-03, merge commit `f95eb6e5cac26f25ad0ce90a08effcf22f7d2b8e` — **exists on GitHub only until you `git fetch`**; the local clone's `origin/develop` was `5e74d69` (pre-merge) when this was written.
- PR finstack#84 (frontend, ~+10.9k lines) OPEN.
- Local branch `feature/chat-messaging` (HEAD `3d94ccc`, 07-02) is the pre-split monolithic dev branch.
- Remaining chat work (console rules, prod deploy) -> root `MEMORY.md` + `finstack-roadmap-and-frontier`.
