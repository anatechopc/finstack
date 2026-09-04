import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/products/screen/loan_schedule_widget.dart';
import 'package:loooans_helpers/data_helpers.dart';

import '../../helpers/helpers.dart';

void main() {
  final loanWithDaily100 = Loan()
    ..id = 'l1'
    ..term = '1m'
    ..penalties = const [
      Penalty(
        id: 'p1',
        name: 'Late fee',
        amount: 100,
        frequency: PenaltyFrequency.daily,
      ),
    ]
    ..allowLatePayments = false;

  group('LoanScheduleWidget table (borrower)', () {
    testWidgets(
      'shows the running penalty on an overdue row, no overflow',
      (tester) async {
        final overdueRow = LoanSchedule()
          ..id = 's1'
          ..loanId = 'l1'
          ..status = LoanStatus.not_paid
          ..dueAt = DateTime.now().subtract(const Duration(days: 3))
          ..amortization = 5000
          ..outstandingBalance = 5000
          ..isOpenTerm = false
          ..interestPayment = 500
          ..principalPayment = 4500;

        await tester.pumpApp(
          LoanScheduleWidget(
            amortization: 5000,
            schedules: [overdueRow],
            completeTerm: '1 month',
            buildTable: true,
            tableHeight: 96,
            loan: loanWithDaily100,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('penalty'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'shows "penalty waived" on a waived row, no overflow',
      (tester) async {
        final waivedRow = LoanSchedule()
          ..id = 's2'
          ..loanId = 'l1'
          ..status = LoanStatus.paid_late
          ..dueAt = DateTime.now().subtract(const Duration(days: 3))
          ..amortization = 5000
          ..outstandingBalance = 5000
          ..isOpenTerm = false
          ..interestPayment = 500
          ..principalPayment = 4500
          ..penalty = 0
          ..penaltyWaivedBy = 'teller-1';

        await tester.pumpApp(
          LoanScheduleWidget(
            amortization: 5000,
            schedules: [waivedRow],
            completeTerm: '1 month',
            buildTable: true,
            tableHeight: 96,
            loan: loanWithDaily100,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('penalty waived'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
