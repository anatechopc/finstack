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
    // Default: the loan has 1 scheduled payment and no other paid schedules,
    // so confirming one does NOT complete the loan (unless a test overrides
    // the load stub to return enough paid schedules).
    when(
      () => schedules.load(
        statements: any(named: 'statements'),
        limit: any(named: 'limit'),
        page: any(named: 'page'),
        reset: any(named: 'reset'),
      ),
    ).thenAnswer((_) async => <LoanSchedule>[]);
    when(() => loans.get(id: any(named: 'id'))).thenAnswer(
      (_) async => Loan()
        ..id = 'loan-1'
        ..period = 1
        ..term = '1m',
    );
    when(
      () => loans.update(
        data: any(named: 'data'),
        updateView: any(named: 'updateView'),
      ),
    ).thenAnswer((i) async => i.namedArguments[#data] as Loan);
  });

  test('confirm sets payment confirmed + schedule paid_on_time', () async {
    final p = pay();
    await svc.confirm(payment: p, confirmedById: 'lender-1');
    expect(p.status, PaymentStatus.confirmed);
    expect(p.confirmedBy, 'lender-1');
    final s = verify(() => schedules.update(data: captureAny(named: 'data')))
        .captured
        .single as LoanSchedule;
    expect(s.status, LoanStatus.paid_on_time);
    expect(s.paymentId, 'pay-1');
  });

  test('reject sets payment rejected + schedule reverted to not_paid',
      () async {
    final p = pay();
    await svc.reject(payment: p, confirmedById: 'lender-1', reason: 'blurry');
    expect(p.status, PaymentStatus.rejected);
    expect(p.rejectionReason, 'blurry');
    final s = verify(() => schedules.update(data: captureAny(named: 'data')))
        .captured
        .single as LoanSchedule;
    expect(s.status, LoanStatus.not_paid);
    expect(s.paymentId, isNull);
  });

  test('confirming the final payment completes a fixed-term loan', () async {
    // The loan has period 1; after this confirmation there is one paid
    // schedule, so the loan should advance to completed (not paid_on_time).
    when(
      () => schedules.load(
        statements: any(named: 'statements'),
        limit: any(named: 'limit'),
        page: any(named: 'page'),
        reset: any(named: 'reset'),
      ),
    ).thenAnswer(
      (_) async => [sched()..status = LoanStatus.paid_on_time],
    );

    await svc.confirm(payment: pay(), confirmedById: 'lender-1');

    final loan = verify(
      () => loans.update(
        data: captureAny(named: 'data'),
        updateView: any(named: 'updateView'),
      ),
    ).captured.single as Loan;
    expect(loan.status, LoanStatus.completed);
  });
}
