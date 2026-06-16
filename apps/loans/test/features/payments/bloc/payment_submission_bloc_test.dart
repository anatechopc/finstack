import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
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
  final img = ImageUrl(name: 'p.jpg', thumbnail: 't', original: 'o');

  setUpAll(() {
    registerFallbackValue(
      Payment.create(
        userId: 'u',
        loanScheduleId: 's',
        bypassPaymentProof: true,
      ),
    );
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
    when(
      () => storage.upload(
        data: any(named: 'data'),
        folder: any(named: 'folder'),
        fileName: any(named: 'fileName'),
        includeOriginal: any(named: 'includeOriginal'),
      ),
    ).thenAnswer((_) async => img);
    when(() => payments.add(data: any(named: 'data')))
        .thenAnswer((i) async => i.namedArguments[#data] as Payment);
    when(() => schedules.update(data: any(named: 'data')))
        .thenAnswer((i) async => i.namedArguments[#data] as LoanSchedule);
  });

  PaymentSubmissionBloc build({
    required List<LoanSchedule> nextDue,
  }) {
    when(
      () => schedules.load(
        statements: any(named: 'statements'),
        limit: any(named: 'limit'),
        page: any(named: 'page'),
        reset: any(named: 'reset'),
      ),
    ).thenAnswer((_) async => nextDue);
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
      isA<PaymentSubmissionState>().having(
        (s) => s.status,
        'status',
        PaymentSubmissionStatus.submitting,
      ),
      isA<PaymentSubmissionState>().having(
        (s) => s.status,
        'status',
        PaymentSubmissionStatus.success,
      ),
    ],
    verify: (_) {
      final p = verify(() => payments.add(data: captureAny(named: 'data')))
          .captured
          .single as Payment;
      expect(p.status, PaymentStatus.pending);
      expect(p.submissionId, 'sub-1');
      expect(p.loanScheduleId, 'sched-1');
      expect(p.userId, 'borrower-1');
      expect(p.transactionPhotoUrl, isNotNull);
    },
  );

  blocTest<PaymentSubmissionBloc, PaymentSubmissionState>(
    'Pay in full creates one pending payment per remaining schedule '
    '(shared submission)',
    build: () => build(nextDue: [_schedule('sched-1'), _schedule('sched-2')]),
    act: (b) =>
        b.add(SubmitPayInFullEvent(fileBytes: bytes, fileName: 'p.jpg')),
    verify: (_) {
      final created = verify(() => payments.add(data: captureAny(named: 'data')))
          .captured
          .cast<Payment>();
      expect(created.length, 2);
      expect(created.every((p) => p.status == PaymentStatus.pending), isTrue);
      expect(created.map((p) => p.submissionId).toSet(), {'sub-1'});
      expect(
        created.map((p) => p.loanScheduleId).toSet(),
        {'sched-1', 'sched-2'},
      );
    },
  );
}
