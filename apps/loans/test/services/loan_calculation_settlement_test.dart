import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/services/loan_calculation_service.dart';

// Golden scenario G7 (finstack#112, campaign Gate 1) for the early-settlement
// formula extracted from LoanSettlementBloc.
//
// Derivation — family of one loan:
//   released = (10000 + 500 charges) - (200 deductions + 100 upfront) = 10200
//   rows with a payment: open-term interest 500 (charge = cash recorded);
//                        fixed-term interest 400 + principal 1000 = 1400
//
// These tests pin the CURRENT formula, which is wrong in several ways that
// finstack#116 owns as one design decision (see the docstring on
// calculateSettlementBalance): the loop assigns instead of accumulating, so
// only the last element counts -> 10200 - 1400 = 8800. Accumulating would
// give 8300, but that is NOT the target either: it would subtract interest
// from principal. The right figure comes from the last row's outstanding
// balance plus accrued interest, over confirmed rows only, top-ups
// included. Flip these expectations in the change that fixes #116, never
// silently.
void main() {
  Loan loan() => Loan()
    ..amount = 10000
    ..additionalCharges = 500
    ..deductions = 200
    ..additionalChargeUpfrontCollection = 100;

  /// A row the payment blocs can actually write: open-term rows carry the
  /// recorded interest in interestPayment as well (and never an
  /// extraPayment); fixed-term rows mirror interestCharge into
  /// interestPayment, here replaced by a sentinel so the branch that reads
  /// interestPayment is really the one under test.
  LoanSchedule paid({
    required double interest,
    bool openTerm = true,
    double principal = 0,
    double extra = 0,
    double? recorded,
  }) =>
      LoanSchedule()
        ..isOpenTerm = openTerm
        ..interestCharge = openTerm ? interest : 999999
        ..interestPayment = recorded ?? interest
        ..principalPayment = principal
        ..extraPayment = extra;

  group('G7 early settlement', () {
    test('remaining = released - last row only (finstack#116)', () {
      final remaining = LoanCalculationService.calculateSettlementBalance(
        loans: [loan()],
        schedules: [
          paid(interest: 500),
          paid(interest: 400, principal: 1000, openTerm: false),
        ],
      );

      expect(
        remaining,
        closeTo(8800, 0.01),
        reason: 'assigns, not accumulates: 10200 - 1400. In production the '
            'bloc passes rows newest-first, so the LEAST recently updated row '
            'is the one that counts. Redesign under finstack#116.',
      );
    });

    test('fixed-term rows credit interestPayment + principal + extra', () {
      final remaining = LoanCalculationService.calculateSettlementBalance(
        loans: [loan()],
        schedules: [
          paid(interest: 300, principal: 600, extra: 100, openTerm: false),
        ],
      );

      expect(remaining, closeTo(9200, 0.01));
    });

    test('open-term rows credit the computed charge, not the cash recorded',
        () {
      final remaining = LoanCalculationService.calculateSettlementBalance(
        loans: [loan()],
        schedules: [paid(interest: 500, recorded: 600)],
      );

      expect(
        remaining,
        closeTo(9700, 0.01),
        reason: 'reads interestCharge (500) although 600 was collected — '
            'current behaviour, part of finstack#116',
      );
    });
  });
}
