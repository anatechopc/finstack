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
