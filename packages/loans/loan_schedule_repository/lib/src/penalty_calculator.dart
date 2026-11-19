import 'dart:math' as math;

import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/src/model/loan_schedule.dart';
import 'package:loooans_helpers/data_helpers.dart';

/// One applied penalty definition with the periods and amount it produced.
final class PenaltyLine {
  const PenaltyLine({
    required this.penalty,
    required this.periods,
    required this.amount,
  });

  final Penalty penalty;
  final int periods;
  final double amount;
}

/// The lines and total for one installment.
final class PenaltyResult {
  const PenaltyResult({required this.lines, required this.total});

  static const none = PenaltyResult(lines: [], total: 0);

  final List<PenaltyLine> lines;
  final double total;
}

/// Calendar days from [dueAt] to [collectedAt] in local time, floored at 0.
/// Collecting on the due date is 0 days late. Time of day is ignored.
int calculateDaysLate({
  required DateTime dueAt,
  required DateTime collectedAt,
}) {
  final due = dueAt.toLocal();
  final collected = collectedAt.toLocal();
  final dueDate = DateTime(due.year, due.month, due.day);
  final collectedDate =
      DateTime(collected.year, collected.month, collected.day);

  return math.max(0, collectedDate.difference(dueDate).inDays);
}

/// Pure penalty math (design spec section 5).
///
/// [amountDue] is the installment as displayed to the collector:
/// `amortization` for term loans, `outstandingBalance` for open-term rows.
/// Percentage penalties are a percent of [amountDue]; every penalty is then
/// multiplied by its frequency's periods for [daysLate].
/// [termDays] is the loan's installment period in days; only per-installment
/// penalties use it.
PenaltyResult computePenalties({
  required double amountDue,
  required List<Penalty> penalties,
  required int daysLate,
  int termDays = 30,
}) {
  if (daysLate <= 0 || penalties.isEmpty) {
    return PenaltyResult.none;
  }

  final lines = <PenaltyLine>[];
  var total = 0.0;

  for (final penalty in penalties) {
    final periods = penalty.frequency.periods(daysLate, termDays: termDays);
    final base = penalty.isPercentage
        ? amountDue * penalty.amount / 100
        : penalty.amount;
    final amount = base * periods;

    lines.add(PenaltyLine(penalty: penalty, periods: periods, amount: amount));
    total += amount;
  }

  return PenaltyResult(lines: lines, total: total);
}

const _unpaidStatuses = {
  LoanStatus.not_paid,
  LoanStatus.not_paid_overdue,
  LoanStatus.payment_submitted,
};

/// What an unpaid installment would owe in penalties if collected on [asOf]
/// (default: now). Applies the loan's allow-late gate. Used for the red line
/// on schedule rows and for the confirmation breakdown. An open-term
/// placeholder row (the principal release or a top-up) is not an
/// installment and owes nothing.
///
/// [loanRows] are the loan's other rows (stored and computed). On an
/// open-term loan the penalty is charged once for the loan per overdue
/// stretch (owner rule R3), so it is shown on the stretch's earliest unpaid
/// bill and later unpaid bills preview 0; the previews of a loan's rows add
/// up to the stretch's penalty once.
PenaltyResult previewPenalty({
  required LoanSchedule schedule,
  required Loan loan,
  DateTime? asOf,
  List<LoanSchedule> loanRows = const [],
}) {
  if (!_unpaidStatuses.contains(schedule.status) ||
      schedule.isPrincipalRelease ||
      schedule.isPlaceholder ||
      loan.allowLatePayments) {
    return PenaltyResult.none;
  }

  // A submitted open-term bill owes what it owed at its transfer.
  final submittedAt =
      schedule.isOpenTerm && schedule.status == LoanStatus.payment_submitted
          ? schedule.collectedAt
          : null;
  final collectedAt = submittedAt ?? asOf ?? DateTime.now();

  if (schedule.isOpenTerm) {
    if (calculateDaysLate(dueAt: schedule.lateFrom, collectedAt: collectedAt) <=
        0) {
      return PenaltyResult.none;
    }

    return _openTermStretchPenalty(
      row: schedule,
      loan: loan,
      collectedAt: collectedAt,
      loanRows: loanRows,
      onEarliestUnchargedOnly: true,
    );
  }

  return computePenalties(
    amountDue: schedule.amortization,
    penalties: loan.penalties,
    daysLate: calculateDaysLate(
      dueAt: schedule.lateFrom,
      collectedAt: collectedAt,
    ),
    termDays: termDaysOf(loan.term),
  );
}

/// The confirmation-time decision for one installment.
final class LatenessResult {
  const LatenessResult({
    required this.daysLate,
    required this.isLate,
    required this.penalties,
  });

  /// Calendar days after the due date, recorded even when [isLate] is false.
  final int daysLate;

  /// True when collected after the due date on a loan that does not allow
  /// late payments. Drives the paid_late status.
  final bool isLate;

  /// Empty unless [isLate].
  final PenaltyResult penalties;
}

