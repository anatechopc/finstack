import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
// The Firestore service reads documents through this entity, which the
// package does not export.
// ignore: implementation_imports
import 'package:loan_schedule_repository/src/model/loan_schedule_entity.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans/services/payment_confirmation_service.dart';
import 'package:loooans_helpers/data_helpers.dart';

// Golden scenario set G13 — late payments on open-term loans (finstack#114).
// Every number below was derived on paper BEFORE the test was written.
//
// #114 kept the cycle's own due date as `originalDueAt` on a row the engine
// billed as due today, and counted lateness from it (`LoanSchedule.lateFrom`).
// Since the owner's rules R1-R5 (2026-11-19, G14) an overdue bill keeps its
// own due date, so `originalDueAt` stays null on new rows and only the
// INTEREST figures below moved (R1/R2: one cycle per bill, no accrual to
// today); every penalty figure is unchanged. Moved, old -> new:
//   G13a/b/e row due Sep 8 -> Aug 31, interest 633.33 (38 days) -> 500.00
//        (30 days), originalDueAt Aug 31 -> none (lateFrom still Aug 31)
//   G13d row due Sep 16 -> Aug 30, interest 533.33 (32 days) -> 250.00
//        (15 days), amount due 500 -> 250; the Sep 15 bill (16 days,
//        266.67) is now its own row, and paying both together still owes
//        2,000 once (R3; per bill it would be 2,000 + 300 = 2,300). MOVED
//        2026-11-19 with #148: a flat amount is charged per missed bill
//        (owner), so both together owe 2,000 + the Sep 15 bill's flat 100
//        once + 100 x ceil(1/15) = 2,200; the 1% a day stays once
//   G13e the stored row is due_at Aug 31 without original_due_at; a row
//        stored by #114's clamp (due_at Sep 8, original_due_at Aug 31)
//        still reads back as 8 days, and one without original_due_at
//        counts from its due_at
// Before #114 days late was always 0 on such a row, so every "before"
// figure below is 0.
//
// Loan: open term, 10,000 at 5% a month, created Jul 2 2026, one paid cycle
// due Aug 1 2026 (balance 10,000). Penalties are the G12 company defaults
// snapshotted on the loan: "Late fee" 100 once and "Daily surcharge" 1% per
// day. A percentage is of the row's outstanding balance (spec section 5,
// D7), here 10,000.
//
//   G13a '1m', seen Sep 8 2026 noon, late payments NOT allowed:
//        next due = Aug 1 + 30 d = Aug 31 < Sep 8: a missed bill, due Aug 31;
//        interest for 30 days = 10,000 x 5% = 500 = amount due;
//        days late Aug 31 -> Sep 8 = 8;
//        once 100 + daily 1% x 10,000 = 100 a day x 8 = 800       -> 900
//        (before: 0 days, 0)
//   G13b the same loan with late payments allowed: 8 days recorded, none
//        charged, paid_on_time; the preview is 0 (as fixed-term P3)
//   G13c on time: seen Aug 15 -> due Aug 31, no originalDueAt, 0;
//        seen ON Aug 31 at noon -> due today, not late: 0 days, 0
//   G13d salary days '15,30', paid cycle due Aug 15, seen Sep 16 noon,
//        penalties 100 once + 1% daily + 100 per installment:
//        bills Aug 30 (15 days, 250.00) and Sep 15 (16 days, 266.67) are
//        missed, Sep 30 (250.00) is current; days late Aug 30 -> Sep 16 = 17;
//        once 100 + daily 100 x 17 = 1,700
//        + per installment 100 x ceil(17/15) = 200                  -> 2,000
//        (a 30-day term would give ceil(17/30) = 1 -> 1,900)
//   G13e the teller confirms the G13a row, collected Sep 8: paid_late,
//        days_late 8, penalty 900, stored with due_at Aug 31; reading it
//        back gives 8 days again
//   G13f collected Sep 5 (after Aug 31): 5 days -> 100 + 500 = 600
//   G13g the principal-release placeholder row (due on the creation date,
//        Jul 2; balance 0) is not an installment: previews 0 and confirms
//        paid_on_time with 0 days and 0 (before: the flat "100 once" was
//        charged on it, paid_late, 68 days "late")
//
// Mutation check: make `LoanSchedule.lateFrom` return `dueAt` -> G13a, b,
// d, e, f and g fail (g through its non-placeholder row).

