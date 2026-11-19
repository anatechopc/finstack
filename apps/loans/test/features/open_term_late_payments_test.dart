import 'package:company_repository/company_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
// Stored rows are read back through this entity, which the package does
// not export.
// ignore: implementation_imports
import 'package:loan_schedule_repository/src/model/loan_schedule_entity.dart';
import 'package:loooans/features/loans/screens/loan_details.dart';
import 'package:loooans/features/payment_center/bloc/payment_center_bloc.dart';
import 'package:loooans/features/payment_center/widget/overdue_summary_tile.dart';
import 'package:loooans/features/products/screen/loan_schedule_widget.dart';
import 'package:loooans/features/users/widget/client_detail/client_detail_schedule_item.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans/services/payment_confirmation_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/widgets/payment_penalty_section.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:payment_repository/payment_repository.dart';
import 'package:storage_repository/storage_repository.dart';
import 'package:user_repository/user_repository.dart';

import '../helpers/helpers.dart';

// finstack#114 and the owner's open-term rules R1-R5 (2026-11-19) at widget
// and bloc level: the screens fed by the real open-term engine.
// Loan: 10,000 at 5% a month ('1m', 500 per 30-day cycle); penalties
// "Late fee" 100 once + "Daily surcharge" 1% of the balance (100) per day.
//
// One missed bill (G13a): paid cycle 38 days ago -> the bill due 8 days ago
// keeps its date (R1), 30 days, 500 (before R1: billed today, 38 days,
// 633.33); 8 days late -> 100 + 100 x 8 = 900; the next bill (+22) is not
// due yet. With fixed dates (Sep 8 2026, paid Aug 1): Aug 31 500 + 900 ->
// Next payment 1,400; Pay in full 1,400 + Sep 30's 500 = 1,900 (allow late:
// 500 / 1,000).
// Two missed bills: paid cycle 68 days ago -> bills due 38 and 8 days ago
// (500 each), +22 current. The stretch runs from the earliest unpaid due
// date (R3): 100 + 100 x 38 = 3,900 once (per bill it would be 3,900 + 900
// = 4,800). Fixed dates, seen Oct 5: Aug 31 and Sep 30 missed -> Next
// payment 500 + 500 + (100 + 100 x 35) = 4,600; Pay in full + Oct 30's 500
// = 5,100.
// Bulk overdue (two missed): total interest 1,000 pays 500 + 500, penalty
// [3,900, 0], days late [38, 8]; 700 pays 500 + 200 (the 300 short carries,
// R4); 400 pays the first bill only and the second stays unpaid.
//
// The client-detail row, the borrower table and the Payment Center read the
// wall clock, so those scenarios are dated relative to today; the payment
// dialog and the borrower totals take a date. Like the golden suite this
// assumes a zone without daylight saving (CI pins TZ=UTC): across a clock
// change the engine's 30-day step lands an hour off (campaign D11).
//
// Rejected submissions stored by #143's app (before R1): billed as due on
// the day they were submitted, interest from the paid cycle to that day,
// the cycle's own date in original_due_at. The engine leaves them as they
// are and bills the next scheduled date after them, from that day.
//   Submitted 2 days ago (paid 38 days ago): 36 days, 600, original due 8
//   days ago -> overdue, 900; the next bill is the scheduled +22 (24 days
//   from the stored row, 400), upcoming. Stored before #114 (no original
//   due date): 100 + 100 x 2 = 300.
//   Submitted 45 days ago (paid 80 days ago, loan 110 days old): 35 days,
//   583.33, amount due 500 (the old cap), original due 50 days ago; next
//   bills -20 (25 days, 416.67, missed) and +10 (500). Stretch from 50
//   days ago: 100 + 100 x 50 = 5,100 once (per bill 5,100 + 2,100 =
//   7,200); Pay in full 500 + 416.67 + 500 + 5,100 = 6,516.67 on every
//   screen.
//   With a 5,000 top-up 50 days ago (stored 15,000, interest 500, penalty
//   100 + 1% x 15,000 x 50 = 7,600): the row is shown and confirmed as
//   stored (#145); the top-up is in its balance, so the next bill (-20, 25
//   days) is 15,000 x 5% x 25/30 = 625.

const lateFee100 = Penalty(id: 'late-fee', name: 'Late fee', amount: 100);
const daily1pct = Penalty(
  id: 'daily',
  name: 'Daily surcharge',
  amount: 1,
  isPercentage: true,
  frequency: PenaltyFrequency.daily,
);

/// Read on every use, so a run that crosses midnight stays consistent with
/// the engine's own clock.
DateTime get today => DateUtils.dateOnly(DateTime.now());