/// Decide lateness and penalties for a payment collected on [collectedAt].
/// Unlike [previewPenalty] this ignores the row's current status, because
/// the caller is about to set it. An open-term placeholder row is never
/// late.
///
/// Days late are per bill, from the bill's own due date. On an open-term
/// loan the penalty is the overdue stretch's, less what earlier payments in
/// the same stretch already charged (R3); [loanRows] are the loan's other
/// rows, stored and computed, that tell where the stretch starts.
LatenessResult resolveLateness({
  required LoanSchedule schedule,
  required Loan loan,
  required DateTime collectedAt,
  List<LoanSchedule> loanRows = const [],
}) =>
    _resolveLateness(
      schedule: schedule,
      loan: loan,
      collectedAt: collectedAt,
      loanRows: loanRows,
    );

/// [resolveLateness] for [schedules] collected together on [collectedAt],
/// in the order given. An open-term stretch penalty is charged once, on the
/// earliest late bill; the other bills of the same payment are late with
/// nothing more to charge. Fixed-term rows are resolved one by one.
List<LatenessResult> resolveLatenessTogether({
  required List<LoanSchedule> schedules,
  required Loan loan,
  required DateTime collectedAt,
  List<LoanSchedule> loanRows = const [],
}) {
  final byLateFrom = List<LoanSchedule>.of(schedules)
    ..sort((a, b) => a.lateFrom.compareTo(b.lateFrom));
  final context = [...loanRows, ...schedules];
  final results = Map<LoanSchedule, LatenessResult>.identity();
  final settled = <LoanSchedule>[];

  for (final schedule in byLateFrom) {
    results[schedule] = _resolveLateness(
      schedule: schedule,
      loan: loan,
      collectedAt: collectedAt,
      loanRows: context,
      paidNow: settled,
    );
    settled.add(schedule);
  }

  return [for (final schedule in schedules) results[schedule]!];
}

LatenessResult _resolveLateness({
  required LoanSchedule schedule,
  required Loan loan,
  required DateTime collectedAt,
  required List<LoanSchedule> loanRows,
  List<LoanSchedule> paidNow = const [],
}) {
  if (schedule.isPlaceholder || schedule.isPrincipalRelease) {
    return const LatenessResult(
      daysLate: 0,
      isLate: false,
      penalties: PenaltyResult.none,
    );
  }

  final daysLate = calculateDaysLate(
    dueAt: schedule.lateFrom,
    collectedAt: collectedAt,
  );
  final isLate = daysLate > 0 && !loan.allowLatePayments;

  return LatenessResult(
    daysLate: daysLate,
    isLate: isLate,
    penalties: !isLate
        ? PenaltyResult.none
        : schedule.isOpenTerm
            ? _openTermStretchPenalty(
                row: schedule,
                loan: loan,
                collectedAt: collectedAt,
                loanRows: loanRows,
                paidNow: paidNow,
              )
            : computePenalties(
                amountDue: schedule.amortization,
                penalties: loan.penalties,
                daysLate: daysLate,
                termDays: termDaysOf(loan.term),
              ),
  );
}

