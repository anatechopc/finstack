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
/// [amountDue] is the base of percentages: the missed bill's amount due
/// (`amortization`) for a penalty on the missed bill (see [Penalty.baseFor];
/// penalties on the outstanding balance are counted per overdue stretch by
/// [previewPenalty] and [resolveLateness] instead).
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
/// [loanRows] are the loan's other rows (stored and computed). A penalty on
/// the outstanding balance is charged once for the loan per overdue stretch
/// (owner rule R3), so it is shown on the stretch's earliest unpaid bill and
/// later unpaid bills preview 0 of it; the previews of a loan's rows add up
/// to the stretch's penalty once. A penalty on the missed bill shows on
/// every late bill.
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

  return _penaltiesFor(
    row: schedule,
    loan: loan,
    collectedAt: submittedAt ?? asOf ?? DateTime.now(),
    loanRows: loanRows,
    onEarliestUnchargedOnly: true,
  );
}

/// Whether a penalty of [loan] is on the outstanding balance on rows of
/// this type, so it is charged once per overdue stretch and confirming a
/// row needs the loan's other rows.
bool chargesPerStretch(Loan loan, {required bool isOpenTerm}) =>
    loan.penalties.any(
      (penalty) =>
          penalty.baseFor(isOpenTerm: isOpenTerm) ==
          PenaltyBase.outstandingBalance,
    );

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
/// Days late are per bill, from the bill's own due date. A penalty on the
/// missed bill is the bill's own; one on the outstanding balance is the
/// overdue stretch's, less what earlier payments in the same stretch already
/// charged (R3); [loanRows] are the loan's other rows, stored and computed,
/// that tell where the stretch starts.
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
/// in the order given. A stretch penalty (on the outstanding balance) is
/// charged once, on the earliest late bill; the other bills of the same
/// payment owe nothing more of it. A penalty on the missed bill is charged
/// on each late bill.
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
        : _penaltiesFor(
            row: schedule,
            loan: loan,
            collectedAt: collectedAt,
            loanRows: loanRows,
            paidNow: paidNow,
          ),
  );
}

/// What late [row] owes when collected on [collectedAt], each penalty
/// counted by its base ([Penalty.baseFor], owner rules 2026-11-19): one on
/// the missed bill per bill, a percent of the row's amount due
/// (`amortization`) times its periods for the row's own days late; one on
/// the outstanding balance once for the loan per overdue stretch
/// ([_Stretch]). Lines follow the order of `loan.penalties`.
///
/// [paidNow] are other rows settled in the same payment, already charged.
/// With [onEarliestUnchargedOnly] (previews) a stretch penalty shows on the
/// stretch's earliest bill not yet charged and 0 on the others.
PenaltyResult _penaltiesFor({
  required LoanSchedule row,
  required Loan loan,
  required DateTime collectedAt,
  required Iterable<LoanSchedule> loanRows,
  Iterable<LoanSchedule> paidNow = const [],
  bool onEarliestUnchargedOnly = false,
}) {
  final daysLate =
      calculateDaysLate(dueAt: row.lateFrom, collectedAt: collectedAt);
  if (daysLate <= 0 || loan.penalties.isEmpty) {
    return PenaltyResult.none;
  }

  final termDays = termDaysOf(loan.term);
  _Stretch? stretch;
  final lines = <PenaltyLine>[];
  var total = 0.0;

  for (final penalty in loan.penalties) {
    final PenaltyLine? line;
    if (penalty.baseFor(isOpenTerm: row.isOpenTerm) == PenaltyBase.missedBill) {
      line = computePenalties(
        amountDue: row.amortization,
        penalties: [penalty],
        daysLate: daysLate,
        termDays: termDays,
      ).lines.single;
    } else {
      stretch ??= _Stretch.of(
        row: row,
        loan: loan,
        collectedAt: collectedAt,
        loanRows: loanRows,
        paidNow: paidNow,
      );
      line = onEarliestUnchargedOnly && stretch.shownOnEarlierBill
          ? null
          : stretch.line(penalty, termDays: termDays);
    }

    if (line != null) {
      lines.add(line);
      total += line.amount;
    }
  }

  return lines.isEmpty
      ? PenaltyResult.none
      : PenaltyResult(lines: lines, total: total);
}

