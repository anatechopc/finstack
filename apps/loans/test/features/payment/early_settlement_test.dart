import 'package:bloc_test/bloc_test.dart';
import 'package:cash_pool_repository/cash_pool_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/loans/bloc/loan_settlement_bloc.dart';
import 'package:loooans/features/loans/screens/statement_of_account_screen.dart';
import 'package:loooans/features/reports/bloc/reports_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans/services/payment_confirmation_service.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:payment_repository/payment_repository.dart';
import 'package:user_repository/user_repository.dart';

// finstack#116 through the real LoanSettlementBloc, its repositories on a
// fake Firestore. The loan repository is the real one behind a mock that
// only drops the loan view write (its repository needs the real Firestore).
//
// G1 (10,000, 3 months, 5%): bill 1 due 10 days ago and paid as billed,
// balance 6,827.9144. Settled today: 6,827.9144 x 5% x 10/30 = 113.80 ->
// 6,941.71 (golden G7a). The borrower's cash pool holds 1,000: the entry
// deducts 1,000 and the rest is collected in person.
// Before: the dialog showed 10,000 - 3,672.09 = 6,327.91, and confirming
// wrote nothing but the loan's completed status.

class _Loans extends Mock implements LoanRepository {}

class _Schedules extends Mock implements LoanScheduleRepository {}

class _Auth extends Mock implements AuthenticationService {}

class _Reports extends MockBloc<ReportsEvent, ReportsState>
    implements ReportsBloc {}

class _Settlement extends MockBloc<LoanSettlementEvent, LoanSettlementState>
    implements LoanSettlementBloc {}

