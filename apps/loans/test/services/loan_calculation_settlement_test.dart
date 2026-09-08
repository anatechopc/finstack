import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/services/loan_calculation_service.dart';

// Golden scenario G7 (finstack#112, campaign Gate 1) for the early-settlement
// formula extracted from LoanSettlementBloc.
//
// Derivation — family of one loan:
//   released = (10000 + 500 charges) - (200 deductions + 100 upfront) = 10200
//   paid open-term schedules: 500 interest; 400 interest + 1000 extra = 1400
//   payments = 500 + 1400 = 1900  ->  remaining = 10200 - 1900 = 8300
//
// CURRENT code ASSIGNS inside the schedule loop instead of accumulating
// (campaign defect D9), so only the last schedule counts:
//   remaining = 10200 - 1400 = 8800
// The test pins 8800 on purpose (behaviour-preserving extraction). The PR
// that fixes D9 must flip this expectation to 8300 — never silently.
void main() {
  Loan loan() => Loan()
    ..amount = 10000
    ..additionalCharges = 500
    ..deductions = 200
    ..additionalChargeUpfrontCollection = 100;

  LoanSchedule paid({
    required double interest,
    bool openTerm = true,
    double principal = 0,
    double extra = 0,
  }) =>
      LoanSchedule()
        ..isOpenTerm = openTerm
        // Real fixed-term rows mirror interestCharge into interestPayment
        // (pinned by G1); the sentinel makes sure the fixed-term branch
        // really reads interestPayment.
        ..interestCharge = openTerm ? interest : 999999
        ..interestPayment = openTerm ? 0 : interest
        ..principalPayment = principal
        ..extraPayment = extra;

  group('G7 early settlement', () {
    test('remaining = released - payments (D9: last schedule only)', () {
      final remaining = LoanCalculationService.calculateSettlementBalance(
        loans: [loan()],
        paidSchedules: [
          paid(interest: 500),
          paid(interest: 400, extra: 1000),
        ],
      );

      expect(
        remaining,
        closeTo(8800, 0.01),
        reason: 'D9 semantics: 10200 - 1400. Becomes 8300 once payments '
            'accumulate; flip deliberately with the D9 fix.',
      );
    });

    test('fixed-term rows count interestPayment + principal', () {
      final remaining = LoanCalculationService.calculateSettlementBalance(
        loans: [loan()],
        paidSchedules: [paid(interest: 300, principal: 700, openTerm: false)],
      );

      expect(remaining, closeTo(9200, 0.01));
    });
  });
}
