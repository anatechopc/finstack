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
PenaltyResult computePenalties({
  required double amountDue,
  required List<Penalty> penalties,
  required int daysLate,
}) {
  if (daysLate <= 0 || penalties.isEmpty) {
    return PenaltyResult.none;
  }

  final lines = <PenaltyLine>[];
  var total = 0.0;

  for (final penalty in penalties) {
    final periods = penalty.frequency.periods(daysLate);
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
  LoanStatus.payment_submitted,
};

/// What an unpaid installment would owe in penalties if collected on [asOf]
/// (default: now). Applies the loan's allow-late gate. Used for the red line
/// on schedule rows and for the confirmation breakdown.
PenaltyResult previewPenalty({
  required LoanSchedule schedule,
  required Loan loan,
  DateTime? asOf,
}) {
  if (!_unpaidStatuses.contains(schedule.status) || loan.allowLatePayments) {
    return PenaltyResult.none;
  }

  final daysLate = calculateDaysLate(
    dueAt: schedule.dueAt,
    collectedAt: asOf ?? DateTime.now(),
  );

  return computePenalties(
    amountDue:
        schedule.isOpenTerm ? schedule.outstandingBalance : schedule.amortization,
    penalties: loan.penalties,
    daysLate: daysLate,
  );
}