DateTime daysFromToday(int days) => DateUtils.addDaysToDate(today, days);

/// Every field is set (the Payment Center state compares loans by value).
Loan openTermLoan({required DateTime createdAt, bool allowLate = false}) =>
    Loan.create(
      userId: 'u1',
      companyId: 'co-1',
      productId: 'pr-1',
      amount: 10000,
      additionalCharges: 0,
      deductions: 0,
      period: 0,
      requirements: const [],
      isForceCollect: false,
      status: LoanStatus.approved,
      dueAt: null,
      reason: 'open term',
      interestRate: 5,
      term: '1m',
      amortization: 500,
      penalties: const [lateFee100, daily1pct],
      allowLatePayments: allowLate,
    )
      ..id = 'loan-1'
      ..createdAt = createdAt
      ..additionalLoanAmounts = [];

LoanSchedule paidCycle(DateTime dueAt) => LoanSchedule()
  ..id = 'sched-1'
  ..loanId = 'loan-1'
  ..companyId = 'co-1'
  ..createdAt = dueAt
  ..updatedAt = dueAt
  ..dueAt = dueAt
  ..paidAt = dueAt
  ..status = LoanStatus.paid_on_time
  ..isOpenTerm = true
  ..outstandingBalance = 10000
  ..principalPayment = 0
  ..interestPayment = 0
  ..interestCharge = 0
  ..amortization = 0
  ..extraPayment = 0
  ..advanceInterestPayments = 0
  ..interestDayMultiplier = 1;

/// The open-term bills after a cycle paid [paidDaysAgo] days ago on a loan
/// created 30 days before it, as the app computes them now.
List<LoanSchedule> billsNow({int paidDaysAgo = 38}) =>
    LoanCalculationService.calculateOpenTermSchedules(
      amount: 10000,
      date: daysFromToday(-paidDaysAgo - 30),
      interestRate: 5,
      term: '1m',
      companyId: 'co-1',
      paidSchedules: [paidCycle(daysFromToday(-paidDaysAgo))],
      now: DateTime.now(),
    ).schedules;

/// What LoansBloc lists for client detail and the borrower now.
List<LoanSchedule> clientRowsNow(Loan loan, List<LoanSchedule> stored) =>
    LoanCalculationService.calculateOpenTerm(
      amount: 10000,
      date: loan.createdAt,
      interestRate: 5,
      term: '1m',
      companyId: 'co-1',
      paidSchedules: stored,
      loan: loan,
      now: DateTime.now(),
    ).schedules;

/// A submission on [submittedAt] that the lender rejected, as #143's app
/// stored it (before R1): billed as due that day with interest from the
/// paid cycle, the cycle's date in original_due_at; read back from
/// Firestore as overdue.
LoanSchedule rejectedSubmission({
  required DateTime paidDue,
  required DateTime submittedAt,
  bool storedBefore114 = false,
  double balance = 10000,
  double? interestCharge,
}) {
  final billedOn = DateUtils.dateOnly(submittedAt);
  final days = billedOn.difference(paidDue).inDays;
  final interest = interestCharge ?? balance * 0.05 * days / 30;
  final row = LoanSchedule()
    ..id = 'sched-2'
    ..loanId = 'loan-1'
    ..companyId = 'co-1'
    ..createdAt = submittedAt
    ..updatedAt = submittedAt
    ..dueAt = billedOn
    ..originalDueAt =
        storedBefore114 ? null : DateUtils.addDaysToDate(paidDue, 30)
    ..status = LoanStatus.not_paid_overdue
    ..isOpenTerm = true
    ..outstandingBalance = balance
    ..principalPayment = 0
    ..interestPayment = 0
    ..interestCharge = interest
    ..amortization = interest < balance * 0.05 ? interest : balance * 0.05
    ..extraPayment = 0
    ..advanceInterestPayments = 0
    ..interestDayMultiplier = days / 30;

  return LoanScheduleEntity.fromJson(row.toJson()).toLoanSchedule();
}

class _Users extends Mock implements UserRepository {}

class _Loans extends Mock implements LoanRepository {}

class _Schedules extends Mock implements LoanScheduleRepository {}

class _Payments extends Mock implements PaymentRepository {}

class _Storage extends Mock implements StorageRepository {}

class _Auth extends Mock implements AuthenticationService {}

