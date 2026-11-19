import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/loans/screens/loan_details.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans/services/top_up_overdue_service.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:product_repository/product_repository.dart';

// The owner's soft block for a top-up on an overdue open-term loan
// (2026-11-19), derived by hand.
//
// Loan: 40,000 open term at 5% a month, term '15d', created Sep 1 2026
// (local). Bills every 15 days from the creation day (R1): Sep 16, Oct 1,
// Oct 16, each 40,000 x 5% x 15/30 = 1,000. Penalties: "Late fee" 100 once
// + "Daily 0.1%" of the balance in force each day (40,000 -> 40 a day).
//
// Seen Sep 21: the Sep 16 bill is missed, 5 days late; Oct 1 is the
// current bill. Pay now = 1,000 + (100 + 5 x 40 = 300) = 1,300.
//   Top-up 10,000, no charges: proceeds 10,000. Deduct releases
//   10,000 - 1,300 = 8,700; the cash pool is not written (net 0), the
//   8,700 is handed over outside the app.
//   Top-up 1,000: proceeds 1,000 < 1,300 -> "Deduct" is refused.
// Seen Sep 16 (the bill is due today, not late) or Sep 15: nothing overdue,
// no warning.
// Seen Oct 1: Sep 16 is 15 days late, Oct 1 is due today. Pay now =
// 1,000 + 1,000 + (100 + 15 x 40 = 700) = 2,700, the penalty once (R3), on
// the Sep 16 bill; Oct 1 is paid on time with 0.
// The balance moves on the approval day (review of #149): 10,000 added
// Sep 21 and approved Sep 26, seen Oct 1 with the Sep 16 bill unpaid. The
// Oct 1 bill (Sep 16 - Oct 1) = 40,000 x 5% x 10/30 + 50,000 x 5% x 5/30 =
// 666.67 + 416.67 = 1,083.33; the stretch penalty on Oct 1 (15 days from
// Sep 16) = 100 + 10 x 40 (Sep 16-25) + 5 x 50 (Sep 26-30) = 750. Approved
// the day it was added (Sep 21), or approved before approval times were
// recorded (from its creation day): 5 x 40,000 + 10 x 50,000 days ->
// 333.33 + 833.33 = 1,166.67 and 100 + 5 x 40 + 10 x 50 = 800.
// Proceeds with charges: 10,000 with a 2% deduction (200), a 300 charge
// collected upfront and a 5% charge added to the balance (500, owed, not
// cash): 10,000 - 200 - 300 = 9,500; with 1,300 overdue, 8,200 released.

const lateFee100 = Penalty(id: 'late-fee', name: 'Late fee', amount: 100);
const daily01pct = Penalty(
  id: 'daily-01',
  name: 'Daily 0.1%',
  amount: 0.1,
  isPercentage: true,
  frequency: PenaltyFrequency.daily,
);

