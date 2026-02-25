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
