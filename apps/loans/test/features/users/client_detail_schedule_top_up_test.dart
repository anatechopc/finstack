import 'package:company_repository/company_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/users/widget/client_detail/client_detail_schedule_item.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:user_repository/user_repository.dart';

import '../../helpers/helpers.dart';

// Integration check for finstack#117 on the schedule list a lender sees after
// a top-up. In the app the path is: AdditionalLoanBloc success ->
// LoansBloc.selectLoan -> _calculateLoanOpen ->
// LoanCalculationService.calculateOpenTerm -> ClientDetailLoanBody, which
// builds one ClientDetailScheduleItem per schedule. LoansBloc cannot be built
// in a test: its constructor reads five `final class` repositories from
// context; they cannot be mocked, their constructors open Firestore, and
// selecting a loan needs the product from one of them. So this test calls the
// real service with the arguments _calculateLoanOpen passes (plus the `now`
// seam) and renders the real row widget.
//
// Expected numbers (G9b in test/services/loan_calculation_open_term_test.dart):
// 10000 at 5% a month, paid row due Aug 1, top-up of 2000 + 100 charges on
// Aug 6 at 14:30, seen on Aug 15.
//   top-up row: balance 12100, 5 days, 10000 * 0.05 * 5/30 = 83.33
//   due row (Aug 31): balance 12100, 30 - 5 = 25 days,
//             12100 * 0.05 * 25/30 = 504.17, amount due 504.17
void main() {
  setUp(() {
    AuthenticationService.instance
      ..user = (User()
        ..id = 'teller-1'
        ..firstName = 'Juan'
        ..lastName = 'Dela Cruz'
        ..userRole = UserRole.admin)
      ..company =
          (Company()..managementType = CompanyManagementType.selfManaged);
  });

  // Process-wide singleton: do not leak the signed-in user into other tests.
  tearDown(AuthenticationService.instance.dispose);

  testWidgets(
    'after a top-up the due row shows and bills the new balance for the '
    'days left',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1600, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final loan = Loan()
        ..id = 'loan-1'
        ..companyId = 'co-1'
        ..amount = 10000
        ..interestRate = 5
        ..term = '1m'
        ..createdAt = DateTime(2026, 7, 2)
        ..additionalChargeUpfrontCollection = 0
        ..additionalLoanAmounts = [
          AdditionalLoanAmount()
            ..id = 'al-1'
            ..amount = 2000
            ..additionalCharges = 100
            ..advanceCharges = 0
            ..createdAt = DateTime(2026, 8, 6, 14, 30)
            ..status = LoanStatus.approved,
        ];
      final persisted = LoanSchedule()
        ..id = 'sched-1'
        ..loanId = loan.id
        ..companyId = loan.companyId
        ..createdAt = DateTime(2026, 7, 2)
        ..updatedAt = DateTime(2026, 7, 2)
        ..dueAt = DateTime(2026, 8)
        ..paidAt = DateTime(2026, 8)
        ..status = LoanStatus.paid_on_time
        ..isOpenTerm = true
        ..outstandingBalance = 10000
        ..principalPayment = 0
        ..interestPayment = 500
        ..interestCharge = 500
        ..amortization = 500
        ..extraPayment = 0
        ..advanceInterestPayments = 0
        ..interestDayMultiplier = 1;

      final schedules = LoanCalculationService.calculateOpenTerm(
        amount: loan.amount,
        date: loan.createdAt,
        term: loan.term,
        interestRate: loan.interestRate,
        paidSchedules: [persisted],
        companyId: loan.companyId,
        loan: loan,
        now: DateTime(2026, 8, 15, 9),
      ).schedules;
      final toPay = <LoanSchedule>[];

      await tester.pumpApp(
        Scaffold(
          body: ListView(
            children: [
              for (final (index, schedule) in schedules.indexed)
                ClientDetailScheduleItem(
                  index: index,
                  schedule: schedule,
                  loan: loan,
                  onMakePayment: toPay.add,
                ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rows = find.byType(ClientDetailScheduleItem);
      expect(rows, findsNWidgets(4));
      Finder inRow(int index, String text) => find.descendant(
            of: rows.at(index),
            matching: find.textContaining(text),
          );

      // Row 2: the top-up keeps the 5 days accrued on the old balance.
      expect(inRow(2, '12,100.00'), findsOneWidget);
      expect(inRow(2, '2,000.00'), findsOneWidget);
      expect(inRow(2, '5.0'), findsOneWidget);
      expect(inRow(2, '83.33'), findsOneWidget);

      // Row 3: the due row charges the new balance for the 25 days left.
      expect(inRow(3, '2026-Aug-31'), findsOneWidget);
      expect(inRow(3, '12,100.00'), findsOneWidget);
      expect(inRow(3, '25.0'), findsOneWidget);
      expect(inRow(3, '504.17'), findsOneWidget);
      expect(
        find.textContaining('83.33'),
        findsOneWidget,
        reason: 'before finstack#117 the due row repeated the 83.33',
      );

      // "Make payment" hands the row to the payment dialog, which prefills
      // the interest payment with schedule.amortization.toStringAsFixed(2).
      await tester.tap(
        find.descendant(of: rows.at(3), matching: find.text('Make payment')),
      );
      expect(toPay, hasLength(1));
      expect(toPay.single.amortization.toStringAsFixed(2), '504.17');
      expect(toPay.single.interestCharge, closeTo(504.17, 0.01));
      expect(toPay.single.outstandingBalance, closeTo(12100, 0.01));
    },
  );
}