void main() {
  group('client-detail schedule row (teller)', () {
    setUp(() {
      AuthenticationService.instance
        ..user = (User()
          ..id = 'teller-1'
          ..userRole = UserRole.admin)
        ..company = (Company()
          ..id = 'co-1'
          ..managementType = CompanyManagementType.selfManaged);
    });

    Future<void> pumpRows(
      WidgetTester tester,
      Loan loan,
      List<LoanSchedule> rows, {
      List<LoanSchedule> loanRows = const [],
    }) async {
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
                  loan: loan,
                  loanRows: loanRows,
                ),
            ],
          ),
        ),
      );
    }

    testWidgets('a missed bill keeps its date: Overdue, 500, 900 for 8 days',
        (tester) async {
      final missed = billsNow().first;
      await pumpRows(
        tester,
        openTermLoan(createdAt: daysFromToday(-68)),
        [missed],
      );

      expect(find.text('Make payment'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(
        find.textContaining('900.00 penalty · 8 days late'),
        findsOneWidget,
      );
      expect(
        find.text(daysFromToday(-8).toDefaultDateFormat()),
        findsOneWidget,
        reason: 'R1: the bill is dated on its cycle, not today',
      );
      expect(find.textContaining('500.00'), findsOneWidget);
      expect(find.textContaining('633.33'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a loan that allows late payments: Overdue, no penalty',
        (tester) async {
      await pumpRows(
        tester,
        openTermLoan(createdAt: daysFromToday(-68), allowLate: true),
        [billsNow().first],
      );

      expect(find.text('Overdue'), findsOneWidget);
      expect(find.textContaining('penalty'), findsNothing);
    });

    testWidgets(
        'two missed bills: the penalty once, Make payment on the '
        'earliest only', (tester) async {
      final loan = openTermLoan(createdAt: daysFromToday(-98));
      final rows = clientRowsNow(loan, [paidCycle(daysFromToday(-68))]);
      final missed =
          rows.where((r) => r.id == NO_ID && !r.isPlaceholder).take(2).toList();
      expect(
        missed.map((r) => DateUtils.dateOnly(r.dueAt)),
        [daysFromToday(-38), daysFromToday(-8)],
      );

      await pumpRows(tester, loan, missed, loanRows: rows);

      expect(find.text('Overdue'), findsNWidgets(2));
      expect(
        find.textContaining('3,900.00 penalty · 38 days late'),
        findsOneWidget,
      );
      expect(find.textContaining('penalty'), findsOneWidget);
      final buttons = tester
          .widgetList<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Make payment'),
          )
          .toList();
      expect(buttons, hasLength(2));
      expect(buttons[0].onPressed, isNotNull);
      expect(
        buttons[1].onPressed,
        isNull,
        reason: 'a later computed bill waits for the earlier one',
      );
    });

    testWidgets('the principal-release row has no Make payment and no penalty',
        (tester) async {
      final loan = openTermLoan(createdAt: daysFromToday(-68));
      final principalRelease =
          clientRowsNow(loan, [paidCycle(daysFromToday(-38))]).first;
      expect(principalRelease.isPlaceholder, isTrue);
      expect(principalRelease.status, LoanStatus.not_paid);

      await pumpRows(tester, loan, [principalRelease]);

      expect(find.text('Make payment'), findsNothing);
      expect(find.textContaining('penalty'), findsNothing);
    });
  });

  testWidgets('borrower schedule table: overdue label and the penalty once',
      (tester) async {
    final rows = billsNow(paidDaysAgo: 68);
    await tester.pumpApp(
      LoanScheduleWidget(
        amortization: 500,
        schedules: rows,
        completeTerm: 'Open term',
        buildTable: true,
        tableHeight: 4 * LoanScheduleWidget.rowHeight,
        loan: openTermLoan(createdAt: daysFromToday(-98)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(LoanStatus.not_paid_overdue.label), findsNWidgets(2));
    expect(find.textContaining('3,900.00 penalty'), findsOneWidget);
    expect(find.textContaining('penalty'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('payment dialog breakdown (PaymentPenaltySection)', () {
    final sep8 = DateTime(2026, 9, 8, 12);
    List<LoanSchedule> rowsOn(DateTime now) =>
        LoanCalculationService.calculateOpenTermSchedules(
          amount: 10000,
          date: DateTime(2026, 7, 2),
          interestRate: 5,
          term: '1m',
          companyId: 'co-1',
          paidSchedules: [paidCycle(DateTime(2026, 8))],
          now: now,
        ).schedules;

    Future<void> pumpSection(
      WidgetTester tester,
      Loan loan,
      List<LoanSchedule> paying, {
      List<LoanSchedule> loanRows = const [],
      DateTime? collectedAt,
    }) {
      return tester.pumpApp(
        Scaffold(
          body: SingleChildScrollView(
            child: FormBuilder(
              child: PaymentPenaltySection(
                schedules: paying,
                loan: loan,
                initialCollectedAt: collectedAt ?? DateTime(2026, 9, 8),
                loanRows: loanRows,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('one missed bill collected Sep 8: 100 once + 8 days x 100',
        (tester) async {
      await pumpSection(
        tester,
        openTermLoan(createdAt: DateTime(2026, 7, 2)),
        [rowsOn(sep8).first],
      );

      expect(find.textContaining('Late fee'), findsOneWidget);
      expect(find.textContaining('Daily surcharge'), findsOneWidget);
      expect(find.textContaining('× 8'), findsOneWidget);
      expect(find.textContaining('800.00'), findsOneWidget);
      expect(find.text('Waive penalties'), findsOneWidget);
    });

    testWidgets('two missed bills paid together: the stretch, once',
        (tester) async {
      final oct5 = DateTime(2026, 10, 5, 12);
      final rows = rowsOn(oct5);
      await pumpSection(
        tester,
        openTermLoan(createdAt: DateTime(2026, 7, 2)),
        rows.sublist(0, 2),
        loanRows: rows,
        collectedAt: DateTime(2026, 10, 5),
      );

      expect(find.text('2 installments'), findsOneWidget);
      expect(find.textContaining('Late fee'), findsOneWidget);
      expect(find.textContaining('Daily surcharge'), findsOneWidget);
      expect(find.textContaining('× 35'), findsOneWidget);
      expect(find.textContaining('3,500.00'), findsOneWidget);
      expect(find.textContaining('× 5'), findsNothing);
    });

    testWidgets('allowed late: 8 days shown, nothing to charge or waive',
        (tester) async {
      await pumpSection(
        tester,
        openTermLoan(createdAt: DateTime(2026, 7, 2), allowLate: true),
        [rowsOn(sep8).first],
      );

      expect(
        find.textContaining('8 days late · late payments allowed'),
        findsOneWidget,
      );
      expect(find.textContaining('Late fee'), findsNothing);
      expect(find.text('Waive penalties'), findsNothing);
    });
  });

  group("borrower's Next payment and Pay in full", () {
    final sep8 = DateTime(2026, 9, 8, 12);

    List<LoanSchedule> clientSchedules(
      Loan loan, {
      DateTime? now,
      List<LoanSchedule>? stored,
    }) =>
        LoanCalculationService.calculateOpenTerm(
          amount: 10000,
          date: loan.createdAt,
          interestRate: 5,
          term: '1m',
          companyId: 'co-1',
          paidSchedules: stored ?? [paidCycle(DateTime(2026, 8))],
          loan: loan,
          now: now ?? sep8,
        ).schedules;

    test('one missed bill: Next payment 1,400, Pay in full 1,900', () {
      final loan = openTermLoan(createdAt: DateTime(2026, 7, 2));
      final due = borrowerAmountsDue(
        schedules: clientSchedules(loan),
        loan: loan,
        asOf: sep8,
      );

      expect(due.unpaid, hasLength(2), reason: 'placeholders are not due');
      expect(due.nextDue!.isPlaceholder, isFalse);
      expect(DateUtils.dateOnly(due.nextDue!.dueAt), DateTime(2026, 8, 31));
      expect(due.payNow, [due.nextDue]);
      expect(due.nextDuePenalty, closeTo(900, 0.01));
      expect(due.nextDueAmount, closeTo(1400, 0.01));
      expect(due.remainingPenalty, closeTo(900, 0.01));
      expect(due.remainingTotal, closeTo(1900, 0.01));
    });

    test('two missed bills (seen Oct 5): both owed now, the penalty once', () {
      final oct5 = DateTime(2026, 10, 5, 12);
      final loan = openTermLoan(createdAt: DateTime(2026, 7, 2));
      final due = borrowerAmountsDue(
        schedules: clientSchedules(loan, now: oct5),
        loan: loan,
        asOf: oct5,
      );

      expect(
        due.payNow.map((s) => DateUtils.dateOnly(s.dueAt)),
        [DateTime(2026, 8, 31), DateTime(2026, 9, 30)],
      );
      expect(due.nextDuePenalty, closeTo(3600, 0.01));
      expect(due.nextDueAmount, closeTo(4600, 0.01));
      expect(due.remainingPenalty, closeTo(3600, 0.01));
      expect(due.remainingTotal, closeTo(5100, 0.01));
    });

    test('allowed late: 500 due, no penalty', () {
      final loan =
          openTermLoan(createdAt: DateTime(2026, 7, 2), allowLate: true);
      final due = borrowerAmountsDue(
        schedules: clientSchedules(loan),
        loan: loan,
        asOf: sep8,
      );

      expect(due.nextDueAmount, closeTo(500, 0.01));
      expect(due.remainingTotal, closeTo(1000, 0.01));
      expect(due.remainingPenalty, 0);
    });

    test('a top-up row is not an installment: only the bills are due', () {
      // Top-up 2,000 on Aug 20: the Aug 31 bill = 10,000 x 5% x 19/30 +
      // 12,000 x 5% x 11/30 = 316.67 + 220 = 536.67 (R5); Sep 30 = 600;
      // penalty on the bill's 12,000 balance: 100 + 120 x 8 = 1,060.
      final loan = openTermLoan(createdAt: DateTime(2026, 7, 2))
        ..additionalLoanAmounts = [
          AdditionalLoanAmount()
            ..id = 'top-1'
            ..amount = 2000
            ..additionalCharges = 0
            ..advanceCharges = 0
            ..createdAt = DateTime(2026, 8, 20)
            ..status = LoanStatus.approved,
        ];
      final schedules = clientSchedules(loan);
      expect(schedules.where((s) => s.isAdditionalLoanAmount), hasLength(1));

      final due = borrowerAmountsDue(
        schedules: schedules,
        loan: loan,
        asOf: sep8,
      );

      expect(due.unpaid, hasLength(2));
      expect(due.unpaid.any((s) => s.isPlaceholder), isFalse);
      expect(due.nextDueAmount, closeTo(536.67 + 1060, 0.01));
      expect(due.remainingTotal, closeTo(536.67 + 600 + 1060, 0.01));
    });

    test('a rejected submission: client detail and borrower count 900 once',
        () {
      // Submitted Sep 6 on the cycle due Aug 31, rejected (stored by #143's
      // app: due Sep 6, original due Aug 31, 36 days, 600). The next bill
      // is the scheduled Sep 30 (Jul 2 + 90), 24 days from Sep 6, not due.
      final loan = openTermLoan(createdAt: DateTime(2026, 7, 2));
      final rejected = rejectedSubmission(
        paidDue: DateTime(2026, 8),
        submittedAt: DateTime(2026, 9, 6, 12),
      );
      expect(rejected.interestCharge, closeTo(600, 0.01));

      final schedules = clientSchedules(
        loan,
        stored: [paidCycle(DateTime(2026, 8)), rejected],
      );
      expect(
        DateUtils.dateOnly(schedules.last.dueAt),
        DateTime(2026, 9, 30),
      );
      expect(schedules.last.interestCharge, closeTo(400, 0.01));

      final clientDetailPenalties = schedules.fold<double>(
        0,
        (sum, s) =>
            sum +
            previewPenalty(
              schedule: s,
              loan: loan,
              asOf: sep8,
              loanRows: schedules,
            ).total,
      );
      expect(clientDetailPenalties, closeTo(900, 0.01));

      final due = borrowerAmountsDue(
        schedules: schedules,
        loan: loan,
        asOf: sep8,
      );
      expect(due.nextDue!.id, 'sched-2');
      expect(due.nextDuePenalty, closeTo(900, 0.01));
      expect(due.remainingPenalty, closeTo(900, 0.01));
    });
  });

  group('Payment Center (bloc): overdue open-term bills', () {
    late _Loans loans;
    late _Schedules schedules;
    late _Payments payments;
    late _Users users;
    var loanCreatedDaysAgo = 68;
    var loanTopUps = <AdditionalLoanAmount>[];

    setUpAll(() {
      registerFallbackValue(Loan());
      registerFallbackValue(LoanSchedule());
      registerFallbackValue(Payment());
    });

    void stubStored(List<LoanSchedule> Function() rows) {
      when(
        () => schedules.allByLoanId(
          loanId: any(named: 'loanId'),
          onlyPaid: any(named: 'onlyPaid'),
        ),
      ).thenAnswer((_) async => rows());
    }

    setUp(() {
      loans = _Loans();
      schedules = _Schedules();
      payments = _Payments();
      users = _Users();
      loanCreatedDaysAgo = 68;
      loanTopUps = [];
      when(
        () => loans.load(
          statements: any(named: 'statements'),
          limit: any(named: 'limit'),
          page: any(named: 'page'),
          reset: any(named: 'reset'),
        ),
      ).thenAnswer((invocation) async {
        final statements =
            invocation.namedArguments[#statements] as List<QueryStatement>;
        return statements.first.field == 'user_id'
            ? [
                openTermLoan(createdAt: daysFromToday(-loanCreatedDaysAgo))
                  ..additionalLoanAmounts = List.of(loanTopUps),
              ]
            : <Loan>[];
      });
      stubStored(() => [paidCycle(daysFromToday(-38))]);
    });

    PaymentCenterBloc newBloc() {
      final auth = _Auth();
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

    Iterable<LoanSchedule> overdueOf(List<LoanSchedule> rows) =>
        rows.where((r) => r.status == LoanStatus.not_paid_overdue);

    /// What the dialog shows and the bulk handler stores for the overdue
    /// rows paid together now.
    List<double> penaltiesOf(
      Iterable<LoanSchedule> rows,
      List<LoanSchedule> stored,
    ) =>
        resolveLatenessTogether(
          schedules: rows.toList(),
          loan: openTermLoan(createdAt: daysFromToday(-loanCreatedDaysAgo)),
          collectedAt: DateTime.now(),
          loanRows: stored,
        ).map((r) => r.penalties.total).toList();

    test('one missed bill: listed overdue on its own date, 500', () async {
      final rows = await actionable();

      expect(rows, hasLength(2));
      final missed = rows.first;
      expect(missed.isOpenTerm, isTrue);
      expect(missed.status, LoanStatus.not_paid_overdue);
      expect(DateUtils.dateOnly(missed.dueAt), daysFromToday(-8));
      expect(missed.originalDueAt, isNull);
      expect(missed.interestCharge, closeTo(500, 0.01));
      expect(rows.last.status, LoanStatus.not_paid);
      expect(DateUtils.dateOnly(rows.last.dueAt), daysFromToday(22));

      final status = PaymentConfirmationService.applyLateness(
        schedule: missed,
        loan: openTermLoan(createdAt: daysFromToday(-68)),
        collectedAt: DateTime.now(),
        actorId: 'teller-1',
      );
      expect(status, LoanStatus.paid_late);
      expect(missed.daysLate, 8);
      expect(missed.penalty, closeTo(900, 0.01));
    });

    testWidgets('two missed bills: one overdue tile, both dates, 1,000',
        (tester) async {
      loanCreatedDaysAgo = 98;
      stubStored(() => [paidCycle(daysFromToday(-68))]);
      final rows = await tester.runAsync(actionable);
      final overdue = overdueOf(rows!).toList();
      expect(overdue, hasLength(2));
      expect(
        penaltiesOf(overdue, [paidCycle(daysFromToday(-68))]),
        [closeTo(3900, 0.01), 0],
      );

      await tester.pumpApp(
        Scaffold(
          body: OverdueSummaryTile(
            overdueSchedules: overdue,
            onPay: () {},
            readOnly: true,
          ),
        ),
      );

      expect(find.text('Overdue - 2 payments'), findsOneWidget);
      expect(
        find.text(
          '${daysFromToday(-38).toDefaultDateFormat()}'
          ' — ${daysFromToday(-8).toDefaultDateFormat()}',
        ),
        findsOneWidget,
      );
      expect(find.text(1000.toCurrency()), findsOneWidget);
    });

    group('bulk overdue payment (the real handler)', () {
      late List<LoanSchedule> written;

      setUp(() {
        loanCreatedDaysAgo = 98;
        stubStored(() => [paidCycle(daysFromToday(-68))]);
        written = [];
        when(() => users.get(id: any(named: 'id'))).thenAnswer(
          (_) async => User()
            ..id = 'u1'
            ..firstName = 'Bea'
            ..lastName = 'Borrower'
            ..emailAddress = 'bea@example.com',
        );
        when(() => payments.add(data: any(named: 'data'))).thenAnswer(
          (invocation) async =>
              (invocation.namedArguments[#data] as Payment)..id = 'pay-1',
        );
        when(() => payments.update(data: any(named: 'data'))).thenAnswer(
          (invocation) async => invocation.namedArguments[#data] as Payment,
        );
        when(() => schedules.add(data: any(named: 'data'))).thenAnswer(
          (invocation) async {
            final row = invocation.namedArguments[#data] as LoanSchedule;
            written.add(row);
            return row;
          },
        );
        when(
          () => loans.update(
            data: any(named: 'data'),
            updateView: any(named: 'updateView'),
          ),
        ).thenAnswer(
          (invocation) async => invocation.namedArguments[#data] as Loan,
        );
        when(() => loans.get(id: any(named: 'id'))).thenAnswer(
          (_) async => openTermLoan(createdAt: daysFromToday(-98)),
        );
      });

      Future<void> payOverdue(double totalInterest) async {
        final overdue = overdueOf(await actionable()).toList();
        final bloc = newBloc()
          ..add(
            MakeOverduePaymentEvent(
              loan: openTermLoan(createdAt: daysFromToday(-98)),
              schedules: overdue,
              totalPrincipalPayment: 0,
              totalInterestPayment: totalInterest,
              otpVerified: true,
            ),
          );
        // The handler writes every row, then stops at the cash-pool step
        // (its repository cannot be mocked).
        await bloc.stream.firstWhere(
          (s) =>
              s.status == PaymentCenterStatus.error ||
              s.status == PaymentCenterStatus.paymentSuccess,
        );
      }

      test('1,000 pays both bills; the penalty is stored once', () async {
        await payOverdue(1000);

        expect(written, hasLength(2));
        expect(
          written.map((r) => r.status),
          everyElement(LoanStatus.paid_late),
        );
        expect(written.map((r) => r.daysLate), [38, 8]);
        expect(written.map((r) => r.penalty), [closeTo(3900, 0.01), 0]);
        expect(written.map((r) => r.interestPayment), [500, 500]);
        expect(
          written.map((r) => DateUtils.dateOnly(r.dueAt)),
          [daysFromToday(-38), daysFromToday(-8)],
        );
      });

      test('700 pays 500 + 200: the 300 short carries to the next bill',
          () async {
        await payOverdue(700);

        expect(written.map((r) => r.interestPayment), [500, 200]);
        final next = LoanCalculationService.calculateOpenTermSchedules(
          amount: 10000,
          date: daysFromToday(-98),
          interestRate: 5,
          term: '1m',
          companyId: 'co-1',
          paidSchedules: [paidCycle(daysFromToday(-68)), ...written],
        ).schedules.single;
        expect(DateUtils.dateOnly(next.dueAt), daysFromToday(22));
        expect(next.amortization, closeTo(800, 0.01));
      });

      test('400 pays the first bill only; the second stays unpaid', () async {
        await payOverdue(400);

        expect(written, hasLength(1));
        expect(written.single.interestPayment, 400);
        expect(written.single.penalty, closeTo(3900, 0.01));
      });
    });

    group('after a rejected submission', () {
      /// The paid cycle and a submission on the next cycle that was rejected,
      /// as Firestore returns them.
      List<LoanSchedule> storedRows({
        required int paidDaysAgo,
        required int submittedDaysAgo,
        bool storedBefore114 = false,
      }) =>
          [
            paidCycle(daysFromToday(-paidDaysAgo)),
            rejectedSubmission(
              paidDue: daysFromToday(-paidDaysAgo),
              submittedAt: daysFromToday(-submittedDaysAgo)
                  .add(const Duration(hours: 12)),
              storedBefore114: storedBefore114,
            ),
          ];

      double penaltyOf(Iterable<LoanSchedule> rows) => rows.fold<double>(
            0,
            (sum, r) =>
                sum +
                resolveLateness(
                  schedule: r,
                  loan: openTermLoan(createdAt: daysFromToday(-68)),
                  collectedAt: DateTime.now(),
                ).penalties.total,
          );

      test('the stored row is the overdue cycle: 900, interest once', () async {
        stubStored(() => storedRows(paidDaysAgo: 38, submittedDaysAgo: 2));
        final rows = await actionable();

        expect(overdueOf(rows).map((r) => r.id), ['sched-2']);
        expect(rows.first.interestCharge, closeTo(600, 0.01));
        expect(penaltyOf(rows), closeTo(900, 0.01));
        // The next bill is the scheduled +22, upcoming, as on client detail.
        expect(rows, hasLength(2));
        expect(rows.last.status, LoanStatus.not_paid);
        expect(rows.last.lateFrom, daysFromToday(22));
        expect(rows.last.interestCharge, closeTo(400, 0.01));
      });

      test('a row stored before #114 counts from its own date (300)', () async {
        stubStored(
          () => storedRows(
            paidDaysAgo: 38,
            submittedDaysAgo: 2,
            storedBefore114: true,
          ),
        );
        final rows = await actionable();

        expect(overdueOf(rows).map((r) => r.id), ['sched-2']);
        expect(rows.first.originalDueAt, isNull);
        expect(penaltyOf(rows), closeTo(300, 0.01));
      });

      test(
          'a top-up before the rejected submission: the stored row is shown '
          'and confirmed as stored (15,000, 500, 7,600)', () async {
        final topUp = AdditionalLoanAmount()
          ..id = 'top-1'
          ..amount = 5000
          ..additionalCharges = 0
          ..advanceCharges = 0
          ..createdAt = daysFromToday(-50)
          ..status = LoanStatus.approved;
        final storedJson = rejectedSubmission(
          paidDue: daysFromToday(-80),
          submittedAt: daysFromToday(-45).add(const Duration(hours: 12)),
          balance: 15000,
          interestCharge: 500,
        ).toJson();

        stubStored(
          () => [
            paidCycle(daysFromToday(-80)),
            LoanScheduleEntity.fromJson(storedJson).toLoanSchedule(),
          ],
        );
        loanCreatedDaysAgo = 110;
        loanTopUps = [topUp];

        final rows = await actionable();
        final stored = rows.firstWhere((r) => r.id == 'sched-2');
        expect(stored.outstandingBalance, closeTo(15000, 0.01));
        expect(stored.interestCharge, closeTo(500, 0.01));
        expect(penaltyOf([stored]), closeTo(7600, 0.01));
        final next = rows.firstWhere((r) => r.id == NO_ID);
        expect(DateUtils.dateOnly(next.dueAt), daysFromToday(-20));
        expect(
          next.interestCharge,
          closeTo(625, 0.01),
          reason: 'the top-up is in the stored balance, not added again',
        );

        // What the bulk handler does with the row before writing it.
        final status = PaymentConfirmationService.applyLateness(
          schedule: stored,
          loan: openTermLoan(createdAt: daysFromToday(-110)),
          collectedAt: DateTime.now(),
          actorId: 'teller-1',
        );
        expect(status, LoanStatus.paid_late);
        expect(stored.penalty, closeTo(7600, 0.01));
        expect(stored.outstandingBalance, closeTo(15000, 0.01));
        expect(stored.interestCharge, closeTo(500, 0.01));
      });

      test(
          'a rejection more than a term old: the Payment Center, client '
          'detail and the borrower show the same rows, 5,100 once', () async {
        stubStored(() => storedRows(paidDaysAgo: 80, submittedDaysAgo: 45));
        loanCreatedDaysAgo = 110;

        final paymentCenter = await actionable();
        final overdue = overdueOf(paymentCenter).toList();
        expect(overdue, hasLength(2));
        expect(overdue.first.id, 'sched-2');
        expect(overdue.first.interestCharge, closeTo(583.33, 0.01));
        expect(overdue.last.lateFrom, daysFromToday(-20));
        expect(overdue.last.interestCharge, closeTo(416.67, 0.01));
        expect(paymentCenter.last.lateFrom, daysFromToday(10));
        final stored = storedRows(paidDaysAgo: 80, submittedDaysAgo: 45);
        expect(penaltiesOf(overdue, stored), [closeTo(5100, 0.01), 0]);

        // What LoansBloc computes for client detail and the borrower: every
        // stored row goes to the engine (loans_bloc.dart, _calculateLoanOpen).
        final loan = openTermLoan(createdAt: daysFromToday(-110));
        final clientSchedules = clientRowsNow(loan, stored);
        final due = borrowerAmountsDue(schedules: clientSchedules, loan: loan);

        expect(
          due.unpaid.map((r) => r.lateFrom),
          paymentCenter.map((r) => r.lateFrom),
        );
        expect(due.remainingPenalty, closeTo(5100, 0.01));
        expect(due.remainingTotal, closeTo(6516.67, 0.01));
        expect(
          clientSchedules.fold<double>(
            0,
            (sum, s) =>
                sum +
                previewPenalty(
                  schedule: s,
                  loan: loan,
                  loanRows: clientSchedules,
                ).total,
          ),
          closeTo(5100, 0.01),
        );
      });
    });

    test('fixed-term rows merge by the day in the business zone (UTC+8)', () {
      // Every test runs under TZ=UTC, so the zone is passed in. A row stored
      // for Sep 15 in Manila comes back from Firestore as Sep 14 16:00Z; the
      // row regenerated on a Manila device reads Sep 15. One cycle.
      LoanSchedule fixedRow(DateTime dueAt, {String id = NO_ID}) =>
          LoanSchedule()
            ..id = id
            ..dueAt = dueAt
            ..status = LoanStatus.not_paid
            ..isOpenTerm = false;
      const manila = Duration(hours: 8);

      final merged = PaymentCenterBloc.mergeUnpaid(
        [fixedRow(DateTime.utc(2026, 9, 14, 16), id: 'sched-3')],
        [fixedRow(DateTime(2026, 9, 15)), fixedRow(DateTime(2026, 10, 15))],
        utcOffset: manila,
      );
      expect(merged.map((s) => s.id), ['sched-3', NO_ID]);
      expect(merged.last.dueAt, DateTime(2026, 10, 15));

      // 15:59Z is still Sep 14 in Manila: a different cycle.
      expect(
        PaymentCenterBloc.mergeUnpaid(
          [fixedRow(DateTime.utc(2026, 9, 14, 15, 59), id: 'sched-3')],
          [fixedRow(DateTime(2026, 9, 15))],
          utcOffset: manila,
        ),
        hasLength(2),
      );
    });
  });
}
