import 'dart:typed_data';

import 'package:company_repository/company_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
// Stored rows are read back through this entity, which the package does
// not export.
// ignore: implementation_imports
import 'package:loan_schedule_repository/src/model/loan_schedule_entity.dart';
import 'package:loooans/features/loans/bloc/additional_loan_bloc.dart';
import 'package:loooans/features/loans/screens/loan_details.dart';
import 'package:loooans/features/loans/widget/top_up_overdue_dialogs.dart';
import 'package:loooans/features/products/requirement_temp_container.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans/services/top_up_overdue_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:payment_repository/payment_repository.dart';
import 'package:storage_repository/storage_repository.dart';
import 'package:user_repository/user_repository.dart';

import '../helpers/helpers.dart';

// The owner's soft block for a top-up on an overdue open-term loan
// (2026-11-19) through the real AdditionalLoanBloc and the real dialogs.
//
// Loan: 40,000 open term at 5%, term '15d', created 20 days ago (D-20).
// Bills: D-5 (15 days, 1,000, missed) and D+10 (the current bill). Penalties
// "Late fee" 100 once + "Daily 0.1%" of the balance in force each day.
// Today: the D-5 bill is 5 days late -> 100 + 5 x 40 = 300. Pay now =
// 1,300. Top-up 10,000, no charges: proceeds 10,000.
//
// Deduct, approved today: one payment, one row (D-5, paid_late, collected
// today, 5 days late, penalty 300, interest 1,000, principal 0, balance
// 40,000); the top-up approved after the row was written, deduction 1,300,
// 8,700 released; no cash-pool entry (the bloc has no cash-pool
// dependency). Next bill D+10: D-5..D on 40,000 (5 days, 333.33) + D..D+10
// on 50,000 (10 days, 833.33) = 1,166.67; nothing overdue.
// Add to the next bill: nothing written but the approval. Today the
// borrower still owes 1,300 (the top-up is not in the balance before its
// day). On D+10: D-5 1,000 + D+10 1,166.67 + penalty over 15 days: 100
// once + 5 x 40 (D-5..D-1 on 40,000) + 10 x 50 (D..D+9 on 50,000) = 800 ->
// 2,966.67.
// A day later: a top-up added yesterday and approved today deducts today's
// 1,300 (yesterday it showed 1,260 = 1,000 + 100 + 4 x 40).

const lateFee100 = Penalty(id: 'late-fee', name: 'Late fee', amount: 100);
const daily01pct = Penalty(
  id: 'daily-01',
  name: 'Daily 0.1%',
  amount: 0.1,
  isPercentage: true,
  frequency: PenaltyFrequency.daily,
);

DateTime get today => DateUtils.dateOnly(DateTime.now());

DateTime daysFromToday(int days) => DateUtils.addDaysToDate(today, days);

Loan loan40k({List<AdditionalLoanAmount> topUps = const []}) => Loan.create(
      userId: 'u1',
      companyId: 'co-1',
      productId: 'pr-1',
      amount: 40000,
      additionalCharges: 0,
      deductions: 0,
      period: 0,
      requirements: const [],
      isForceCollect: false,
      status: LoanStatus.approved,
      dueAt: null,
      reason: 'open term',
      interestRate: 5,
      term: '15d',
      amortization: 1000,
      penalties: const [lateFee100, daily01pct],
    )
      ..id = 'loan-1'
      ..createdAt = daysFromToday(-20)
      ..additionalLoanAmounts = List.of(topUps);

AdditionalLoanAmount pendingTopUp({
  OverdueChoice? choice = OverdueChoice.deduct,
  double amount = 10000,
  int createdDaysAgo = 0,
}) =>
    AdditionalLoanAmount.create(
      loanId: 'loan-1',
      amount: amount,
      additionalCharges: 0,
      advanceCharges: 0,
      deductions: 0,
      selfiePhotoUrl: ImageUrl(name: 'selfie'),
      signatureUrl: ImageUrl(name: 'signature'),
      overdueChoice: choice,
    )
      ..id = 'topup-1'
      ..createdAt = DateTime.now().subtract(Duration(days: createdDaysAgo));

