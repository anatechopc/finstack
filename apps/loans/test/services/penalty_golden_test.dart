import 'package:company_repository/company_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/services/payment_confirmation_service.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:product_repository/product_repository.dart';

// Golden scenario set G12 — penalties (loooans#72, added to the campaign's
// Gate 1 suite on the owner's request, 2026-09-08). Every number below was
// derived on paper BEFORE the test was written.
//
// The chain under test is the real one: a company's default penalties
// pre-fill a product (copy-on-create), the product's penalties and its
// "allow late payments" flag are snapshotted onto the loan at creation
// (loans_bloc.dart, `Loan.create(penalties: ..., allowLatePayments: ...)`),
// and a payment confirmed after the due date charges them.
//
// The ONLY trigger is a late collection: collection date after the row's due
// date (calendar days, time of day ignored) on a loan that does not allow
// late payments. There is no grace period, threshold or cap.
//
// Company defaults used here: "Late fee" flat 100 once, "Daily surcharge"
// 1% of the amount due per day late. Term-loan row amortization 2,500;
// open-term row outstanding balance 10,000. Collected 5 days late unless
// stated.
//
//   P1 term loan, 5 days late:  once 100 x 1 = 100
//                               daily 1% x 2,500 = 25 x 5 = 125   -> 225
//   P2 company without defaults: product [] -> loan [] -> late but 0
//   P3 product allows late payments: 5 days recorded, not late, 0
//   P4 open-term row, 5 days late: base is the balance 10,000
//                               daily 1% x 10,000 = 100 x 5 = 500
//                               once 100                          -> 600
//   P5 cadence (2% monthly of 2,500 = 50/period; 100 per installment):
//        monthly, 30 days  -> ceil(30/30) = 1 period -> 50
//        monthly, 31 days  -> ceil(31/30) = 2 periods -> 100
//        per installment, '15d' loan, 31 days -> ceil(31/15) = 3 -> 300
//        per installment, '1m' loan, 31 days  -> ceil(31/30) = 2 -> 200
//   P6 collected ON the due date: 0 days, not late; the day after: 1 day
//   P7 waive with a reason: charge 0, who/why recorded, definitions kept so
//      the 225 can be reconstructed; nothing to waive when the company has
//      no defaults, so no reason is needed either
//
// Mutation check: change `(daysLate / 30).ceil()` to `/ 31` in
// loooans_helpers' penalty.dart -> the P5 "31 days" row must fail.

const lateFee100 = Penalty(id: 'late-fee', name: 'Late fee', amount: 100);
const daily1pct = Penalty(
  id: 'daily',
  name: 'Daily surcharge',
  amount: 1,
  isPercentage: true,
  frequency: PenaltyFrequency.daily,
);
const monthly2pct = Penalty(
  id: 'monthly',
  name: 'Monthly surcharge',
  amount: 2,
  isPercentage: true,
  frequency: PenaltyFrequency.monthly,
);
const perInstallment100 = Penalty(
  id: 'per-installment',
  name: 'Installment fee',
  amount: 100,
  frequency: PenaltyFrequency.perInstallment,
);

final dueDate = DateTime(2026, 8, 15);

DateTime daysAfterDue(int days) => DateTime(2026, 8, 15 + days);

/// A product created under [company]: the wizard pre-fills its penalties
/// from the company defaults (copy-on-create).
Product productOf(Company company, {bool allowLatePayments = false}) =>
    Product()
      ..penalties = List<Penalty>.of(company.defaultPenalties)
      ..allowLatePayments = allowLatePayments;

/// A loan under [product]: loans_bloc snapshots the product's penalties and
/// allow-late flag at creation.
Loan loanUnder(Product product, {String term = '1m'}) => Loan.create(
      userId: 'u1',
      companyId: 'c1',
      productId: 'pr1',
      amount: 10000,
      additionalCharges: 0,
      deductions: 0,
      period: 4,
      requirements: const [],
      isForceCollect: false,
      status: LoanStatus.approved,
      dueAt: null,
      reason: 'golden',
      interestRate: 5,
      term: term,
      amortization: 2500,
      penalties: List<Penalty>.of(product.penalties),
      allowLatePayments: product.allowLatePayments,
    );

LoanSchedule row({bool isOpenTerm = false}) => LoanSchedule.create(
      dueAt: dueDate,
      loanId: 'l1',
      outstandingBalance: 10000,
      principalPayment: 2000,
      interestCharge: 500,
      amortization: 2500,
      interestDayMultiplier: 1,
      companyId: 'c1',
      isOpenTerm: isOpenTerm,
    );

