# MEMORY.md

Log of refactoring and bug fix work done across multiple sessions.

---

## Issue #47 — Reviews: admin responses to borrower reviews (IN PROGRESS)

Adds the ability for a company's `admin`/`reviewModerator` to respond to a borrower review; the borrower sees the response and gets notified. Tracks `anatechopc/loooans` issue #47. Branch: `develop` (uncommitted as of 2026-06-02).

**Locked design decisions:** one response per review; response is editable + deletable; `admin` + `reviewModerator` of the review's `provider_id` company may respond; borrower notified only on the **first** response-set transition (not every edit), to avoid spam.

**Done so far:**
- **Data model** (`packages/loans/review_repository`) — `Review`/`ReviewEntity` gained `response`, `respondedAt`, `respondedById`, `respondedByName` (snake_case JSON keys). Helpers on `Review`: `hasResponse`, `setResponse(...)`, `clearResponse()` — all four fields always written/cleared together so the doc never holds a partial response. 9 package tests green.
- **Go trigger** (`functions/loans/triggers/review_updated.go`) — see `functions/loans/MEMORY.md`. Fires only on `response` first-set transition, notifies `review.user_id`. 8 tests green.
- **Borrower-side rendering** (`apps/loans/lib/features/products/widget/loan_offer_detail/loan_offer_reviews_section.dart`) — new private `_ReviewResponseBlock` shown beneath a review when `review.hasResponse`. Indented + left-accent so it reads as a nested reply; header "Response from {respondedByName}" + `respondedAt` date; **black text** (grey is unreadable on the green background — see memory). Widget test at `test/features/products/widget/loan_offer_detail/loan_offer_reviews_section_test.dart` (3 cases, TDD red→green). This is the app's first real widget test beyond the VGV counter boilerplate — uses the existing `tester.pumpApp()` helper in `test/helpers/`.

