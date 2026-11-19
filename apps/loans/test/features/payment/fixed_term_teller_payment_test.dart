import 'package:company_repository/company_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
// Stored rows are read back through this entity, which the package does
// not export.
// ignore: implementation_imports
import 'package:loan_schedule_repository/src/model/loan_schedule_entity.dart';
import 'package:loooans/features/loans/bloc/payment_bloc.dart';
import 'package:loooans/features/payment_center/bloc/payment_center_bloc.dart';
import 'package:loooans/features/products/screen/loan_schedule_widget.dart';
import 'package:loooans/features/users/widget/client_detail/client_detail_schedule_item.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans/services/payment_confirmation_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:payment_repository/payment_repository.dart';
import 'package:storage_repository/storage_repository.dart';
import 'package:user_repository/user_repository.dart';

import '../../helpers/helpers.dart';

// finstack#140 and #150 through the teller's real handlers: the G1 loan
// (10,000, 3 months, 5%, P 3,672.0856; golden G1/G1t) created 70 days ago,
// so rows 1 and 2 are overdue and row 3 is upcoming.
//
// #140: a computed row holds the balance after its scheduled principal
// (row 1: 6,827.9144), so a teller payment of the scheduled principal
// stores it unchanged. Before the fix the handlers subtracted the principal
// again.
//   Client detail / Payment Center single, the dialog's 3,172.09: stored
//     6,827.91 (was 3,655.82); next bills 3,672.09 and 3,672.08 (was
//     3,672.09 and 174.86).
//   Client detail, 4,172.09 (1,000 extra): stored 5,827.91 (was 2,655.82);
//     next bills 3,672.09 and 2,569.58.
//   Payment Center bulk, rows 1 and 2 at the scheduled principal: stored
//     6,827.91 and 3,497.22 (was 3,655.83 and 166.53); next bill 3,672.09.
// #150: in client detail only the earliest unpaid installment can be paid.
// #152 (golden G16a): bill 1 paid 500 + 3,000 (172.09 short) stores 7,000;
//   bill 2 is 3,844.18 = 350.00 + 3,494.18 (was 3,672.09), bill 3 3,681.11
//   before and after bill 2 is paid as the dialog fills it (was 3,672.09). A
//   last bill paid 175.29 + 3,000 leaves 505.82: the loan stays open (was
//   completed) and one more row bills it on bill 3's due date; paying it
//   completes the loan. The loan is stored on a fake Firestore here, so its
//   status is what the next screen reads.

class _Users extends Mock implements UserRepository {}

class _Loans extends Mock implements LoanRepository {}

class _Schedules extends Mock implements LoanScheduleRepository {}

class _Payments extends Mock implements PaymentRepository {}

class _Storage extends Mock implements StorageRepository {}

class _Auth extends Mock implements AuthenticationService {}

DateTime get today => DateUtils.dateOnly(DateTime.now());

DateTime get createdAt => DateUtils.addDaysToDate(today, -70);

Loan fixedTermLoan() => Loan.create(
      userId: 'u1',
      companyId: 'co-1',
      productId: 'pr-1',
      amount: 10000,
      additionalCharges: 0,
      deductions: 0,
      period: 3,
      requirements: const [],
      isForceCollect: false,
      status: LoanStatus.approved,
      dueAt: null,
      reason: 'fixed term',
      interestRate: 5,
      term: '1m',
      amortization: 3672.09,
    )
      ..id = 'loan-1'
      ..createdAt = createdAt
      ..additionalLoanAmounts = [];

/// The rows client detail lists after [stored]: the stored rows, then the
/// computed ones (LoansBloc's `_calculateLoan`).
List<LoanSchedule> clientRows(List<LoanSchedule> stored) => [
      ...stored,
      ...LoanCalculationService.calculateFixedTerm(
        amount: 10000,
        monthsToPay: 3,
        date: createdAt,
        interestRate: 5,
        term: '1m',
        companyId: 'co-1',
        paidSchedules: List.of(stored),
      ).schedules,
    ];

/// [row] as Firestore hands it back.
LoanSchedule readBack(LoanSchedule row) =>
    LoanScheduleEntity.fromJson(row.toJson()).toLoanSchedule();

