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
//   G7j G7d with G7e's penalties: the Oct 1 bill submitted Sep 30, on time,
//       owes nothing at its transfer (as the Pay dialog shows it); the next
//       bill, Oct 31, is not due -> 10,566.67 (was 10,566.67 + 100 + 1% x
//       10,000 x 4 = 500 more, the review of #157's probe P1). Submitted
//       Oct 3, 2 days late: 100 + 1% x 10,000 x 2 = 300 -> 10,866.67.
//   G7k G1 with #152's carried shortfall: bill 1 paid 500 + 2,900 leaves
//       7,100; bill 2 bills 3,672.09 + 272.09 carried = 3,944.18 (interest
//       7,100 x 5% = 355.00, principal 3,589.18), paid as billed: 3,510.82.
//       Settled Oct 11, 10 days after bill 2's due date: 3,510.82 x 5% x
//       10/30 = 58.51 -> 3,569.33. The shortfall is in the balance, so it
//       is not added again.
//   G7l G1 with a part-paid last bill (#156): bills 1 and 2 paid as billed
//       (bill 2: interest 341.3957, principal 3,330.6899, balance 3,497.2244;
//       no carry, so not rounded); bill 3 (Nov 1: interest 174.8612,
//       principal 3,497.2244) paid its interest + 3,000 leaves 497.2244; the rest of it, a second row due Nov 1,
//       paid 200 leaves 297.2244. Two confirmed rows share Nov 1: the later
//       is the lower balance. Settled Nov 11: 297.2244 x 5% x 10/30 = 4.95
//       -> 302.17 (taking the other row: 497.22 + 8.29 = 505.51).
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

    test('G7j a submitted bill owes the penalty of its transfer only', () {
      const lateFee = Penalty(id: 'late-fee', name: 'Late fee', amount: 100);
      const daily = Penalty(
        id: 'daily',
        name: 'Daily surcharge',
        amount: 1,
        isPercentage: true,
        frequency: PenaltyFrequency.daily,
      );
      LoanSchedule submittedOn(DateTime sentAt) => LoanSchedule()
        ..id = 'row-2'
        ..loanId = 'loan-1'
        ..companyId = 'co-1'
        ..createdAt = sentAt
        ..updatedAt = sentAt
        ..dueAt = DateTime(2026, 10)
        ..paymentId = 'payment-2'
        ..collectedAt = sentAt
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
      final loan = openTerm(penalties: const [lateFee, daily]);

      final onTime = LoanCalculationService.settlementOf(
        loan: loan,
        rows: [sep1Bill(), submittedOn(DateTime(2026, 9, 30, 9))],
        now: DateTime(2026, 10, 5, 10),
      );
      expect(onTime.penalty, 0);
      expect(
        LoanCalculationService.settlementAmount(onTime),
        closeTo(10566.67, 0.005),
      );

      final late = LoanCalculationService.settlementOf(
        loan: loan,
        rows: [sep1Bill(), submittedOn(DateTime(2026, 10, 3, 9))],
        now: DateTime(2026, 10, 5, 10),
      );
      expect(late.penalty, 300);
      expect(
        LoanCalculationService.settlementAmount(late),
        closeTo(10866.67, 0.005),
      );
    });

    /// G1's next computed bill after the stored [rows], as the app bills it.
    LoanSchedule nextBill(List<LoanSchedule> rows) =>
        LoanCalculationService.calculateFixedTerm(
          amount: 10000,
          monthsToPay: 3,
          date: DateTime(2026, 8),
          interestRate: 5,
          term: '1m',
          companyId: 'co-1',
          paidSchedules: List.of(rows),
        ).schedules.first;

    /// [row] stored as paid on [on] after a teller recorded [interest] and
    /// [principal] on it.
    LoanSchedule pay(
      LoanSchedule row, {
      required String id,
      required DateTime on,
      required double interest,
      required double principal,
    }) {
      PaymentConfirmationService.recordTellerPayment(
        row,
        interestPayment: interest,
        principalPayment: principal,
      );

      return row
        ..id = id
        ..loanId = 'loan-1'
        ..createdAt = on
        ..paidAt = on
        ..collectedAt = on
        ..status = LoanStatus.paid_on_time;
    }

    test('G7k a carried shortfall is in the balance, not added again', () {
      final bill1 = g1Bill1();
      PaymentConfirmationService.recordTellerPayment(
        bill1,
        interestPayment: 500,
        principalPayment: 2900,
      );
      final bill2 = nextBill([bill1]);
      expect(bill2.amortization, closeTo(3944.18, 1e-9));
      expect(bill2.interestCharge, closeTo(355, 1e-9));
      expect(bill2.principalPayment, closeTo(3589.18, 1e-9));
      pay(
        bill2,
        id: 'row-2',
        on: DateTime(2026, 10),
        interest: 355,
        principal: 3589.18,
      );
      expect(bill2.outstandingBalance, closeTo(3510.82, 1e-6));

      final row = LoanCalculationService.settlementOf(
        loan: fixedTerm(),
        rows: [bill1, bill2],
        now: DateTime(2026, 10, 11, 10),
      );

      expect(row.principalPayment, closeTo(3510.82, 1e-6));
      expect(row.interestPayment, 58.51);
      expect(
        LoanCalculationService.settlementAmount(row),
        closeTo(3569.33, 0.005),
      );
    });

    test('G7l a part-paid last bill: the later of its two rows counts', () {
      final bill1 = g1Bill1();
      final bill2 = nextBill([bill1]);
      pay(
        bill2,
        id: 'row-2',
        on: DateTime(2026, 10),
        interest: bill2.interestCharge,
        principal: bill2.principalPayment,
      );
      expect(bill2.outstandingBalance, closeTo(3497.2244, 1e-4));
      final bill3 = nextBill([bill1, bill2]);
      expect(bill3.interestCharge, closeTo(174.8612, 1e-4));
      expect(bill3.principalPayment, closeTo(3497.2244, 1e-4));
      pay(
        bill3,
        id: 'row-3',
        on: DateTime(2026, 11),
        interest: bill3.interestCharge,
        principal: 3000,
      );
      expect(bill3.outstandingBalance, closeTo(497.2244, 1e-4));
      final rest = nextBill([bill1, bill2, bill3]);
      expect(rest.partPaidAt, isNotNull);
      expect(rest.dueAt, bill3.dueAt);
      expect(rest.principalPayment, closeTo(497.2244, 1e-4));
      pay(
        rest,
        id: 'row-3b',
        on: DateTime(2026, 11, 3),
        interest: 0,
        principal: 200,
      );
      expect(rest.outstandingBalance, closeTo(297.2244, 1e-4));

      final row = LoanCalculationService.settlementOf(
        loan: fixedTerm(),
        // The rest listed before the row it follows: order must not matter.
        rows: [bill1, bill2, rest, bill3],
        now: DateTime(2026, 11, 11, 10),
      );

      expect(row.principalPayment, closeTo(297.2244, 1e-4));
      expect(row.interestPayment, 4.95);
      expect(
        LoanCalculationService.settlementAmount(row),
        closeTo(302.17, 0.005),
      );
    });
  });
}