const lateFee100 = Penalty(id: 'late-fee', name: 'Late fee', amount: 100);
const daily1pct = Penalty(
  id: 'daily',
  name: 'Daily surcharge',
  amount: 1,
  isPercentage: true,
  frequency: PenaltyFrequency.daily,
);
const perInstallment100 = Penalty(
  id: 'per-installment',
  name: 'Installment fee',
  amount: 100,
  frequency: PenaltyFrequency.perInstallment,
);

final loanCreated = DateTime(2026, 7, 2);

Loan openTermLoan({
  String term = '1m',
  bool allowLatePayments = false,
  List<Penalty> penalties = const [lateFee100, daily1pct],
}) =>
    Loan()
      ..id = 'loan-1'
      ..createdAt = loanCreated
      ..status = LoanStatus.approved
      ..period = 0
      ..term = term
      ..additionalChargeUpfrontCollection = 0
      ..additionalLoanAmounts = []
      ..penalties = List<Penalty>.of(penalties)
      ..allowLatePayments = allowLatePayments;

LoanSchedule paidCycle(DateTime dueAt) => LoanSchedule()
  ..id = 'sched-1'
  ..loanId = 'loan-1'
  ..companyId = 'co-1'
  ..createdAt = loanCreated
  ..updatedAt = loanCreated
  ..dueAt = dueAt
  ..paidAt = dueAt
  ..status = LoanStatus.paid_on_time
  ..isOpenTerm = true
  ..outstandingBalance = 10000
  ..principalPayment = 0
  ..interestPayment = 0
  ..interestCharge = 0
  ..amortization = 0
  ..extraPayment = 0
  ..advanceInterestPayments = 0
  ..interestDayMultiplier = 1;

/// The open-term bills as the app computes them on [now].
List<LoanSchedule> billsOn({
  required DateTime now,
  String term = '1m',
  DateTime? paidDueAt,
}) =>
    LoanCalculationService.calculateOpenTermSchedules(
      amount: 10000,
      date: loanCreated,
      interestRate: 5,
      term: term,
      companyId: 'co-1',
      paidSchedules: [paidCycle(paidDueAt ?? DateTime(2026, 8))],
      now: now,
    ).schedules;

/// The first bill after the paid cycle (the missed one when overdue).
LoanSchedule nextRow({
  required DateTime now,
  String term = '1m',
  DateTime? paidDueAt,
}) =>
    billsOn(now: now, term: term, paidDueAt: paidDueAt).first;