void main() {
  late _Loans loans;
  late _Schedules schedules;
  late _Payments payments;
  late _Users users;
  late _Auth auth;
  late List<LoanSchedule> written;

  setUpAll(() {
    registerFallbackValue(Loan());
    registerFallbackValue(LoanSchedule());
    registerFallbackValue(Payment());
  });

  setUp(() {
    loans = _Loans();
    schedules = _Schedules();
    payments = _Payments();
    users = _Users();
    auth = _Auth();
    written = [];
    var paymentCount = 0;

    when(() => auth.company).thenReturn(
      Company()
        ..id = 'co-1'
        ..managementType = CompanyManagementType.selfManaged,
    );
    when(() => auth.user).thenReturn(
      User()
        ..id = 'teller-1'
        ..firstName = 'Tess'
        ..lastName = 'Teller'
        ..emailAddress = 'teller@example.com',
    );
    when(() => users.get(id: any(named: 'id'))).thenAnswer(
      (_) async => User()
        ..id = 'u1'
        ..firstName = 'Bea'
        ..lastName = 'Borrower'
        ..emailAddress = 'bea@example.com',
    );
    when(() => payments.add(data: any(named: 'data'))).thenAnswer(
      (i) async =>
          (i.namedArguments[#data] as Payment)..id = 'pay-${++paymentCount}',
    );
    when(() => payments.update(data: any(named: 'data'))).thenAnswer(
      (i) async => i.namedArguments[#data] as Payment,
    );
    when(() => schedules.add(data: any(named: 'data'))).thenAnswer((i) async {
      final row = (i.namedArguments[#data] as LoanSchedule)
        ..id = 'stored-${written.length + 1}';
      written.add(row);
      return row;
    });
    when(
      () => schedules.load(
        statements: any(named: 'statements'),
        limit: any(named: 'limit'),
        page: any(named: 'page'),
        reset: any(named: 'reset'),
      ),
    ).thenAnswer((_) async => written.map(readBack).toList());
    when(
      () => schedules.allByLoanId(
        loanId: any(named: 'loanId'),
        onlyPaid: any(named: 'onlyPaid'),
      ),
    ).thenAnswer((_) async => written.map(readBack).toList());
    when(
      () => loans.update(
        data: any(named: 'data'),
        updateView: any(named: 'updateView'),
      ),
    ).thenAnswer((i) async => i.namedArguments[#data] as Loan);
    when(() => loans.get(id: any(named: 'id')))
        .thenAnswer((_) async => fixedTermLoan());
    when(
      () => loans.load(
        statements: any(named: 'statements'),
        limit: any(named: 'limit'),
        page: any(named: 'page'),
        reset: any(named: 'reset'),
        includeAdditionalLoanAmounts:
            any(named: 'includeAdditionalLoanAmounts'),
      ),
    ).thenAnswer((i) async {
      final statements = i.namedArguments[#statements] as List<QueryStatement>;
      return statements.first.field == 'user_id'
          ? [fixedTermLoan()]
          : <Loan>[];
    });
  });

  group('client detail (PaymentBloc)', () {
    Future<void> pay(String principal) async {
      final rows = clientRows(const []);
      final bloc = PaymentBloc.withDependencies(
        userRepository: users,
        loanRepository: loans,
        loanScheduleRepository: schedules,
        storageRepository: _Storage(),
        paymentRepository: payments,
        authService: auth,
      );
      addTearDown(bloc.close);

      bloc.makePayment(
        loan: fixedTermLoan(),
        schedule: rows.first,
        loanRows: rows,
        interestPayment: rows.first.interestPayment.toStringAsFixed(2),
        payment: principal,
        otpVerified: true,
      );
      // It writes the loan and the row, then stops at the cash pool (not
      // mockable here).
      await bloc.stream.firstWhere((s) => s.message?.isNotEmpty ?? false);
    }

    test("the dialog's 3,172.09: stored 6,827.91, then 3,672.09 + 3,672.08",
        () async {
      await pay('3172.09');

      final stored = readBack(written.single);
      expect(stored.outstandingBalance, closeTo(6827.91, 0.000001));
      expect(stored.principalPayment, 3172.09);
      expect(stored.interestPayment, 500);
      final next = clientRows([stored]).skip(1);
      expect(next.map((s) => s.amortization.toStringAsFixed(2)), [
        '3672.09',
        '3672.08',
      ]);
      expect(next.last.outstandingBalance, closeTo(0, 0.0001));
    });

    test('1,000 extra principal: stored 5,827.91, then 3,672.09 + 2,569.58',
        () async {
      await pay('4172.09');

      final stored = readBack(written.single);
      expect(stored.outstandingBalance, closeTo(5827.91, 0.000001));
      expect(stored.extraPayment, closeTo(1000.0044, 0.0001));
      final next = clientRows([stored]).skip(1);
      expect(next.map((s) => s.amortization.toStringAsFixed(2)), [
        '3672.09',
        '2569.58',
      ]);
      expect(next.last.outstandingBalance, closeTo(0, 0.0001));
    });
  });

  PaymentCenterBloc newBloc() {
    final bloc = PaymentCenterBloc.withDependencies(
      userRepository: users,
      loanRepository: loans,
      loanScheduleRepository: schedules,
      paymentRepository: payments,
      storageRepository: _Storage(),
      authService: auth,
    );
    addTearDown(bloc.close);
    return bloc;
  }

  /// What the Payment Center lists to pay for the borrower now.
  Future<List<LoanSchedule>> actionable() async {
    final bloc = newBloc()
      ..add(SelectBorrowerEvent(borrower: User()..id = 'u1'));
    final state = await bloc.stream.firstWhere(
      (s) =>
          s.status == PaymentCenterStatus.borrowerSelected ||
          s.status == PaymentCenterStatus.error,
    );
    expect(state.status, PaymentCenterStatus.borrowerSelected);

    return state.borrowerLoans.single.actionableSchedules;
  }

  Future<void> run(PaymentCenterEvent event) async {
    final bloc = newBloc()..add(event);
    // The handler writes every row and the loan, then stops at the
    // cash-pool step (its repository cannot be mocked).
    await bloc.stream.firstWhere(
      (s) =>
          s.status == PaymentCenterStatus.error ||
          s.status == PaymentCenterStatus.paymentSuccess,
    );
  }

  group('Payment Center (PaymentCenterBloc)', () {
    test('before paying: rows 1 and 2 overdue, row 3 upcoming', () async {
      final rows = await actionable();

      expect(rows.map((r) => r.status), [
        LoanStatus.not_paid_overdue,
        LoanStatus.not_paid_overdue,
        LoanStatus.not_paid,
      ]);
      expect(rows.first.outstandingBalance, closeTo(6827.9144, 0.0001));
    });

    test("single payment, the dialog's 3,172.09: stored 6,827.91, then "
        '3,672.09 + 3,672.08', () async {
      final row1 = (await actionable()).first;
      await run(
        MakePaymentEvent(
          loan: fixedTermLoan(),
          schedule: row1,
          interestPayment: 500,
          payment: 3172.09,
          otpVerified: true,
        ),
      );

      expect(written.single.outstandingBalance, closeTo(6827.91, 0.000001));
      final next = await actionable();
      expect(next.map((s) => s.amortization.toStringAsFixed(2)), [
        '3672.09',
        '3672.08',
      ]);
      expect(next.first.outstandingBalance, closeTo(3497.2199, 0.0001));
    });

    test('bulk overdue payment of rows 1 and 2: stored 6,827.91 and '
        '3,497.22, then 3,672.09', () async {
      final overdue = (await actionable())
          .where((r) => r.status == LoanStatus.not_paid_overdue)
          .toList();
      expect(overdue, hasLength(2));
      await run(
        MakeOverduePaymentEvent(
          loan: fixedTermLoan(),
          schedules: overdue,
          totalPrincipalPayment:
              overdue.fold<double>(0, (sum, s) => sum + s.principalPayment),
          totalInterestPayment:
              overdue.fold<double>(0, (sum, s) => sum + s.interestPayment),
          otpVerified: true,
        ),
      );

      expect(written.map((r) => r.outstandingBalance), [
        closeTo(6827.9144, 0.0001),
        closeTo(3497.2244, 0.0001),
      ]);
      final next = await actionable();
      expect(next, hasLength(1));
      expect(next.single.amortization, closeTo(3672.0856, 0.0001));
      expect(next.single.outstandingBalance, closeTo(0, 0.0001));
    });
  });

  group('client detail: the earliest unpaid installment only (#150)', () {
    setUp(() {
      AuthenticationService.instance
        ..user = (User()
          ..id = 'teller-1'
          ..userRole = UserRole.admin)
        ..company = (Company()
          ..id = 'co-1'
          ..managementType = CompanyManagementType.selfManaged);
    });

    /// The "Make payment" buttons of [rows], in row order.
    Future<List<OutlinedButton>> pumpButtons(
      WidgetTester tester,
      List<LoanSchedule> rows,
    ) async {
      tester.view
        ..physicalSize = const Size(2400, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpApp(
        Scaffold(
          body: Column(
            children: [
              for (final row in rows)
                ClientDetailScheduleItem(
                  index: 2,
                  schedule: row,
                  onMakePayment: (_) {},
                  loan: fixedTermLoan(),
                  loanRows: rows,
                ),
            ],
          ),
        ),
      );

      return tester
          .widgetList<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Make payment'),
          )
          .toList();
    }

    testWidgets('two overdue installments: only the first can be paid',
        (tester) async {
      final buttons = await pumpButtons(tester, clientRows(const []));

      expect(find.text('Overdue'), findsNWidgets(2));
      expect(buttons, hasLength(3));
      expect(buttons[0].onPressed, isNotNull, reason: 'row 1, overdue');
      expect(buttons[1].onPressed, isNull, reason: 'row 2, overdue');
      expect(buttons[2].onPressed, isNull, reason: 'row 3, upcoming');
    });

    testWidgets('after row 1 is paid, row 2 is next', (tester) async {
      final row1 = clientRows(const []).first
        ..id = 'sched-1'
        ..status = LoanStatus.paid_late
        ..paidAt = DateTime.now();
      final buttons = await pumpButtons(tester, clientRows([row1]));

      expect(buttons, hasLength(2), reason: 'the paid row has none');
      expect(buttons[0].onPressed, isNotNull, reason: 'row 2');
      expect(buttons[1].onPressed, isNull, reason: 'row 3');
    });

    testWidgets('a rejected stored installment is payable; the next waits',
        (tester) async {
      final rejected = readBack(
        clientRows(const []).first
          ..id = 'sched-1'
          ..status = LoanStatus.not_paid_overdue,
      );
      final buttons = await pumpButtons(tester, clientRows([rejected]));

      expect(buttons, hasLength(3));
      expect(buttons[0].onPressed, isNotNull, reason: 'the rejected row');
      expect(buttons[1].onPressed, isNull);
      expect(buttons[2].onPressed, isNull);
    });
  });

  group('#152 a short principal is added to the next bill', () {
    late LoanRepository real;
    late String loanId;

    setUp(() async {
      real = LoanRepository.withFirestore(FakeFirebaseFirestore());
      loanId = (await real.add(data: fixedTermLoan())).id;
      when(() => loans.get(id: any(named: 'id'))).thenAnswer(
        (i) => real.get(id: i.namedArguments[#id] as String),
      );
      // The loan view needs the real Firestore; the loan itself is written.
      when(
        () => loans.update(
          data: any(named: 'data'),
          updateView: any(named: 'updateView'),
        ),
      ).thenAnswer((i) => real.update(data: i.namedArguments[#data] as Loan));
      when(
        () => loans.load(
          statements: any(named: 'statements'),
          limit: any(named: 'limit'),
          page: any(named: 'page'),
          reset: any(named: 'reset'),
          includeAdditionalLoanAmounts:
              any(named: 'includeAdditionalLoanAmounts'),
        ),
      ).thenAnswer((i) async {
        final statements =
            i.namedArguments[#statements] as List<QueryStatement>;
        return statements.first.field == 'user_id'
            ? [await real.get(id: loanId)]
            : <Loan>[];
      });
    });

    Future<LoanStatus> loanStatus() async =>
        (await real.get(id: loanId)).status;

    /// Client detail records [row] with the dialog's [interest] and
    /// [principal].
    Future<void> payInClientDetail(
      LoanSchedule row,
      List<LoanSchedule> rows, {
      required String interest,
      required String principal,
    }) async {
      final bloc = PaymentBloc.withDependencies(
        userRepository: users,
        loanRepository: loans,
        loanScheduleRepository: schedules,
        storageRepository: _Storage(),
        paymentRepository: payments,
        authService: auth,
      );
      addTearDown(bloc.close);

      bloc.makePayment(
        loan: await real.get(id: loanId),
        schedule: row,
        loanRows: rows,
        interestPayment: interest,
        payment: principal,
        otpVerified: true,
      );
      await bloc.stream.firstWhere((s) => s.message?.isNotEmpty ?? false);
    }

    /// The Payment Center records [row]; the interest as the dialog fills
    /// it unless given.
    Future<void> payInPaymentCenter(
      LoanSchedule row, {
      required double principal,
      double? interest,
    }) async =>
        run(
          MakePaymentEvent(
            loan: await real.get(id: loanId),
            schedule: row,
            interestPayment: interest ??
                double.parse(row.interestPayment.toStringAsFixed(2)),
            payment: principal,
            otpVerified: true,
          ),
        );

    test('client detail: 500 + 3,000 stores 7,000; bill 2 is 3,844.18, '
        'then bill 3 is 3,681.11', () async {
      var rows = clientRows(const []);
      await payInClientDetail(
        rows.first,
        rows,
        interest: '500.00',
        principal: '3000.00',
      );

      final stored = readBack(written.single);
      expect(stored.outstandingBalance, closeTo(7000, 0.000001));
      expect(stored.principalPayment, 3000);
      expect(stored.interestPayment, 500);
      expect(stored.extraPayment, 0);
      rows = clientRows([stored]);
      final bill2 = rows[1];
      expect(bill2.amortization.toStringAsFixed(2), '3844.18');
      expect(bill2.interestPayment.toStringAsFixed(2), '350.00');
      expect(bill2.principalPayment.toStringAsFixed(2), '3494.18');
      expect(rows[2].amortization.toStringAsFixed(2), '3681.11');

      await payInClientDetail(
        bill2,
        rows,
        interest: bill2.interestPayment.toStringAsFixed(2),
        principal: bill2.principalPayment.toStringAsFixed(2),
      );
      final storedTwo = written.map(readBack).toList();
      expect(storedTwo.last.outstandingBalance, closeTo(3505.82, 0.000001));
      final bill3 = clientRows(storedTwo).last;
      expect(bill3.interestPayment.toStringAsFixed(2), '175.29');
      expect(bill3.principalPayment.toStringAsFixed(2), '3505.82');
      expect(bill3.amortization.toStringAsFixed(2), '3681.11');
      expect(
        bill3.amortization,
        closeTo(rows[2].amortization, 0.000001),
        reason: 'the projection equals the bill after bill 2 is paid',
      );
    });

    test('Payment Center single: 500 + 3,000 stores 7,000; bill 2 is '
        '3,844.18', () async {
      await payInPaymentCenter((await actionable()).first, principal: 3000);

      expect(written.single.outstandingBalance, closeTo(7000, 0.000001));
      expect(written.single.principalPayment, 3000);
      final next = await actionable();
      expect(next.map((s) => s.status), [
        LoanStatus.not_paid_overdue,
        LoanStatus.not_paid,
      ]);
      expect(next.map((s) => s.amortization.toStringAsFixed(2)), [
        '3844.18',
        '3681.11',
      ]);
      expect(next.first.interestPayment, closeTo(350, 0.000001));
      expect(next.first.principalPayment.toStringAsFixed(2), '3494.18');
      expect(await loanStatus(), LoanStatus.paid_late);
    });

    test('Payment Center: a short last bill keeps the loan open; paying its '
        '505.82 remainder completes it', () async {
      await payInPaymentCenter((await actionable()).first, principal: 3000);
      final bill2 = (await actionable()).first;
      await payInPaymentCenter(
        bill2,
        principal: double.parse(bill2.principalPayment.toStringAsFixed(2)),
      );
      final bill3 = (await actionable()).single;
      expect(bill3.amortization.toStringAsFixed(2), '3681.11');

      await payInPaymentCenter(bill3, principal: 3000);
      expect(written.last.outstandingBalance, closeTo(505.82, 0.000001));
      expect(
        await loanStatus(),
        LoanStatus.paid_on_time,
        reason: 'before #152 this was completed with 505.82 owed',
      );

      final remainder = (await actionable()).single;
      expect(remainder.amortization, closeTo(505.82, 0.000001));
      expect(remainder.principalPayment, closeTo(505.82, 0.000001));
      expect(remainder.interestPayment, 0);
      expect(remainder.dueAt.isAtSameMomentAs(bill3.dueAt), isTrue);
      expect(remainder.status, LoanStatus.not_paid);

      await payInPaymentCenter(remainder, principal: 505.82, interest: 0);
      expect(written, hasLength(4));
      expect(written.last.outstandingBalance, closeTo(0, 0.000001));
      expect(await loanStatus(), LoanStatus.completed);
      expect(await actionable(), isEmpty);
    });

    test('Payment Center: the last bill as billed completes the loan',
        () async {
      await payInPaymentCenter((await actionable()).first, principal: 3000);
      final bill2 = (await actionable()).first;
      await payInPaymentCenter(
        bill2,
        principal: double.parse(bill2.principalPayment.toStringAsFixed(2)),
      );
      final bill3 = (await actionable()).single;
      await payInPaymentCenter(bill3, principal: 3505.82);

      expect(written.last.outstandingBalance, closeTo(0, 0.000001));
      expect(await loanStatus(), LoanStatus.completed);
    });

    /// Client detail records the next bill, as the dialog fills it unless
    /// [principal] is given (#155: the last bill and a remainder row are
    /// recorded, not sent to settlement).
    Future<LoanSchedule> payNextInClientDetail({String? principal}) async {
      final rows = clientRows(written.map(readBack).toList());
      final next = rows.firstWhere((s) => s.id == NO_ID);
      await payInClientDetail(
        next,
        rows,
        interest: next.interestPayment.toStringAsFixed(2),
        principal: principal ?? next.principalPayment.toStringAsFixed(2),
      );

      return next;
    }

    test('client detail: the last bill as billed completes the loan (#155)',
        () async {
      await payNextInClientDetail(principal: '3000.00');
      await payNextInClientDetail();
      expect(await loanStatus(), LoanStatus.paid_late);
      final bill3 = await payNextInClientDetail();

      expect(bill3.principalPayment, closeTo(3505.82, 0.000001));
      expect(written.last.outstandingBalance, closeTo(0, 0.000001));
      expect(await loanStatus(), LoanStatus.completed);
    });

    test('client detail: a short last bill stays open; its 505.82 remainder '
        'completes the loan (#155)', () async {
      await payNextInClientDetail(principal: '3000.00');
      await payNextInClientDetail();
      await payNextInClientDetail(principal: '3000.00');
      expect(written.last.outstandingBalance, closeTo(505.82, 0.000001));
      expect(await loanStatus(), LoanStatus.paid_on_time);

      final remainder = await payNextInClientDetail();
      expect(remainder.amortization, closeTo(505.82, 0.000001));
      expect(remainder.interestPayment, 0);
      expect(written, hasLength(4));
      expect(written.last.outstandingBalance, closeTo(0, 0.000001));
      expect(await loanStatus(), LoanStatus.completed);
    });
  });

  testWidgets("#152 the borrower's compact schedule shows bill 2 as "
      '3,844.18, not the 3,672.09 amortization', (tester) async {
    final stored = clientRows(const []).first;
    PaymentConfirmationService.recordTellerPayment(
      stored,
      interestPayment: 500,
      principalPayment: 3000,
    );
    stored
      ..id = 'sched-1'
      ..status = LoanStatus.paid_late;
    final bill2 = clientRows([stored])[1];

    await tester.pumpApp(
      Scaffold(
        body: Builder(
          builder: (context) =>
              LoanScheduleWidget.scheduleItem(context, schedule: bill2),
        ),
      ),
    );

    expect(find.text(bill2.amortization.toCurrency()), findsOneWidget);
    expect(bill2.amortization.toCurrency(), contains('3,844.18'));
  });
}
