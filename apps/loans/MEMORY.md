# MEMORY.md

Log of refactoring and bug fix work done across multiple sessions.

---

## Refactoring Plan

Full plan documented at: `~/.claude-personal/plans/tender-tickling-kahn.md`

### Phase 0: Quick Wins — COMPLETED

- Fixed `LoansState` Equatable `props` in `lib/features/loans/bloc/loans_state.dart`
- Fixed `ProductState` Equatable `props` in `lib/features/products/bloc/product_state.dart`
- Fixed `ReportsState` Equatable `props` in `lib/features/reports/bloc/reports_state.dart`
- Guarded service re-initialization in `lib/app/view/app.dart` redirect callback with `_initialized` flag
- Removed dead/commented-out code in `loans_functions.dart`, `product_state.dart`, `loans_state.dart`

### Phase 1: Extract Shared Utility Functions — COMPLETED

- **1A** — Created `lib/services/charge_calculator.dart` (charge/deduction calculation helper, percentage parsing)
  - Replaced 2 identical charge loops in `loans_bloc.dart`
  - Replaced 6 inline percentage parsers in `product_bloc.dart`
  - Replaced charge loop in `loans_bloc_extension_add_loan_amount.dart`
- **1B** — Created `lib/services/address_builder.dart`
  - Replaced inline address construction in `CompanyBloc`, `RegistrationBloc`, `UserBloc`, `AuthenticationBloc`
- **1C** — Created `lib/services/session_loader.dart`
  - Extracted ~75 duplicate lines from `initializeAuth()` and `_handleLoginEvent()` in `authentication_bloc.dart`

### Phase 2: Extract Loan Calculation Service — COMPLETED

- Created `lib/services/loan_calculation_service.dart` with `LoanCalculationResult`, `calculateFixedTerm()`, `calculateOpenTerm()`, `calculateLoanAmount()`
- Wired into `LoansBloc`, replaced mutable globals
- Deleted `lib/features/loans/bloc/loans_functions.dart`
- Deleted `lib/features/loans/bloc/loans_bloc_extension_calculate_loan_open.dart`
- Updated `reports_bloc_extension_soa.dart`

### Phase 3: Split `app_widgets.dart` — COMPLETED

- Split `lib/widgets/app_widgets.dart` (1,661 lines) into:
  - `lib/widgets/form_widgets.dart`
  - `lib/widgets/button_widgets.dart`
  - `lib/widgets/dialog_widgets.dart`
  - `lib/widgets/profile_widgets.dart`
  - `lib/widgets/notification_widgets.dart`
  - `lib/widgets/layout_widgets.dart`
- `app_widgets.dart` became a barrel file re-exporting all new files

### Phase 4: Split `app.dart` Routing & Providers — COMPLETED

- Created `lib/app/routing/router.dart`
- Created `lib/app/di/repository_providers.dart`
- Created `lib/app/di/bloc_providers.dart`
- Created `lib/app/view/alpha_banner.dart`
- Created `lib/app/theme.dart`
- Simplified `app.dart` to compose these pieces

### Phase 5: Break Up LoansBloc God Object — COMPLETED

- **5A** — Extracted `PaymentBloc` (`lib/features/loans/bloc/payment_bloc.dart`)
- **5B** — Extracted `LoanSettlementBloc` (`lib/features/loans/bloc/loan_settlement_bloc.dart`)
- **5C** — Extracted `AdditionalLoanBloc` (`lib/features/loans/bloc/additional_loan_bloc.dart`)
- **5D** — Slimmed down remaining `LoansBloc`, removed unused dependencies

### Phase 6: Split Giant UI Screens — COMPLETED

- **6A** — `loan_client_detail.dart` (1,947 lines) split into `lib/features/users/widget/client_detail/`
- **6B** — `add_product_screen.dart` (1,642 lines) split into `lib/features/products/widget/add_product/`
- **6C** — `add_user_widget.dart` (1,134 lines) split into `lib/features/users/widget/add_user/`
- **6E** — Remaining 700+ line screens split (`loan_application.dart`, `update_profile_screen.dart`, `loan_offer_detail.dart`)

### Phase 7: Move Notification Creation to Go Backend — COMPLETED

- **7A** — Created `triggers/notification_helpers.go` in Go backend with shared helpers
- **7B** — Modified `triggers/loan_changes.go` to create notification documents on loan status changes
- **7C** — Created `triggers/review_created.go` (Firestore trigger on reviews collection)
- **7D** — Created `triggers/payment_created.go` (Firestore trigger on payments collection)
- **7E** — Removed all notification creation calls from Flutter `loans_bloc.dart`
- **7F** — Slimmed `notification_service.dart` from 583 to ~140 lines (kept FCM token management + notification stream only)

