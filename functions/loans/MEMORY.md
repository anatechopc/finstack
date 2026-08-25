# MEMORY.md

Log of work done on the loans Cloud Functions (Go backend).

---

## Server-side user provisioning — addUser + sendPasswordSetupLink (2026-06-19)

Phase A of issue #69 (server-side user creation). Two new HTTP Cloud Functions following the adapter+core pattern.

### New endpoints

**`addUser`** — `api/users/add_user.go` (adapter) + `api/users/add_user_core.go` (core)

Admin-only POST. Mints a Firebase Auth account, atomically writes `users/{uid}` + optional `address` doc via a Firestore batch, then best-effort sends a set-password invite email. Returns `{uid, inviteSent}`.

Authorisation matrix (enforced server-side, cannot be bypassed by the client):
- Caller must be `admin` or `appAdmin`; all other roles get 403.
- `staffRoles` (`admin`, `loanOfficer`, `teller`, `reviewModerator`) are allowed in **any** company management type.
- `customer` role is only allowed when the caller's company has `management_type == "selfManaged"` — app-managed companies do not self-onboard borrowers.
- `appAdmin` role is rejected outright (cannot be provisioned via this endpoint).
- `company_id`, `user_role`, `id`, and `invited_by_admin` are server-authoritative: the client cannot supply or override them.

Atomic write with compensating rollback: if the Firestore batch fails after the Auth account is created, `DeleteAuthUser` is called to roll back the orphaned account.

**`sendPasswordSetupLink`** — `api/users/send_password_setup_link.go` (adapter) + `api/users/send_password_setup_link_core.go` (core)

Unauthenticated POST. Generates a Firebase `PasswordResetLink` and emails it via MS Graph. Used for admin "Resend invite" and user "Forgot password". Always returns 200 — any error (including "no such user") is swallowed to prevent account-existence enumeration.

### Invite email

`api/users/invite_email.go` — shared helper used by both adapters. Calls `authClient.PasswordResetLink` to generate the link (never stores a plaintext password after first use) and sends a branded HTML email via `utils.SendEmail` (MS Graph).

### Duplicate welcome-email suppression

`triggers/user_created.go` now calls `ShouldSkipWelcomeEmail(fields)` at the top of `UserCreated`. If the newly-created user doc has `invited_by_admin == true`, the generic "Verify your account" email is skipped — admin-provisioned users already receive the set-password invite. Self-registered users are unaffected.

### Random password helper

`utils/generate_password.go` — `GenerateRandomPassword()` returns a 24-character cryptographically-random password using `crypto/rand`. It is only ever used as the throwaway initial password for admin-provisioned accounts; the user immediately replaces it via the set-password link, so it is never shown to anyone.

### IAM requirements

Both `addUser` and `sendPasswordSetupLink` use MS Graph (email) and Firebase Auth — they need the same `--set-env-vars "$MS_GRAPH_ENV_VARS" --set-secrets "$MS_GRAPH_SECRETS"` flags as `sendEmail`, and the runtime SA must have `roles/secretmanager.secretAccessor` for the `ms-graph-client-secret` in Secret Manager. This is already granted on `loooans-dev-stg`; **prod (`loooans-prod`) IAM grant is pending before the first master deploy.**

### Function count

Deploy script bumped: 13 → 15 (`addUser_$environment` + `sendPasswordSetupLink_$environment`).

### Tests

- `test/utils/generate_password_test.go` — length + uniqueness
- `test/users/add_user_core_test.go` — 10 core tests (happy paths, authz matrix, rollback, best-effort invite, field stamping)
- `test/users/send_password_setup_link_core_test.go` — 3 tests (known email, empty email no-op, unknown email never leaks)
- `test/triggers/user_created_skip_test.go` — 3 cases for `ShouldSkipWelcomeEmail`
- All green via `CGO_ENABLED=0 go test ./...`.

---

## userChanges — cascade profile rename to user_loan_views.user_full_name (2026-06-17)

Bug: `user_loan_views` denormalizes the borrower name in `user_full_name`, set once at loan creation (`loans_bloc.dart` → `user.completeNameEasternOrder`). When a user renamed their profile, the lender's "Loan clients" list stayed stale (live User detail showed the new name).

