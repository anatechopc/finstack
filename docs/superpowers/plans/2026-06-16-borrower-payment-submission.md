# Borrower Payment Submission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a borrower pay a loan by uploading a bank-transfer screenshot as proof; the payment stays pending until a lender confirms or rejects it from the Payment Center.

**Architecture:** Reuse the existing `Payment` model + `StorageRepository` + the teller "mark schedule paid" logic. Add a `PaymentStatus` lifecycle to `Payment`. A new borrower `PaymentSubmissionBloc` creates pending payments (Pay now = 1 schedule, Pay in full = N schedules sharing a `submission_id`). The Payment Center gains a pending-submissions view whose confirm/reject reuses an extracted shared `PaymentConfirmationService`. Go: de-dup the `paymentCreated` notification per submission and add a `paymentUpdated` trigger to notify the borrower on confirm/reject.

**Tech Stack:** Flutter (Dart, BLoC, json_serializable codegen), Firebase (Firestore, Storage), Go Cloud Functions (adapter+core).

**Spec:** `docs/superpowers/specs/2026-06-16-borrower-payment-submission-design.md` · **Issue:** finstack#64

**Conventions (read once):**
- `fvm flutter` for all Flutter commands; never bare `flutter`. Run from `apps/loans/`.
- Regenerate model code in a package: `cd packages/<group>/<pkg> && fvm dart run build_runner build --delete-conflicting-outputs`. `*.g.dart` is gitignored.
- Run a single test file: `fvm flutter test test/path/file_test.dart`.
- Go tests on macOS: `cd functions/loans && CGO_ENABLED=0 go test ./...`. Each sub-dir (`api/`, `triggers/`, `utils/`, `types/`, `test/`) is its own module.
- Date fields are int millis (`handleDateTimeToJson`/`handleDateTimeFromJson`). Go writers MUST use `.UnixMilli()`.
- Branch: `feature/borrower-payment-submission` (already created off `develop`).

---

## File Structure

**Create:**
- `packages/loans/payment_repository/lib/src/model/payment_status.dart` — the status enum.
- `packages/loans/payment_repository/test/src/payment_test.dart` — model status/round-trip tests.
- `apps/loans/lib/features/payments/bloc/payment_submission_bloc.dart` (+ `_event.dart`, `_state.dart`) — borrower submit flow.
- `apps/loans/lib/features/payments/widget/submit_payment_dialog.dart` — borrower dialog (bank details + amount + screenshot picker).
- `apps/loans/lib/services/payment_confirmation_service.dart` — shared confirm/reject logic (mark schedule paid / reverted), reused by teller + lender.
- `apps/loans/test/features/payments/bloc/payment_submission_bloc_test.dart`
- `apps/loans/test/services/payment_confirmation_service_test.dart`
- `functions/loans/triggers/payment_updated.go` — borrower confirm/reject notification.
- `functions/loans/test/triggers/payment_updated_test.go`

**Modify:**
- `packages/loans/payment_repository/lib/src/model/payment_entity.dart` — add `status`, `rejection_reason`, `submission_id`.
- `packages/loans/payment_repository/lib/src/model/payment.dart` — `Payment.create(...)` gains `status`, `submissionId`; add `markConfirmed`/`markRejected` helpers.
- `apps/loans/lib/features/loans/screens/loan_details.dart:_nextPayment` — wire Pay now / Pay in full → `showSubmitPaymentDialog`.
- `apps/loans/lib/app/di/bloc_providers.dart` — register `PaymentSubmissionBloc`.
- `apps/loans/lib/features/payment_center/` (bloc + screen) — add pending-submissions view + confirm/reject using `PaymentConfirmationService`.
- `functions/loans/triggers/payment_created.go` — de-dup notification per `submission_id`.
- `functions/loans/loooans_cloud_functions.go` — register `paymentUpdated`.
- `.github/scripts/deploy_functions.sh` — deploy `paymentUpdated`.
- `functions/loans/MEMORY.md`, `apps/loans/MEMORY.md` — log the work.

---

## Phase 1 — Payment status lifecycle (model)

### Task 1: Add the `PaymentStatus` enum

**Files:**
- Create: `packages/loans/payment_repository/lib/src/model/payment_status.dart`
- Modify: `packages/loans/payment_repository/lib/payment_repository.dart` (barrel export)

- [ ] **Step 1: Create the enum**

```dart
// packages/loans/payment_repository/lib/src/model/payment_status.dart
enum PaymentStatus {
  /// Borrower submitted proof; awaiting a lender's confirm/reject.
  pending('Pending'),

  /// A lender confirmed the payment (also the default for teller-created and
  /// legacy payment documents that predate this field).
  confirmed('Confirmed'),

  /// A lender rejected the proof; the borrower may resubmit.
  rejected('Rejected');

  const PaymentStatus(this.label);

  final String label;
}
```

- [ ] **Step 2: Export it from the barrel**

Read `packages/loans/payment_repository/lib/payment_repository.dart`; add (next to the other model exports):

```dart
export 'src/model/payment_status.dart';
```

- [ ] **Step 3: Verify it compiles**

Run: `cd packages/loans/payment_repository && fvm flutter analyze lib/src/model/payment_status.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add packages/loans/payment_repository/lib/src/model/payment_status.dart packages/loans/payment_repository/lib/payment_repository.dart
git commit -m "feat(payments): add PaymentStatus enum"
```

### Task 2: Add status fields to `PaymentEntity` + `Payment.create`

**Files:**
- Modify: `packages/loans/payment_repository/lib/src/model/payment_entity.dart`
- Modify: `packages/loans/payment_repository/lib/src/model/payment.dart`
- Test: `packages/loans/payment_repository/test/src/payment_test.dart` (create)

