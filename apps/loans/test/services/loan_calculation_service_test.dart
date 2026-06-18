import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans_helpers/data_helpers.dart';

void main() {
  group('calculateFixedTerm contract', () {
    // calculateFixedTerm returns ONLY the computed remaining schedules; callers
    // (the teller flow + LoansBloc._calculateLoan) prepend the persisted
    // paidSchedules themselves. This test pins that contract so a future change
    // doesn't reintroduce double-counting in the teller (which does
    // `[...paidSchedules, ...result.schedules]`).
    test('does NOT include the persisted schedules in its output', () {
      final persisted = LoanSchedule()
        ..id = 'real-sched-1'
        ..loanId = 'loan-1'
        ..status = LoanStatus.payment_submitted
        ..dueAt = DateTime(2024, 12, 19)
        ..amortization = 40.92
        ..outstandingBalance = 36.87;

      final result = LoanCalculationService.calculateFixedTerm(
        amount: 100,
        monthsToPay: 3,
        date: DateTime(2024, 11, 19),
        interestRate: 11,
        term: '1m',
        companyId: 'co-1',
        paidSchedules: [persisted],
      );

      expect(
        result.schedules.any((s) => s.id == 'real-sched-1'),
        isFalse,
        reason: 'paidSchedules must not leak into the computed output',
      );
      expect(result.schedules.every((s) => s.id == NO_ID), isTrue);
    });
  });
}
