# MEMORY.md

Log of work done on the loans Cloud Functions (Go backend).

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