- [ ] **Step 1: Write the failing test**

```dart
// packages/loans/payment_repository/test/src/payment_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_repository/src/model/payment.dart';
import 'package:payment_repository/src/model/payment_entity.dart';
import 'package:payment_repository/src/model/payment_status.dart';

Map<String, dynamic> baseJson() => <String, dynamic>{
      'created_at': 1726137187726,
      'updated_at': 1726137187726,
      'id': 'pay-1',
      'user_id': 'user-1',
      'loan_schedule_id': 'sched-1',
    };

void main() {
  group('PaymentEntity status lifecycle', () {
    test('defaults to confirmed when status is absent (legacy/teller docs)', () {
      final p = PaymentEntity.fromJson(baseJson());
      expect(p.status, PaymentStatus.confirmed);
    });

    test('round-trips status / rejection_reason / submission_id', () {
      final json = baseJson()
        ..['status'] = 'pending'
        ..['rejection_reason'] = 'blurry'
        ..['submission_id'] = 'sub-9';
      final p = PaymentEntity.fromJson(json);
      expect(p.status, PaymentStatus.pending);
      expect(p.rejectionReason, 'blurry');
      expect(p.submissionId, 'sub-9');
      final out = p.toJson();
      expect(out['status'], 'pending');
      expect(out['rejection_reason'], 'blurry');
      expect(out['submission_id'], 'sub-9');
    });

    test('Payment.create defaults to pending-free confirmed; can be pending', () {
      final confirmed = Payment.create(
        userId: 'u',
        loanScheduleId: 's',
        bypassPaymentProof: true,
      );
      expect(confirmed.status, PaymentStatus.confirmed);

      final pending = Payment.create(
        userId: 'u',
        loanScheduleId: 's',
        bypassPaymentProof: true,
        status: PaymentStatus.pending,
        submissionId: 'sub-1',
      );
      expect(pending.status, PaymentStatus.pending);
      expect(pending.submissionId, 'sub-1');
    });
  });
}
```