**Admin side (images 4–5) — DONE (2026-06-02):** new feature dir `lib/features/reviews/`.
- `bloc/reviews_bloc.dart` (+ `reviews_event.dart`, `reviews_state.dart`) — `ReviewsBloc`. Events: `LoadCompanyReviewsEvent` (loads `provider_id == authService.company.id`), `RespondToReviewEvent` (sets response with logged-in admin's `user.id` / `completeNameEasternOrder`), `DeleteReviewResponseEvent` (clears). Two constructors: default `ReviewsBloc(BuildContext)` for DI, `ReviewsBloc.withDependencies({reviewRepository, authService})` for tests. Repo field typed as `BaseRepository<Review>` (abstract/mockable) because concrete `ReviewRepository` is a `final class` (can't be mocked). 4 bloc tests.
- `widget/review_response_dialog.dart` — `ReviewResponseDialog` + `showReviewResponseDialog(context, review:)`. Original review on top, `Message` field (prefilled in edit mode), Send; **Delete response** button shown only when `review.hasResponse`. 5 widget tests.
- `widget/reviews_dialog.dart` — `ReviewsDialog({required summary})` + `showReviewsDialog(context)`. Header summary via pure `reviewsSummary(Company)` (kept out of the widget so it's testable without the auth singleton); list reuses borrower `LoanOfferReviewItem` (so existing responses render) + a Respond/Edit button per row. 5 widget tests.
- Score card wired in `lib/features/reports/widgets/report_cards_widget.dart` — replaced the commented `'reviews'` block with a real `ScoreCardWidget` (★ `avg.toStringAsFixed(1)` `(reviewCount)` from `AuthenticationService.instance.company`, no GoogleFonts), `footerIcon` opens `showReviewsDialog`. Added `namedReportCards(context)['reviews']!` to the compact grid (the full grid picks it up via `.values`).
- `ReviewsBloc` registered in `lib/app/di/bloc_providers.dart` (ReviewRepository was already provided in `repository_providers.dart`).
- **All 17 app tests pass; `flutter analyze` clean on all touched files.**

**Still remaining:**
- **Firestore rules — DEFERRED** (user chose to skip for now, 2026-06-02). NOTE: repo Firestore rules are NOT the source of truth — `apps/loans/firestore.rules` is the stale default template (its `allow` expired 2024-06-22) and `firebase.json` references only `firestore.indexes.json`; only `firestore:indexes` is deployed (`scripts/deploy-indexes.sh`). Real rules are **console-managed manually** (same pattern as prod RTDB rules). The review-response permission (admin/reviewModerator of the review's `provider_id` company may write only `response*` fields; borrowers read-only) must be added there separately.
- PR not yet opened; all work still uncommitted on `develop`.

---

## Lender payout accounts (2026-06-17, branch `feature/lender-payout-accounts`)

Makes the borrower-payment-submission feature usable: lenders had no way to set
bank details, so the borrower's Submit dialog was permanently blocked. Stacked on
`feature/borrower-payment-submission` (PR #65). Spec/plan in `docs/superpowers/`.

- **Lender CRUD** — `lib/features/bank_details/`: `BankDetailsBloc` (Load/Add/Update/Delete over `BaseRepository<BankDetails>`, scoped to `authService.company.id` + `DataType.provider`). `PayoutAccountsSection` + `showBankDetailsFormDialog` rendered inside `SettingsWidget`, gated to a self-managed company admin (`hasCompany && userRole.index > customer && managementType == selfManaged`). Delete is **soft** (repo sets `deletedAt`; `load` filters `deleted_at == null`).
- **Multiple accounts**: lender can keep several; the borrower Submit dialog shows a dropdown when >1 (auto-selects when exactly 1), Send requires a selection. The chosen account id is recorded via new `Payment.paidToBankDetailsId` (`paid_to_bank_details_id`). Payment Center pending-submission card resolves it (`get(id)`, cached + hasError-guarded) → "Paid to: <bank> …<last4>".
- **GOTCHA**: the `bank_details` stored id field is **`dataId`** (camelCase — `BankDetailsEntity.dataId` has NO `@JsonKey`, unlike its snake_case siblings). Query `field: 'dataId'`, NOT `data_id`. The original submit dialog used `data_id` and silently matched nothing — fixed.
- **Firestore rule** (console-managed, deferred): a company admin may write `bank_details` where `dataId == their company` — tracked with the payments rule.

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

### iOS migration (same PR, after CocoaPods became available)

- `ios/Podfile` platform uncommented and set to `iOS 13.0` (Flutter 3.44 rejects iOS 12 minimum).
- `IPHONEOS_DEPLOYMENT_TARGET` bumped 12.0 → 13.0 across all 9 flavor/build-type combinations in `Runner.xcodeproj/project.pbxproj`.
- Flutter auto-migrated:
  - **UIScene lifecycle**: `AppDelegate.swift` now uses `@main` + `FlutterImplicitEngineDelegate`, plugins register via `didInitializeImplicitFlutterEngine`. `Info.plist` gained `UIApplicationSceneManifest`.
  - `.gitignore` adds `.build/`, `.swiftpm/`.
  - `AppFrameworkInfo.plist` drops stale `MinimumOSVersion 11.0`.
  - `Runner.xcscheme` LastUpgradeVersion 1430 → 1510.
- `Podfile.lock` now tracked. Only 3 cocoapods remain (`flutter_keyboard_visibility`, `flutter_local_notifications`, `printing` — the non-SPM plugins) plus the `Flutter` runtime. Everything else (Firebase, AppCheck, etc.) moved to Swift Package Manager.

### SPM is enabled — repo moved to a no-space path

Flutter 3.44 auto-enables Swift Package Manager. Initially that **broke on the old project path** (`/Users/.../Anaheim Technologies/...`): Flutter URL-encodes the path when locating `pubspec.yaml` for SPM Package.swift, producing `%20` which never resolves to a real file. The repo was relocated to `/Users/deibeeed/Projects/AnaheimTechnologies/finstack` (no space) and SPM auto-integration now succeeds.

What SPM integration added when it succeeded:
- `Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` and `Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved` — SPM's lockfile equivalent. Tracked in git.
- `<PreActions>` block on each flavor xcscheme (`development`, `staging`, `production`) running `$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh prepare` before Xcode build. Generated per-flavor by `flutter build ios` — if you add a new flavor, run a build once to populate.
- `Podfile.lock` dropped from 1682 lines to 33 once SPM took over the bulk of dependencies.

The 3 plugins that don't yet support SPM still pull in via CocoaPods; both managers coexist transparently. `pod install` runs in <1 second after the first build because there's so little for it to do.

Future-Flutter warning: "Disabling Swift Package Manager will not be allowed in a future version of Flutter" — so this stays on, no caveat. If a future plugin or dependency needs the repo path to not have spaces again, keep it that way.

---

## Borrower Payment Submission — Flutter side (branch `feature/borrower-payment-submission`, finstack #64)

Borrowers can now submit their own payment proof for confirmation, instead of only tellers recording payments in the Payment Center.

- **`PaymentStatus` lifecycle** (`packages/loans/payment_repository`): `pending` / `confirmed` / `rejected`. `@JsonKey(defaultValue: PaymentStatus.confirmed)` so legacy + teller-created docs (no `status` field) deserialize as `confirmed` — no migration needed. Borrower submissions start `pending`; teller/force/OTP paths stay `confirmed`.
- **`submission_id` grouping**: Pay-in-full spans multiple schedules → all the payments from one submit share a single `submission_id`. Lets the Payment Center group a multi-schedule submission as one reviewable unit and lets the Go `paymentCreated` trigger de-dup lender notifications per submission.
- **`PaymentSubmissionBloc`** (`lib/features/payments/bloc/`) + submit dialog (`lib/features/payments/widget/`): borrower picks the lender's payout account (bank details via `BankDetailsRepository` filtered to `DataType.provider`), uploads a transaction screenshot, and the bloc writes one `pending` `Payment` per selected schedule. Open-term schedules carry `id == NO_ID` at submit time → payment is added first, then the schedule, then the payment is backfilled with the real `loan_schedule_id`. Schedules are flipped to `LoanStatus.payment_submitted`.
- **Payment Center pending-submissions**: tellers confirm/reject pending borrower submissions, reusing `PaymentConfirmationService` (same confirm/reject path that flips schedule status and writes `confirmed_by` / `confirmed_at` / `rejection_reason`). Covered by `test/features/payment_center/payment_center_confirm_test.dart`.
- **`loan_id` denormalized onto `Payment`** (`payment_entity.dart` / `payment.dart` `Payment.create(loanId:)`): every creation site now writes the real loan id directly on the payment. Needed because open-term payments are created with `loan_schedule_id = NO_ID`, so the Go trigger's schedule fallback can't resolve the loan at creation time — `loan_id` makes lender notification work for all loan types. Wired at all three `Payment.create` sites: borrower `PaymentSubmissionBloc._onSubmit` (`loanId: event.loanId`), teller `PaymentCenterBloc._handleMakePaymentEvent` and `_handleMakeOverduePaymentEvent` (`loanId: loan.id` + explicit `status: PaymentStatus.confirmed` for intent clarity — default was already confirmed, no behavior change).
- **DEFERRED**: the Firestore security rule for *who* may write/confirm payments (borrower may create `pending`; only teller/admin may move to `confirmed`/`rejected`) is still managed in the console, not in repo rules. Close this before relying on the rule for authorization.

---

## Server-side user provisioning — Phase C (frontend) — branch `feat/user-provisioning-frontend` → PR closes finstack #69

Phase C is the Flutter half of moving admin-initiated user creation server-side (Phase A=PR #70 backend, B=PR #72 hosting — both merged + deployed to dev). It fixes finstack #2 properly (an admin adding a user no longer client-side-mints an account / replaces the admin session) and supersedes #69. Spec/plan in `docs/superpowers/`. Delivered in 4 groups (G1–G4), each via implement→spec-review→quality-review.

- **G1 — data layer** (`packages/core/user_repository`): `UserNetworkService`/`UserRepository.createUser({role, user, address, idToken}) → ({uid, inviteSent})` (POST `/api/users/add`) + `sendPasswordSetupLink({email})` (POST `/api/users/password/setup-link`, unauth); dropped the unused `createUserAccess`. New `User.createInvited({required role, ...})` factory (uid-less `NO_ID`, email required, photos optional). Surfaced `invited_by_admin` on `UserEntity` (the server-stamped flag) + regenerated `.g.dart`.
- **G2/G3 — the "admin adds a user" rework** (`RegistrationBloc` + form + entries): new `SubmitInvitedUserEvent` + server-backed `_handleSubmitInvitedUser` (uploads optional photos, `User.createInvited`, calls `userRepository.createUser(role: role.name, ...)`); `registerInvitedUser(data, {role})` replaces the old `registerManagedUser`/managed handler. `RegisterScreenFormUsersWidget` now carries `isAdminCreating` + `isTeamMemberMode` (replacing `isUserCompanyManaged`): email always required; password/facebook/selfie/profile-pic-required only for self-registration; a staff role picker (`UserRole.companyManagedRoles`) in team-member mode. **Two entries:** "Add team member" (users_screen; both company types) routes through the new path; "Add Borrower" (borrowers_screen + layout_widgets) gated on `allowAddClients` (selfManaged only). Added `RegistrationBloc.withDependencies` seam (widens `_companyRepository`/`_addressRepository` to `BaseRepository<T>` — the concrete classes are `final` → unmockable). **Key fix found mid-build:** the old "Add User" entry passed `forCompanyUser: true`, routing to `RegisterScreenFormProvidersWidget`→`registerProvider`→client-side `createUserCredential` (temp pw `Password123!`) — i.e. bug #2 for staff too; flipped to the server path. Self-registration and provider self-signup left untouched.

Three commits on the dead-code/resend-invite/forgot-password slice (G4):

- **C8 — `refactor: remove dead user-creation paths` (89ef8fc)**: deleted the now-unused client-side user-creation paths — `UserBloc.addUser` / `AddUserEvent` / `_handleAddUserEvent`, the `User.createManagedCustomer` factory (shared package `packages/core/user_repository`), and the dead `forCompanyUser` branch + param in `showAddUserWidget` (`dialog_widgets.dart` + `app_widgets.dart`), collapsing it to the `AddUserWidget` path. Removed the now-unused `extensions.dart` / `string_helpers.dart` / `RegisterScreenFormProvidersWidget` imports. Provider self-registration and the `registerCompanyManagedUser` machinery left fully intact (now dead-but-harmless, follow-up).
- **C9 — `feat(users): admin Resend invite action` (d23350b)**: `UserBloc.resendInvite` + `ResendInviteEvent` + handler calling `sendPasswordSetupLink`, emitting `UserState.success("Invite re-sent.")` / `error`. UI: a per-row "Resend invite" `IconButton` on the **Users screen** (`lib/features/users/screens/users_screen.dart`, the compact/medium team-member ListView rows) gated to team managers (`_canResendInvite`) with a non-empty target email, plus a `BlocListener<UserBloc, UserState>` SnackBar. (Chose `users_screen.dart` over `client_detail_action_buttons.dart` — the latter is loan-scoped, not a per-user panel.)
- **C10 — `feat(auth): login Forgot password (set/reset link)` (555dee0)**: `AuthenticationBloc.forgotPassword` + `ForgotPasswordEvent` + handler that calls `sendPasswordSetupLink` and emits the SAME neutral `success` message on both happy + error paths (never leaks whether the account exists). Login screen: small email-prompt `AlertDialog` (`_showForgotPasswordDialog`) dispatches it; the `BlocConsumer` success branch now shows the neutral message **inline as a SnackBar when `AuthenticationService.instance.isLoggedIn == false`** (forgot-password) and only navigates on a real login — preserving normal login-success routing.

### Test-seam pattern note (important)
Added `UserBloc.withDependencies` and `AuthenticationBloc.withDependencies` mirroring `RegistrationBloc.withDependencies`. Gotcha: `AddressRepository`, `CompanyRepository`, `SettingsRepository`, `UserLoanViewRepository` are all `final class` → **cannot be mocked with mocktail** (`invalid_use_of_type_outside_library`). Where the bloc only calls `BaseRepository` methods on one (e.g. `UserLoanViewRepository`, unused in `UserBloc`), the seam types it as `BaseRepository<T>` so it IS mockable. Where the bloc calls a concrete method (`AddressRepository.getByDataType`, or passes the repo into `SessionLoader.loadSession` which needs concrete types), the field stays concrete but the seam makes it an **optional nullable param** (guarded with `!` at the real call sites, which the resend-invite/forgot-password tests never reach). The default `BuildContext` ctors are unchanged → production behavior identical.

- Tests: `test/features/users/user_bloc_resend_invite_test.dart` (success + error), `test/features/authentication/authentication_bloc_forgot_password_test.dart` (success + error-still-neutral). All pass.
- `fvm flutter analyze` (whole app): zero net-new issues vs the pre-work baseline (6224 before == 6224 after, line-number-normalized diff empty).
- Still console-managed before prod: nothing new here, but the password-setup-link backend (Phase A, PR #70) must be deployed for these flows to actually deliver email.

---

## Notification permission no longer blocks startup (branch `fix/notification-permission-blocking-startup`)

Found during the chat dev smoke test (2026-07-09): the deployed dev web app rendered a **blank page indefinitely** because `bootstrap()` did `await requestPermissions()` **before `runApp()`** — the whole app waited on the browser's notification-permission prompt. Additionally, `requestPermissions()` recursed on any non-authorized status; since browsers won't re-show the prompt after an explicit deny, a denial spun a permanent `getNotificationSettings`/`requestPermission` busy-loop.

- Fix in `lib/bootstrap.dart`: `runApp()` first, then `unawaited(requestPermissions())`; the request only fires when `authorizationStatus == notDetermined` (never re-prompts on denial).
- Timing note: on web, FCM `getToken` needs granted permission — and with a restored session, `NotificationService.initializeToken()` (router init, right after `runApp`) can now run while the prompt is still pending. On web the JS SDK's `getToken` awaits the same prompt and REJECTS (`messaging/permission-blocked`) on denial; the `.then` chain had no error handler, so review hardening added a `catchError` that logs instead of surfacing an unhandled async rejection (no token on denial is correct).
- Drive-by in the same file: `print` → `debugPrint` in `showFlutterNotification` (pre-existing `avoid_print` from monorepo-genesis commit `275ad55`).

---

## Chat blocs never received data — dataStream subscribed before loadNext (branch `fix/chat-dead-stream-subscription`)

Caught by the dev smoke test (2026-07-09), right after the startup fix unblocked the UI: the Messages screen body stayed blank forever — the inbox query's results never reached the bloc. (The orphaned query itself still opened a Firestore listener — `addStream` subscribes its source regardless of controller listeners — the data just poured into a controller nobody was listening to.)

- **Cause:** in the chat services, **every** `loadNext` call (the `reset` flag is ignored there) runs `resetStreamController()`, which **replaces** the controller behind `dataStream`. `ConversationsBloc` and `ChatBloc` subscribed to `dataStream` in their constructors and called `loadNext` afterwards — leaving their subscriptions on the old, dead controller. Inbox and chat-room messages could never load. Working blocs (LoansBloc/ProductBloc) don't hit this because they expose `dataStream` as a getter consumed at widget build time; the loans-style services also gate their resets on `switchStream`, not `reset`.
- **Why tests missed it:** the bloc tests mocked the repository with a fixed stream and stubbed `loadNext` — the reset never happens under mocks. Beware of this pattern generally: any bloc that `.listen()`s a repo `dataStream` before calling `loadNext` is broken in production and green under mocktail. **Regression tests now exist** (`_ResettingFakeRepo` / `_ResettingFakeMessages` in the chat bloc tests) — the fakes swap their controller on `loadNext` like the real service.
- **Fix (after adversarial review of the first cut):** in both chat blocs, `_onSubscribe` is fully synchronous — `if (isClosed) return` guard (bloc 8.1.4's default transformer is CONCURRENT and `close()` drains pending events), then cancel-old-sub → `loadNext` → listen, in one turn. Chat services now hold their query subscription (`_querySub`) and cancel it on every `loadNext` + expose `dispose()` (called from `ChatBloc.close()`, since `MessageRepository` is per-room) — the chat-side listener leak is gone. `ConversationsScreen` no longer re-dispatches Subscribe in `initState` (the bloc auto-subscribes). The `/chat/:roomId` route is keyed by `roomId` — go_router reuses the page element on param-only changes (`/chat/A → /chat/B`, exactly what the FCM chat-tap does), which would otherwise keep room A's bloc alive and send messages to the wrong room. Inbox row: "Awaiting" chip moved to the subtitle line (the trailing stack overflowed 28px).
- **Follow-up worth filing:** the same abandon-the-controller-mid-addStream leak exists in the ~20 loans-style services (gated on `switchStream` there). A base-level `pipe()` helper in `BaseFirestoreService` that holds and cancels the source subscription would fix the class; chat services demonstrate the shape.

---

## OTP error surfacing — passthrough narrowed, verifyOtp covered, tests wired to CI (branch `feature/otp-error-surfacing`, finstack #91, 2026-08-12)

The Go OTP endpoints return 400s written for end users; this branch surfaces them instead of a generic "Cannot request OTP". An independent review found the first implementation leaked internals and broke a payment flow:

- **The 4xx window was too wide.** `userMessage` echoed any `400-499` body, but `ValidateRequestV2` runs *before* any OTP logic and emits **401** with raw Go/Firebase SDK text — including `firebase admin initialization error: google: could not find default credentials...` — plus a bare `Unauthorized` for the common expired-token case. All of it rendered verbatim in user snackbars. **Only 400 is passed through now**; 401 maps to a sign-in prompt, everything else to a generic message.
- **`verifyOtp` had the same bug one method away**, still throwing a raw `HttpException` that surfaced as `Cannot verify OTP: HttpException: Verify OTP error: 400 OTP expired`. Both endpoints now share an `OtpApiException` base (`RequestOtpException`, `VerifyOtpException`), exported from `user_repository`.
- **`userMessageOr(fallback)`** lets each flow keep its own wording. The first implementation retired the payment flows' `'Failed to send OTP'` for the auth flow's copy on every HTTP failure, including 5xx.
- **`PaymentCenterStatus.otpError` (new)**: OTP failures previously emitted `PaymentCenterStatus.error`, and `payment_center_screen.dart` pops the topmost **root** route on `error`. During the OTP step that route is the OTP dialog itself (`showDialog(barrierDismissible: false)`, default `useRootNavigator: true`, `initState` dispatches `RequestOtpEvent`), so the dialog was popped, resolved `null`, and the caller abandoned the payment — the actionable message tore down the flow it was explaining how to fix. It also removed a duplicate snackbar, since both listeners reacted to `error`. **Do not route recoverable OTP failures through `error`.** (This was pre-existing on `develop`, not introduced by the branch.)
- Expected 4xx rejections log at `warning`, not `severe`.

### Test seams and CI

- **`PaymentBloc.withDependencies` / `PaymentCenterBloc.withDependencies`** added, mirroring `AuthenticationBloc`/`RegistrationBloc`. Neither bloc could be constructed without a `BuildContext`, so neither had *any* test. `cashPoolRepository`, `productRepository` (final classes — unmockable) and `settingsService` (`SettingsService.instance` throws until app init) are optional and `late`, so a test that reaches a handler needing them fails loudly rather than using a stand-in.
- **No workflow ran `flutter test` before this branch** — the green checks proved only that the web build compiled. `loans-app-development.yml` now gates on package + app tests. See root `MEMORY.md` for the codegen-ordering constraint and the two deleted scaffold tests.
