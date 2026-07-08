# RTDB path catalog + feature flag anchors

Companion to `../SKILL.md`. Every claim verified against the repo 2026-07-07 (branch `feature/chat-messaging`). Paths relative to repo root `/Users/deibeeed/Projects/AnaheimTechnologies/finstack`.

Definitions:
- **RTDB** = Firebase Realtime Database (JSON tree, separate from Firestore). Instance URLs are hardcoded in `functions/loans/utils/initialize_firebase.go` (`loooans-dev-stg-default-rtdb` / `loooans-prod-default-rtdb`, both `asia-southeast1`).
- **Env-scoped** = lives under `dev/` or `stg/` child nodes in the dev-stg instance, at root in prod.
- **Global** = same path in every environment; within `loooans-dev-stg` that means dev and stg SHARE the node.
- Rules sources: `apps/loans/database.rules.json` (dev-stg) and `apps/loans/database.rules.prod.json` (prod, deployed manually — no firebase.json wiring). Go functions use the Admin SDK, which **bypasses rules entirely**.

## Path catalog

### `otp/{hash}` — GLOBAL

The SMS-OTP queue. Keyed by hash/token, never by userId.

| Role | Who | Anchor |
|---|---|---|
| Create entry | Go `requestOtp` (Admin SDK) | `functions/loans/api/users/request_otp.go:341` — `db.NewRef("otp/" + hash).Set(...)` |
| Consume + delete | Go `verifyOtp` | `functions/loans/api/users/verify_otp.go:219` (Get), `:225` (Delete) |
| Listen + send SMS + write back `sms_status` | sms-gateway Android app (signed in as `sms-gateway@loooans.com`) | `apps/sms-gateway/app/src/main/java/com/loooans/smsgateway/SmsGatewayService.kt:81` (ChildEventListener), `:138`/`:158` (status write-back) |

Rules: `.read: "auth != null"` (ANY authed user can read every OTP — open security finding, see `finstack-security-hardening`); per-`$hash` `.write` restricted to `auth.token.email == 'sms-gateway@loooans.com'`.

Because it is global, ONE gateway phone serves both dev and stg OTP traffic in `loooans-dev-stg`; which queue a gateway device serves is decided solely by which project's `google-services.json` is installed in it.

### `gateway_status/{deviceId}` — GLOBAL

Gateway heartbeat. Writer: sms-gateway, every 30s (`SmsGatewayService.kt:169-181`, `delay(30_000)`), plus a status write on service start/stop (`:71-73`). Rules: read any-auth, write gateway-email only. No Flutter reader exists in `apps/loans` as of 2026-07-07 — observed via the gateway app UI / Firebase console.

### `app/sessions/{uid}` — GLOBAL, owner-only

Single-session enforcement. Writer/reader: Flutter `packages/core/authentication_repository/lib/src/data/authentication_database.dart:12-40` — `setSession` reads `app/sessions/{uid}`; if a session map exists it throws `SessionException` ("Already logged in"), else writes `{device_name, last_login}` (millis). Rules: read/write only `auth.uid == $uid`.

### `{dev|stg}/companies/{companyId}/report_summary/...` — env-scoped

The report aggregation tree (sales / products / total_summary / capital_usage subtrees, time-bucketed keys like `year:2026:month:7`).

| Role | Who | Anchor |
|---|---|---|
| Write (increment totals) | Go `loanChanges` | `functions/loans/triggers/loan_changes.go` — `getReportPaths(basePath)` + `applyToNodeValue`/`addReportDataItem`; env node from local `getPathEnv()` (~`:504`) |
| Write | Go `loanScheduleChanges` | `functions/loans/triggers/loan_schedule_changes.go:109` (same `getPathEnv`, same package) |
| Write | Go `capitalCreated` | `functions/loans/triggers/capital_created.go:81` — uses `utils.GetMinifiedEnv()` |
| Read | Flutter reports feature | `packages/loans/reports_repository/lib/src/data/database/reports_realtime_database_service.dart` — `dbRef.child('report_summary'...)`; `basePath` set by `ReportsRepository.init(companyId:)` from `apps/loans/lib/features/reports/bloc/reports_bloc.dart:139` |

Rules: `report_summary` read any-auth. Known correctness weaknesses of the writer (non-transactional read-modify-write, swallowed errors): `finstack-loan-engine-and-reporting-campaign`.

### `{dev|stg}/companies/{companyId}/loans/{loanId}:product_type` — env-scoped

Loan→product-type lookup pairs (node key literally contains a colon). Writer: Flutter `LoanRealtimeDatabaseService.addLoanProductTypePair` (`packages/loans/loan_repository/lib/src/data/database/loan_realtime_database_service.dart:9`). Reader: Go `loan_changes.go:98` `getProductType` (fails the trigger with "product type not found" if absent). Rules: `companies/$companyId/loans/$loanId` read+write any-auth.

### `{dev|stg}/companies/{companyId}/authentication/force_logout` — env-scoped in dev-stg rules, ROOT in prod rules AND in code