- [ ] **Step 2: Run it (fails — fields don't exist yet)**

Run: `cd packages/loans/payment_repository && fvm flutter test test/src/payment_test.dart`
Expected: compile error — `status`/`rejectionReason`/`submissionId` not defined.

- [ ] **Step 3: Add the fields to `PaymentEntity`**

Read `payment_entity.dart`. Add the import at top:

```dart
import 'package:payment_repository/src/model/payment_status.dart';
```

Add these fields next to the existing ones (e.g. after `comment`):

```dart
  @JsonKey(name: 'status', defaultValue: PaymentStatus.confirmed)
  late PaymentStatus status;

  @JsonKey(name: 'rejection_reason')
  String? rejectionReason;

  @JsonKey(name: 'submission_id')
  String? submissionId;
```

Add all three to the Equatable `props` list and to `toEntity()`/`toPayment()` copy methods if present (mirror how `comment`/`confirmedBy` are copied — read those lines and replicate for the three new fields).

- [ ] **Step 4: Update `Payment.create`**

Read `payment.dart`. Add params to the factory signature:

```dart
    PaymentStatus status = PaymentStatus.confirmed,
    String? submissionId,
```

In the factory body cascade (where it sets `..comment = comment` etc.), add:

```dart
      ..status = status
      ..submissionId = submissionId
```

(Leave `rejectionReason` unset at create; it is set later by reject.) Add the import for `payment_status.dart` if not already exported into scope.

- [ ] **Step 5: Add `markConfirmed` / `markRejected` helpers to `Payment`**

In `payment.dart`, add methods to the `Payment` class:

```dart
  /// Lender confirms: set status + audit fields together.
  void markConfirmed({required String confirmedById}) {
    status = PaymentStatus.confirmed;
    confirmedBy = confirmedById;
    confirmedAt = DateTime.timestamp();
    rejectionReason = null;
  }

  /// Lender rejects with a reason. Keeps the record as an audit trail.
  void markRejected({required String confirmedById, required String reason}) {
    status = PaymentStatus.rejected;
    confirmedBy = confirmedById;
    confirmedAt = DateTime.timestamp();
    rejectionReason = reason;
  }
```

- [ ] **Step 6: Regenerate code**

Run: `cd packages/loans/payment_repository && fvm dart run build_runner build --delete-conflicting-outputs`
Expected: `Succeeded`. Confirm `payment_entity.g.dart` now references `status`/`rejection_reason`/`submission_id`.

- [ ] **Step 7: Run the test (passes)**

Run: `cd packages/loans/payment_repository && fvm flutter test test/src/payment_test.dart`
Expected: All tests pass.

- [ ] **Step 8: Analyze**

Run: `cd packages/loans/payment_repository && fvm flutter analyze lib test`
Expected: `No issues found!`

- [ ] **Step 9: Commit**

```bash
git add packages/loans/payment_repository/lib/src/model/payment_entity.dart packages/loans/payment_repository/lib/src/model/payment.dart packages/loans/payment_repository/test/src/payment_test.dart
git commit -m "feat(payments): add status/rejection_reason/submission_id to Payment"
```

---

## Phase 2 — Shared confirmation service

Extract the "mark a schedule paid / reverted" logic so the teller flow and the new lender-confirm flow share one implementation. **First read** `apps/loans/lib/features/payment_center/bloc/payment_center_bloc.dart` `_handleMakePaymentEvent` (~lines 517–644) to copy the exact schedule/loan update rules (status → `paid_on_time`/`paid_late` based on `dueAt`, set `paidAt`, `paymentId`, advance `Loan.status`).

### Task 3: `PaymentConfirmationService`

**Files:**
- Create: `apps/loans/lib/services/payment_confirmation_service.dart`
- Test: `apps/loans/test/services/payment_confirmation_service_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// apps/loans/test/services/payment_confirmation_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/services/payment_confirmation_service.dart';

void main() {
  group('PaymentConfirmationService.scheduleStatusForConfirmation', () {
    test('on-time when dueAt is in the future', () {
      final due = DateTime.now().add(const Duration(days: 3));
      expect(
        PaymentConfirmationService.scheduleStatusForConfirmation(dueAt: due),
        LoanStatus.paid_on_time,
      );
    });

    test('late when dueAt is in the past', () {
      final due = DateTime.now().subtract(const Duration(days: 3));
      expect(
        PaymentConfirmationService.scheduleStatusForConfirmation(dueAt: due),
        LoanStatus.paid_late,
      );
    });

    test('revertedStatus is overdue when dueAt is past, else not_paid', () {
      final past = DateTime.now().subtract(const Duration(days: 1));
      final future = DateTime.now().add(const Duration(days: 1));
      expect(PaymentConfirmationService.revertedStatus(dueAt: past),
          LoanStatus.not_paid_overdue);
      expect(PaymentConfirmationService.revertedStatus(dueAt: future),
          LoanStatus.not_paid);
    });
  });
}
```

- [ ] **Step 2: Run it (fails)**

Run: `cd apps/loans && fvm flutter test test/services/payment_confirmation_service_test.dart`
Expected: FAIL — `PaymentConfirmationService` not defined.

- [ ] **Step 3: Implement the pure helpers + apply methods**

```dart
// apps/loans/lib/services/payment_confirmation_service.dart
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:payment_repository/payment_repository.dart';

/// Shared rules for marking a [LoanSchedule] paid (on confirm) or reverted
/// (on reject). Used by both the teller Payment Center flow and the new
/// borrower-submission confirm/reject flow so the rules live in one place.
class PaymentConfirmationService {
  PaymentConfirmationService({
    required this.loanScheduleRepository,
    required this.loanRepository,
    required this.paymentRepository,
  });

  final LoanScheduleRepository loanScheduleRepository;
  final LoanRepository loanRepository;
  final PaymentRepository paymentRepository;

  /// Pure: on confirmation, a schedule is paid_on_time unless its dueAt is past.
  static LoanStatus scheduleStatusForConfirmation({required DateTime dueAt}) {
    return dueAt.isBefore(DateTime.now())
        ? LoanStatus.paid_late
        : LoanStatus.paid_on_time;
  }

  /// Pure: on rejection, a schedule reverts to not_paid (or overdue if past).
  static LoanStatus revertedStatus({required DateTime dueAt}) {
    return dueAt.isBefore(DateTime.now())
        ? LoanStatus.not_paid_overdue
        : LoanStatus.not_paid;
  }

  /// Confirm a borrower-submitted [payment]: persist the confirmed payment,
  /// mark its schedule paid, and advance the loan status.
  Future<void> confirm({
    required Payment payment,
    required String confirmedById,
  }) async {
    payment.markConfirmed(confirmedById: confirmedById);
    await paymentRepository.update(data: payment);

    final schedule =
        await loanScheduleRepository.get(id: payment.loanScheduleId);
    schedule
      ..paidAt = DateTime.timestamp()
      ..paymentId = payment.id
      ..status = scheduleStatusForConfirmation(dueAt: schedule.dueAt);
    await loanScheduleRepository.update(data: schedule);

    await _advanceLoanStatus(schedule.loanId, schedule.status);
  }

  /// Reject a borrower-submitted [payment]: keep it as an audit record but
  /// free its schedule so the borrower can resubmit.
  Future<void> reject({
    required Payment payment,
    required String confirmedById,
    required String reason,
  }) async {
    payment.markRejected(confirmedById: confirmedById, reason: reason);
    await paymentRepository.update(data: payment);

    final schedule =
        await loanScheduleRepository.get(id: payment.loanScheduleId);
    schedule
      ..paidAt = null
      ..paymentId = null
      ..status = revertedStatus(dueAt: schedule.dueAt);
    await loanScheduleRepository.update(data: schedule);
  }

  Future<void> _advanceLoanStatus(String loanId, LoanStatus status) async {
    final loan = await loanRepository.get(id: loanId);
    await loanRepository.update(data: loan..status = status);
  }
}
```

> NOTE while implementing: verify `LoanSchedule` exposes `dueAt`, `loanId`, `paidAt`, `paymentId`, `status` and `Loan` exposes `status` (confirmed by the exploration). If `loanScheduleRepository.get`/`loanRepository.get` signatures differ, match the actual repository API.

- [ ] **Step 4: Run the test (passes)**

Run: `cd apps/loans && fvm flutter test test/services/payment_confirmation_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
cd apps/loans && fvm flutter analyze lib/services/payment_confirmation_service.dart test/services/payment_confirmation_service_test.dart
git add apps/loans/lib/services/payment_confirmation_service.dart apps/loans/test/services/payment_confirmation_service_test.dart
git commit -m "feat(payments): shared PaymentConfirmationService (confirm/reject schedule rules)"
```

---

## Phase 3 — Borrower submit flow

### Task 4: `PaymentSubmissionBloc` events/state

**Files:**
- Create: `apps/loans/lib/features/payments/bloc/payment_submission_bloc.dart`, `payment_submission_event.dart`, `payment_submission_state.dart`

- [ ] **Step 1: Define events** (`payment_submission_event.dart`)

```dart
part of 'payment_submission_bloc.dart';

sealed class PaymentSubmissionEvent {}

/// Submit proof for the next due schedule only.
final class SubmitPayNowEvent extends PaymentSubmissionEvent {
  SubmitPayNowEvent({required this.fileBytes, required this.fileName});
  final Uint8List fileBytes;
  final String fileName;
}

/// Submit proof for the entire remaining balance (all unpaid schedules).
final class SubmitPayInFullEvent extends PaymentSubmissionEvent {
  SubmitPayInFullEvent({required this.fileBytes, required this.fileName});
  final Uint8List fileBytes;
  final String fileName;
}
```

- [ ] **Step 2: Define state** (`payment_submission_state.dart`)

```dart
part of 'payment_submission_bloc.dart';

enum PaymentSubmissionStatus { initial, submitting, success, error }

final class PaymentSubmissionState extends Equatable {
  const PaymentSubmissionState({
    this.status = PaymentSubmissionStatus.initial,
    this.message,
  });

  final PaymentSubmissionStatus status;
  final String? message;

  PaymentSubmissionState copyWith({
    PaymentSubmissionStatus? status,
    String? message,
  }) =>
      PaymentSubmissionState(status: status ?? this.status, message: message);

  @override
  List<Object?> get props => [status, message];
}
```

- [ ] **Step 3: Define the bloc shell** (`payment_submission_bloc.dart` — handlers added in Task 5)

```dart
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:payment_repository/payment_repository.dart';
import 'package:storage_repository/storage_repository.dart';
import 'package:uuid/uuid.dart';

part 'payment_submission_event.dart';
part 'payment_submission_state.dart';

class PaymentSubmissionBloc
    extends Bloc<PaymentSubmissionEvent, PaymentSubmissionState> {
  PaymentSubmissionBloc(BuildContext context)
      : this.withDependencies(
          paymentRepository: context.read<PaymentRepository>(),
          loanScheduleRepository: context.read<LoanScheduleRepository>(),
          storageRepository: context.read<StorageRepository>(),
          authService: AuthenticationService.instance,
        );

  PaymentSubmissionBloc.withDependencies({
    required this.paymentRepository,
    required this.loanScheduleRepository,
    required this.storageRepository,
    required this.authService,
    String Function()? newSubmissionId,
  })  : _newSubmissionId = newSubmissionId ?? (() => const Uuid().v4()),
        super(const PaymentSubmissionState()) {
    on<SubmitPayNowEvent>(_onPayNow);
    on<SubmitPayInFullEvent>(_onPayInFull);
  }

  final BaseRepository<Payment> paymentRepository;
  final BaseRepository<LoanSchedule> loanScheduleRepository;
  final StorageRepository storageRepository;
  final AuthenticationService authService;
  final String Function() _newSubmissionId;

  // handlers added in Task 5
}
```

> Verify `uuid` is a dependency of `apps/loans` (`grep uuid apps/loans/pubspec.yaml`). The exploration shows `uuid 4.5.2` is resolved — if it's transitive only, add `uuid: ^4.5.2` to `apps/loans/pubspec.yaml` and `fvm flutter pub get`.

### Task 5: Submit handlers (TDD)

**Files:**
- Modify: `apps/loans/lib/features/payments/bloc/payment_submission_bloc.dart`
- Test: `apps/loans/test/features/payments/bloc/payment_submission_bloc_test.dart` (create)

- [ ] **Step 1: Write the failing test**

```dart
// apps/loans/test/features/payments/bloc/payment_submission_bloc_test.dart
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/payments/bloc/payment_submission_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:payment_repository/payment_repository.dart';
import 'package:storage_repository/storage_repository.dart';
import 'package:user_repository/user_repository.dart';

class _MockPaymentRepo extends Mock implements BaseRepository<Payment> {}
class _MockScheduleRepo extends Mock implements BaseRepository<LoanSchedule> {}
class _MockStorage extends Mock implements StorageRepository {}
class _MockAuth extends Mock implements AuthenticationService {}
class _MockUser extends Mock implements User {}

LoanSchedule _schedule(String id, {LoanStatus status = LoanStatus.not_paid}) =>
    LoanSchedule()
      ..id = id
      ..loanId = 'loan-1'
      ..status = status
      ..dueAt = DateTime.now().add(const Duration(days: 5))
      ..amortization = 100;

void main() {
  late BaseRepository<Payment> payments;
  late BaseRepository<LoanSchedule> schedules;
  late StorageRepository storage;
  late AuthenticationService auth;
  late User user;
  final bytes = Uint8List.fromList([1, 2, 3]);
  final img = ImageUrl()..name = 'p.jpg'..thumbnail = 't'..original = 'o';

  setUpAll(() {
    registerFallbackValue(Payment.create(
        userId: 'u', loanScheduleId: 's', bypassPaymentProof: true));
    registerFallbackValue(_schedule('x'));
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    payments = _MockPaymentRepo();
    schedules = _MockScheduleRepo();
    storage = _MockStorage();
    auth = _MockAuth();
    user = _MockUser();
    when(() => auth.user).thenReturn(user);
    when(() => user.id).thenReturn('borrower-1');
    when(() => storage.upload(
          data: any(named: 'data'),
          folder: any(named: 'folder'),
          fileName: any(named: 'fileName'),
          includeOriginal: any(named: 'includeOriginal'),
        )).thenAnswer((_) async => img);
    when(() => payments.add(data: any(named: 'data')))
        .thenAnswer((i) async => i.namedArguments[#data] as Payment);
    when(() => schedules.update(data: any(named: 'data')))
        .thenAnswer((i) async => i.namedArguments[#data] as LoanSchedule);
  });

  PaymentSubmissionBloc build({
    required List<LoanSchedule> nextDue,
  }) {
    // The bloc reads the loan's schedules from the schedule repo; stub load.
    when(() => schedules.load(
          statements: any(named: 'statements'),
          limit: any(named: 'limit'),
          page: any(named: 'page'),
          reset: any(named: 'reset'),
        )).thenAnswer((_) async => nextDue);
    return PaymentSubmissionBloc.withDependencies(
      paymentRepository: payments,
      loanScheduleRepository: schedules,
      storageRepository: storage,
      authService: auth,
      newSubmissionId: () => 'sub-1',
    );
  }

  blocTest<PaymentSubmissionBloc, PaymentSubmissionState>(
    'Pay now uploads proof + creates ONE pending payment for the next schedule',
    build: () => build(nextDue: [_schedule('sched-1')]),
    act: (b) => b.add(SubmitPayNowEvent(fileBytes: bytes, fileName: 'p.jpg')),
    expect: () => [
      isA<PaymentSubmissionState>()
          .having((s) => s.status, 'status', PaymentSubmissionStatus.submitting),
      isA<PaymentSubmissionState>()
          .having((s) => s.status, 'status', PaymentSubmissionStatus.success),
    ],
    verify: (_) {
      final p = verify(() => payments.add(data: captureAny(named: 'data')))
          .captured.single as Payment;
      expect(p.status, PaymentStatus.pending);
      expect(p.submissionId, 'sub-1');
      expect(p.loanScheduleId, 'sched-1');
      expect(p.userId, 'borrower-1');
      expect(p.transactionPhotoUrl, isNotNull);
    },
  );

  blocTest<PaymentSubmissionBloc, PaymentSubmissionState>(
    'Pay in full creates one pending payment per remaining schedule (shared submission)',
    build: () =>
        build(nextDue: [_schedule('sched-1'), _schedule('sched-2')]),
    act: (b) =>
        b.add(SubmitPayInFullEvent(fileBytes: bytes, fileName: 'p.jpg')),
    verify: (_) {
      final created = verify(() => payments.add(data: captureAny(named: 'data')))
          .captured.cast<Payment>();
      expect(created.length, 2);
      expect(created.every((p) => p.status == PaymentStatus.pending), isTrue);
      expect(created.map((p) => p.submissionId).toSet(), {'sub-1'});
      expect(created.map((p) => p.loanScheduleId).toSet(),
          {'sched-1', 'sched-2'});
    },
  );
}
```

- [ ] **Step 2: Run it (fails)**

Run: `cd apps/loans && fvm flutter test test/features/payments/bloc/payment_submission_bloc_test.dart`
Expected: FAIL — handlers `_onPayNow`/`_onPayInFull` not defined.

- [ ] **Step 3: Implement the handlers**

Add to `payment_submission_bloc.dart`:

```dart
  Future<void> _onPayNow(
    SubmitPayNowEvent event,
    Emitter<PaymentSubmissionState> emit,
  ) async {
    await _submit(event.fileBytes, event.fileName, payInFull: false, emit: emit);
  }

  Future<void> _onPayInFull(
    SubmitPayInFullEvent event,
    Emitter<PaymentSubmissionState> emit,
  ) async {
    await _submit(event.fileBytes, event.fileName, payInFull: true, emit: emit);
  }

  Future<void> _submit(
    Uint8List bytes,
    String fileName, {
    required bool payInFull,
    required Emitter<PaymentSubmissionState> emit,
  }) async {
    emit(state.copyWith(status: PaymentSubmissionStatus.submitting));
    try {
      final userId = authService.user.id;
      final targets = await _unpaidSchedules(userId, payInFull: payInFull);
      if (targets.isEmpty) {
        emit(state.copyWith(
          status: PaymentSubmissionStatus.error,
          message: 'No schedule to pay.',
        ));
        return;
      }

      final loanId = targets.first.loanId;
      final proof = await storageRepository.upload(
        data: bytes,
        folder: 'users/$userId/loans/$loanId',
        fileName: fileName,
        includeOriginal: true,
      );
      final submissionId = _newSubmissionId();

      for (final schedule in targets) {
        final payment = Payment.create(
          userId: userId,
          loanScheduleId: schedule.id,
          transactionPhotoUrl: proof,
          status: PaymentStatus.pending,
          submissionId: submissionId,
        );
        final saved = await paymentRepository.add(data: payment);
        schedule
          ..status = LoanStatus.payment_submitted
          ..paymentId = saved.id;
        await loanScheduleRepository.update(data: schedule);
      }

      emit(state.copyWith(status: PaymentSubmissionStatus.success));
    } catch (err) {
      emit(state.copyWith(
        status: PaymentSubmissionStatus.error,
        message: err is Exception ? 'Submit failed: $err' : 'Submit failed',
      ));
    }
  }

  /// Returns the schedules to pay: the single next-due one, or all remaining
  /// unpaid ones (Pay in full), via the LoanCalculationService-backed list the
  /// app already uses. IMPLEMENTATION NOTE: read how LoansBloc/ProductBloc
  /// obtains the borrower's payable schedules (LoanCalculationService — see
  /// apps/loans MEMORY) and reuse it; do NOT query Firestore directly for
  /// schedule lists. For the test, this is stubbed via loanScheduleRepository.load.
  Future<List<LoanSchedule>> _unpaidSchedules(
    String userId, {
    required bool payInFull,
  }) async {
    final all = await loanScheduleRepository.load(
      reset: true,
      limit: null,
      statements: [
        QueryStatement(field: 'user_id', isEqualTo: userId),
      ],
    );
    final unpaid = all
        .where((s) =>
            s.status != LoanStatus.paid_on_time &&
            s.status != LoanStatus.paid_late &&
            s.status != LoanStatus.payment_submitted)
        .toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    if (unpaid.isEmpty) return [];
    return payInFull ? unpaid : [unpaid.first];
  }
```

> IMPLEMENTATION NOTE: the schedule-source above is a placeholder query for the bloc test. Before wiring the real dialog, replace `_unpaidSchedules` to use the app's existing payable-schedule source (`LoanCalculationService` — schedules are NOT all pre-stored in Firestore; see `apps/loans/MEMORY.md` "Loan schedules are NOT pre-created"). Keep the same return contract so the tests stand.

- [ ] **Step 4: Run the test (passes)**

Run: `cd apps/loans && fvm flutter test test/features/payments/bloc/payment_submission_bloc_test.dart`
Expected: PASS (both cases).

- [ ] **Step 5: Commit**

```bash
git add apps/loans/lib/features/payments/ apps/loans/test/features/payments/
git commit -m "feat(payments): PaymentSubmissionBloc (pay now / pay in full -> pending payments)"
```

### Task 6: Submit dialog UI + wire the buttons

**Files:**
- Create: `apps/loans/lib/features/payments/widget/submit_payment_dialog.dart`
- Modify: `apps/loans/lib/features/loans/screens/loan_details.dart` (`_nextPayment`)
- Modify: `apps/loans/lib/app/di/bloc_providers.dart`

- [ ] **Step 1: Register the bloc**

In `bloc_providers.dart`, add the import and `BlocProvider(create: PaymentSubmissionBloc.new),` next to the other providers.

- [ ] **Step 2: Build the dialog**

`submit_payment_dialog.dart` — a `showSubmitPaymentDialog(context, {required bool payInFull, required String companyId, required double amount})` that:
1. Reads `BankDetailsRepository` from context; `load(statements: [QueryStatement(field: 'data_id', isEqualTo: companyId)])`, filter `dataType == DataType.company`. Show bank name / account name / account number, or a disabled state + message if none.
2. Shows the `amount.toCurrency()` to pay.
3. A file picker — reuse the app's existing picker used by the Payment Center (`grep -rn "FilePicker\|pickFiles\|image_picker\|fileBytes" apps/loans/lib/features/payment_center` and mirror that exact widget/util so the returned `(Uint8List bytes, String name)` matches).
4. Wraps the dialog in `BlocProvider.value(value: context.read<PaymentSubmissionBloc>())` and a `BlocListener` that closes on `success` and shows the error message on `error`.
5. **Send** button dispatches `SubmitPayNowEvent` or `SubmitPayInFullEvent` with the picked bytes/name; disabled until a file is chosen and bank details exist.

Mirror the existing dialog style (`AlertDialog` + `AppWidgets.defaultFilledButton` + `Gap`) used by `_reviewDialog` in `loan_details.dart`.

- [ ] **Step 3: Wire the buttons in `_nextPayment`**

In `loan_details.dart` `_nextPayment`, replace the two `TODO: redirect to payment channel` dialogs:
- "Pay now" `onPressed` → `showSubmitPaymentDialog(context, payInFull: false, companyId: <loan company id>, amount: <next due amount>)`.
- "Pay in full" `onPressed` → `showSubmitPaymentDialog(context, payInFull: true, companyId: <loan company id>, amount: <remaining balance>)`.

Read the surrounding code to obtain the company id (from `userLoanView`/`loan`) and the amounts (next due from the schedule list, remaining = sum of unpaid). Use the same `LoanCalculationService`-backed source as the bloc.

- [ ] **Step 4: Widget test** (`apps/loans/test/features/payments/widget/submit_payment_dialog_test.dart`)

Test: with a `MockPaymentSubmissionBloc` (`MockBloc`) and a `BankDetailsRepository` stub returning empty → the dialog shows the "no bank details" message and the Send button is disabled; with bank details + a chosen file → Send dispatches `SubmitPayNowEvent`. Mirror the structure of `apps/loans/test/features/reviews/widget/review_response_dialog_test.dart` (present via a real route so `Navigator.pop` works).

- [ ] **Step 5: Analyze, test, commit**

```bash
cd apps/loans && fvm flutter analyze lib/features/payments lib/features/loans/screens/loan_details.dart && fvm flutter test test/features/payments
git add apps/loans/lib/features/payments apps/loans/lib/features/loans/screens/loan_details.dart apps/loans/lib/app/di/bloc_providers.dart apps/loans/test/features/payments
git commit -m "feat(payments): borrower submit-payment dialog wired to Pay now/Pay in full"
```

---

## Phase 4 — Lender confirm/reject (Payment Center)

> **First read** `apps/loans/lib/features/payment_center/bloc/payment_center_bloc.dart` and its screen to learn the existing structure (how it lists/loads payments, how the teller `_handleMakePaymentEvent` works). Reuse `PaymentConfirmationService` (Task 3) for the actual schedule/loan mutations.

### Task 7: Pending-submissions load + confirm/reject events

**Files:**
- Modify: `apps/loans/lib/features/payment_center/bloc/payment_center_bloc.dart` (+ its event/state files)
- Test: `apps/loans/test/features/payment_center/payment_center_confirm_test.dart` (create)

- [ ] **Step 1: Write the failing test** (confirm + reject)

```dart
// apps/loans/test/features/payment_center/payment_center_confirm_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/services/payment_confirmation_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:payment_repository/payment_repository.dart';

class _Payments extends Mock implements PaymentRepository {}
class _Schedules extends Mock implements LoanScheduleRepository {}
class _Loans extends Mock implements LoanRepository {}

void main() {
  late PaymentConfirmationService svc;
  late _Payments payments;
  late _Schedules schedules;
  late _Loans loans;

  LoanSchedule sched() => LoanSchedule()
    ..id = 'sched-1'
    ..loanId = 'loan-1'
    ..status = LoanStatus.payment_submitted
    ..dueAt = DateTime.now().add(const Duration(days: 5));
  Payment pay() => Payment.create(
        userId: 'u',
        loanScheduleId: 'sched-1',
        bypassPaymentProof: true,
        status: PaymentStatus.pending,
      )..id = 'pay-1';

  setUpAll(() {
    registerFallbackValue(pay());
    registerFallbackValue(sched());
    registerFallbackValue(Loan());
  });
  setUp(() {
    payments = _Payments();
    schedules = _Schedules();
    loans = _Loans();
    svc = PaymentConfirmationService(
      loanScheduleRepository: schedules,
      loanRepository: loans,
      paymentRepository: payments,
    );
    when(() => payments.update(data: any(named: 'data')))
        .thenAnswer((i) async => i.namedArguments[#data] as Payment);
    when(() => schedules.get(id: any(named: 'id')))
        .thenAnswer((_) async => sched());
    when(() => schedules.update(data: any(named: 'data')))
        .thenAnswer((i) async => i.namedArguments[#data] as LoanSchedule);
    when(() => loans.get(id: any(named: 'id')))
        .thenAnswer((_) async => Loan()..id = 'loan-1');
    when(() => loans.update(data: any(named: 'data')))
        .thenAnswer((i) async => i.namedArguments[#data] as Loan);
  });

  test('confirm sets payment confirmed + schedule paid_on_time', () async {
    final p = pay();
    await svc.confirm(payment: p, confirmedById: 'lender-1');
    expect(p.status, PaymentStatus.confirmed);
    expect(p.confirmedBy, 'lender-1');
    final s = verify(() => schedules.update(data: captureAny(named: 'data')))
        .captured.single as LoanSchedule;
    expect(s.status, LoanStatus.paid_on_time);
    expect(s.paymentId, 'pay-1');
  });

  test('reject sets payment rejected + schedule reverted to not_paid', () async {
    final p = pay();
    await svc.reject(payment: p, confirmedById: 'lender-1', reason: 'blurry');
    expect(p.status, PaymentStatus.rejected);
    expect(p.rejectionReason, 'blurry');
    final s = verify(() => schedules.update(data: captureAny(named: 'data')))
        .captured.single as LoanSchedule;
    expect(s.status, LoanStatus.not_paid);
    expect(s.paymentId, isNull);
  });
}
```

- [ ] **Step 2: Run it**

Run: `cd apps/loans && fvm flutter test test/features/payment_center/payment_center_confirm_test.dart`
Expected: PASS immediately (this validates `PaymentConfirmationService` from Task 3 against repo-typed mocks). If it fails, fix the service to match the real repo signatures.

- [ ] **Step 3: Add bloc events + handlers**

Add to the Payment Center bloc: `LoadPendingSubmissionsEvent` (loads payments where `status == pending` for the lender's company loans, groups by `submission_id` into a `PendingSubmission` view-model holding the payments + total amount + borrower), `ConfirmSubmissionEvent(submissionId)` and `RejectSubmissionEvent(submissionId, reason)` that loop the submission's payments through `PaymentConfirmationService.confirm`/`reject`, then reload. Inject `PaymentConfirmationService` into the bloc constructor (build it from the three repos read via `context.read`).

- [ ] **Step 4: Pending-submissions UI**

Add a tab/section to the Payment Center screen listing `PendingSubmission`s with the screenshot (tap to view full image via `original`), amount, borrower, and **Confirm** / **Reject** (reject opens a small reason dialog). Mirror existing Payment Center list styling.

- [ ] **Step 5: Analyze, test, commit**

```bash
cd apps/loans && fvm flutter analyze lib/features/payment_center && fvm flutter test test/features/payment_center
git add apps/loans/lib/features/payment_center apps/loans/test/features/payment_center
git commit -m "feat(payments): Payment Center pending-submissions confirm/reject"
```

---

## Phase 5 — Go backend

### Task 8: `paymentUpdated` trigger (notify borrower on confirm/reject)

**Files:**
- Create: `functions/loans/triggers/payment_updated.go`, `functions/loans/test/triggers/payment_updated_test.go`
- Modify: `functions/loans/loooans_cloud_functions.go`, `.github/scripts/deploy_functions.sh`

> Mirror `functions/loans/triggers/review_updated.go` (adapter+core). Read it first.

- [ ] **Step 1: Write the failing core test**

```go
// functions/loans/test/triggers/payment_updated_test.go (package triggers_test)
// Cases: pending->confirmed notifies user_id ("confirmed"); pending->rejected
// notifies user_id with reason; confirmed->confirmed no-op; pending->pending
// no-op; nil snapshots no-op; missing user_id no-op.
// Use the fakes.Notifier; assert notifier.Notifications recipient == user_id
// and the message contains "confirmed" / "rejected" + reason.
```

Write the full test mirroring `review_updated_test.go` structure (a `depsWith(notifier)` helper, before/after `map[string]any`, assert on `notifier.Notifications`).

- [ ] **Step 2: Implement core + adapter**

`HandlePaymentUpdatedCore(ctx, paymentId, before, after, deps)`:
- nil guard on before/after.
- read `before["status"]`, `after["status"]` (strings).
- fire only on `before==pending && (after==confirmed || after==rejected)`.
- `userId := after["user_id"]`; if empty, no-op.
- build notification: confirmed → "Your payment was confirmed."; rejected → "Your payment was rejected" + `after["rejection_reason"]`. `notification_type: "payment"`, carry `payment_id`, `user_id`, `loan_id` (if present).
- `return deps.Notify(ctx, userId, title, message, data)`.

Adapter `PaymentUpdated(ctx, ev)` mirrors `ReviewUpdated`: unmarshal proto, `extractPaymentChange` (id + flatten `status`/`user_id`/`loan_id`/`rejection_reason`), wire `Notify` via `createNotification`.

- [ ] **Step 3: Register + deploy**

In `loooans_cloud_functions.go` add `functions.CloudEvent("paymentUpdated", triggers.PaymentUpdated)`. In `deploy_functions.sh` add a deploy block mirroring `reviewUpdated` (trigger `document.v1.updated` on `${collectionPrefix}payments/{uid}`, `--service-account=$serviceAccount --gen2 ...`); bump the "All N functions" counts.

- [ ] **Step 4: Build + test**

Run: `cd functions/loans && CGO_ENABLED=0 go build ./... && CGO_ENABLED=0 go test ./test/triggers/ -run PaymentUpdated -v`
Expected: build OK, tests pass.

- [ ] **Step 5: Commit**

```bash
git add functions/loans/triggers/payment_updated.go functions/loans/test/triggers/payment_updated_test.go functions/loans/loooans_cloud_functions.go .github/scripts/deploy_functions.sh
git commit -m "feat(functions): paymentUpdated trigger notifies borrower on confirm/reject"
```

### Task 9: De-dup `paymentCreated` notification per submission

**Files:**
- Modify: `functions/loans/triggers/payment_created.go`
- Test: extend/create `functions/loans/test/triggers/payment_created_test.go`

> `paymentCreated` currently notifies admins/loan officers on every payment doc. For "Pay in full" that fires N times. De-dup so only the first payment of a `submission_id` notifies.

- [ ] **Step 1: Decide the cheapest correct de-dup**

Refactor `paymentCreated` into adapter+core (mirror `reviewCreated`) if not already. In core, only notify when this payment is the **first** of its `submission_id`: query `payments where submission_id == X order by created_at asc limit 1` and notify only if its id equals the created payment's id. Inject the lookup as a dep so it is unit-testable. (If `submission_id` is empty — legacy/teller payments — always notify.)

- [ ] **Step 2: Tests** — first-of-submission notifies; second-of-submission no-op; empty submission_id notifies. Use a fake for the "first payment id of submission" lookup.

- [ ] **Step 3: Build, test, commit**

```bash
cd functions/loans && CGO_ENABLED=0 go build ./... && CGO_ENABLED=0 go test ./...
git add functions/loans/triggers/payment_created.go functions/loans/test/triggers/payment_created_test.go
git commit -m "fix(functions): notify lenders once per payment submission"
```

---

## Phase 6 — Wire-up, full suite, docs

### Task 10: Teller flow sets explicit status + full verification

**Files:**
- Modify: `apps/loans/lib/features/payment_center/bloc/payment_center_bloc.dart` (teller `Payment.create` call → add `status: PaymentStatus.confirmed` for clarity; behavior unchanged since default is confirmed)
- Modify: `functions/loans/MEMORY.md`, `apps/loans/MEMORY.md`

- [ ] **Step 1:** Add `status: PaymentStatus.confirmed` to the teller `Payment.create(...)` call (explicit; no behavior change).

- [ ] **Step 2:** Run the full suites:

```bash
cd apps/loans && fvm flutter test
cd ../../packages/loans/payment_repository && fvm flutter test
cd ../../../functions/loans && CGO_ENABLED=0 go test ./...
cd ../../apps/loans && fvm flutter analyze lib
```
Expected: all green; analyze clean on touched files.

- [ ] **Step 3:** Update `apps/loans/MEMORY.md` and `functions/loans/MEMORY.md` with a summary (feature, status lifecycle, submission_id grouping, paymentUpdated trigger, the still-deferred Firestore rule for who may confirm).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore(payments): teller status explicit; memory + final verification"
```

### Task 11: Open the PR

- [ ] Push and open a PR to `develop` titled `feat(payments): borrower payment submission (#64)` summarizing the flow, linking issue #64 and the spec, and noting the **Firestore rule** (who may write payments / set `status=confirmed`) is console-managed and must be applied before release (same as the reviews rule).

---

## Self-Review

**Spec coverage:**
- Status enum + fields → Tasks 1–2. ✓
- Borrower Pay now / Pay in full + bank details + screenshot upload → Tasks 4–6. ✓
- Pending state + schedule `payment_submitted` → Task 5. ✓
- Lender notified on submit → Task 9 (de-dup). ✓
- Lender confirm/reject in Payment Center, reuse teller logic → Tasks 3, 7. ✓
- Borrower notified on confirm/reject → Task 8. ✓
- Exact amount, no cash pool → service does not touch CashPool. ✓
- Testing (Flutter blocs/model/widget, Go triggers) → throughout. ✓

**Known implementation-time verifications (called out inline, not placeholders):**
- The borrower payable-schedule source must use `LoanCalculationService` (schedules aren't all in Firestore) — Task 5/6 notes this; the bloc keeps a repo-`load` seam only for testing.
- Exact repo method signatures (`get`/`update`/`load`) and `LoanSchedule`/`Loan` field names to be confirmed against the real classes while implementing Task 3/5/7.
- The file-picker util to mirror from the Payment Center — Task 6.

**Type consistency:** `PaymentStatus` (pending/confirmed/rejected), `PaymentConfirmationService.confirm/reject`, `submission_id`/`submissionId`, `SubmitPayNowEvent`/`SubmitPayInFullEvent` used consistently across tasks.