void main() {
  final withDefaults = Company()
    ..defaultPenalties = const [lateFee100, daily1pct];
  final withoutDefaults = Company();

  group('G12 penalties from company defaults', () {
    test('P1 defaults imposed on the product: 5 days late charges 225', () {
      final loan = loanUnder(productOf(withDefaults));
      final schedule = row();

      final lateness = resolveLateness(
        schedule: schedule,
        loan: loan,
        collectedAt: daysAfterDue(5),
      );

      expect(lateness.daysLate, 5);
      expect(lateness.isLate, isTrue);
      expect(lateness.penalties.lines, hasLength(2));
      expect(lateness.penalties.lines[0].amount, closeTo(100, 0.01));
      expect(lateness.penalties.lines[1].periods, 5);
      expect(lateness.penalties.lines[1].amount, closeTo(125, 0.01));
      expect(lateness.penalties.total, closeTo(225, 0.01));

      final status = PaymentConfirmationService.applyLateness(
        schedule: schedule,
        loan: loan,
        collectedAt: daysAfterDue(5),
        actorId: 'teller-1',
      );

      expect(status, LoanStatus.paid_late);
      expect(schedule.daysLate, 5);
      expect(schedule.penalty, closeTo(225, 0.01));
      expect(schedule.penalties, [lateFee100, daily1pct]);
      expect(schedule.penaltyWaivedBy, isNull);
    });

    test('P2 company without defaults: paid late, nothing to penalize', () {
      final product = productOf(withoutDefaults);
      expect(product.penalties, isEmpty, reason: 'nothing to pre-fill');

      final loan = loanUnder(product);
      expect(loan.penalties, isEmpty, reason: 'nothing to snapshot');

      final schedule = row();
      final lateness = resolveLateness(
        schedule: schedule,
        loan: loan,
        collectedAt: daysAfterDue(5),
      );

      expect(lateness.isLate, isTrue, reason: 'still a late payment');
      expect(lateness.daysLate, 5);
      expect(lateness.penalties.lines, isEmpty);
      expect(lateness.penalties.total, 0);

      final status = PaymentConfirmationService.applyLateness(
        schedule: schedule,
        loan: loan,
        collectedAt: daysAfterDue(5),
        actorId: 'teller-1',
      );

      expect(status, LoanStatus.paid_late, reason: 'late is still tagged');
      expect(schedule.penalty, 0);
      expect(schedule.penalties, isEmpty);
    });

    test('P3 product allows late payments: days recorded, no penalty', () {
      final loan = loanUnder(productOf(withDefaults, allowLatePayments: true));
      final schedule = row();

      final status = PaymentConfirmationService.applyLateness(
        schedule: schedule,
        loan: loan,
        collectedAt: daysAfterDue(5),
        actorId: 'teller-1',
      );

      expect(status, LoanStatus.paid_on_time);
      expect(schedule.daysLate, 5);
      expect(schedule.penalty, 0);
      expect(schedule.penalties, isEmpty);
    });

    test('P4 open-term row: percentages are of the outstanding balance', () {
      final lateness = resolveLateness(
        schedule: row(isOpenTerm: true),
        loan: loanUnder(productOf(withDefaults)),
        collectedAt: daysAfterDue(5),
      );

      expect(lateness.penalties.lines[1].amount, closeTo(500, 0.01));
      expect(lateness.penalties.total, closeTo(600, 0.01));
    });
  });

  group('G12 cadence', () {
    test('P5 monthly rounds a started month up; per installment follows term',
        () {
      double totalFor({
        required Penalty penalty,
        required int daysLate,
        String term = '1m',
      }) =>
          computePenalties(
            amountDue: 2500,
            penalties: [penalty],
            daysLate: daysLate,
            termDays: termDaysOf(term),
          ).total;

      expect(totalFor(penalty: monthly2pct, daysLate: 30), closeTo(50, 0.01));
      expect(totalFor(penalty: monthly2pct, daysLate: 31), closeTo(100, 0.01));
      expect(
        totalFor(penalty: perInstallment100, daysLate: 31, term: '15d'),
        closeTo(300, 0.01),
      );
      expect(
        totalFor(penalty: perInstallment100, daysLate: 31),
        closeTo(200, 0.01),
      );
      expect(termDaysOf('15,30'), 15);
      expect(termDaysOf('1m'), 30);
    });

    test('P6 the only trigger is a collection after the due date', () {
      final loan = loanUnder(productOf(withDefaults));

      final onTheDay = resolveLateness(
        schedule: row(),
        loan: loan,
        collectedAt: DateTime(2026, 8, 15, 23, 59),
      );
      expect(onTheDay.daysLate, 0);
      expect(onTheDay.isLate, isFalse);
      expect(onTheDay.penalties.total, 0);

      final nextMorning = resolveLateness(
        schedule: row(),
        loan: loan,
        collectedAt: DateTime(2026, 8, 16, 0, 1),
      );
      expect(nextMorning.daysLate, 1);
      expect(nextMorning.penalties.total, closeTo(125, 0.01));
    });
  });

  group('G12 waiving', () {
    test('P7 waive with a reason: charge 0, who and why kept, terms kept', () {
      final schedule = row();

      final status = PaymentConfirmationService.applyLateness(
        schedule: schedule,
        loan: loanUnder(productOf(withDefaults)),
        collectedAt: daysAfterDue(5),
        actorId: 'teller-1',
        waivePenalty: true,
        waiveReason: 'Typhoon',
      );

      expect(status, LoanStatus.paid_late);
      expect(schedule.daysLate, 5);
      expect(schedule.penalty, 0);
      expect(schedule.penaltyWaivedBy, 'teller-1');
      expect(schedule.penaltyWaiveReason, 'Typhoon');
      expect(
        schedule.penalties,
        [lateFee100, daily1pct],
        reason: 'the waived 225 stays reconstructible from the terms',
      );
    });

    test('P7b nothing to waive without company defaults, no reason needed',
        () {
      final schedule = row();

      final status = PaymentConfirmationService.applyLateness(
        schedule: schedule,
        loan: loanUnder(productOf(withoutDefaults)),
        collectedAt: daysAfterDue(5),
        actorId: 'teller-1',
        waivePenalty: true,
      );

      expect(status, LoanStatus.paid_late);
      expect(schedule.penalty, 0);
      expect(schedule.penaltyWaivedBy, isNull);
      expect(schedule.penaltyWaiveReason, isNull);
    });
  });
}