### Phase 8: Reduce Singleton Coupling — COMPLETED

- All 9 BLoCs now accept `AuthenticationService` as a constructor parameter instead of using `.instance`
- `PaymentBloc` also accepts `SettingsService`
- `SessionLoader` updated to accept optional `AuthenticationService` and `DeviceService` parameters
- `NotificationService.instance` kept in `AuthenticationBloc` (justified by lifecycle ordering)

### Phase 9: Theme Consolidation — COMPLETED

- **9A** — Expanded `lib/app/theme.dart` with comprehensive Material 3 theme tokens:
  - `ColorScheme` with all brand colors mapped to semantic roles
  - `TextTheme` with Urbanist font at all standard sizes (displayLarge through labelSmall)
  - `InputDecorationTheme` matching form widget patterns
  - `FilledButtonThemeData` and `OutlinedButtonThemeData`
  - `DialogThemeData` with green background
  - `CardThemeData`, `ChipThemeData`, `ProgressIndicatorThemeData`
- **9B** — Added design token constants to `lib/utils/screen_helpers.dart`:
  - `AppSpacing` (xs, sm, md, lg, xl, xxl)
  - `AppTypography` (displayLarge through labelSmall font sizes)
- **9C** — Created `DESIGN.md` with full design system documentation

### Phase 10: Widget Theme Compliance — COMPLETED

Updated widget files to use theme values instead of hardcoded styling:

- **button_widgets.dart** — Removed `GoogleFonts.urbanist()` textStyle; buttons now inherit from theme
- **form_widgets.dart** — Replaced `GoogleFonts` with `TextStyle`, removed explicit dialog `backgroundColor`
- **dialog_widgets.dart** — Removed explicit `backgroundColor: AppColors.green1` from 4 dialogs; removed explicit `CircularProgressIndicator` color
- **display_widgets.dart** — Removed `GoogleFonts.urbanist()` from RichText
- **notification_widgets.dart** — Replaced `AppColors.white` with `colorScheme.surface`, replaced hardcoded `TextStyle` with theme text styles

---

## Bug Fixes (Post-Refactoring)

### google_fonts AssetManifest.json error

- **Symptom:** `google_fonts was unable to load font Urbanist-Regular` / `Unable to load asset: 'AssetManifest.json'`
- **Cause:** Build cache corruption
- **Fix:** `fvm flutter clean && fvm flutter pub get`

### Loan offer selection UI bugs (3 related issues)

- **Symptom 1:** Draggable sheet bounces down and back up when selecting a different loan offer
- **Symptom 2:** Background color of loan detail doesn't match the selected item's color
- **Symptom 3:** Selected indicator (white border) not showing on the loan offer item
- **Root cause:** Non-admin `BlocListener` in `loan_offers_widget.dart` always navigated via GoRouter on product selection, causing `MainScreen` to rebuild (resetting sheet position, `_selectedColor`, and `_selectedIndex`)
- **Fix in `loan_offers_widget.dart` (line 80-84):** Wrapped GoRouter navigation in `if (isCompactOrMedium)` so desktop doesn't navigate on product selection
- **Fix in `loan_offer_item.dart`:** Added `didUpdateWidget` override to sync internal `_selectedState` with parent's `widget.selected` prop

### Selection delay when switching loan offer items

- **Symptom:** ~1 second delay before the newly selected item appears selected
- **Root cause:** Grid's `BlocBuilder.buildWhen` didn't include `ProductStatus.loading`, so the old item didn't visually deselect until the BLoC finished network calls
- **Fix in `loan_offers_widget.dart` (line 310-317):** Added `ProductStatus.loading` to the grid's `buildWhen` list

### Progressive loading for loan offer detail

- **Symptom:** Entire detail panel waited for reviews to load before showing anything
- **Root cause:** `_handleSelectProductEvent` in `product_bloc.dart` loaded product + reviews sequentially before emitting `selected`
- **Fix in `product_bloc.dart` (lines 738-772):** Restructured to emit `selected` immediately after product/charges/deductions are ready, then load reviews in background and emit `ProductState.refresh()` when done
- **Fix in `loan_offer_detail.dart`:** Wrapped `_reviews()` and `_compactBody()` methods in `BlocBuilder<ProductBloc, ProductState>` with `buildWhen` for `ProductStatus.selected` and `ProductStatus.refresh`, so reviews populate asynchronously

