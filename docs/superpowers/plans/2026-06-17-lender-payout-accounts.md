# Lender Payout Accounts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Let a self-managed lender manage multiple payout bank accounts in Settings, let the borrower choose which to pay to, and record the chosen account on the payment.

**Architecture:** Reuse `BankDetailsRepository` (CRUD, soft delete). New `BankDetailsBloc` + a "Payout accounts" section in `SettingsWidget`. Extend the borrower submit dialog (account dropdown) and `Payment` (`paid_to_bank_details_id`). Payment Center resolves the id for display. Frontend-only.

**Tech Stack:** Flutter (Dart, BLoC, json_serializable).

**Spec:** `docs/superpowers/specs/2026-06-17-lender-payout-accounts-design.md`

**Conventions:** `fvm flutter`/`fvm dart`; single quotes; `debugPrint` not `print`; do NOT modify `packages/core`/`packages/loans` except `payment_repository` (Task 1). Regen codegen: `cd packages/loans/payment_repository && fvm dart run build_runner build --delete-conflicting-outputs` (`*.g.dart` gitignored). Branch `feature/lender-payout-accounts` (already created).

**Key facts (verified):**
- `BankDetails.create({required String dataId, required DataType dataType, required String bankName, required String accountNumber, required String accountName})`; id is `NO_ID` until added. Stored id field is `dataId` (camelCase). `DataType.provider` for a lender/company. From `package:bank_details_repository/bank_details_repository.dart`.
- `BankDetailsRepository implements BaseRepository<BankDetails>`: `add/update/delete/load/get`. `delete` is soft (sets `deletedAt`); `load` auto-filters `deleted_at == null`. `load(statements: [QueryStatement(field: 'dataId', isEqualTo: companyId)])`.
- `authService.company.id` (the lender company); `authService.user.userRole` (`UserRole`, `customer` is lowest index). `authService.company.managementType == CompanyManagementType.selfManaged` gates lender write-actions (see `payment_center_bloc.dart`).
- `SubmitPaymentEvent({required schedules, required loanId, required fileBytes, required fileName})` in `apps/loans/lib/features/payments/bloc/payment_submission_event.dart`.

---

## Task 1: Add `paidToBankDetailsId` to Payment

**Files:** Modify `packages/loans/payment_repository/lib/src/model/payment_entity.dart`, `payment.dart`; test `packages/loans/payment_repository/test/src/payment_test.dart`.

- [ ] **Step 1: Failing test** — append a `group` to `payment_test.dart`:
```dart
  test('round-trips paid_to_bank_details_id', () {
    final json = baseJson()..['paid_to_bank_details_id'] = 'bd-1';
    final p = PaymentEntity.fromJson(json);
    expect(p.paidToBankDetailsId, 'bd-1');
    expect(p.toJson()['paid_to_bank_details_id'], 'bd-1');
  });
```
(`baseJson()` already exists in that file.)

- [ ] **Step 2:** Run `cd packages/loans/payment_repository && fvm flutter test test/src/payment_test.dart` → compile failure.

- [ ] **Step 3:** In `payment_entity.dart` add (next to `loanId`), include in `props` and the `toPayment()` cascade (mirror `loanId`):
```dart
  @JsonKey(name: 'paid_to_bank_details_id')
  String? paidToBankDetailsId;
```

- [ ] **Step 4:** In `payment.dart` `Payment.create`, add param `String? paidToBankDetailsId,` and `..paidToBankDetailsId = paidToBankDetailsId` to the cascade.

- [ ] **Step 5:** Regen: `cd packages/loans/payment_repository && fvm dart run build_runner build --delete-conflicting-outputs`. Confirm `paid_to_bank_details_id` in `payment_entity.g.dart`.

- [ ] **Step 6:** `fvm flutter test` (package) → pass. `fvm flutter analyze lib test` → clean (ignore the pre-existing `PaymentEntity._` unused warning).

- [ ] **Step 7: Commit**
```bash
git add packages/loans/payment_repository/lib/src/model/payment_entity.dart packages/loans/payment_repository/lib/src/model/payment.dart packages/loans/payment_repository/test/src/payment_test.dart
git commit -m "feat(payments): add paid_to_bank_details_id to Payment"
```

---

## Task 2: `BankDetailsBloc` (CRUD)

**Files:** Create `apps/loans/lib/features/bank_details/bloc/bank_details_bloc.dart` (+ `_event.dart`, `_state.dart`); test `apps/loans/test/features/bank_details/bloc/bank_details_bloc_test.dart`.

> Mirror the existing `ReviewsBloc` (`apps/loans/lib/features/reviews/bloc/reviews_bloc.dart`) for the two-constructor + `BaseRepository<T>` pattern. READ it first.

