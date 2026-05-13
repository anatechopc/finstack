# MEMORY.md

Log of work done on the loans Cloud Functions (Go backend).

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