### Wrong principal balance for consecutive additional loans (Issue #4)

- **Symptom:** Adding 2+ additional loans to an open-term loan showed the same (wrong) principal balance for all
- **Root cause 1 (stale UI):** `BlocListener<AdditionalLoanBloc>` success handler in `loan_client_detail.dart` didn't call `selectLoan()` to refresh loan data after a successful additional loan
- **Fix:** Added `loansBloc.selectLoan()` call before popping the dialog
- **Root cause 2 (double-counted OB):** `_handleAddLoanAmountEvent` in `additional_loan_bloc.dart` mutated the last Firestore schedule's `outstandingBalance += totalAmount`, but `calculateOpenTerm` already adds additional loan amounts in its dedicated loop
- **Fix:** Removed the `Future.microtask` block that updated the schedule's OB; also removed unused `LoanScheduleRepository` dependency
- **Root cause 3 (wrong processing order):** `loan.additionalLoanAmounts` was iterated in reverse chronological order (newest first), causing older loans to pick up inflated OB values and overwrite newer schedules
- **Fix in `loan_calculation_service.dart`:** Added `sortedBy((a) => a.createdAt)` before the `for` loop
- **PR:** #33

---

## Completed Work (continued)

### SMS OTP Payment Verification (Issue #66) — 2026-02-18

**Status:** Implemented. Pending deployment and testing.

**Approach:** Uses a dedicated Android device as SMS gateway, Firebase RTDB as message queue. Avoids telco registration.

**Flutter changes:**
- `authentication_bloc.dart` — Added `_otpToken` field, `_handleVerifyOtpEvent` now uses stored token (hash) instead of userId to read OTP from RTDB
- `user_network_service.dart` — Added `requestOtpForUser()` and `verifyPaymentOtp()` methods
- `user_repository.dart` — Added proxy methods for the above
- `payment_event.dart` — Added `RequestPaymentOtpEvent`, `VerifyPaymentOtpEvent`, and `otpVerified` flag on `PayLoanScheduleEvent`
- `payment_state.dart` — Added `otpRequested`, `otpVerified` statuses + `token`, `expireAt` fields
- `payment_bloc.dart` — Added `UserRepository` dependency, OTP request/verify handlers, `otpVerified` branch in payment handler with SMS OTP audit comment
- `payment_otp_dialog.dart` — **New** widget: loading spinner, 6-digit input, countdown timer, verify/resend/cancel buttons
- `client_detail_dialogs.dart` — Uncommented "thru Mobile OTP" button, implemented mobile-otp branch with OTP dialog + cash pool reminder

**Key architecture:**
- Teller requests OTP → Go backend writes to RTDB `otp/{hash}` with `sms_status: "pending"`
- Android gateway listens for pending entries, sends SMS, updates status to "sent"
- Borrower enters code on teller's device → Flutter verifies via `verifyPaymentOtp` endpoint
- Payment recorded with SMS OTP audit trail

**Note:** `verifyPaymentOtp` Flutter URL is `$LOOOANS_BASE_API_URL/users/verify/payment-otp` — ensure API routing matches Go function entry point.

---

## SMS OTP Payment Fix (PR #38) — 2026-03-11

**Issue:** OTP-verified payments did not create a payment document. Schedule was not marked as paid.

**Root cause:** `Payment.create()` factory requires proof (`transactionPhotoUrl` or `autoCollectRef`) unless `bypassPaymentProof` is `true`. The OTP path passed `bypassPaymentProof: event.force` (false), so it threw. Exception was caught silently.

**Fixes applied:**
- `payment_bloc.dart` — `bypassPaymentProof: event.force || event.otpVerified`
- `payment_bloc.dart` — OTP audit comment now fetches borrower via `userRepository.get(id: loan.userId)` and logs their details; teller recorded as `processed_by`
- `payment_otp_dialog.dart` — Added `SizedBox(height: 8)` between action buttons
- `database.rules.json` — Comprehensive RTDB rules for all paths (otp, sessions, reports, loans, gateway_status, force_logout). Split into dev-stg and prod files.
- `firebase.json` — Wired `database.rules.json` for `firebase deploy --only database`
- `database.rules.prod.json` — Separate prod rules (no `dev/`/`stg/` prefixes). Deploy manually with `firebase database:rules:set`.
- `docs/DATA_FLOW.md` — Added payment verification methods table
- `docs/ERD.md` — Added Payment entity field descriptions
- `apps/loans/README.md` — Added RTDB rules deployment instructions