/// What client detail lists for [loan] with [stored] rows, on [now].
List<LoanSchedule> clientRows(
  Loan loan, {
  List<LoanSchedule> stored = const [],
  DateTime? now,
}) =>
    LoanCalculationService.calculateOpenTerm(
      amount: 40000,
      date: loan.createdAt,
      interestRate: 5,
      term: '15d',
      companyId: 'co-1',
      paidSchedules: stored,
      loan: loan,
      now: now ?? DateTime.now(),
    ).schedules;

/// [row] as Firestore hands it back.
LoanSchedule roundTrip(LoanSchedule row) =>
    LoanScheduleEntity.fromJson(row.toJson()).toLoanSchedule();

class _Loans extends Mock implements LoanRepository {}

class _Schedules extends Mock implements LoanScheduleRepository {}

class _Payments extends Mock implements PaymentRepository {}

class _Storage extends Mock implements StorageRepository {}

class _Auth extends Mock implements AuthenticationService {}

void main() {
  group('AdditionalLoanBloc (the real handlers)', () {
    late _Loans loans;
    late _Schedules schedules;
    late _Payments payments;
    late _Storage storage;
    late Loan stored;
    late List<LoanSchedule> storedRows;
    late List<Payment> paymentDocs;
    late List<LoanSchedule> rowsAdded;
    late List<({LoanStatus loanStatus, AdditionalLoanAmount topUp, bool view})>
        loanUpdates;
    var managementType = CompanyManagementType.selfManaged;

    setUpAll(() {
      registerFallbackValue(Loan());
      registerFallbackValue(LoanSchedule());
      registerFallbackValue(Payment());
      registerFallbackValue(Uint8List(0));
    });

    setUp(() {
      loans = _Loans();
      schedules = _Schedules();
      payments = _Payments();
      storage = _Storage();
      stored = loan40k(topUps: [pendingTopUp()]);
      storedRows = [];
      paymentDocs = [];
      rowsAdded = [];
      loanUpdates = [];
      managementType = CompanyManagementType.selfManaged;

      when(() => loans.get(id: any(named: 'id')))
          .thenAnswer((_) async => stored);
      when(
        () => loans.update(
          data: any(named: 'data'),
          updateView: any(named: 'updateView'),
        ),
      ).thenAnswer((invocation) async {
        final loan = invocation.namedArguments[#data] as Loan;
        loanUpdates.add(
          (
            loanStatus: loan.status,
            // A copy: the bloc keeps changing the same object.
            topUp: loan.additionalLoanAmounts.last.toAdditionalLoanAmount(),
            view: invocation.namedArguments[#updateView] as bool? ?? false,
          ),
        );
        return loan;
      });
      when(
        () => schedules.allByLoanId(
          loanId: any(named: 'loanId'),
          onlyPaid: any(named: 'onlyPaid'),
        ),
      ).thenAnswer((_) async => [for (final r in storedRows) roundTrip(r)]);
      when(() => schedules.add(data: any(named: 'data'))).thenAnswer(
        (invocation) async {
          final row = (invocation.namedArguments[#data] as LoanSchedule)
            ..id = 'stored-${rowsAdded.length + 1}';
          rowsAdded.add(row);
          return row;
        },
      );
      when(() => payments.add(data: any(named: 'data'))).thenAnswer(
        (invocation) async {
          final payment = (invocation.namedArguments[#data] as Payment)
            ..id = 'pay-${paymentDocs.length + 1}';
          paymentDocs.add(payment);
          return payment;
        },
      );
      when(() => payments.update(data: any(named: 'data'))).thenAnswer(
        (invocation) async => invocation.namedArguments[#data] as Payment,
      );
      when(
        () => storage.upload(
          data: any(named: 'data'),
          folder: any(named: 'folder'),
          fileName: any(named: 'fileName'),
        ),
      ).thenAnswer((invocation) async {
        return ImageUrl(name: invocation.namedArguments[#fileName] as String);
      });
    });

    AdditionalLoanBloc newBloc() {
      final auth = _Auth();
      when(() => auth.company).thenAnswer(
        (_) => Company()
          ..id = 'co-1'
          ..managementType = managementType,
      );
      when(() => auth.user).thenReturn(
        User()
          ..id = 'officer-1'
          ..firstName = 'Olive'
          ..lastName = 'Officer'
          ..emailAddress = 'officer@example.com',
      );
      final bloc = AdditionalLoanBloc.withDependencies(
        authService: auth,
        loanRepository: loans,
        storageRepository: storage,
        loanScheduleRepository: schedules,
        paymentRepository: payments,
      );
      addTearDown(bloc.close);
      return bloc;
    }

    Future<AdditionalLoanState> settled(AdditionalLoanBloc bloc) =>
        bloc.stream.firstWhere(
          (s) =>
              s.status == AdditionalLoanStatus.success ||
              s.status == AdditionalLoanStatus.error,
        );

    Future<AdditionalLoanState> approve({
      double? expected,
      LoanStatus status = LoanStatus.approved,
    }) {
      final bloc = newBloc()
        ..updateAdditionalLoanAmount(
          loanId: 'loan-1',
          additionalLoanAmountId: 'topup-1',
          status: status,
          expectedDeduction: expected,
        );
      return settled(bloc);
    }

    void expectNothingPaid() {
      expect(paymentDocs, isEmpty);
      expect(rowsAdded, isEmpty);
      verifyNever(() => schedules.update(data: any(named: 'data')));
    }

    test('adding with "deduct" stores the choice and nothing else', () async {
      stored = loan40k();
      final bloc = newBloc()
        ..addLoanAmount(
          'loan-1',
          '10000',
          selfiePhoto: SimpleFileData('selfie.png', Uint8List(1)),
          signatureBytes: Uint8List(1),
          overdueChoice: OverdueChoice.deduct,
        );

      expect((await settled(bloc)).status, AdditionalLoanStatus.success);
      expect(loanUpdates, hasLength(1));
      final topUp = loanUpdates.single.topUp;
      expect(topUp.amount, 10000);
      expect(topUp.status, LoanStatus.pending);
      expect(topUp.overdueChoice, OverdueChoice.deduct);
      expect(topUp.approvedAt, isNull);
      expect(topUp.overdueDeduction, 0);
      expect(topUp.deductedPaymentIds, isEmpty);
      expect(loanUpdates.single.loanStatus, LoanStatus.approved);
      expectNothingPaid();
    });

    test('approving "deduct": the bill paid from the top-up, 8,700 released',
        () async {
      final before = DateTime.now();
      final state = await approve(expected: 1300);
      final after = DateTime.now();

      expect(state.status, AdditionalLoanStatus.success, reason: state.message);
      expect(state.message, contains(8700.toCurrency()));

      // One confirmed payment per bill, naming the top-up.
      expect(paymentDocs, hasLength(1));
      final payment = paymentDocs.single;
      expect(payment.userId, 'u1');
      expect(payment.loanId, 'loan-1');
      expect(payment.loanScheduleId, 'stored-1');
      expect(payment.status, PaymentStatus.confirmed);
      expect(payment.confirmedBy, 'officer-1');
      expect(payment.transactionPhotoUrl, isNull);
      expect(payment.comment, contains('Paid from additional loan topup-1'));

      // The row: late, collected today, with its penalty.
      expect(rowsAdded, hasLength(1));
      final row = rowsAdded.single;
      expect(DateUtils.dateOnly(row.dueAt), daysFromToday(-5));
      expect(row.status, LoanStatus.paid_late);
      expect(row.collectedAt!.isBefore(before), isFalse);
      expect(row.collectedAt!.isAfter(after), isFalse);
      expect(row.daysLate, 5);
      expect(row.penalty, closeTo(300, 0.001));
      expect(row.penalties, [lateFee100, daily01pct]);
      expect(row.interestPayment, closeTo(1000, 0.001));
      expect(row.principalPayment, 0);
      expect(row.outstandingBalance, 40000);
      expect(row.paymentId, 'pay-1');
      expect(row.loanId, 'loan-1');

      // The deduction is recorded before the bills, then the approval.
      expect(loanUpdates, hasLength(2));
      expect(loanUpdates.first.topUp.status, LoanStatus.pending);
      expect(loanUpdates.first.topUp.overdueDeduction, 1300);
      final topUp = loanUpdates.last.topUp;
      expect(topUp.status, LoanStatus.approved);
      expect(topUp.overdueDeduction, 1300);
      expect(topUp.deductedPaymentIds, ['pay-1']);
      expect(
        TopUpOverdueService.proceeds(topUp) - topUp.overdueDeduction,
        8700,
      );
      // Approved after the row was computed: the row does not hold it.
      expect(topUp.approvedAt!.isBefore(row.createdAt), isFalse);
      expect(loanUpdates.last.loanStatus, LoanStatus.paid_late);
      expect(loanUpdates.last.view, isTrue);

      // The next bill splits at the top-up's day; nothing is overdue.
      final approvedLoan = loan40k(topUps: [topUp]);
      final rows = clientRows(approvedLoan, stored: [roundTrip(row)]);
      final next = rows.lastWhere((r) => r.id == NO_ID && !r.isPlaceholder);
      expect(DateUtils.dateOnly(next.dueAt), daysFromToday(10));
      expect(next.outstandingBalance, 50000);
      expect(next.amortization, closeTo(333.33 + 833.33, 0.01));
      expect(
        TopUpOverdueService.overdue(loan: approvedLoan, schedules: rows),
        isNull,
      );
    });

    test(
        'approving "add to the next bill" writes only the approval; '
        'the next bill holds the overdue bill and the old-balance days',
        () async {
      stored = loan40k(topUps: [pendingTopUp(choice: OverdueChoice.nextBill)]);

      final state = await approve(expected: 0);

      expect(state.status, AdditionalLoanStatus.success, reason: state.message);
      expectNothingPaid();
      expect(loanUpdates, hasLength(1));
      final topUp = loanUpdates.single.topUp;
      expect(topUp.status, LoanStatus.approved);
      expect(topUp.approvedAt, isNotNull);
      expect(topUp.overdueDeduction, 0);
      expect(loanUpdates.single.loanStatus, LoanStatus.approved);
      expect(loanUpdates.single.view, isFalse);

      final approvedLoan = loan40k(topUps: [topUp]);
      // Today: the missed bill on the old balance, its penalty running.
      expect(
        TopUpOverdueService.overdue(
          loan: approvedLoan,
          schedules: clientRows(approvedLoan),
        )!
            .amount,
        1300,
      );

      // On the next bill's day: both bills and the stretch's penalty.
      final d10 = daysFromToday(10).add(const Duration(hours: 12));
      final due = borrowerAmountsDue(
        schedules: clientRows(approvedLoan, now: d10),
        loan: approvedLoan,
        asOf: d10,
      );
      expect(
        due.payNow.map((s) => DateUtils.dateOnly(s.dueAt)),
        [daysFromToday(-5), daysFromToday(10)],
      );
      expect(due.payNow.first.amortization, closeTo(1000, 0.001));
      expect(due.payNow.last.amortization, closeTo(1166.67, 0.01));
      expect(due.nextDuePenalty, closeTo(800, 0.001));
      expect(due.nextDueAmount, closeTo(2966.67, 0.01));
    });

    test('overdue amount more than the top-up: refused, nothing written',
        () async {
      stored = loan40k(topUps: [pendingTopUp(amount: 1000)]);

      final state = await approve(expected: 1300);

      expect(state.status, AdditionalLoanStatus.error);
      expect(state.message, contains('more than the cash'));
      expectNothingPaid();
      expect(loanUpdates, isEmpty);
    });

    test('declining a "deduct" top-up writes only the decline', () async {
      final state = await approve(status: LoanStatus.declined);

      expect(state.status, AdditionalLoanStatus.success);
      expectNothingPaid();
      expect(loanUpdates, hasLength(1));
      expect(loanUpdates.single.topUp.status, LoanStatus.declined);
      expect(loanUpdates.single.topUp.approvedAt, isNull);
      expect(loanUpdates.single.topUp.overdueDeduction, 0);
    });

    test('a second approval is refused: no deduction, approved_at kept',
        () async {
      final approvedAt = DateTime.utc(2026, 1, 2);
      stored = loan40k(
        topUps: [
          pendingTopUp()
            ..status = LoanStatus.approved
            ..approvedAt = approvedAt,
        ],
      );

      for (final status in [LoanStatus.approved, LoanStatus.declined]) {
        final state = await approve(expected: 1300, status: status);
        expect(state.status, AdditionalLoanStatus.error);
        expect(state.message, contains('already approved'));
      }
      expectNothingPaid();
      expect(loanUpdates, isEmpty);
      expect(stored.additionalLoanAmounts.single.approvedAt, approvedAt);
    });

    test('approved a day later: deducts the approval day amount', () async {
      stored = loan40k(topUps: [pendingTopUp(createdDaysAgo: 1)]);

      // What the dialog showed yesterday is refused, nothing written.
      final stale = await approve(expected: 1260);
      expect(stale.status, AdditionalLoanStatus.error);
      expect(stale.message, contains('now ${1300.toCurrency()}'));
      expectNothingPaid();
      expect(loanUpdates, isEmpty);

      final state = await approve(expected: 1300);
      expect(state.status, AdditionalLoanStatus.success, reason: state.message);
      expect(rowsAdded.single.penalty, closeTo(300, 0.001));
      expect(loanUpdates.last.topUp.overdueDeduction, 1300);
    });

    test('bills paid since the top-up was added are not deducted', () async {
      storedRows = [
        clientRows(loan40k()).firstWhere((r) => !r.isPlaceholder)
          ..id = 'paid-1'
          ..status = LoanStatus.paid_late
          ..paidAt = DateTime.now()
          ..collectedAt = DateTime.now()
          ..interestPayment = 1000,
      ];

      final stale = await approve(expected: 1300);
      expect(stale.status, AdditionalLoanStatus.error);
      expectNothingPaid();

      final state = await approve(expected: 0);
      expect(state.status, AdditionalLoanStatus.success, reason: state.message);
      expectNothingPaid();
      expect(loanUpdates.single.topUp.status, LoanStatus.approved);
      expect(loanUpdates.single.topUp.overdueDeduction, 0);
    });

    test('an approval interrupted after recording the deduction is refused',
        () async {
      stored = loan40k(topUps: [pendingTopUp()..overdueDeduction = 1300]);

      for (final status in [LoanStatus.approved, LoanStatus.declined]) {
        final state = await approve(expected: 1300, status: status);
        expect(state.status, AdditionalLoanStatus.error);
        expect(state.message, contains('stopped'));
      }
      expectNothingPaid();
      expect(loanUpdates, isEmpty);
    });

    test('an app-managed company cannot deduct', () async {
      managementType = CompanyManagementType.app;

      final state = await approve(expected: 1300);

      expect(state.status, AdditionalLoanStatus.error);
      expectNothingPaid();
      expect(loanUpdates, isEmpty);
    });
  });

  group('the dialogs', () {
    Future<T?> run<T>(
      WidgetTester tester,
      Future<T> Function(BuildContext context) open, {
      String? tap,
    }) async {
      T? result;
      var done = false;
      await tester.pumpApp(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await open(context);
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      if (tap != null) {
        await tester.tap(find.text(tap));
        await tester.pumpAndSettle();
      }
      expect(done, isTrue);
      return result;
    }

    testWidgets('no bill past due: no warning, the top-up goes ahead',
        (tester) async {
      final loan = loan40k()..createdAt = daysFromToday(-10);
      final answer = await run(
        tester,
        (context) => askTopUpOverdueChoice(
          context,
          loan: loan,
          schedules: clientRows(loan),
          proceeds: 10000,
        ),
      );

      expect(find.byType(AlertDialog), findsNothing);
      expect(answer!.proceed, isTrue);
      expect(answer.choice, isNull);
    });

    for (final (button, choice) in [
      ('Deduct from the top-up', OverdueChoice.deduct),
      ('Add to the next bill', OverdueChoice.nextBill),
      ('Cancel', null),
    ]) {
      testWidgets('overdue: the warning, then "$button"', (tester) async {
        final loan = loan40k();
        late Future<({bool proceed, OverdueChoice? choice})> pending;
        await tester.pumpApp(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => pending = askTopUpOverdueChoice(
                  context,
                  loan: loan,
                  schedules: clientRows(loan),
                  proceeds: 10000,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.text('This loan has overdue bills'), findsOneWidget);
        expect(find.textContaining(1300.toCurrency()), findsOneWidget);
        expect(find.textContaining(8700.toCurrency()), findsOneWidget);

        await tester.tap(find.text(button));
        await tester.pumpAndSettle();
        final answer = await pending;
        expect(answer.proceed, choice != null);
        expect(answer.choice, choice);
      });
    }

    testWidgets('overdue more than the top-up: "Deduct" is not offered',
        (tester) async {
      final loan = loan40k();
      await tester.pumpApp(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => askTopUpOverdueChoice(
                context,
                loan: loan,
                schedules: clientRows(loan),
                proceeds: 1000,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Deduct from the top-up is not available'),
        findsOneWidget,
      );
      final deduct = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Deduct from the top-up'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(deduct.onPressed, isNull);
    });

    testWidgets('approval of "deduct": shows today\'s 1,300 and 8,700',
        (tester) async {
      final topUp = pendingTopUp();
      final loan = loan40k(topUps: [topUp]);
      final shown = await run(
        tester,
        (context) => showTopUpApprovalDialog(
          context,
          topUp: topUp,
          loan: loan,
          schedules: clientRows(loan),
        ),
        tap: 'Approve',
      );

      expect(shown, 1300);
    });

    testWidgets('approval of "deduct": the amounts on screen', (tester) async {
      final topUp = pendingTopUp();
      final loan = loan40k(topUps: [topUp]);
      await tester.pumpApp(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTopUpApprovalDialog(
                context,
                topUp: topUp,
                loan: loan,
                schedules: clientRows(loan),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.textContaining(1300.toCurrency()), findsOneWidget);
      expect(
        find.textContaining('Cash to release: ${8700.toCurrency()}'),
        findsOneWidget,
      );
    });

    testWidgets('approval of "deduct" over the top-up: no Approve',
        (tester) async {
      final topUp = pendingTopUp(amount: 1000);
      final loan = loan40k(topUps: [topUp]);
      await tester.pumpApp(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTopUpApprovalDialog(
                context,
                topUp: topUp,
                loan: loan,
                schedules: clientRows(loan),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Decline it'), findsOneWidget);
      final approveButton = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Approve'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(approveButton.onPressed, isNull);
    });

    testWidgets('approval of "add to the next bill": nothing deducted',
        (tester) async {
      final topUp = pendingTopUp(choice: OverdueChoice.nextBill);
      final loan = loan40k(topUps: [topUp]);
      final shown = await run(
        tester,
        (context) => showTopUpApprovalDialog(
          context,
          topUp: topUp,
          loan: loan,
          schedules: clientRows(loan),
        ),
        tap: 'Approve',
      );

      expect(shown, 0);
    });
  });
}