- [ ] **Step 1: Events** (`bank_details_event.dart`):
```dart
part of 'bank_details_bloc.dart';

sealed class BankDetailsEvent {}

final class LoadBankDetailsEvent extends BankDetailsEvent {}

final class AddBankDetailsEvent extends BankDetailsEvent {
  AddBankDetailsEvent({
    required this.bankName,
    required this.accountName,
    required this.accountNumber,
  });
  final String bankName;
  final String accountName;
  final String accountNumber;
}

final class UpdateBankDetailsEvent extends BankDetailsEvent {
  UpdateBankDetailsEvent({required this.bankDetails});
  final BankDetails bankDetails;
}

final class DeleteBankDetailsEvent extends BankDetailsEvent {
  DeleteBankDetailsEvent({required this.bankDetails});
  final BankDetails bankDetails;
}
```

- [ ] **Step 2: State** (`bank_details_state.dart`):
```dart
part of 'bank_details_bloc.dart';

enum BankDetailsStatus { initial, loading, loaded, saving, error }

final class BankDetailsState extends Equatable {
  const BankDetailsState({
    this.status = BankDetailsStatus.initial,
    this.accounts = const [],
    this.message,
  });

  final BankDetailsStatus status;
  final List<BankDetails> accounts;
  final String? message;

  BankDetailsState copyWith({
    BankDetailsStatus? status,
    List<BankDetails>? accounts,
    String? message,
  }) =>
      BankDetailsState(
        status: status ?? this.status,
        accounts: accounts ?? this.accounts,
        message: message,
      );

  @override
  List<Object?> get props => [status, accounts, message];
}
```

- [ ] **Step 3: Bloc** (`bank_details_bloc.dart`):
```dart
import 'package:bank_details_repository/bank_details_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'bank_details_event.dart';
part 'bank_details_state.dart';

class BankDetailsBloc extends Bloc<BankDetailsEvent, BankDetailsState> {
  BankDetailsBloc(BuildContext context)
      : this.withDependencies(
          bankDetailsRepository: context.read<BaseRepository<BankDetails>>(),
          authService: AuthenticationService.instance,
        );

  BankDetailsBloc.withDependencies({
    required this.bankDetailsRepository,
    required this.authService,
  }) : super(const BankDetailsState()) {
    on<LoadBankDetailsEvent>(_onLoad);
    on<AddBankDetailsEvent>(_onAdd);
    on<UpdateBankDetailsEvent>(_onUpdate);
    on<DeleteBankDetailsEvent>(_onDelete);
  }

  final BaseRepository<BankDetails> bankDetailsRepository;
  final AuthenticationService authService;

  Future<List<BankDetails>> _load() async {
    final all = await bankDetailsRepository.load(
      reset: true,
      limit: null,
      statements: [
        QueryStatement(field: 'dataId', isEqualTo: authService.company.id),
      ],
    );
    return all.where((b) => b.dataType == DataType.provider).toList();
  }

  Future<void> _onLoad(
    LoadBankDetailsEvent event,
    Emitter<BankDetailsState> emit,
  ) async {
    emit(state.copyWith(status: BankDetailsStatus.loading));
    try {
      emit(state.copyWith(
        status: BankDetailsStatus.loaded,
        accounts: await _load(),
      ));
    } catch (err) {
      emit(state.copyWith(
        status: BankDetailsStatus.error,
        message: 'Failed to load payout accounts',
      ));
    }
  }

  Future<void> _onAdd(
    AddBankDetailsEvent event,
    Emitter<BankDetailsState> emit,
  ) async {
    emit(state.copyWith(status: BankDetailsStatus.saving));
    try {
      await bankDetailsRepository.add(
        data: BankDetails.create(
          dataId: authService.company.id,
          dataType: DataType.provider,
          bankName: event.bankName,
          accountName: event.accountName,
          accountNumber: event.accountNumber,
        ),
      );
      emit(state.copyWith(
        status: BankDetailsStatus.loaded,
        accounts: await _load(),
      ));
    } catch (err) {
      emit(state.copyWith(
        status: BankDetailsStatus.error,
        message: 'Failed to add account',
      ));
    }
  }

  Future<void> _onUpdate(
    UpdateBankDetailsEvent event,
    Emitter<BankDetailsState> emit,
  ) async {
    emit(state.copyWith(status: BankDetailsStatus.saving));
    try {
      await bankDetailsRepository.update(data: event.bankDetails);
      emit(state.copyWith(
        status: BankDetailsStatus.loaded,
        accounts: await _load(),
      ));
    } catch (err) {
      emit(state.copyWith(
        status: BankDetailsStatus.error,
        message: 'Failed to update account',
      ));
    }
  }

  Future<void> _onDelete(
    DeleteBankDetailsEvent event,
    Emitter<BankDetailsState> emit,
  ) async {
    emit(state.copyWith(status: BankDetailsStatus.saving));
    try {
      await bankDetailsRepository.delete(data: event.bankDetails);
      emit(state.copyWith(
        status: BankDetailsStatus.loaded,
        accounts: await _load(),
      ));
    } catch (err) {
      emit(state.copyWith(
        status: BankDetailsStatus.error,
        message: 'Failed to delete account',
      ));
    }
  }
}
```