**RTDB rules deployed to `loooans-dev-stg`**. Production pending.

**Issue #66 (Borrower acknowledgement) closed.**

---

## Payment Center Feature (Issue #11) — 2026-03-19

**Status:** Implemented. Pending manual testing.

**What:** Unified Payment Center — a standalone screen where tellers can search for a borrower, view all their loans (including add-on loans), and make payments directly without navigating to individual loan detail screens.

**Files created (11):**
- `features/payment_center/bloc/payment_center_bloc.dart` — Standalone BLoC handling search, loan loading, payment processing, OTP
- `features/payment_center/bloc/payment_center_event.dart` — Events (search, select, expand, pay, OTP)
- `features/payment_center/bloc/payment_center_state.dart` — State with status enum + copyWith
- `features/payment_center/model/borrower_loan_group.dart` — Groups parent Loan with children and actionable schedules
- `features/payment_center/screen/payment_center_screen.dart` — Main screen with search + two-section loan list
- `features/payment_center/widget/borrower_search_widget.dart` — TypeAhead search for borrowers
- `features/payment_center/widget/borrower_loan_section.dart` — Section A: borrower's loans with actions
- `features/payment_center/widget/co_maker_loan_section.dart` — Section B: read-only co-maker loans
- `features/payment_center/widget/loan_card_widget.dart` — Expandable loan card with inline payables
- `features/payment_center/widget/payable_tile_widget.dart` — Single payable row with Pay button
- `features/payment_center/widget/payment_center_dialogs.dart` — Payment dialog + OTP dialog (adapted from client_detail_dialogs)

**Files modified (4):**
- `app/routing/paths.dart` — Added `paymentCenter` path
- `app/routing/router.dart` — Added GoRoute inside ShellRoute
- `app/di/bloc_providers.dart` — Registered PaymentCenterBloc
- `utils/constants.dart` — Added menu item (teller + admin only)

**Key architecture decisions:**
- Standalone BLoC — does not depend on LoansBloc, PaymentBloc, or existing payment dialog
- Payment logic replicated from PaymentBloc (signature/OTP/force paths, cash pool deduction)
- Reuses existing dialogs: `showSettleAccountDialog`, `showSignatureDialog` from client_detail_dialogs
- Loans grouped by parent/child relationship with actionable schedules (overdue + next upcoming)
- Auto-refreshes after payment via `RefreshBorrowerDataEvent`

---

## Pending Work

**Subtask #67 (take photo + signature before payment):** Verified FULLY IMPLEMENTED — signature pad, selfie capture, Cloud Storage upload, integrated into payment and additional loan flows.

### SMS OTP — Remaining items
- Deploy RTDB rules to `loooans-prod` when ready
- Extend SMS OTP to additional loan flow (future)

---

## Key Notes

- Always use `fvm flutter` (not plain `flutter`) — project uses FVM with Flutter 3.38.4
- Run `fvm flutter analyze` after changes to verify no errors
- Pre-existing info/warning issues exist (deprecated `withOpacity`, TODO style, `reassemble` usage) — not introduced by this work
- The Go backend is at `loooans/go/loooans_cloud_functions/`
- Three Firebase flavors: development, staging (`loooans-dev-stg`), production (`loooans-prod`)
- Design system documented in `DESIGN.md`; theme tokens defined in `lib/app/theme.dart`
- Prefer using theme values (`Theme.of(context).colorScheme`, `Theme.of(context).textTheme`) over hardcoded `AppColors` and `GoogleFonts` in widgets

---

## Mobile Number Verification UI (issue #13)

- New `MobileVerificationScreen` at `Paths.mobileVerification` reused by login gate and post-profile-edit re-verify.
- 4-minute resend cooldown; OTP expiry stays at 5 minutes (existing backend behavior). `AuthenticationState.requestOtp` now carries a `canResendAt: DateTime` for the screen's countdown.
- `LoginScreen` no longer hosts OTP dialogs — replaced by `GoRouter.of(context).go(Paths.mobileVerification)`. The dormant `aiVerified` branch and `VerifyWidget` were deleted.
- `AuthenticationBloc._checkUserVerificationStatus` now actually checks `(user.verificationStatus & UserVerificationStatus.mobileNumberVerified.value) == 0`. The bloc's verify path now calls backend `UserRepository.verifyOtp` instead of client-side RTDB compare.
- Profile widget shows ✓ icon when verified; "Verify" CTA when unverified. Update-profile mobile field is disabled with "Editable in N days" while inside the 90-day window.
- After a profile mobile-number change saves successfully, `UserBloc` emits `UserState.requireMobileVerify`, and `UpdateProfileScreen` routes to `Paths.mobileVerification`.
- Follow-up #134 covers `bloc_test` and widget tests (deferred — `AuthenticationBloc` currently uses `AuthenticationService.instance` singleton and takes `BuildContext` directly; testable refactor is part of the same issue).