Force-logout broadcast flag. Reader: Flutter `authentication_database.dart:6` — listens at ROOT `companies/{companyId}/authentication/force_logout` (no env node). Writer: only the DISABLED Go job `functions/loans/job/subscription_job.go:427` (also root path). Source-level mismatch: the dev-stg rules file defines `force_logout` only under `dev/`/`stg/`, so on dev/stg the source rules deny the root read the app performs. Deployed console rules may differ (unverifiable from repo). Flagged in SKILL.md; triage via `finstack-debugging-playbook` before changing either side.

### `{dev|stg}/typing/{roomId}/{userId}` — env-scoped (chat, in-flight)

Typing presence. Writer/reader: Flutter `TypingService` (`packages/core/chat_repository/lib/src/data/database/typing_service.dart`) — throttled ping + `onDisconnect` clear; own 3-way `_prefix` (dev fallback). Rules (both files, committed on the chat branch): read any-auth per `$roomId`, write only `auth.uid == $userId`. Chat deployment state: `finstack-roadmap-and-frontier`.

## Flutter `String.fromEnvironment('ENVIRONMENT')` consumers — the complete list

Compile-time; a build without `--dart-define=ENVIRONMENT=...` behaves as development in ALL of these:

| Anchor | What it switches |
|---|---|
| `packages/core/loooans_helpers/lib/src/data_helpers/database/base_firestore_service.dart:28` | Firestore collection prefix `dev_`/`stg_`/`''` |
| `packages/core/loooans_helpers/lib/src/data_helpers/database/base_realtime_database_service.dart:10` | RTDB env node `dev/`/`stg/`/root |
| `packages/core/chat_repository/lib/src/data/database/typing_service.dart:30` | typing path prefix (same scheme) |
| `packages/core/loooans_helpers/lib/src/string_helpers.dart:34` | `LOOOANS_BASE_URL` subdomain (`dev.`/`stg.`/none) |
| `apps/loans/lib/bootstrap.dart:49` | Log level (prod `INFO`, else `ALL`) |
| `apps/loans/lib/features/authentication/screen/login_screen.dart:141` | Dev-only login autofill (real-looking credentials committed in source — dev convenience, review before shipping screenshots) |

Adding a seventh consumer? Follow the SKILL.md checklist and add it to this table.

## Feature flags — full anchors

No central flag system exists. Three storage patterns:

### Per-user settings doc (Firestore `{prefix}settings`, one doc per user)

Backed by `packages/loans/settings_repository` (`settings_firestore_service.dart:18` — `collectionName => 'settings'`, prefix automatic via `BaseFirestoreService`). Surfaced through singleton `SettingsService` (`apps/loans/lib/services/settings_service.dart`); loaded per user by `initializeForUser` (queries `user_id ==`, warns if more than one doc).

| Flag | Getter (default) | Gates |
|---|---|---|
| `forcePaymentConfirmation` | `settings_service.dart:78` (false) | Borrower must confirm payments: `features/loans/bloc/payment_bloc.dart:116`, `features/payment_center/bloc/payment_center_bloc.dart:950`, dialogs in `payment_center_dialogs.dart:174,388`, `client_detail_dialogs.dart:263` |
| `appUseClassicUI` (field `useClassicUI`) | `settings_service.dart:75` (false) | Classic vs new home UI |
| `enableProductAddOns` | `settings_service.dart:80` (false) | Add-ons UI: `client_detail_action_buttons.dart:164`, toggle in `widgets/settings_widget.dart:54` |

### Per-product Firestore fields

`packages/loans/product_repository/lib/src/model/product_entity.dart` (defaults in `product.dart:19-23`):

| Flag | Notes |
|---|---|
| `forceCollect` (default false) | Copied onto each loan as `isForceCollect` (`packages/loans/loan_repository/lib/src/model/loan_entity.dart:90`) |
| `allowRequestMaxLoanAmountExtension` (default false) | Max-amount extension requests |
| `allowAddOns` (default true) | Mirrored into `product_view` (`product_view_entity.dart:104`) |

### Derived (not stored)

`AuthenticationService.allowAddClients` (`apps/loans/lib/services/authentication_service.dart:93`) = `company.managementType == CompanyManagementType.selfManaged`. Gates add-client UI: `borrowers_screen.dart:189`, `layout_widgets.dart:219,227`, `home_screen.dart:46`, `loan_application.dart:66`, `client_detail_action_buttons.dart:160`.

### DORMANT — do not resurrect without a product decision

AutoCollect / UnionBank auto-debit: commented-out UI + TODOs at `apps/loans/lib/features/users/widget/profile_widget.dart:37-52` (disabled `_autoCollect()` widget, defined at `:295`), `add_product_screen.dart:306` (comment re `_enforceAutoCollect()`), marketing copy `features/index/widgets/section_5_widget.dart:119`. Status/roadmap: `finstack-roadmap-and-frontier`.
