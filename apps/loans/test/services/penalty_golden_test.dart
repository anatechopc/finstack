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
// What runs here and what does not. The lateness decision and the penalty
// math are the production functions (`resolveLateness`, `computePenalties`,
// `termDaysOf`, `PaymentConfirmationService.applyLateness`) on the real
// `Company`, `Product`, `Loan` and `LoanSchedule` models. The two copy steps
// before them are made by the helpers below. The helpers mirror the
// production call sites and do NOT run them:
//   company defaults -> product: product_bloc.dart fills `_penalties` from
//     `authService.company.defaultPenalties` and saves the product with
//     `penalties: List<Penalty>.of(_penalties)`
//   product -> loan: loans_bloc.dart, `Loan.create(penalties:
//     List<Penalty>.of(product.penalties), allowLatePayments: ...)`
// `Loan.create` keeps the list it is given, so a loan is independent of its
// product only because the call site copies; `loanUnder` copies the same
// way. The loan -> row copy at confirmation is production code
// (`applyLateness`), and P8 runs it.
//
// The ONLY trigger is a late collection: collection date after the row's due
// date (calendar days, time of day ignored) on a loan that does not allow
// late payments. There is no grace period, threshold or cap.
//
// Company defaults used here: "Late fee" flat 100 once, "Daily surcharge"
// 1% of the amount due per day late. Term-loan row amortization 2,500;
// open-term row outstanding balance 10,000. Collected 5 days late unless
// stated. The loan itself is 12,000 with amortization 3,000, different from
// the row on purpose: a base read from the loan instead of the row would
// give 100 + 30 x 5 = 250 in P1 and 100 + 120 x 5 = 700 in P4.
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
//   P5b per installment through resolveLateness, the term read from the
//       loan (100 per installment; due Jul 15, collected Aug 15 = 31 days):
//        '15d' loan -> ceil(31/15) = 3 -> 300
//        '1m' loan  -> ceil(31/30) = 2 -> 200
//   P6 collected ON the due date: 0 days, not late, paid_on_time, 0;
//      the day after: 1 day -> 100 + 25 x 1 = 125
//   P7 waive with a reason: charge 0, who/why recorded, definitions kept so
//      the 225 can be reconstructed; nothing to waive when the company has
//      no defaults, so no reason is needed either
//   P7c waive without a reason (none given, or blank) when 225 is owed:
//      rejected, and the row is left as it was
//   P8 edits made after the loan exists (the company clears its defaults;
//      the product swaps to 2% monthly and allows late payments): the loan
//      still holds the two original terms -> 5 days late is still 225;
//      clearing the loan's list after confirmation leaves the row's copy
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
/// from the company defaults (copy-on-create). Mirrors product_bloc.dart,
/// which saves the product with its own `List<Penalty>.of(...)` copy.
Product productOf(Company company, {bool allowLatePayments = false}) =>
    Product()
      ..penalties = List<Penalty>.of(company.defaultPenalties)
      ..allowLatePayments = allowLatePayments;

/// A loan under [product]: loans_bloc snapshots the product's penalties and
/// allow-late flag at creation. `Loan.create` keeps the list it is given, so
/// the copy is made here exactly as the production call site makes it
/// (`List<Penalty>.of(product.penalties)` in loans_bloc.dart).
///
/// Amount 12,000 and amortization 3,000 differ from the row's 10,000 and
/// 2,500 so a penalty base read from the loan cannot pass for the row's.
Loan loanUnder(Product product, {String term = '1m'}) => Loan.create(
      userId: 'u1',
      companyId: 'c1',
      productId: 'pr1',
      amount: 12000,
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
      amortization: 3000,
      penalties: List<Penalty>.of(product.penalties),
      allowLatePayments: product.allowLatePayments,
    );

LoanSchedule row({bool isOpenTerm = false, DateTime? dueAt}) =>
    LoanSchedule.create(
      dueAt: dueAt ?? dueDate,
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

    test('P5b per installment reads the term from the loan', () {
      final company = Company()..defaultPenalties = const [perInstallment100];

      // Due Jul 15, collected Aug 15: 31 days, and no zone changes its clock
      // in between. Aug 15 to Sep 15 would count 30 in Chile, whose clocks
      // go forward on Sep 6.
      LatenessResult collectedLate({required String term}) => resolveLateness(
            schedule: row(dueAt: DateTime(2026, 7, 15)),
            loan: loanUnder(productOf(company), term: term),
            collectedAt: DateTime(2026, 8, 15),
          );

      final halfMonth = collectedLate(term: '15d');
      expect(halfMonth.daysLate, 31);
      expect(halfMonth.penalties.lines.single.periods, 3);
      expect(halfMonth.penalties.total, closeTo(300, 0.01));

      final monthly = collectedLate(term: '1m');
      expect(monthly.penalties.lines.single.periods, 2);
      expect(monthly.penalties.total, closeTo(200, 0.01));
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

      final onTimeRow = row();
      final onTimeStatus = PaymentConfirmationService.applyLateness(
        schedule: onTimeRow,
        loan: loan,
        collectedAt: DateTime(2026, 8, 15, 23, 59),
        actorId: 'teller-1',
      );
      expect(onTimeStatus, LoanStatus.paid_on_time);
      expect(onTimeRow.daysLate, 0);
      expect(onTimeRow.penalty, 0);
      expect(onTimeRow.penalties, isEmpty);

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

    test('P7c waive without a reason is rejected, row left as it was', () {
      final loan = loanUnder(productOf(withDefaults));

      for (final reason in [null, '   ']) {
        final schedule = row();

        expect(
          () => PaymentConfirmationService.applyLateness(
            schedule: schedule,
            loan: loan,
            collectedAt: daysAfterDue(5),
            actorId: 'teller-1',
            waivePenalty: true,
            waiveReason: reason,
          ),
          throwsException,
          reason: 'waive reason: "$reason"',
        );
        expect(schedule.collectedAt, isNull);
        expect(schedule.daysLate, 0);
        expect(schedule.penalty, 0);
        expect(schedule.penalties, isEmpty);
        expect(schedule.penaltyWaivedBy, isNull);
        expect(schedule.penaltyWaiveReason, isNull);
      }
    });
  });

  group('G12 snapshot', () {
    test('P8 later edits to the company and product do not reach the loan',
        () {
      final company = Company()..defaultPenalties = [lateFee100, daily1pct];
      final product = productOf(company);
      final loan = loanUnder(product);

      // These two steps hold because the helpers copy the way the production
      // call sites do (see the top of the file); they do not run those sites.
      // Both lists are edited in place: a shared list would show the edit.
      company.defaultPenalties.clear();
      expect(product.penalties, [lateFee100, daily1pct]);

      product.penalties
        ..clear()
        ..add(monthly2pct);
      product.allowLatePayments = true;
      expect(loan.penalties, [lateFee100, daily1pct]);
      expect(loan.allowLatePayments, isFalse);

      final schedule = row();
      final status = PaymentConfirmationService.applyLateness(
        schedule: schedule,
        loan: loan,
        collectedAt: daysAfterDue(5),
        actorId: 'teller-1',
      );

      expect(status, LoanStatus.paid_late);
      expect(schedule.penalty, closeTo(225, 0.01));

      // This step is production code: applyLateness gives the row its own
      // copy, so the charge stays reconstructible whatever the loan's list
      // becomes.
      loan.penalties.clear();
      expect(schedule.penalties, [lateFee100, daily1pct]);
    });
  });
}