Loan loan40k() => Loan.create(
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
      ..createdAt = DateTime(2026, 9, 1, 9)
      ..additionalLoanAmounts = [];

AdditionalLoanAmount topUp({
  double amount = 10000,
  double deductions = 0,
  double advanceCharges = 0,
}) =>
    AdditionalLoanAmount.create(
      loanId: 'loan-1',
      amount: amount,
      additionalCharges: 0,
      advanceCharges: advanceCharges,
      deductions: deductions,
      selfiePhotoUrl: ImageUrl(name: 'selfie'),
      signatureUrl: ImageUrl(name: 'signature'),
      overdueChoice: OverdueChoice.deduct,
    )..id = 'topup-1';

/// What client detail lists for the loan on [now].
List<LoanSchedule> rowsOn(Loan loan, DateTime now) =>
    LoanCalculationService.calculateOpenTerm(
      amount: 40000,
      date: loan.createdAt,
      interestRate: 5,
      term: '15d',
      companyId: 'co-1',
      loan: loan,
      now: now,
    ).schedules;

void main() {
  final sep21 = DateTime(2026, 9, 21, 10);

  group('overdue amount (what Pay now shows)', () {
    test('one missed bill: 1,000 + 300 = 1,300', () {
      final loan = loan40k()..additionalLoanAmounts = [topUp()];
      final overdue = TopUpOverdueService.overdue(
        loan: loan,
        schedules: rowsOn(loan, sep21),
        asOf: sep21,
      );

      expect(overdue, isNotNull);
      expect(overdue!.bills, hasLength(1));
      expect(overdue.bills.single.dueAt, DateTime(2026, 9, 16));
      expect(overdue.bills.single.amortization, closeTo(1000, 0.001));
      expect(overdue.amount, 1300);
    });

    test('a pending top-up does not change it (#137)', () {
      final loan = loan40k()..additionalLoanAmounts = [topUp()];
      final without = loan40k();

      expect(
        TopUpOverdueService.overdue(
          loan: loan,
          schedules: rowsOn(loan, sep21),
          asOf: sep21,
        )!
            .amount,
        TopUpOverdueService.overdue(
          loan: without,
          schedules: rowsOn(without, sep21),
          asOf: sep21,
        )!
            .amount,
      );
    });

    test('nothing past due (bill due today, or none yet): no warning', () {
      final loan = loan40k();
      for (final day in [DateTime(2026, 9, 16, 10), DateTime(2026, 9, 15)]) {
        expect(
          TopUpOverdueService.overdue(
            loan: loan,
            schedules: rowsOn(loan, day),
            asOf: day,
          ),
          isNull,
          reason: '$day',
        );
      }
    });

    test('missed bill + bill due today: 1,000 + 1,000 + 700 = 2,700', () {
      final oct1 = DateTime(2026, 10, 1, 10);
      final loan = loan40k();
      final overdue = TopUpOverdueService.overdue(
        loan: loan,
        schedules: rowsOn(loan, oct1),
        asOf: oct1,
      )!;

      expect(
        overdue.bills.map((b) => b.dueAt),
        [DateTime(2026, 9, 16), DateTime(2026, 10)],
      );
      expect(overdue.amount, 2700);
    });

    test('a fixed-term loan never warns', () {
      final loan = loan40k()..period = 6;

      expect(
        TopUpOverdueService.overdue(
          loan: loan,
          schedules: rowsOn(loan40k(), sep21),
          asOf: sep21,
        ),
        isNull,
      );
    });
  });

  group('deduction split (settle, in memory)', () {
    test('one bill: paid late on the collection day, 1,000 + 300', () {
      final loan = loan40k();
      final rows = rowsOn(loan, sep21);
      final bills = TopUpOverdueService.overdue(
        loan: loan,
        schedules: rows,
        asOf: sep21,
      )!
          .bills;

      final total = TopUpOverdueService.settle(
        loan: loan,
        bills: bills,
        schedules: rows,
        collectedAt: sep21,
        actorId: 'officer-1',
      );

      expect(total, 1300);
      final bill = bills.single;
      expect(bill.status, LoanStatus.paid_late);
      expect(bill.collectedAt, sep21);
      expect(bill.daysLate, 5);
      expect(bill.penalty, closeTo(300, 0.001));
      expect(bill.penalties, [lateFee100, daily01pct]);
      expect(bill.interestPayment, closeTo(1000, 0.001));
      expect(bill.principalPayment, 0);
      expect(bill.outstandingBalance, 40000);
      expect(bill.loanId, 'loan-1');
    });

    test('two bills: the stretch penalty once, on the late bill', () {
      final oct1 = DateTime(2026, 10, 1, 10);
      final loan = loan40k();
      final rows = rowsOn(loan, oct1);
      final bills = TopUpOverdueService.overdue(
        loan: loan,
        schedules: rows,
        asOf: oct1,
      )!
          .bills;

      final total = TopUpOverdueService.settle(
        loan: loan,
        bills: bills,
        schedules: rows,
        collectedAt: oct1,
        actorId: 'officer-1',
      );

      expect(total, 2700);
      expect(bills.map((b) => b.status), [
        LoanStatus.paid_late,
        LoanStatus.paid_on_time,
      ]);
      expect(bills.map((b) => b.penalty), [closeTo(700, 0.001), 0]);
      expect(bills.map((b) => b.daysLate), [15, 0]);
      expect(
        bills.map((b) => b.interestPayment),
        [closeTo(1000, 0.001), closeTo(1000, 0.001)],
      );
    });
  });

  group('a top-up moves the balance from its approval day', () {
    final oct1 = DateTime(2026, 10, 1, 10);

    ({double bill, double penalty}) onOct1(DateTime? approvedAt) {
      final loan = loan40k()
        ..additionalLoanAmounts = [
          topUp()
            ..status = LoanStatus.approved
            ..createdAt = DateTime(2026, 9, 21, 10)
            ..approvedAt = approvedAt,
        ];
      final rows = rowsOn(loan, oct1);
      final bills = rows.where((r) => !r.isPlaceholder).toList();
      expect(
        bills.map((b) => b.dueAt),
        [DateTime(2026, 9, 16), DateTime(2026, 10)],
      );
      final due = borrowerAmountsDue(schedules: rows, loan: loan, asOf: oct1);

      return (bill: bills.last.amortization, penalty: due.nextDuePenalty);
    }

    test('approved Sep 26: 1,083.33 and a 750 penalty', () {
      final (:bill, :penalty) = onOct1(DateTime(2026, 9, 26, 10));
      expect(bill, closeTo(1083.33, 0.01));
      expect(penalty, closeTo(750, 0.001));
    });

    test('approved the day it was added: 1,166.67 and 800', () {
      final (:bill, :penalty) = onOct1(DateTime(2026, 9, 21, 11));
      expect(bill, closeTo(1166.67, 0.01));
      expect(penalty, closeTo(800, 0.001));
    });

    test('approved before approval times were recorded: its creation day', () {
      final (:bill, :penalty) = onOct1(null);
      expect(bill, closeTo(1166.67, 0.01));
      expect(penalty, closeTo(800, 0.001));
    });
  });

  group('proceeds and the cash released', () {
    test('no charges: 10,000 - 1,300 = 8,700 released', () {
      final proceeds = TopUpOverdueService.proceeds(topUp());

      expect(proceeds, 10000);
      expect(proceeds - 1300, 8700);
    });

    test('deductions and advance charges leave the cash handed over', () {
      expect(
        TopUpOverdueService.proceeds(
          topUp(deductions: 200, advanceCharges: 300),
        ),
        9500,
      );
      expect(
        TopUpOverdueService.proceedsOf(
          amount: 10000,
          charges: const [
            Charge(
              id: 'upfront',
              amount: 300,
              description: 'Processing fee',
              isUpfrontCollection: true,
            ),
            Charge(
              id: 'added',
              amount: 5,
              description: 'Service charge',
              isPercentage: true,
            ),
          ],
          deductions: const [
            Charge(
              id: 'less',
              amount: 2,
              description: 'Insurance',
              isPercentage: true,
            ),
          ],
        ),
        9500,
      );
      expect(9500 - 1300, 8200);
    });

    test('larger than the top-up: 1,300 is more than 1,000 handed over', () {
      expect(TopUpOverdueService.proceeds(topUp(amount: 1000)), 1000);
      expect(1300 > TopUpOverdueService.proceeds(topUp(amount: 1000)), isTrue);
    });
  });
}