/// Owner rule R3 (2026-11-19): a penalty on the outstanding balance is
/// charged once for the loan, not once per missed bill. An overdue stretch
/// runs from the earliest unpaid due date until no bill is late. "Once" is
/// charged once per stretch; daily per day of the stretch; monthly and per
/// installment per started period of the stretch. A payment is charged the
/// stretch's penalty up to its collection date less what earlier payments in
/// the same stretch were charged up to their own collection dates (waived
/// counts as charged), so no day is charged twice.
///
/// A submitted bill not yet confirmed ends its lateness at its transfer but
/// has not been charged anything (review of #146: two bills in one
/// submission still owe the stretch once).
final class _Stretch {
  const _Stretch._({
    required this.start,
    required this.daysNow,
    required this.daysCharged,
    required this.shownOnEarlierBill,
    required this.balanceOn,
  });

  /// The stretch as [row], late at [collectedAt], sees it. [loanRows] are
  /// the loan's rows; only bills of [row]'s loan type count.
  factory _Stretch.of({
    required LoanSchedule row,
    required Loan loan,
    required DateTime collectedAt,
    required Iterable<LoanSchedule> loanRows,
    required Iterable<LoanSchedule> paidNow,
  }) {
    final collectedOn = _localDay(collectedAt);
    final ownDue = _localDay(row.lateFrom);
    var start = ownDue;
    var startRow = row;
    final unchargedDues = <DateTime>[];
    final latePeriods = <(DateTime, DateTime, bool, LoanSchedule)>[];

    for (final other in loanRows) {
      if (!_isBill(other, like: row) || _sameRow(other, row)) {
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
          startRow = other;
        }
      } else if (_localDay(settledAt).isAfter(dueOn)) {
        // A submitted bill not yet confirmed has been charged nothing.
        final charged =
            inThisPayment || other.status != LoanStatus.payment_submitted;
        latePeriods.add((dueOn, _localDay(settledAt), charged, other));
      }
    }

    // Late periods that ran into the stretch belong to it.
    for (var grew = true; grew;) {
      grew = false;
      for (final (dueOn, settledOn, _, other) in latePeriods) {
        if (dueOn.isBefore(start) && settledOn.isAfter(start)) {
          start = dueOn;
          startRow = other;
          grew = true;
        }
      }
    }

    // Only a bill that is not merely submitted has been charged.
    DateTime? chargedTo;
    for (final (dueOn, settledOn, charged, _) in latePeriods) {
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

    // Open-term: the balance in force each day (review of #146: a top-up
    // mid-stretch raises the base from its day only, whichever bill is
    // charged). Fixed-term: the principal still owed on the stretch's first
    // due date, before that bill's principal is paid (its balance is the
    // one after its principal), for the whole stretch.
    final firstBill = startRow;
    final balanceOn = row.isOpenTerm
        ? _balanceOn(row: row, loan: loan)
        : (DateTime _) =>
            firstBill.outstandingBalance + firstBill.principalPayment;

    return _Stretch._(
      start: start,
      daysNow: collectedOn.difference(start).inDays,
      daysCharged: chargedTo == null ? 0 : chargedTo.difference(start).inDays,
      shownOnEarlierBill: unchargedDues.any((dueOn) => dueOn.isBefore(ownDue)),
      balanceOn: balanceOn,
    );
  }

  final DateTime start;
  final int daysNow;
  final int daysCharged;

  /// An earlier bill of the stretch has not been charged yet; previews show
  /// the stretch on it.
  final bool shownOnEarlierBill;

  final double Function(DateTime day) balanceOn;

  /// [penalty]'s periods added since earlier payments of the stretch, or
  /// null when there are none. A percentage is of the balance on the day
  /// each charged period starts.
  PenaltyLine? line(Penalty penalty, {required int termDays}) {
    final periodsBefore =
        penalty.frequency.periods(daysCharged, termDays: termDays);
    final periods =
        penalty.frequency.periods(daysNow, termDays: termDays) - periodsBefore;
    if (periods <= 0) {
      return null;
    }

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

    return PenaltyLine(penalty: penalty, periods: periods, amount: amount);
  }
}

/// The loan's balance in force on a day, worked out from [row]'s balance
/// (in force on its due day) and the loan's approved top-ups, each in force
/// from its own day. Only approved top-ups released money (#137).
double Function(DateTime day) _balanceOn({
  required LoanSchedule row,
  required Loan loan,
}) {
  final rowDay = _localDay(row.dueAt);
  final topUps = [
    for (final topUp in loan.additionalLoanAmounts)
      if (topUp.status == LoanStatus.approved)
        (
          day: _localDay(topUp.createdAt),
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

/// A bill (not a placeholder or the principal release) of [like]'s loan
/// type.
bool _isBill(LoanSchedule schedule, {required LoanSchedule like}) =>
    schedule.isOpenTerm == like.isOpenTerm &&
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