---

## DateTime fields — helpers expect millis (PR #47)

`handleDateTimeFromJson` and `handleDateTimeNullableFromJson` in `loooans_helpers/data_helpers/constants.dart` accept either a `num` (millis since epoch — the codebase convention) or a Firestore `Timestamp` (duck-typed via `.toDate()` to avoid a cloud_firestore dependency in `loooans_helpers`). New entities should keep using these helpers via `@JsonKey(fromJson: handleDateTimeNullableFromJson, toJson: handleDateTimeToJson)`.

If a `TypeError: Instance of 'Timestamp' is not a subtype of type 'num'` ever surfaces again, the culprit is a backend producer that wrote a raw `time.Time` instead of `.UnixMilli()` — fix it at the producer. The Flutter helper's tolerance is defensive, not a license to store Timestamps deliberately.

---

## Flutter 3.38.4 → 3.44.0 upgrade (issue #46, 2026-05-25)

Bumped the project to the latest stable Flutter. Branch: `chore/flutter-3.44-upgrade`.

**Required toolchain bumps** (driven by plugins Flutter 3.44 pulls in):
- AGP `8.7.2` → `8.11.1` (`android/settings.gradle`)
- Kotlin `1.9.20` → `2.2.20` (settings.gradle + `kotlin-stdlib-jdk7` in app/build.gradle)
- Gradle wrapper `8.9` → `8.14.3`
- `compileSdk`/`targetSdk` `34` → `36`
- Java source/target `1_8` → `17`, `jvmTarget` `1.8` → `17` (Java 8 is "obsolete" warning otherwise)
- `org.gradle.jvmargs` `1536M` → `4096M` (Jetifier OOM during dex transforms — the same gotcha noted in root memory; 2048M wasn't enough at this point, used 4096M)
- Flutter 3.44 auto-added migration shims: `android.builtInKotlin=false`, `android.newDsl=false` in `gradle.properties` — keep these.

**Real bugs surfaced and fixed:**
- `scripts/bump_version.sh` used millis-since-epoch as the build number (`$(date +%s%N)/1000000`) → 13-digit values like `1778731308889` overflow Android's `Int` `versionCode` (max ~2.1B). Old AGP silently truncated; new toolchain throws `For input string: "..."`. Switched to `date +%s` (seconds, ~10 digits, fits until 2038). Also re-bumped `pubspec.yaml` to a valid current value.
- `packages/core/storage_repository` had `sdk: ">=2.18.0 <3.0.0"` — impossibly restrictive vs Dart 3. Latent bug pub had been tolerating. Widened to `>=3.0.0 <4.0.0`.

**Codemod:** 54 `.withOpacity(x)` call sites → `.withValues(alpha: x)` across `lib/` (deprecated in Flutter 3.27+, will become an error in a future release). Pure syntactic substitution.

**Build verification:**
- Web build ✅, Android debug APK ✅, analyzer 0 errors (132 infos/warnings, all pre-existing)
- iOS not verified locally (no CocoaPods on this machine); plugin versions changed so `Podfile.lock` will need refreshing on a Mac.
- 2 package tests fail (`address_repository`, `bank_details_repository`) — confirmed pre-existing on `develop`, scaffold tests that construct Firestore-backed repos without `Firebase.initializeApp()`.

**Known follow-ups (not in this PR):**
- KGP → Built-in Kotlin migration: 5 plugins still use KGP (camera_android_camerax, device_info_plus, firebase_remote_config, package_info_plus, shared_preferences_android). Future Flutter releases will fail if KGP is still in use — plugin updates needed.
- SPM (Swift Package Manager) for iOS plugins: `printing`, `flutter_keyboard_visibility`, `flutter_local_notifications` — future-deprecation warning.
- Wasm dry-run flags incompatibilities in `image` package + `flutter_keyboard_visibility_web` (`dart:html`) — only affects wasm builds, not the default JS build.

CI workflows auto-extract the Flutter version from `apps/loans/.fvmrc` — no workflow edits needed.