Fix: extended the existing `userChanges` adapter+core trigger (`triggers/user_changes.go`) with a second, independent path. `HandleUserChangedCore` now also composes the before/after full name from `first_name`/`last_name`/`middle_name`; on a change it calls a new injected dep `UpdateUserLoanViewNames(ctx, userId, newFullName)`. The mobile-verification path is untouched and runs independently (name-only edit refreshes views, leaves verification alone; mobile-only edit clears verification, leaves views alone; both → both).
- Name composition replicates Flutter `User.completeNameEasternOrder` exactly: `'$lastName, $firstName${middleName != null ? ' $middleName' : ''}'` → Go `lastName + ", " + firstName (+ " " + middleName if non-empty)`. A null/absent Firestore `middle_name` arrives as `""` from the proto and is omitted (matches what the list renders). Middle name is the FULL name, not an initial.
- Adapter `UpdateUserLoanViewNames` queries `{prefix}user_loan_views where user_id == userId` (equality-only, served by the automatic single-field index — no composite index/IAM needed) and does a single-field `Set({user_full_name}, MergeAll)` per matching doc. `flattenFields` extended to carry the three name fields.
- New fake `LoanViewNameUpdater` in `test/fakes/fakes.go`. 5 new/updated core tests in `test/triggers/user_changes_test.go`: name changed → cascade with correct eastern-order name; no middle name → omitted; name unchanged (mobile-only) → no cascade but mobile logic still runs; cascade error propagates; mobile-only change asserts no cascade.
- `CGO_ENABLED=0 go build ./...` + `go test ./...` green. `go vet` clean for this code (the two pre-existing `loan_changes.go` lock-copy warnings are untouched). No new IAM — `userChanges` already deployed with the runtime SA.

---

## Firebase Admin: keyless credentials (security incident, 2026-06-11)

`utils/initialize_firebase.go` had a **hardcoded service-account private key** committed in source. Google's secret scanner detected it in the GitHub repo and **auto-disabled** the key (`SERVICE_ACCOUNT_KEY_DISABLE_REASON_EXPOSED`, key id `2a8c7ca0…` on `firebase-adminsdk-bqdg7@loooans-dev-stg`). Because every function/trigger inits Firebase via `InitializeFirebase`, which used `option.WithCredentialsJSON(<that key>)`, all Admin calls began failing with `rpc error: code = Unauthenticated` — surfaced first as a 500 from `requestOtp` ("verify mobile number").

