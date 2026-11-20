import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans/services/payment_confirmation_service.dart';
import 'package:loooans_helpers/data_helpers.dart';

// Golden scenario G7 (finstack#116, campaign D9): the early-settlement
// figure. Owner decision 2026-11-20: the balance after the last CONFIRMED
// payment row, approved top-ups included, plus interest accrued from that
// row's due date to the settlement day. Defaults for the owner to confirm:
// interest is balance x rate x days / 30 on the balance in force each day
// (a top-up from its approval day); with no confirmed row it runs from the
// loan's creation day; a row due after the settlement day accrues 0; the
// penalties the missed bills owe that day are added (the Pay dialog's
// calculator); an open-term row paid short adds its unpaid interest (R4).
// Every number below was derived by hand before the code changed.
//
// G1 loan (fixed-term): 10,000, 3 months, 5%, created Aug 1 2026.
//   P = 10,000 x 0.05 / (1 - 1.05^-3) = 500 / 0.1361624 = 3,672.0856.
//   Bill 1, Sep 1: interest 500, principal 3,172.0856, balance 6,827.9144.
// Open-term loan: 10,000 at 5% a month, '1m', created Aug 2 2026; the
//   Sep 1 bill (500) paid on time, its row holding balance 10,000.
//
//   G7a G1 settled Sep 11, 10 days after bill 1 was paid as billed:
//       6,827.9144 + 6,827.9144 x 5% x 10/30 (113.7986 -> 113.80)
//       = 6,941.71. Was 10,000 - (500 + 3,172.09) = 6,327.91.
//   G7b G1, bill 1 paid 500 + 2,900: balance 6,827.9144 + (3,172.0856 -
//       2,900) = 7,100. Settled Sep 7: 7,100 x 5% x 6/30 = 71.00 ->
//       7,171.00. Was 10,000 - 3,400 = 6,600 (#116, review of #156).
//   G7c open-term, a 2,000 + 100 top-up approved Sep 11, settled Sep 21:
//       10,000 x 5% x 10/30 = 166.6667 (Sep 1 -> 11) + 12,100 x 5% x 10/30
//       = 201.6667 (Sep 11 -> 21) = 368.33; 12,100 + 368.33 = 12,468.33.
//       Was 10,000 - 500 = 9,500 (top-up ignored, interest subtracted).
//   G7d open-term, the Oct 1 bill submitted Sep 30 and not confirmed,
//       settled Oct 5: not credited, so interest runs from Sep 1: 34 days,
//       566.67 -> 10,566.67 (credited it would be 10,066.67). Was 9,500.
//   G7e open-term with penalties "Late fee" 100 once + "Daily surcharge" 1%
//       of the balance per day; the Oct 1 bill missed, settled Oct 11:
//       interest Sep 1 -> Oct 11 = 40 days, 666.67; penalties as the Pay
//       dialog charges the bill that day: 100 + 1% x 10,000 x 10 = 1,100;
//       10,000 + 666.67 + 1,100 = 11,766.67, recorded paid late. Was 9,500.
//   G7f no confirmed row: 10,000 + 500 charges - 200 deductions (100
//       collected upfront is not in the balance) = 10,300, open-term,
//       settled Aug 22, 20 days after creation: 10,300 x 5% x 20/30 =
//       343.33 -> 10,643.33. Was 10,200 (released, nothing credited).
//   G7g G1, bill 1 (due Sep 1) paid early Aug 25, settled Aug 28: the row
//       is due after the settlement day, 0 accrued -> 6,827.91. Was 6,327.91.
//   G7h open-term, the Sep 1 bill paid 300 of 500, settled Sep 4: 10,000 x
//       5% x 3/30 = 50 + the 200 short (R4) -> 10,250. Paid 600 of 500:
//       nothing back, 10,050. Both were 9,500 (the charge, not the cash).
//   G7i a family: G1 as in G7a plus an open-term special loan of 5,000
//       created Sep 1 with no rows, settled Sep 11: 5,000 x 5% x 10/30 =
//       83.33 -> 5,083.33; total 6,941.71 + 5,083.33 = 12,025.04.
void main() {
  Loan fixedTerm() => Loan.create(
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
        dueAt: DateTime(2026, 11),
        reason: 'fixed term',
        interestRate: 5,
        term: '1m',
        amortization: 3672.09,
      )
        ..id = 'loan-1'
        ..createdAt = DateTime(2026, 8)
        ..additionalLoanAmounts = [];

  Loan openTerm({
    double amount = 10000,
    List<Penalty> penalties = const [],
    DateTime? createdAt,
    String id = 'loan-1',
  }) =>
      Loan.create(
        userId: 'u1',
        companyId: 'co-1',
        productId: 'pr-1',
        amount: amount,
        additionalCharges: 0,
        deductions: 0,
        period: 0,
        requirements: const [],
        isForceCollect: false,
        status: LoanStatus.paid_on_time,
        dueAt: null,
        reason: 'open term',
        interestRate: 5,
        term: '1m',
        amortization: 500,
        penalties: penalties,
      )
        ..id = id
        ..createdAt = createdAt ?? DateTime(2026, 8, 2)
        ..additionalLoanAmounts = [];

  /// G1's bill 1 as the app stores it: the computed row, paid.
  LoanSchedule g1Bill1({DateTime? paidAt}) {
    final row = LoanCalculationService.calculateFixedTerm(
      amount: 10000,
      monthsToPay: 3,
      date: DateTime(2026, 8),
      interestRate: 5,
      term: '1m',
      companyId: 'co-1',
    ).schedules.first;

    return row
      ..id = 'row-1'
      ..loanId = 'loan-1'
      ..createdAt = paidAt ?? row.dueAt
      ..paidAt = paidAt ?? row.dueAt
      ..status = LoanStatus.paid_on_time
      ..interestPayment = row.interestCharge;
  }

  /// The open-term Sep 1 bill, stored with [status] and [paid] interest.
  LoanSchedule sep1Bill({
    LoanStatus status = LoanStatus.paid_on_time,
    double paid = 500,
  }) =>
      LoanSchedule()
        ..id = 'row-1'
        ..loanId = 'loan-1'
        ..companyId = 'co-1'
        ..createdAt = DateTime(2026, 9)
        ..updatedAt = DateTime(2026, 9)
        ..dueAt = DateTime(2026, 9)
        ..paidAt = DateTime(2026, 9)
        ..status = status
        ..isOpenTerm = true
        ..outstandingBalance = 10000
        ..principalPayment = 0
        ..interestCharge = 500
        ..amortization = 500
        ..interestPayment = paid
        ..extraPayment = 0
        ..advanceInterestPayments = 0
        ..interestDayMultiplier = 1;

  double settle(Loan loan, List<LoanSchedule> rows, DateTime now) =>
      LoanCalculationService.calculateSettlementBalance(
        loans: [loan],
        schedules: rows,
        now: now,
      );

  group('G7 early settlement (#116)', () {
    test('G7a fixed-term, 10 days after bill 1 was paid as billed', () {
      final bill1 = g1Bill1();
      expect(bill1.outstandingBalance, closeTo(6827.9144, 0.0001));

      final row = LoanCalculationService.settlementOf(
        loan: fixedTerm(),
        rows: [bill1],
        now: DateTime(2026, 9, 11, 10),
      );

      expect(row.principalPayment, closeTo(6827.9144, 0.0001));
      expect(row.interestCharge, 113.80);
      expect(row.interestPayment, 113.80);
      expect(row.penalty, 0);
      expect(row.outstandingBalance, 0);
      expect(row.status, LoanStatus.paid_on_time);
      expect(row.isOpenTerm, isFalse);
      expect(row.loanId, 'loan-1');
      expect(row.interestDayMultiplier * 30, closeTo(10, 1e-9));
      expect(
        LoanCalculationService.settlementAmount(row),
        closeTo(6941.71, 0.005),
      );
    });

    test('G7b fixed-term, bill 1 paid 500 + 2,900: 7,100 owed', () {
      final bill1 = g1Bill1();
      PaymentConfirmationService.recordTellerPayment(
        bill1,
        interestPayment: 500,
        principalPayment: 2900,
      );
      expect(bill1.outstandingBalance, closeTo(7100, 1e-9));

      expect(
        settle(fixedTerm(), [bill1], DateTime(2026, 9, 7, 10)),
        closeTo(7171, 0.005),
      );
    });

    test('G7c open-term, a top-up approved between the bill and settling', () {
      final loan = openTerm()
        ..additionalLoanAmounts = [
          AdditionalLoanAmount()
            ..id = 'top-up-1'
            ..amount = 2000
            ..additionalCharges = 100
            ..advanceCharges = 0
            ..createdAt = DateTime(2026, 9, 10)
            ..approvedAt = DateTime(2026, 9, 11, 9)
            ..status = LoanStatus.approved,
          // A pending top-up released nothing: not owed.
          AdditionalLoanAmount()
            ..id = 'top-up-2'
            ..amount = 9000
            ..additionalCharges = 0
            ..advanceCharges = 0
            ..createdAt = DateTime(2026, 9, 15)
            ..status = LoanStatus.pending,
        ];

      final row = LoanCalculationService.settlementOf(
        loan: loan,
        rows: [sep1Bill()],
        now: DateTime(2026, 9, 21, 10),
      );

      expect(row.principalPayment, 12100);
      expect(row.interestPayment, 368.33);
      expect(row.isOpenTerm, isTrue);
      expect(
        LoanCalculationService.settlementAmount(row),
        closeTo(12468.33, 0.005),
      );
    });

    test('G7d a submitted payment is not credited', () {
      final submitted = LoanSchedule()
        ..id = 'row-2'
        ..loanId = 'loan-1'
        ..companyId = 'co-1'
        ..createdAt = DateTime(2026, 9, 30)
        ..updatedAt = DateTime(2026, 9, 30)
        ..dueAt = DateTime(2026, 10)
        ..paymentId = 'payment-2'
        ..collectedAt = DateTime(2026, 9, 30)
        ..status = LoanStatus.payment_submitted
        ..isOpenTerm = true
        ..outstandingBalance = 10000
        ..principalPayment = 0
        ..interestCharge = 500
        ..amortization = 500
        ..interestPayment = 0
        ..extraPayment = 0
        ..advanceInterestPayments = 0
        ..interestDayMultiplier = 1;

      expect(
        settle(openTerm(), [sep1Bill(), submitted], DateTime(2026, 10, 5, 10)),
        closeTo(10566.67, 0.005),
      );
    });

    test('G7e a missed bill owes the penalties the Pay dialog charges', () {
      const lateFee = Penalty(id: 'late-fee', name: 'Late fee', amount: 100);
      const daily = Penalty(
        id: 'daily',
        name: 'Daily surcharge',
        amount: 1,
        isPercentage: true,
        frequency: PenaltyFrequency.daily,
      );
      final loan = openTerm(penalties: const [lateFee, daily]);

      final row = LoanCalculationService.settlementOf(
        loan: loan,
        rows: [sep1Bill()],
        now: DateTime(2026, 10, 11, 10),
      );

      expect(row.interestPayment, 666.67);
      expect(row.penalty, 1100);
      expect(row.penalties, const [lateFee, daily]);
      expect(row.daysLate, 10);
      expect(row.status, LoanStatus.paid_late);
      expect(
        LoanCalculationService.settlementAmount(row),
        closeTo(11766.67, 0.005),
      );
      // A loan that allows late payments charges nothing.
      expect(
        settle(
          loan..allowLatePayments = true,
          [sep1Bill()],
          DateTime(2026, 10, 11, 10),
        ),
        closeTo(10666.67, 0.005),
      );
    });

    test('G7f no confirmed row: the amount released, from creation', () {
      final loan = openTerm()
        ..additionalCharges = 500
        ..deductions = 200
        ..additionalChargeUpfrontCollection = 100;

      expect(
        settle(loan, const [], DateTime(2026, 8, 22, 10)),
        closeTo(10643.33, 0.005),
      );
    });

    test('G7g a row due after the settlement day accrues nothing', () {
      final row = LoanCalculationService.settlementOf(
        loan: fixedTerm(),
        rows: [g1Bill1(paidAt: DateTime(2026, 8, 25))],
        now: DateTime(2026, 8, 28, 10),
      );

      expect(row.interestPayment, 0);
      expect(row.interestDayMultiplier, 0);
      expect(
        LoanCalculationService.settlementAmount(row),
        closeTo(6827.91, 0.005),
      );
    });

    test('G7h an open-term row paid short adds what it left unpaid (R4)', () {
      expect(
        settle(openTerm(), [sep1Bill(paid: 300)], DateTime(2026, 9, 4, 10)),
        closeTo(10250, 0.005),
      );
      expect(
        settle(openTerm(), [sep1Bill(paid: 600)], DateTime(2026, 9, 4, 10)),
        closeTo(10050, 0.005),
      );
    });

    test('G7i a family: each loan settles on its own rows', () {
      final special = openTerm(
        amount: 5000,
        createdAt: DateTime(2026, 9),
        id: 'loan-2',
      );

      expect(
        LoanCalculationService.calculateSettlementBalance(
          loans: [fixedTerm(), special],
          schedules: [g1Bill1()],
          now: DateTime(2026, 9, 11, 10),
        ),
        closeTo(12025.04, 0.005),
      );
    });
  });
}