- [ ] **Step 4: Test** (`bank_details_bloc_test.dart`) — mock `BaseRepository<BankDetails>` and `AuthenticationService` (+ `Company`). Cover: Load emits loaded with filtered provider accounts; Add calls `add` with `dataType: provider` + reloads; Delete calls `delete` + reloads. Mirror `reviews_bloc_test.dart` setup. Run `cd apps/loans && fvm flutter test test/features/bank_details` → pass.

- [ ] **Step 5: Commit**
```bash
git add apps/loans/lib/features/bank_details apps/loans/test/features/bank_details
git commit -m "feat(bank-details): BankDetailsBloc CRUD for lender payout accounts"
```

---

## Task 3: "Payout accounts" section in Settings + DI

**Files:** Modify `apps/loans/lib/widgets/settings_widget.dart`; create `apps/loans/lib/features/bank_details/widget/payout_accounts_section.dart`, `apps/loans/lib/features/bank_details/widget/bank_details_form_dialog.dart`; modify `apps/loans/lib/app/di/bloc_providers.dart`.

- [ ] **Step 1:** Register `BlocProvider(create: BankDetailsBloc.new)` in `bloc_providers.dart` (+ import). (`BankDetailsRepository` is already registered as `BaseRepository<BankDetails>` in `repository_providers.dart`.)

- [ ] **Step 2:** `bank_details_form_dialog.dart` — `Future<({String bankName, String accountName, String accountNumber})?> showBankDetailsFormDialog(BuildContext, {BankDetails? existing})`: an `AlertDialog` with 3 required `TextFormField`s (prefilled from `existing`), returns the entered values on Save (or null on cancel). Use the app's form style.

- [ ] **Step 3:** `payout_accounts_section.dart` — `PayoutAccountsSection` widget:
  - Wrap in `BlocProvider(create: BankDetailsBloc.new)` and dispatch `LoadBankDetailsEvent` on init (a small `StatefulWidget` or `BlocProvider(..., child: Builder)` that adds the event).
  - Header "Payout accounts" + a `BlocBuilder<BankDetailsBloc, BankDetailsState>`:
    - loading → spinner; loaded empty → "No payout accounts yet"; loaded → a list of rows `bank · accountName · accountNumber` each with an Edit (`showBankDetailsFormDialog(existing: acct)` → `UpdateBankDetailsEvent(bankDetails: acct..bankName=.. etc)`) and a Delete (confirm → `DeleteBankDetailsEvent`).
  - "+ Add account" button → `showBankDetailsFormDialog()` → `AddBankDetailsEvent(...)`.
  - READ how `BankDetails` fields are mutated for update (the entity has settable `bankName`/`accountName`/`accountNumber`); construct the updated object from the existing one + new values.