Fix (keyless, the correct pattern):
- `InitializeFirebase` now calls `firebase.NewApp(ctx, conf)` with **no credentials option** → uses Application Default Credentials = the function's **runtime service account** (metadata server). Removed the embedded key and the now-unused `types.FirebaseOptions` (`types/firebase_options.go` deleted). Also fixed a latent bug: prod previously used the dev-stg key.
- `deploy_functions.sh` now discovers the project's `firebase-adminsdk-*` SA and deploys every function with `--service-account=<it>` (it already has Firestore/RTDB/Auth roles). The deploying identity needs `roles/iam.serviceAccountUser` (actAs) on that SA.
- The disabled key stays disabled (it's compromised + in git history). Do NOT re-enable or re-embed a key. Local runs need ADC out of band (`gcloud auth application-default login`).
- IAM to verify before redeploy: the firebase-adminsdk SA has Firebase roles (default yes); CI deployer has actAs on it.

---

## reviewCreated refactored to adapter+core (Issue #47 follow-up, 2026-06-02)

`triggers/review_created.go` was a monolithic adapter with no tests. Refactored into the same adapter+core split as `reviewUpdated`:
- `HandleReviewCreatedCore(ctx, reviewId, review, deps) (notifyFailures []error, lookupErr error)` — pure fan-out. Notifies the company's admins + reviewModerators of a new review. Two-value return preserves the original's exact semantics: responder-lookup failure → `lookupErr` (adapter returns it → retry); per-recipient Notify failures → collected in `notifyFailures` (best-effort, adapter logs them, no retry — avoids re-notifying recipients that succeeded). Empty `provider_id` → no-op.
- Deps: `GetResponderIds` (wraps `getCompanyUserIdsByRole`), `Notify` (wraps `createNotification`).
- Adapter `ReviewCreated` + `extractReviewCreate` helper (skips on missing value / review id, mirroring `extractReviewChange`). Now also `defer fs.Close()` and guards missing review id (originally would have proceeded with an empty id).
- 5 core tests in `test/triggers/review_created_test.go` (notifies admins+mods, missing-provider no-op, no-responders no-op, lookup-error propagates, notify-error best-effort). Reuses the `Notifier` fake; `responderLister` test helper for the id lookup.
- Behavior changes (all improvements): missing `provider_id`/`value`/review-`id` now skip gracefully instead of returning an error that would retry-storm on a malformed doc. Happy path identical.

## reviewUpdated trigger — notify borrower on admin response (Issue #47, 2026-06-02)

New trigger `triggers/review_updated.go` for the reviews-response feature (full feature notes in `apps/loans/MEMORY.md`). Follows the adapter+core split (per the established pattern):
- `HandleReviewUpdatedCore(ctx, reviewId, before, after, deps)` — pure, testable. Fires **only** on the `response` transition `empty/nil → non-empty` (first set). No-ops on edits, clears, unrelated field changes, nil snapshots, and missing `user_id`. Builds a borrower notification (`notification_type: "review"`, carrying `review_id`/`company_id`/`product_id`/`user_id`).
- `ReviewUpdated(ctx, event)` — CloudEvent adapter; unmarshals the Firestore update protobuf, then delegates to core.
- Registered in `loooans_cloud_functions.go` `init()`. Fakes in `test/fakes/`. 11 core tests in `test/triggers/review_updated_test.go` (set vs no-op transitions + authorization gate) — all green via `CGO_ENABLED=0 go test ./...`.
- **Authorization gate (defence in depth, added post-review):** `HandleReviewUpdatedCore` now verifies `responded_by_id` belongs to an `admin`/`reviewModerator` of the review's `provider_id` company (`IsAuthorizedResponder` dep, implemented via the existing `getCompanyUserIdsByRole` helper) before notifying. A spoofed/unauthorized response (one that slipped past the still-deferred Firestore rule) no longer sends the borrower a trusted-looking notification. Verification error → return error (retry), not a silent notify. NOTE: this gates the *notification* only — the Firestore rule is still required to prevent the unauthorized *write/display* of the response itself.
- `go vet` clean for this code; the two pre-existing `loan_changes.go` lock-copy warnings are untouched by this work.

---

## Completed Work

### Notification Triggers (from Flutter refactoring Phase 7)

- Created `triggers/notification_helpers.go` — shared helpers for building notification documents
- Created `triggers/loan_changes.go` — Firestore trigger that creates notification documents on loan status changes
- Created `triggers/review_created.go` — Firestore trigger on reviews collection
- Created `triggers/payment_created.go` — Firestore trigger on payments collection

### CI/CD Improvements

- Enabled parallel deployment of Cloud Functions in CI
- Added `workflow_dispatch` to all workflows for manual testing

### SMS OTP Feature (Issue #66) — 2026-02-18

- **Modified `api/users/request_otp.go`:**
  - Changed RTDB key from `otp/{userId}` to `otp/{hash}` (allows concurrent OTPs per user)
  - Added `target_user_id` field — teller can request OTP for a borrower
  - Added `reason`, `requested_by`, `phone`, `message`, `sms_status` fields to RTDB write
  - Replaced TransmitSMS API call with RTDB-based SMS queue (gateway picks up pending entries)
  - Removed `bytes` and `os` imports (no longer needed)
- **Created `api/users/verify_payment_otp.go`:**
  - New endpoint: reads `otp/{token}` from RTDB, checks expiry, verifies OTP via `service.VerifyOtp()`
  - On success: deletes OTP entry, returns `{"verified": true}`
  - On failure: returns 400 `{"verified": false, "message": "Invalid OTP"}`
- **Registered `verifyPaymentOtp` in `loooans_cloud_functions.go`**
- **Updated deploy script:** Added `requestOtp` (was missing!) and `verifyPaymentOtp` entries (8→10 functions)

---

## Key Notes

- Use `utils.GetEnvironment()` for environment-specific config — never hardcode collection prefixes
- Register every new function in `loooans_cloud_functions.go` `init()`
- Each subdirectory (`api/`, `triggers/`, `utils/`, `types/`) is a separate Go module with its own `go.mod`
- Run `go mod tidy` in the sub-module directory when adding dependencies

---

## verifyOtp generalization + userChanges trigger (issue #13)

- `verify_payment_otp.go` renamed/generalized into `verify_otp.go`. Adapter+core split: `VerifyOtp` (HTTP adapter) wires real Firebase clients; `VerifyOtpCore` is pure logic, tested with in-memory fakes from `test/fakes/`.
- `reason` is sourced from the RTDB OTP entry (written by `RequestOtp`), never from the verify request body — covered by `TestVerifyOtpCore_ReasonReadFromRTDB_NotRequest`.
- New `userChanges` trigger fires on `users/{uid}` updates and clears `verificationStatus` mobile bit + nulls `mobile_verified_at` when `mobile_number` changes. Same adapter+core pattern: `UserChanges` adapter + `HandleUserChangedCore` pure function.
- Old `verifyPaymentOtp_<env>` Cloud Run service is no longer redeployed by `.github/scripts/deploy_functions.sh` — orphaned services should be deleted manually from GCP console after the first successful deploy on each env.
- This feature established the Go adapter+core unit-test pattern. Future PRs touching Go handlers should follow it; backfilling existing untested code is out of scope and tracked separately.
- Local Go test workaround on macOS 26.x: `CGO_ENABLED=0 go test ./...`. CI on Linux uses `go test -v ./...` directly.
- Hosting: `/api/users/verify/payment-otp` rewrite removed; `/api/users/verify/otp` → `verifyotp-<env>` Cloud Run service added across all 3 hosting target blocks in `apps/loans/firebase.json`.

---

## Timestamp Writes — Always use `.UnixMilli()`, never raw `time.Time` (PR #48)

The Firebase Admin SDK in Go auto-serialises a Go `time.Time` as a Firestore **Timestamp** protocol object. The Flutter client expects timestamp fields as `num` millis (per `loooans_helpers/handleDateTimeToJson` returning `millisecondsSinceEpoch`), and json_serializable's generated `fromJson` casts via `as num?` — that cast throws `TypeError: Instance of 'Timestamp' is not a subtype of type 'num'` when it hits a server-written Firestore Timestamp.

When writing date/time fields to Firestore (or RTDB) from Go code, always convert:

```go
// ❌ Wrong — Admin SDK serialises as Firestore Timestamp.
update["updated_at"] = time.Now()

// ✅ Right — stores int64 millis matching the codebase convention.
update["updated_at"] = time.Now().UnixMilli()
```

Caught in `verify_otp.go` (PR #48); the convention is consistent everywhere else, e.g. `request_otp.go` writes `time.Now().UnixMilli()` and `expireAt.UnixMilli()`. PR #47 added defensive Timestamp tolerance to the Flutter helpers, but the canonical fix is at the producer.

---

## Borrower Payment Submission — Go side (branch `feature/borrower-payment-submission`, finstack #64)

The borrower submission flow writes `pending` payments that a teller later confirms/rejects; the Go triggers keep both parties notified.

- **New `paymentUpdated` trigger**: fires on `payments/{id}` updates and notifies the **borrower** when their submission transitions `pending → confirmed` or `pending → rejected` (rejection carries `rejection_reason`). No-ops on any other transition (e.g. confirmed→confirmed, backfill writes). Adapter+core split: `PaymentUpdated` adapter wires real Firebase clients, `HandlePaymentUpdatedCore` is pure logic tested with in-memory fakes from `test/fakes/`. Registered in `loooans_cloud_functions.go` `init()` and added to the `deploy_functions.sh` deploy block. **Function counter 12 → 13.**
- **`paymentCreated` refactored to adapter+core** (was inline). While refactoring, **fixed the pre-existing `loan_id` bug**: it resolved the loan via the payment's schedule, but open-term payments are created with `loan_schedule_id = NO_ID` (backfilled just after), so the schedule lookup returned nothing and lenders weren't notified. Now resolves the loan via `loan_id` on the payment (denormalized by the Flutter side at every creation site) and falls back to the schedule for older docs that lack it.
- **De-dup per `submission_id`**: Pay-in-full creates one payment per schedule, all sharing a `submission_id`. `paymentCreated` now notifies the lender **once per submission** instead of once per schedule. Payments with no `submission_id` (legacy/single) notify per-payment as before.
- Same testing/deploy conventions as elsewhere: `CGO_ENABLED=0 go test ./...` locally on macOS; every new function registered in `init()` and added to `deploy_functions.sh`; `go mod tidy` per sub-module when deps change.

---

## Request OTP phone normalization — hardening after independent review (branch `feature/otp-phone-normalization`, finstack #89, 2026-08-12)

`requestOtp` now normalizes `mobile_number` to E.164 using the country from the user's address before writing the RTDB entry. An independent review found five defects in the first implementation, **each reproduced by running the code**, not by reading the diff:

- **`phonenumbers` v1.1.8 panicked** on RFC3966-shaped input (`"9175551291;phone-context=x tel:y"` → `slice bounds out of range`). `mobile_number` is written client-side straight to Firestore (`update_user.go` is a stub; the app's `digitsOnly`/`maxLength(10)` is UI-only), so any authenticated client could plant the value and turn every call into a 500. **Now on v1.5.0** — the newest release that keeps a `go 1.19` directive, so the **`go122` runtime is unaffected**. v1.6.0+ forces `go 1.23.0`; do not upgrade past v1.5.0 without also moving the runtime in `deploy_functions.sh` (~20 `--runtime go122` occurrences). A `recover` guards `NormalizePhoneE164` regardless. **(Superseded 2026-08-14: `go122` was retired by GCF and the runtime is now `go126` — see the runtime section below. The v1.5.0 ceiling no longer applies; upgrading `phonenumbers` is now a free choice, though nothing requires it.)**
- **Keypad alpha-to-digit conversion**: `"0917LOOOANS"` normalized to `"+639175666267"` — a real, unrelated subscriber — and passed `IsValidNumber`, so the OTP was delivered to a stranger with a 200 response. This happens in **every** library version, so input is now screened for non-dialable characters *before* `Parse`. Screening, not a version bump, is the fix.
- **Landlines passed validation**: `"0288887777"` → `"+63288887777"`, accepted, then silently undeliverable — the exact failure the feature exists to prevent. Now requires `GetNumberType` to be `MOBILE` or `FIXED_LINE_OR_MOBILE`.
- **Company-affiliated users were permanently locked out**: the address query filtered on `data_type == "user"`, but registration writes only a `provider` doc keyed on `company_id`, and the app resolves those users' addresses from it (`session_loader.dart`). A lender's founding admin got a 400 telling them to complete an address record **no screen would ever create**. `ReadUserAddress` now falls back to the company's provider address.
- **`country` is free text** in the profile editor (registration hardcodes it, the editor does not), so typing `"PH"` locked the user out. Common aliases and ISO codes now resolve. A country dropdown remains the durable fix.

Also: `Limit(1)` let a soft-deleted address mask a live one (now skips deleted docs); `ErrAddressMissing` and `ErrCountryUnknown` produced byte-identical 400s despite needing different remedies (now distinct); and error text no longer echoes the raw phone number, which reaches both logs and the 400 body.

**400 bodies are shown to end users verbatim** by the Flutter client (finstack #91), so they are written in neutral phrasing — the same endpoint serves a borrower verifying their own number and a teller acting for one. Changing these strings changes user-facing copy.

**Not fixed, by decision**: the payment-acknowledgement path (`reason=payment`) shares the mobile branch and so inherits the address precondition — whether payments should be gated on address completeness is a product call.

**Withdrawn finding**: "12 live PH prefixes rejected" was wrong — v1.8.1 rejects `0900-0904, 0913, 0940, 0941, 0980, 0982, 0984, 0990` identically, so it is not stale metadata.

---

## GCF runtime `go122` retired — every function deploy failing (2026-08-14)

**Google removed `go122` from Cloud Functions 2nd gen.** Every deploy of the
whole fleet failed on the `gcloud functions deploy` step:

```
ERROR: (gcloud.functions.deploy) Invalid value for [--runtime]:
go122 is not a supported runtime on GCF 2nd gen
```

- **Build and Test passed** in the same runs — this is a deploy-time rejection
  only, so a green check on the test job proves nothing about deployability.
- **17 functions failed together**, i.e. all of them. The last successful
  functions deploy was **2026-07-09**; every merge after that silently left the
  backend frozen at that build. Nothing regressed — already-deployed functions
  kept serving — but no backend change reached any environment for five weeks.
- **First revealed by the docs-only merge of PR #92** (2026-08-13), then again by
  PR #89 (2026-08-14). Neither PR caused it; the retirement did.

**Fix**: `--runtime` moved to `go126` in `deploy_functions.sh` (17 occurrences —
note **two flag spellings**, `--runtime go122` ×6 and `--runtime=go122` ×11; a
grep for one form finds only a third of them). Available in `asia-east1` at the
time: `go123` DEPRECATED, `go124`/`go125`/`go126` GA. `go126` chosen for the
longest runway.

`functions/loans/go.mod` still declares `go 1.22.12` and was deliberately left
alone — the directive pins *language semantics*, not the build toolchain, so a
newer runtime builds it unchanged.

**Verified before merge** by building and testing under the real toolchain
without installing it system-wide:

```bash
cd functions/loans
GOTOOLCHAIN=go1.26.0 CGO_ENABLED=0 go build ./...   # exit 0
GOTOOLCHAIN=go1.26.0 CGO_ENABLED=0 go test ./...    # all packages ok
```

`GOTOOLCHAIN` (Go 1.21+) downloads the requested toolchain on demand — use it to
test a runtime bump instead of trusting that it will build server-side.

**CI toolchain parity**: the three `loans-functions-*.yml` workflows pinned
`go-version: '1.22'` while GCF built with the runtime's own Go. They now pin
`'1.26'` so the tests run on the toolchain that actually builds the deploy.
Keep these two in step — a drifted pair is the same blind spot as CI never
running `flutter test`.
---

## OTP SMS was carrier-filtered on the support address (2026-08-20)

**Every OTP SMS this system ever sent was dropped by the carrier**, independently
of the two code bugs fixed in #89/#90. The 149-char template carried
`support@loooans.com`, and PH carriers filter link-bearing person-to-person SMS.

**The failure was structurally invisible.** The gateway passes
`deliveryIntent = null` (`SmsGatewayService.kt:255,257`), so the only signal is
`sentIntent` -> `Activity.RESULT_OK`, meaning *the radio accepted it*. A message
accepted by the radio and dropped by the SMSC is written `sms_status: "sent"`
with a `sent_at`, identical to a real delivery. Do not read "sent" as "delivered".

**Evidence - seven variants through the live dev gateway to one handset, same
SIM, same recipient, ~30s apart, listed in the order sent:**

| # | Body | Result |
|---|---|---|
| 1 | `test` | delivered |
| 2 | `Your Loooans OTP is 123456` | delivered |
| 3 | full template **with** the address | **dropped** |
| 4 | full template **minus** the address | delivered |
| 5 | warning prefix + OTP | delivered |
| 6 | full template **with** the address (repeat) | **dropped** |
| 7 | shipped body, app CTA | delivered |

All seven were recorded `sms_status: "sent"`. The real OTP sent that morning
(same template) also never arrived.

**Order matters and excludes throttling**: the first drop is #3, and #4 and #5
were delivered *after* it. A cumulative rate-limit would degrade with each send,
not recover - so the discriminator is content, not volume.

**Rule: no email address, URL, or link-like token in the SMS body; ASCII only;
one 160-char GSM-7 segment.** Guarded by
`TestRequestOtpCore_MobileObjective_SmsBodyIsCarrierSafe`, with the detector
itself pinned by `TestSmsBodyLinkDetector` (a substring denylist was the first
attempt and was too narrow - `loooans.net`, `bit.ly/x`, `loooans://verify` all
passed it, while `1.Complete` false-positived).

**There is no support address anywhere in the OTP flow, and there never was.**
`support@loooans.com` appeared exactly once in the whole repo - the SMS line
removed here - and the email OTP body has never carried one (`createHtmlBody`
closes with "please do not reply"). The app's only real support address is
`support@anaheimtechnologies.com` (`app_footer_widget.dart:49`), a **different
domain**, so the removed address may never have been a live mailbox. The SMS CTA
therefore names the app ("contact us in the Loooans app") - actionable, and
link-free so it survives the filter.

**Ruled out while diagnosing** (so nobody re-chases them): dual-SIM /
subscription selection - the phone has exactly one active subscription
(Smart PH, subId 8, slot 0, default for SMS, `IN_SERVICE`, `HOME`, unbarred);
multipart splitting - every body is one GSM-7 segment; prepaid credit and the
IMS/IWLAN path - both excluded once plain text delivered on the same SIM;
client-side coupling - no Dart code reads, parses, or autofills an SMS anywhere
in the monorepo, so the body is human-read copy, not a parsed contract.

**Still open:** the gateway requests no delivery report, so a future copy edit
that re-trips the filter is again silent. Passing a real `deliveryIntent` is the
only way to separate `sent` (radio accepted) from `delivered` (handset
acknowledged). Also: the guard runs in CI against one call site - a second SMS
body added elsewhere would be ungated until validation moves to the write
boundary (`deps.WriteOtp`). Current headroom: the shipped body is 140 chars,
20 below the GSM-7 limit; one non-ASCII rune makes it 3 UCS-2 parts.

---

## 2026-08-25 — Search backend: server-side `search_tokens` (finstack#56)

Built the backend half of client/offer search on branch `worktree-search-design-spec`
(15 commits). Design spec `docs/superpowers/specs/2026-08-24-search-design.md` is the
binding authority; the full decision log — including several rulings I got wrong and an
implementer corrected — is in the SDD ledger (git-ignored, `.superpowers/sdd/`).

**Approach:** prefix-expansion token arrays (`search_tokens`) written **server-side** by
triggers, queried with `array-contains`. Rejected in the spec: BigQuery for search (OLAP,
wrong latency profile — see #98 for reporting), a typed query DSL, single-field prefix
matching, and Typesense at this stage.

**What shipped:** `utils/search/` (tokenizer, phone canonicalization, per-entity
composition) + golden vectors shared with Dart; `search_tokens` written from `userChanges`
**and** `userCreated`; the `product_views` projection **moved from Flutter to a Go trigger**
(`productWritten`); 6 composite indexes; a re-runnable backfill.

### Traps worth remembering

- **`userChanges` writes a field that re-fires `userChanges`.** Termination depends entirely
  on `flattenFields` parsing the `search_tokens` **array** back out of the CloudEvent so
  `SearchTokensForUser` can see the tokens already match. That `case` looks like dead weight
  next to the string cases. Deleting it = infinite trigger loop billing production. It is
  pinned by `triggers/user_changes_internal_test.go` — an *internal* test, because
  `flattenFields` is unexported.
- **CI was not running that test, or building 6 of 7 modules.** `go test ./...` from
  `functions/loans` reaches only `com.loooans.app`; `api`, `job`, `test/fakes`, `triggers`,
  `types`, `utils` were never built or tested. That is why `job` sat with a stale `go.mod`
  that did not compile. Fixed in all three `loans-functions-*.yml` to loop over every
  `go.mod`. **Do not pipe the go commands** — a pipeline exits with its last element's
  status and silently swallows failures (my first draft did exactly that).
- **`product_views` is written by Go, read by `ProductViewEntity`, which has 14 `late`
  non-nullable fields.** An incomplete document crashes the app on read.
  `BuildProductViewCreate`/`BuildProductViewUpdate` are the **only** thing enforcing that
  contract — the backfill calls `HandleProductWrittenCore` rather than reimplementing, on
  purpose. Never write a second projection.
- **`deleted_at` must be written as an explicit null.** Firestore's `isNull: true` matches
  only documents where the field **exists**, so a view missing it is invisible to every
  listing while looking perfect in the console.
- **Dates are epoch millis, not Timestamps** (`handleDateTimeToJson`). Firestore **sorts by
  type before value**, so mixing `int` and `Timestamp` in one field silently splits the
  ordering into two blocks. `utils.ToInt64` now converts `time.Time` for exactly this reason.
- **`load()` vs `loadNext()` sort differently** and the `orderBy` sits *after* the caller's
  filters, near the end of the method. I misread a `sed` line range as a method boundary and
  got an index wrong because of it. Confirm which function a line is in before citing it.
- **Phone canonicalization must trim `63`/`0` in a loop**, not once each (`00639175550142`).
  Go had this bug and fixed it in `fd65833`; the golden vectors now pin it.

### Deferred, with issues
#100 (latent no-merge data loss in the Dart view writers — unreachable today, would be
catastrophic if the flag were enabled), #101 (hard-deleted product orphans its view),
#102 (company rename rots its offers' tokens — nothing fires on `companies`), #103
(interest-rate facet needs a query path before it can be indexed), #99, #98.

### Open / needs a human
- **Task 7 Step 6 never ran:** the backfill has only been exercised against fakes. ADC was
  absent in the session. Needs `gcloud auth application-default login`, then a
  `-dry-run=true` pass against `loooans-dev-stg`.
- **Nothing in CI deploys `firestore.indexes.json`**, and all 41 indexes name unprefixed
  collections (`users`, not `dev_users`). Indexes must exist before the frontend lands or
  the first search fails with `FAILED_PRECONDITION`.
- **`firestore.rules` is the default allow-all template, expired 2024-06-22, and
  `firebase.json` has no `"rules"` key** — so it is not deployed and the live rules are
  unknown. Relevant because search's authorization is enforced in query construction
  (client-side); rules are the only real backstop.
