# OTP Phone Number Normalization — Design

- **Date**: 2026-07-24
- **Trigger**: OTP SMS silently not delivered (dev-stg, 2026-07-24). Root cause: the app's forms store `mobile_number` as a bare 10-digit national number (`9175551291`) — the `+63` in the UI is a cosmetic prefix widget — and the SMS gateway passes it verbatim to `SmsManager`, producing an unroutable destination. RTDB `/otp/` history confirms: every entry with an E.164 number delivered; every bare 10-digit entry shows a retry storm (16 attempts 05-06..05-11, 5 attempts 07-24), all falsely marked `sent` because the gateway registers no `sentIntent`.
- **Related**: [loooans#132](https://github.com/anatechopc/loooans/issues/132) (rate limiting, separate), `finstack-security-hardening` (OTP design findings, untouched here).

## Goal

Make OTP SMS deliverable for every user by normalizing the stored mobile number to E.164 at request time, deriving the country prefix from the user's address instead of hardcoding `+63` — and make the gateway report real delivery outcomes so future failures are visible instead of falsely `sent`.

## Scope

**In scope**
- Backend (`request_otp.go`): normalize the target user's `mobile_number` to E.164 before writing the RTDB entry, using the country from the user's address record; reject un-normalizable requests with a 400.
- Flutter app: surface the new 400 messages in the mobile-verification screen and payment-OTP dialog (verify propagation; adjust only if the message is swallowed).
- SMS gateway app: register `sentIntent` per SMS (all parts for multipart), write `sent` only on `RESULT_OK`, otherwise `failed` + concrete result code; skip entries whose `expire_at` has passed.

**Out of scope** (deliberate)
- Canonicalizing the stored `mobile_number` format / data migration (request-time normalization makes it unnecessary; revisit if another consumer of the field appears).
- Country dropdown in address forms (free-text `country` can break the strict policy via typos — file as follow-up).
- Rate limiting / resend caps — loooans#132.
- Gateway heartbeat alerting; deleting the two dead `/gateway_status` device entries (manual ops task).

## Key decisions

| Decision | Choice | Reason |
|---|---|---|
| Where to normalize | Backend, at request time (`RequestOtpCore`) | Single choke point; fixes all existing users with no migration or UI change. |
| Country source | `{prefix}address` doc (`data_id == uid`, `data_type == 'user'`) → `country` string | User's request: no hardcoded `+63`; address exists for every registered user (registration hardcodes `Philippines`). |
| Unknown/missing country or invalid number | **Reject with 400** (user's choice) | Fail loudly; never queue an undeliverable or wrongly-prefixed SMS. |
| Parsing/validation | `github.com/nyaruka/phonenumbers` (Go libphonenumber) | Correct trunk-zero stripping, per-region validity, E.164 formatting — not naive string-prepend. |
| Country-name → ISO region | Small in-code map, trimmed/lowercased match; initially `philippines → PH` | Only `Philippines` is producible by registration; unknowns reject per policy. Extend the map as countries are added. |
| Already-E.164 stored numbers | Pass through `phonenumbers.Parse` unchanged | `+`-prefixed input ignores the region hint, so legacy well-formed docs work even with a broken address. |
| Gateway `deliveryIntent` | Not used (only `sentIntent`) | Submission outcome is the actionable signal; delivery receipts are carrier-flaky and add receiver lifetime complexity for little diagnostic value. |

## Design

### 1. Backend — `functions/loans/api/`

New helper `api/service/phone_service.go`:

```go
// NormalizePhoneE164 maps countryName → ISO region, parses number with
// phonenumbers, validates it, and returns E.164. Returns service-level
// errors for unknown country / invalid number; RequestOtpCore maps them
// to the users-package sentinels below (service cannot import users).
func NormalizePhoneE164(number, countryName string) (string, error)
```

`RequestOtpDeps` gains `ReadUserAddress func(ctx, uid string) (country string, err error)` — Firestore query on `{prefix}address` where `data_id == uid` and `data_type == 'user'`, limit 1, skipping soft-deleted docs (`deleted_at` set). Returns `("", nil)` when no doc exists — Core maps that to `ErrAddressMissing`, mirroring the `ReadUser` → `ErrUserNotFound` convention.

`RequestOtpCore` mobile path becomes: read user → read address country → `NormalizePhoneE164(mobileNumber, country)` → write normalized value to `entry["phone"]`. The email objective path is untouched (no address read).

New sentinel errors and adapter mapping (HTTP 400):
- `ErrAddressMissing` / `ErrCountryUnknown` → "Cannot determine the country for the user's mobile number. Please complete the user's address record."
- `ErrPhoneInvalid` → "The mobile number on record is not a valid phone number for <Country>."

`go mod tidy` in `api/`; no new function registration (existing `requestOtp` endpoint).

### 2. Flutter app — error surfacing

`requestOtp` already returns typed 4xx messages for other cases (missing mobile number, user not found). Verify the 400 body text reaches: (a) `MobileVerificationScreen` via `AuthenticationBloc.requestOtp`, (b) the payment-OTP dialog via `PaymentBloc`. If either shows a generic failure, thread the server message into the error state. No new strings server-side beyond the two above.

### 3. SMS gateway — honest delivery status

In `SmsGatewayService.sendSms`:
- Skip entries where `expire_at < now` (guards the replay-after-offline burst; entry is left untouched).
- Create a `PendingIntent` (unique request code per hash) for `sentIntent`; for multipart, one per part, tracking that **all** parts report `RESULT_OK`.
- A registered `BroadcastReceiver` maps the result: `RESULT_OK` (all parts) → `sms_status: sent` + `sent_at`; any error code → `sms_status: failed` + `error: "RESULT_ERROR_<NAME> (<code>)"`.
- The synchronous try/catch stays as-is for immediate exceptions.

Status is now written from the receiver, not immediately after the `sendTextMessage` call. `onChildChanged` re-processing on `pending` is unchanged (resend path).

## Error handling

- Backend: all three new failures are 400s with actionable messages; 500 only for transport errors (unchanged pattern).
- Gateway: a send with no broadcast result within 60s is marked `failed` with `error: "timeout waiting for send result"` (watchdog coroutine), so entries can't hang in `pending` after a swallowed broadcast.

## Testing

- **Go (core+fakes pattern, table-driven)**: 10-digit PH number → `+63…`; `09…` 11-digit → `+63…`; already-`+63` passes through with empty/unknown country; missing address → 400; unknown country → 400; invalid number (bad length/prefix) → 400; email objective performs no address read. Adapter test: sentinel → status code/message mapping.
- **Gateway (JVM unit tests, existing `OtpEntryTest` style)**: expiry-skip logic; multipart all-OK vs one-part-failure aggregation; result-code → error-string mapping. Manual device test for the end-to-end send (documented in PR).
- **Flutter**: only if code changes prove necessary (see §2), bloc test for the error state message.

## PR plan

1. **PR 1 — backend** (`functions/loans/`): normalization + tests. Deployable alone; strictly improves behavior (backend-first discipline).
2. **PR 2 — gateway** (`apps/sms-gateway/`): sentIntent + expiry skip + tests; manual APK install on the gateway phone after merge.

## Verification evidence for the diagnosis (2026-07-24)

- RTDB `/otp/`: 47 residual (never-verified) entries; all `+639…` entries ≤2 attempts, all bare-10-digit entries in retry storms, incl. `sent` to fake `1234567890`.
- Git: the `+63` prefix widget, `digitsOnly`, `maxLength(10)` predate the monorepo (`275ad55`) — forms never stored a prefix; the one working number was seeded outside the forms.
- Gateway heartbeat live during all of today's sends (`sent_at` ≈ `created_at` + 1s).