/// Owner rule R3 (2026-11-19): an open-term penalty is on the loan's
/// balance, so it is charged once for the loan, not once per missed bill.
/// An overdue stretch runs from the earliest unpaid due date until no bill
/// is late. "Once" is charged once per stretch; daily per day of the
/// stretch; monthly and per installment per started period of the stretch.
/// A payment is charged the stretch's penalty up to [collectedAt] less what
/// earlier payments in the same stretch were charged up to their own
/// collection dates (waived counts as charged), so no day is charged twice.
///
/// [row] is late at [collectedAt]. [paidNow] are other rows settled in the
/// same payment, already charged. A submitted bill not yet confirmed ends
/// its lateness at its transfer but has not been charged anything (review
/// of #146: two bills in one submission still owe the stretch once). With
/// [onEarliestUnchargedOnly] (previews) the stretch shows on its earliest
/// bill not yet charged and 0 on the others.
PenaltyResult _openTermStretchPenalty({
  required LoanSchedule row,
  required Loan loan,
  required DateTime collectedAt,
  required Iterable<LoanSchedule> loanRows,
  Iterable<LoanSchedule> paidNow = const [],
  bool onEarliestUnchargedOnly = false,
}) {
  final collectedOn = _localDay(collectedAt);
  final ownDue = _localDay(row.lateFrom);
  var start = ownDue;
  final unchargedDues = <DateTime>[];
  final latePeriods = <(DateTime, DateTime, bool)>[];

  for (final other in loanRows) {
    if (!_isOpenTermBill(other) || _sameRow(other, row)) {
      continue;
    }

    final dueOn = _localDay(other.lateFrom);
    if (!dueOn.isBefore(collectedOn)) {
      continue;
    }

    final inThisPayment = paidNow.any((paid) => _sameRow(paid, other));
    final settledAt = inThisPayment ? collectedAt : _settledOn(other);
    if (settledAt == null) {
      // Unpaid and late on the collection day: the same stretch.
      unchargedDues.add(dueOn);
      if (dueOn.isBefore(start)) {
        start = dueOn;
      }
    } else if (_localDay(settledAt).isAfter(dueOn)) {
      // A submitted bill not yet confirmed has been charged nothing.
      final charged =
          inThisPayment || other.status != LoanStatus.payment_submitted;
      latePeriods.add((dueOn, _localDay(settledAt), charged));
    }
  }

  // Late periods that ran into the stretch belong to it.
  for (var grew = true; grew;) {
    grew = false;
    for (final (dueOn, settledOn, _) in latePeriods) {
      if (dueOn.isBefore(start) && settledOn.isAfter(start)) {
        start = dueOn;
        grew = true;
      }
    }
  }

  // Only a bill that is not merely submitted has been charged.
  DateTime? chargedTo;
  for (final (dueOn, settledOn, charged) in latePeriods) {
    if (!settledOn.isAfter(start)) {
      continue;
    }
    if (!charged) {
      unchargedDues.add(dueOn);
      continue;
    }
    final end = settledOn.isAfter(collectedOn) ? collectedOn : settledOn;
    if (chargedTo == null || end.isAfter(chargedTo)) {
      chargedTo = end;
    }
  }

  if (onEarliestUnchargedOnly &&
      unchargedDues.any((dueOn) => dueOn.isBefore(ownDue))) {
    return PenaltyResult.none;
  }

  final daysNow = collectedOn.difference(start).inDays;
  final daysCharged =
      chargedTo == null ? 0 : chargedTo.difference(start).inDays;
  final termDays = termDaysOf(loan.term);
  final balanceOn = _balanceOn(row: row, loan: loan);
  final lines = <PenaltyLine>[];
  var total = 0.0;

  for (final penalty in loan.penalties) {
    final periodsBefore =
        penalty.frequency.periods(daysCharged, termDays: termDays);
    final periods =
        penalty.frequency.periods(daysNow, termDays: termDays) - periodsBefore;
    if (periods <= 0) {
      continue;
    }

    // A percentage is of the balance in force on the day each charged
    // period starts (review of #146: a top-up mid-stretch raises the base
    // from its day only, whichever bill is charged).
    final periodDays = switch (penalty.frequency) {
      PenaltyFrequency.once => 0,
      PenaltyFrequency.daily => 1,
      PenaltyFrequency.monthly => 30,
      PenaltyFrequency.perInstallment => termDays < 1 ? 30 : termDays,
    };
    var amount = 0.0;
    for (var period = periodsBefore; period < periodsBefore + periods;) {
      final periodStart =
          DateTime(start.year, start.month, start.day + period * periodDays);
      amount += penalty.isPercentage
          ? balanceOn(periodStart) * penalty.amount / 100
          : penalty.amount;
      period++;
    }

    lines.add(PenaltyLine(penalty: penalty, periods: periods, amount: amount));
    total += amount;
  }

  return lines.isEmpty
      ? PenaltyResult.none
      : PenaltyResult(lines: lines, total: total);
}

/// The loan's balance in force on a day, worked out from [row]'s balance
/// (in force on its due day) and the loan's approved top-ups, each in force
/// from the day it was approved (`effectiveAt`). Only approved top-ups
/// released money (#137).
double Function(DateTime day) _balanceOn({
  required LoanSchedule row,
  required Loan loan,
}) {
  final rowDay = _localDay(row.dueAt);
  final topUps = [
    for (final topUp in loan.additionalLoanAmounts)
      if (topUp.status == LoanStatus.approved)
        (
          day: _localDay(topUp.effectiveAt),
          added: topUp.amount + topUp.additionalCharges
        ),
  ];

  return (day) {
    var balance = row.outstandingBalance;
    for (final topUp in topUps) {
      if (day.isBefore(topUp.day) && !topUp.day.isAfter(rowDay)) {
        balance -= topUp.added;
      } else if (rowDay.isBefore(topUp.day) && !topUp.day.isAfter(day)) {
        balance += topUp.added;
      }
    }
    return balance;
  };
}

bool _isOpenTermBill(LoanSchedule schedule) =>
    schedule.isOpenTerm &&
    !schedule.isPlaceholder &&
    !schedule.isPrincipalRelease;

bool _sameRow(LoanSchedule a, LoanSchedule b) =>
    identical(a, b) || (a.id != NO_ID && a.id == b.id);

const _paidStatuses = {LoanStatus.paid_on_time, LoanStatus.paid_late};

/// When an open-term bill stopped being late, or null while it is unpaid. A
/// borrower submission records its transfer time as `collectedAt`, so a
/// submitted bill stops being late then, whichever bill is confirmed first;
/// it counts as charged only once it is no longer payment_submitted.
DateTime? _settledOn(LoanSchedule schedule) =>
    schedule.collectedAt ??
    (_paidStatuses.contains(schedule.status)
        ? (schedule.paidAt ?? schedule.dueAt)
        : null);

/// [dateTime]'s calendar day in local time.
DateTime _localDay(DateTime dateTime) {
  final local = dateTime.toLocal();
  return DateTime(local.year, local.month, local.day);
}