void main() {
  final sep8 = DateTime(2026, 9, 8, 12);

  group('G13 open-term lateness counts from the cycle due date', () {
    test('G13a not allowed late: 8 days late, 900, the bill keeps its date',
        () {
      final row = nextRow(now: sep8);

      expect(DateUtils.dateOnly(row.dueAt), DateTime(2026, 8, 31));
      expect(row.originalDueAt, isNull);
      expect(row.lateFrom, DateTime(2026, 8, 31));
      expect(row.interestCharge, closeTo(500, 0.01));
      expect(row.amortization, closeTo(500, 0.01));
      expect(row.outstandingBalance, closeTo(10000, 0.01));

      final loan = openTermLoan();
      final preview = previewPenalty(schedule: row, loan: loan, asOf: sep8);
      expect(preview.lines, hasLength(2));
      expect(preview.lines[0].amount, closeTo(100, 0.01));
      expect(preview.lines[1].periods, 8);
      expect(preview.lines[1].amount, closeTo(800, 0.01));
      expect(preview.total, closeTo(900, 0.01));

      final lateness =
          resolveLateness(schedule: row, loan: loan, collectedAt: sep8);
      expect(lateness.daysLate, 8);
      expect(lateness.isLate, isTrue);
      expect(lateness.penalties.total, closeTo(900, 0.01));
    });

    test('G13b allowed late: 8 days recorded, nothing charged', () {
      final row = nextRow(now: sep8);
      final loan = openTermLoan(allowLatePayments: true);

      expect(
        previewPenalty(schedule: row, loan: loan, asOf: sep8).total,
        0,
      );

      final status = PaymentConfirmationService.applyLateness(
        schedule: row,
        loan: loan,
        collectedAt: sep8,
        actorId: 'teller-1',
      );
      expect(status, LoanStatus.paid_on_time);
      expect(row.daysLate, 8);
      expect(row.penalty, 0);
      expect(row.penalties, isEmpty);
    });

    test('G13c an on-time row keeps no original due date and owes 0', () {
      final loan = openTermLoan();

      final early = nextRow(now: DateTime(2026, 8, 15));
      expect(DateUtils.dateOnly(early.dueAt), DateTime(2026, 8, 31));
      expect(early.originalDueAt, isNull);
      expect(
        previewPenalty(
          schedule: early,
          loan: loan,
          asOf: DateTime(2026, 8, 15),
        ).total,
        0,
      );

      final onTheDay = nextRow(now: DateTime(2026, 8, 31, 12));
      expect(DateUtils.dateOnly(onTheDay.dueAt), DateTime(2026, 8, 31));
      expect(onTheDay.originalDueAt, isNull);
      final lateness = resolveLateness(
        schedule: onTheDay,
        loan: loan,
        collectedAt: DateTime(2026, 8, 31, 12),
      );
      expect(lateness.daysLate, 0);
      expect(lateness.isLate, isFalse);
      expect(lateness.penalties.total, 0);
    });

    test('G13d salary days "15,30": 17 days late, 2,000', () {
      final sep16 = DateTime(2026, 9, 16, 12);
      final rows = billsOn(
        now: sep16,
        term: '15,30',
        paidDueAt: DateTime(2026, 8, 15),
      );
      final row = rows.first;

      expect(DateUtils.dateOnly(row.dueAt), DateTime(2026, 8, 30));
      expect(row.originalDueAt, isNull);
      expect(row.interestCharge, closeTo(250, 0.01));
      expect(row.amortization, closeTo(250, 0.01));
      expect(DateUtils.dateOnly(rows[1].dueAt), DateTime(2026, 9, 15));
      expect(rows[1].interestCharge, closeTo(266.67, 0.01));

      final loan = openTermLoan(
        term: '15,30',
        penalties: const [lateFee100, daily1pct, perInstallment100],
      );
      final lateness =
          resolveLateness(schedule: row, loan: loan, collectedAt: sep16);
      expect(lateness.daysLate, 17);
      expect(lateness.penalties.lines[1].amount, closeTo(1700, 0.01));
      expect(lateness.penalties.lines[2].periods, 2);
      expect(lateness.penalties.lines[2].amount, closeTo(200, 0.01));
      expect(lateness.penalties.total, closeTo(2000, 0.01));

      // Both paid together: the 1% a day once (R3), the flat 100 once and
      // 100 per installment on each bill: 2,000 + 100 + 100 = 2,200.
      final together = resolveLatenessTogether(
        schedules: rows.sublist(0, 2),
        loan: loan,
        collectedAt: sep16,
        loanRows: rows,
      );
      expect(together.map((r) => r.daysLate), [17, 1]);
      expect(
        together.fold<double>(0, (sum, r) => sum + r.penalties.total),
        closeTo(2200, 0.01),
      );
    });
  });

  group('G13 confirmation', () {
    test('G13e the stored row keeps original_due_at and days_late', () {
      final row = nextRow(now: sep8);
      final loan = openTermLoan();

      final status = PaymentConfirmationService.applyLateness(
        schedule: row,
        loan: loan,
        collectedAt: sep8,
        actorId: 'teller-1',
      );
      expect(status, LoanStatus.paid_late);
      expect(row.collectedAt, sep8);
      expect(row.daysLate, 8);
      expect(row.penalty, closeTo(900, 0.01));
      expect(row.penalties, [lateFee100, daily1pct]);

      final json = row.toJson();
      expect(json['original_due_at'], isNull);
      expect(json['due_at'], DateTime(2026, 8, 31).millisecondsSinceEpoch);
      expect(json['days_late'], 8);
      expect(json['penalty'], closeTo(900, 0.01));

      final stored = LoanScheduleEntity.fromJson(json).toLoanSchedule();
      expect(
        resolveLateness(schedule: stored, loan: loan, collectedAt: sep8)
            .daysLate,
        8,
      );

      // A row stored by #114's clamp still reads back as 8 days late, and
      // one written before #114 (no original_due_at) counts from due_at.
      final clampRow = Map<String, dynamic>.of(json)
        ..['due_at'] = DateTime(2026, 9, 8).millisecondsSinceEpoch
        ..['original_due_at'] = DateTime(2026, 8, 31).millisecondsSinceEpoch;
      final fromClamp = LoanScheduleEntity.fromJson(clampRow).toLoanSchedule();
      // Documents come back as UTC instants; compare the instant.
      expect(
        fromClamp.originalDueAt?.millisecondsSinceEpoch,
        DateTime(2026, 8, 31).millisecondsSinceEpoch,
      );
      expect(
        resolveLateness(schedule: fromClamp, loan: loan, collectedAt: sep8)
            .daysLate,
        8,
      );

      final writtenBefore114 = Map<String, dynamic>.of(clampRow)
        ..remove('original_due_at');
      final old =
          LoanScheduleEntity.fromJson(writtenBefore114).toLoanSchedule();
      expect(old.originalDueAt, isNull);
      expect(
        old.lateFrom.millisecondsSinceEpoch,
        DateTime(2026, 9, 8).millisecondsSinceEpoch,
      );
    });

    test('G13f collected before the billing date: 5 days, 600', () {
      final lateness = resolveLateness(
        schedule: nextRow(now: sep8),
        loan: openTermLoan(),
        collectedAt: DateTime(2026, 9, 5),
      );

      expect(lateness.daysLate, 5);
      expect(lateness.isLate, isTrue);
      expect(lateness.penalties.total, closeTo(600, 0.01));
    });

    test('G13g the principal-release placeholder owes no penalty', () {
      final loan = openTermLoan();
      final schedules = LoanCalculationService.calculateOpenTerm(
        amount: 10000,
        date: loanCreated,
        interestRate: 5,
        term: '1m',
        companyId: 'co-1',
        paidSchedules: [paidCycle(DateTime(2026, 8))],
        loan: loan,
        now: sep8,
      ).schedules;

      final placeholder = schedules.first;
      expect(placeholder.isPlaceholder, isTrue);
      expect(placeholder.status, LoanStatus.not_paid);
      expect(placeholder.dueAt, loanCreated);
      expect(
        previewPenalty(schedule: placeholder, loan: loan, asOf: sep8).total,
        0,
      );
      final missed =
          schedules.firstWhere((s) => s.id == NO_ID && !s.isPlaceholder);
      expect(DateUtils.dateOnly(missed.dueAt), DateTime(2026, 8, 31));
      expect(
        previewPenalty(
          schedule: missed,
          loan: loan,
          asOf: sep8,
          loanRows: schedules,
        ).total,
        closeTo(900, 0.01),
      );

      // Confirming it is not late either (before: paid_late, 68 days, 100).
      final status = PaymentConfirmationService.applyLateness(
        schedule: placeholder,
        loan: loan,
        collectedAt: sep8,
        actorId: 'teller-1',
      );
      expect(status, LoanStatus.paid_on_time);
      expect(placeholder.daysLate, 0);
      expect(placeholder.penalty, 0);
    });
  });
}