- [ ] **Step 4:** In `settings_widget.dart`, render `const PayoutAccountsSection()` **only for a self-managed company admin**: gate on `AuthenticationService.instance.hasCompany && AuthenticationService.instance.user.userRole.index > UserRole.customer.index && AuthenticationService.instance.company.managementType == CompanyManagementType.selfManaged`. READ the file first to place it cleanly and match its layout (it's a form column).

- [ ] **Step 5:** Widget test `apps/loans/test/features/bank_details/widget/payout_accounts_section_test.dart`: with a mocked bloc (`MockBloc`) seeded with two accounts → both rows render + "Add account" present; tapping Add (and completing the form) adds an `AddBankDetailsEvent` (verify). Mirror an existing widget test that uses `MockBloc`/`whenListen`.

- [ ] **Step 6:** `cd apps/loans && fvm flutter analyze lib/features/bank_details lib/widgets/settings_widget.dart lib/app/di && fvm flutter test test/features/bank_details` → clean + pass.

- [ ] **Step 7: Commit**
```bash
git add apps/loans/lib/features/bank_details apps/loans/lib/widgets/settings_widget.dart apps/loans/lib/app/di apps/loans/test/features/bank_details
git commit -m "feat(bank-details): lender payout accounts management in Settings"
```

---

## Task 4: Borrower dialog — choose account + record id

**Files:** Modify `apps/loans/lib/features/payments/widget/submit_payment_dialog.dart`, `apps/loans/lib/features/payments/bloc/payment_submission_event.dart`, `apps/loans/lib/features/payments/bloc/payment_submission_bloc.dart`; tests `apps/loans/test/features/payments/...`.

- [ ] **Step 1:** Add `String? bankDetailsId` to `SubmitPaymentEvent` (new required-ish field; make it `required String bankDetailsId` since a submission must target an account). In `payment_submission_bloc.dart` `_onSubmit`, pass `paidToBankDetailsId: event.bankDetailsId` to `Payment.create(...)`. Update the existing bloc tests to pass `bankDetailsId: 'bd-1'` and assert the created payment's `paidToBankDetailsId == 'bd-1'`.

- [ ] **Step 2:** In `submit_payment_dialog.dart` `_loadBankDetails`, keep the FULL filtered list (rename `_bankDetails` usage): store `List<BankDetails> _accounts` and a `BankDetails? _selected`. On load: if 1 account, auto-select it; if >1, leave `_selected` null.

- [ ] **Step 3:** In `build`:
  - `hasBankDetails` → `_accounts.isNotEmpty`.
  - If `_accounts.length > 1`: render a `DropdownButton<BankDetails>` (items labelled `'${a.bankName} ·…${a.accountNumber.length >= 4 ? a.accountNumber.substring(a.accountNumber.length - 4) : a.accountNumber}'`) bound to `_selected` (setState on change). If `== 1`: show the single account's details (as today). If `0`: existing "not set up" message.
  - Show the selected account's `bankName`/`accountName`/`accountNumber` block when `_selected != null`.
  - `canSend = _selected != null && hasFile && !submitting` (selection now required).
  - On Send: `add(SubmitPaymentEvent(schedules: widget.schedules, loanId: widget.loanId, fileBytes: _fileBytes!, fileName: _fileName!, bankDetailsId: _selected!.id))`.

- [ ] **Step 4:** Update the dialog widget test: the existing "bank details present" case now has exactly one account → auto-selected, Send enabled once a file is chosen (the test already can't pick a file, so assert Send stays disabled with no file but the account renders). Add a case with two accounts → a dropdown is shown and Send is disabled until selection. Mirror existing structure.

- [ ] **Step 5:** `cd apps/loans && fvm flutter analyze lib/features/payments && fvm flutter test test/features/payments` → clean + pass.

- [ ] **Step 6: Commit**
```bash
git add apps/loans/lib/features/payments apps/loans/test/features/payments
git commit -m "feat(payments): borrower selects which payout account to pay to"
```

---

## Task 5: Payment Center — show "Paid to"

**Files:** Modify `apps/loans/lib/features/payment_center/widget/pending_submission_section.dart`.

- [ ] **Step 1:** In `_PendingSubmissionCard`, read the submission's first payment `paidToBankDetailsId`. If non-null, resolve it via `context.read<BaseRepository<BankDetails>>().get(id: ...)` (a `FutureBuilder`) and render a small "Paid to: `${bank.bankName}` …`${last4}`" line. If null or the lookup fails, render nothing (graceful). Match the card's existing text style.

- [ ] **Step 2:** `cd apps/loans && fvm flutter analyze lib/features/payment_center/widget/pending_submission_section.dart` → clean. `cd apps/loans && fvm flutter test test/features/payment_center` → pass.

- [ ] **Step 3: Commit**
```bash
git add apps/loans/lib/features/payment_center/widget/pending_submission_section.dart
git commit -m "feat(payments): show which payout account a submission targeted"
```

---

## Task 6: Full verification + docs + PR

- [ ] **Step 1:** `cd apps/loans && fvm flutter test` (full) → green. `cd packages/loans/payment_repository && fvm flutter test` → green. `cd apps/loans && fvm flutter analyze lib` → no new issues.

- [ ] **Step 2:** Append a section to `apps/loans/MEMORY.md`: lender payout accounts (multiple, in Settings, soft-deleted), borrower account selection, `paid_to_bank_details_id` on Payment, the `dataId` (camelCase) query gotcha, and that the Firestore rule for company admins writing `bank_details` is console-managed.

- [ ] **Step 3: Commit**
```bash
git add apps/loans/MEMORY.md
git commit -m "chore(bank-details): memory + final verification"
```

- [ ] **Step 4:** Push and open a PR with base `feature/borrower-payment-submission` (retarget to `develop` once #65 merges), summarizing the lender CRUD + borrower selection, linking the spec, and noting the console-managed `bank_details` write rule.

---

## Self-Review

- Lender adds/edits/deletes accounts → Task 2 (bloc) + Task 3 (UI). ✓
- Borrower chooses when >1, records id → Task 4. ✓
- Lender sees where money went → Task 5. ✓
- Multiple accounts, soft delete → repo reused; list UI. ✓
- Model field `paid_to_bank_details_id` consistent across Tasks 1/4/5. ✓
- Type consistency: `BankDetailsBloc`, `BankDetailsState.accounts`, `DataType.provider`, `field: 'dataId'`, `paidToBankDetailsId` used consistently. ✓