void main() {
  late FakeFirebaseFirestore firestore;
  late LoanRepository real;
  late _Loans loans;
  late LoanScheduleRepository schedules;
  late PaymentRepository payments;
  late CashPoolRepository cashPool;
  late _Auth auth;
  late String loanId;
  late LoanSchedule bill1;

  final today = DateUtils.dateOnly(DateTime.now());
  final bill1Due = DateUtils.addDaysToDate(today, -10);

  setUpAll(() {
    registerFallbackValue(Loan());
    registerFallbackValue(LoanSchedule());
  });

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    real = LoanRepository.withFirestore(firestore);
    schedules = LoanScheduleRepository.withFirestore(firestore);
    payments = PaymentRepository.withFirestore(firestore);
    cashPool = CashPoolRepository.withFirestore(firestore);

    final loan = await real.add(
      data: Loan.create(
        userId: 'u1',
        companyId: 'co-1',
        productId: 'pr-1',
        amount: 10000,
        additionalCharges: 0,
        deductions: 0,
        period: 3,
        requirements: const [],
        isForceCollect: false,
        status: LoanStatus.paid_on_time,
        dueAt: null,
        reason: 'fixed term',
        interestRate: 5,
        term: '1m',
        amortization: 3672.09,
      )..createdAt = DateTime(bill1Due.year, bill1Due.month - 1, bill1Due.day),
    );
    loanId = loan.id;

    final computed = LoanCalculationService.calculateFixedTerm(
      amount: 10000,
      monthsToPay: 3,
      date: loan.createdAt,
      interestRate: 5,
      term: '1m',
      companyId: 'co-1',
    ).schedules.first;
    bill1 = await schedules.add(
      data: computed
        ..loanId = loanId
        ..dueAt = bill1Due
        ..paidAt = bill1Due
        ..paymentId = 'payment-0'
        ..status = LoanStatus.paid_on_time
        ..interestPayment = computed.interestCharge,
    );
    await cashPool.add(data: CashPool.create(userId: 'u1', amount: 1000));

    loans = _Loans();
    when(() => loans.get(id: any(named: 'id'))).thenAnswer(
      (i) => real.get(id: i.namedArguments[#id] as String),
    );
    when(
      () => loans.load(
        statements: any(named: 'statements'),
        limit: any(named: 'limit'),
        page: any(named: 'page'),
        reset: any(named: 'reset'),
        includeAdditionalLoanAmounts:
            any(named: 'includeAdditionalLoanAmounts'),
      ),
    ).thenAnswer(
      (i) => real.load(
        statements: i.namedArguments[#statements] as List<QueryStatement>?,
        limit: i.namedArguments[#limit] as int?,
        page: i.namedArguments[#page] as int?,
        reset: i.namedArguments[#reset] as bool,
        includeAdditionalLoanAmounts:
            i.namedArguments[#includeAdditionalLoanAmounts] as bool,
      ),
    );
    when(
      () => loans.update(
        data: any(named: 'data'),
        updateView: any(named: 'updateView'),
      ),
    ).thenAnswer((i) => real.update(data: i.namedArguments[#data] as Loan));

    auth = _Auth();
    when(() => auth.user).thenReturn(
      User()
        ..id = 'teller-1'
        ..firstName = 'Tess'
        ..lastName = 'Teller'
        ..emailAddress = 'teller@example.com',
    );
  });

  LoanSettlementBloc newBloc() {
    final bloc = LoanSettlementBloc.withDependencies(
      loanRepository: loans,
      loanScheduleRepository: schedules,
      paymentRepository: payments,
      cashPoolRepository: cashPool,
      authService: auth,
    );
    addTearDown(bloc.close);

    return bloc;
  }

  Future<LoanSettlementState> settle(LoanSettlementBloc bloc) {
    bloc.settleLoanAccount(loanId: loanId);

    return bloc.stream.firstWhere(
      (s) =>
          s.status == LoanSettlementStatus.confirmSettlement ||
          s.status == LoanSettlementStatus.error,
    );
  }

  Future<LoanSettlementState> confirm(
    LoanSettlementBloc bloc,
    double amount,
  ) {
    bloc.confirmLoanAccountSettlement(loanId: loanId, amount: amount);

    return bloc.stream.firstWhere(
      (s) =>
          s.status == LoanSettlementStatus.success ||
          s.status == LoanSettlementStatus.error,
    );
  }

  test('confirming records the row, the payment and the cash pool entry',
      () async {
    final bloc = newBloc();
    expect(bill1.outstandingBalance, closeTo(6827.9144, 0.0001));

    final shown = await settle(bloc);
    expect(shown.status, LoanSettlementStatus.confirmSettlement);
    expect(shown.remainingBalance, closeTo(6941.71, 0.005));

    final done = await confirm(bloc, shown.remainingBalance!);
    expect(done.status, LoanSettlementStatus.success, reason: done.message);

    final rows = await schedules.allByLoanId(loanId: loanId, onlyPaid: false);
    expect(rows, hasLength(2));
    final row = rows.singleWhere((r) => r.id != bill1.id);
    expect(row.id, '$loanId-settlement');
    expect(row.paymentId, '$loanId-settlement');
    expect(row.principalPayment, closeTo(6827.9144, 0.0001));
    expect(row.interestCharge, 113.80);
    expect(row.interestPayment, 113.80);
    expect(row.penalty, 0);
    expect(row.outstandingBalance, 0);
    expect(row.status, LoanStatus.paid_on_time);
    expect(row.isOpenTerm, isFalse);
    expect(row.companyId, 'co-1');
    expect(DateUtils.dateOnly(row.dueAt.toLocal()), today);
    expect(row.paidAt, isNotNull);

    final payment = await payments.get(id: row.paymentId!);
    expect(payment.loanScheduleId, row.id);
    expect(payment.loanId, loanId);
    expect(payment.userId, 'u1');
    expect(payment.status, PaymentStatus.confirmed);
    expect(payment.confirmedBy, 'teller-1');
    expect(payment.comment, contains('Early settlement'));

    final pool = await cashPool.load(
      reset: true,
      limit: null,
      statements: [const QueryStatement(field: 'user_id', isEqualTo: 'u1')],
    );
    final entry = pool.singleWhere(
      (e) => e.status == CashPoolStatus.acknowledged_payment,
    );
    expect(entry.amount, 1000);
    expect(entry.paymentId, payment.id);
    expect(entry.loanId, loanId);
    expect(entry.comment, contains('collected from user in person'));

    expect((await real.get(id: loanId)).status, LoanStatus.completed);
  });

  test('a settled loan is not settled again', () async {
    final bloc = newBloc();
    final shown = await settle(bloc);
    await confirm(bloc, shown.remainingBalance!);

    final again = await settle(bloc);
    expect(again.status, LoanSettlementStatus.error);
    expect(again.message, contains('already settled'));

    final confirmedAgain = await confirm(bloc, shown.remainingBalance!);
    expect(confirmedAgain.status, LoanSettlementStatus.error);
    expect(
      await schedules.allByLoanId(loanId: loanId, onlyPaid: false),
      hasLength(2),
    );
  });

  test('two confirmations at once (a double tap) record one settlement',
      () async {
    final bloc = newBloc();
    final shown = await settle(bloc);

    final outcomes = bloc.stream
        .where(
          (s) =>
              s.status == LoanSettlementStatus.success ||
              s.status == LoanSettlementStatus.error,
        )
        .take(2)
        .toList();
    bloc
      ..confirmLoanAccountSettlement(
        loanId: loanId,
        amount: shown.remainingBalance!,
      )
      ..confirmLoanAccountSettlement(
        loanId: loanId,
        amount: shown.remainingBalance!,
      );

    expect(
      (await outcomes).map((s) => s.status),
      [LoanSettlementStatus.success, LoanSettlementStatus.error],
    );
    expect(
      await schedules.allByLoanId(loanId: loanId, onlyPaid: false),
      hasLength(2),
    );
    expect(
      await payments.load(
        reset: true,
        limit: null,
        statements: [QueryStatement(field: 'loan_id', isEqualTo: loanId)],
      ),
      hasLength(1),
    );
  });

  test('a figure other than the one shown is not recorded', () async {
    final bloc = newBloc();

    final done = await confirm(bloc, 6327.91);
    expect(done.status, LoanSettlementStatus.error);
    expect(done.message, contains('6,941.71'));
    expect(
      await schedules.allByLoanId(loanId: loanId, onlyPaid: false),
      hasLength(1),
    );
    expect((await real.get(id: loanId)).status, LoanStatus.paid_on_time);
  });

  /// Bill 2 of G1 submitted by the borrower on [loan], not yet confirmed.
  Future<(Payment, LoanSchedule)> submitBill2(String loan) async {
    final payment = await payments.add(
      data: Payment.create(
        userId: 'u1',
        loanScheduleId: NO_ID,
        loanId: loan,
        bypassPaymentProof: true,
        status: PaymentStatus.pending,
      ),
    );
    final row = await schedules.add(
      data: LoanSchedule.create(
        dueAt: DateUtils.addDaysToDate(today, 20),
        loanId: loan,
        outstandingBalance: 3497.22,
        principalPayment: 3330.69,
        interestCharge: 341.40,
        amortization: 3672.09,
        interestDayMultiplier: 1,
        companyId: 'co-1',
        status: LoanStatus.payment_submitted,
      )..paymentId = payment.id,
    );
    await payments.update(data: payment..loanScheduleId = row.id);

    return (payment, row);
  }

  // Review of #157: settled with a submission pending, the lender's later
  // confirmation collected it a second time and moved the loan back to
  // paid; a rejection moved it to not paid.
  test('a payment waiting for confirmation stops the settlement', () async {
    await submitBill2(loanId);
    final bloc = newBloc();

    final shown = await settle(bloc);
    expect(shown.status, LoanSettlementStatus.error);
    expect(shown.message, contains('waiting for confirmation'));
    final done = await confirm(bloc, 6941.71);
    expect(done.status, LoanSettlementStatus.error);
    expect(done.message, contains('waiting for confirmation'));
    expect(
      await schedules.allByLoanId(loanId: loanId, onlyPaid: false),
      hasLength(2),
    );
    expect((await real.get(id: loanId)).status, LoanStatus.paid_on_time);
  });

  test("a special loan's pending payment stops the settlement too", () async {
    final special = await real.add(
      data: Loan.create(
        userId: 'u1',
        companyId: 'co-1',
        productId: 'pr-2',
        amount: 5000,
        additionalCharges: 0,
        deductions: 0,
        period: 0,
        requirements: const [],
        isForceCollect: false,
        status: LoanStatus.approved,
        dueAt: null,
        reason: 'special',
        interestRate: 5,
        term: '1m',
        amortization: 250,
        parentId: loanId,
      ),
    );
    await submitBill2(special.id);

    final shown = await settle(newBloc());
    expect(shown.status, LoanSettlementStatus.error);
    expect(shown.message, contains('waiting for confirmation'));
  });

  test('a submission on a settled loan can be neither confirmed nor rejected',
      () async {
    final (payment, row) = await submitBill2(loanId);
    // A loan settled before this check existed.
    await real.update(
      data: (await real.get(id: loanId))..status = LoanStatus.completed,
    );
    final service = PaymentConfirmationService(
      loanScheduleRepository: schedules,
      loanRepository: loans,
      paymentRepository: payments,
    );

    await expectLater(
      service.confirm(payment: payment, confirmedById: 'teller-1'),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      service.reject(
        payment: payment,
        confirmedById: 'teller-1',
        reason: 'duplicate',
      ),
      throwsA(isA<Exception>()),
    );
    expect((await payments.get(id: payment.id)).status, PaymentStatus.pending);
    expect(
      (await schedules.get(id: row.id)).status,
      LoanStatus.payment_submitted,
    );
    expect((await real.get(id: loanId)).status, LoanStatus.completed);
  });

  // Review of #157: two devices that both read the loan before either wrote
  // both passed the checks; the second wrote another row and payment.
  test('a second device that read before the first wrote records nothing',
      () async {
    // Device B's reads, taken before device A writes anything.
    final staleLoan = await real.get(id: loanId);
    final staleRows = await schedules.allByLoanId(
      loanId: loanId,
      onlyPaid: false,
    );
    final staleLoans = _Loans();
    when(() => staleLoans.get(id: any(named: 'id')))
        .thenAnswer((_) async => staleLoan);
    when(
      () => staleLoans.load(
        statements: any(named: 'statements'),
        limit: any(named: 'limit'),
        page: any(named: 'page'),
        reset: any(named: 'reset'),
        includeAdditionalLoanAmounts:
            any(named: 'includeAdditionalLoanAmounts'),
      ),
    ).thenAnswer((_) async => []);
    final staleSchedules = _Schedules();
    when(
      () => staleSchedules.load(
        statements: any(named: 'statements'),
        limit: any(named: 'limit'),
        page: any(named: 'page'),
        reset: any(named: 'reset'),
      ),
    ).thenAnswer((_) async => staleRows);
    when(() => staleSchedules.create(data: any(named: 'data'))).thenAnswer(
      (i) => schedules.create(data: i.namedArguments[#data] as LoanSchedule),
    );

    final a = newBloc();
    final shown = await settle(a);
    expect(
      (await confirm(a, shown.remainingBalance!)).status,
      LoanSettlementStatus.success,
    );

    final b = LoanSettlementBloc.withDependencies(
      loanRepository: staleLoans,
      loanScheduleRepository: staleSchedules,
      paymentRepository: payments,
      cashPoolRepository: cashPool,
      authService: auth,
    );
    addTearDown(b.close);
    final done = await confirm(b, shown.remainingBalance!);

    expect(done.status, LoanSettlementStatus.error);
    expect(done.message, contains('already recorded'));
    expect(
      await schedules.allByLoanId(loanId: loanId, onlyPaid: false),
      hasLength(2),
    );
    expect(
      await payments.load(
        reset: true,
        limit: null,
        statements: [QueryStatement(field: 'loan_id', isEqualTo: loanId)],
      ),
      hasLength(1),
    );
    final pool = await cashPool.load(
      reset: true,
      limit: null,
      statements: [const QueryStatement(field: 'user_id', isEqualTo: 'u1')],
    );
    expect(
      pool.where((e) => e.status == CashPoolStatus.acknowledged_payment),
      hasLength(1),
    );
  });

  // A fixed-term loan has no statement (it is refused as not open-term), so
  // "Settle account" did nothing for one before: it waited for a statement
  // to read the borrower from.
  testWidgets('"Settle account" works without a statement', (tester) async {
    final reports = _Reports();
    when(() => reports.state).thenReturn(const ReportsState.error('x'));
    when(() => reports.soaModel).thenReturn(null);
    final settlement = _Settlement();
    when(() => settlement.state).thenReturn(const LoanSettlementState());

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ReportsBloc>.value(value: reports),
          BlocProvider<LoanSettlementBloc>.value(value: settlement),
        ],
        child: const MaterialApp(
          home: Scaffold(body: StatementOfAccountScreen(loanId: 'loan-ft')),
        ),
      ),
    );
    await tester.tap(find.text('Settle account'));

    verify(() => settlement.settleLoanAccount(loanId: 'loan-ft')).called(1);
  });
}
