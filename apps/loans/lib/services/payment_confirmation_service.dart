import 'dart:math';

import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:payment_repository/payment_repository.dart';

/// Shared rules for marking a [LoanSchedule] paid (on confirm) or reverted
/// (on reject). Used by both the teller Payment Center flow and the new
/// borrower-submission confirm/reject flow so the rules live in one place.
class PaymentConfirmationService {
  PaymentConfirmationService({
    required this.loanScheduleRepository,
    required this.loanRepository,
    required this.paymentRepository,
  });

  final LoanScheduleRepository loanScheduleRepository;
  final LoanRepository loanRepository;
  final PaymentRepository paymentRepository;

  /// Applies the collection-date rule to [schedule] in place and returns the
  /// status to persist. Every confirmation path (client-detail teller flow,
  /// Payment Center single and bulk-overdue flows, borrower-submission
  /// confirm) routes through here so "late" means one thing app-wide
  /// (loooans#71, loooans#72, loooans#78).
  ///
  /// Throws before touching the row when [waivePenalty] is set without a
  /// reason and there is something to waive.
  ///
  /// [loanRows] are the loan's other rows (stored and computed). An
  /// open-term penalty is charged once per overdue stretch (owner rule R3):
  /// rows of the same payment confirmed earlier carry it, and this row is
  /// charged only what the stretch added since.
  static LoanStatus applyLateness({
    required LoanSchedule schedule,
    required Loan loan,
    required DateTime collectedAt,
    required String actorId,
    bool waivePenalty = false,
    String? waiveReason,
    List<LoanSchedule> loanRows = const [],
  }) {
    final lateness = resolveLateness(
      schedule: schedule,
      loan: loan,
      collectedAt: collectedAt,
      loanRows: loanRows,
    );
    final waived = waivePenalty && lateness.penalties.total > 0;
    final reason = waiveReason?.trim() ?? '';

    if (waived && reason.isEmpty) {
      throw Exception('A reason is required to waive penalties');
    }

    schedule
      ..collectedAt = collectedAt
      ..daysLate = lateness.daysLate
      ..penalties = lateness.isLate ? List<Penalty>.of(loan.penalties) : []
      ..penalty = waived ? 0 : lateness.penalties.total
      ..penaltyWaivedBy = waived ? actorId : null
      ..penaltyWaiveReason = waived ? reason : null;

    return lateness.isLate ? LoanStatus.paid_late : LoanStatus.paid_on_time;
  }

  /// Owner rule R4 for a bulk payment of open-term bills: [totalInterest]
  /// pays them oldest first, each up to its amount due (`amortization`). A
  /// bill that gets nothing stays unpaid; a short one carries the rest to
  /// the next bill. Anything above the total due stays on the last bill, as
  /// on a single bill (no credit). [schedules] must be in due-date order.
  static List<double> splitOpenTermInterest({
    required List<LoanSchedule> schedules,
    required double totalInterest,
  }) {
    var left = totalInterest;
    final shares = <double>[];
    for (var i = 0; i < schedules.length; i++) {
      final share = i == schedules.length - 1
          ? left
          : min(left, schedules[i].amortization);
      shares.add(max<double>(0, share));
      left -= share;
    }

    return shares;
  }

  /// Throws when [schedules] include the open-term principal release, which
  /// is never a payment: recording it would book the whole principal as
  /// repaid on the day it was released (finstack#138).
  static void rejectPrincipalRelease(Iterable<LoanSchedule> schedules) {
    if (schedules.any((s) => s.isPrincipalRelease)) {
      throw Exception('The principal release is not a payment');
    }
  }

  /// Records a teller payment of [interestPayment] and [principalPayment] on
  /// [schedule] with the balance left after it. Every teller path (client
  /// detail, Payment Center single and bulk) routes through here.
  ///
  /// A fixed-term row already holds the balance after its scheduled
  /// principal, so only the difference from that principal moves it (#140:
  /// subtracting the whole payment again under-billed the rest of the
  /// schedule). Principal above the schedule is the row's extra payment. An
  /// open-term row holds the balance before the payment.
  static void recordTellerPayment(
    LoanSchedule schedule, {
    required double interestPayment,
    required double principalPayment,
  }) {
    if (schedule.isOpenTerm) {
      schedule.outstandingBalance -= principalPayment - schedule.extraPayment;
    } else {
      final extraPayment = principalPayment - schedule.principalPayment;
      if (extraPayment > 0.0) {
        schedule.extraPayment = extraPayment;
      }
      schedule.outstandingBalance -= extraPayment;
    }

    schedule
      ..interestPayment = interestPayment
      ..principalPayment = principalPayment;
  }

  /// A submitted open-term bill is settled, for the overdue stretch, at its
  /// transfer (review of #146): rows submitted before submissions recorded
  /// it on the row get it from their payment here, in memory.
  static Future<void> settleSubmittedAtTheirTransfer(
    List<LoanSchedule> rows,
    PaymentRepository paymentRepository,
  ) async {
    for (final row in rows) {
      final paymentId = row.paymentId;
      if (row.status == LoanStatus.payment_submitted &&
          row.collectedAt == null &&
          paymentId != null &&
          paymentId.isNotEmpty) {
        row.collectedAt =
            (await paymentRepository.get(id: paymentId)).createdAt;
      }
    }
  }

  /// Throws when [loan] is settled: confirming a submission then would
  /// collect it a second time and move the loan back to paid, rejecting it
  /// would move the loan back to not paid (review of #157). Nothing is
  /// written.
  static void rejectSettled(Loan loan) {
    if (loan.status == LoanStatus.completed) {
      throw Exception(
        'This loan is settled: its pending payment can no longer be '
        'confirmed or rejected',
      );
    }
  }

  /// Pure: on rejection, a schedule reverts to not_paid (or overdue if its
  /// dueAt is already past).
  static LoanStatus revertedStatus({required DateTime dueAt}) {
    return dueAt.toLocal().isBefore(DateTime.now())
        ? LoanStatus.not_paid_overdue
        : LoanStatus.not_paid;
  }

  /// Confirm a borrower-submitted [payment]: persist the confirmed payment,
  /// mark its schedule paid, and advance the loan status to match.
  ///
  /// [collectedAt] defaults to when the borrower submitted the transfer, not
  /// when a teller got round to confirming it (loooans#71).
  Future<void> confirm({
    required Payment payment,
    required String confirmedById,
    DateTime? collectedAt,
    bool waivePenalty = false,
    String? waiveReason,
  }) async {
    final schedule =
        await loanScheduleRepository.get(id: payment.loanScheduleId);
    rejectPrincipalRelease([schedule]);
    final loan = await loanRepository.get(id: schedule.loanId);
    rejectSettled(loan);
    // A penalty on the balance is one per overdue stretch (R3): rows of the
    // same submission confirmed before this one are stored with their
    // collection date, and unpaid earlier bills mark where the stretch
    // starts.
    final loanRows =
        schedule.isOpenTerm || chargesPerStretch(loan, isOpenTerm: false)
            ? await _loadLoanSchedules(loan.id)
            : const <LoanSchedule>[];
    await settleSubmittedAtTheirTransfer(loanRows, paymentRepository);

    // Decided first so a missing waive reason aborts the whole confirmation.
    final status = applyLateness(
      schedule: schedule,
      loan: loan,
      collectedAt: collectedAt ?? payment.createdAt,
      actorId: confirmedById,
      waivePenalty: waivePenalty,
      waiveReason: waiveReason,
      loanRows: loanRows,
    );

    payment.markConfirmed(confirmedById: confirmedById);
    await paymentRepository.update(data: payment);

    // The borrower paid the amount shown, interest only: a submission
    // carries no principal (#138: a planned row kept the whole principal as
    // repaid). Recording the interest lets a row from the old clamp (more
    // interest charged than shown) carry the rest to the next bill (R4).
    if (schedule.isOpenTerm) {
      schedule.principalPayment = 0;
      if (schedule.interestPayment <= 0) {
        schedule.interestPayment = schedule.amortization;
      }
    }

    schedule
      ..paidAt = DateTime.timestamp()
      ..paymentId = payment.id
      ..status = status;
    await loanScheduleRepository.update(data: schedule);

    await _advanceLoanStatus(loan, schedule.status);
  }

  /// Reject a borrower-submitted [payment]: keep it as an audit record but
  /// free its schedule so the borrower can resubmit.
  Future<void> reject({
    required Payment payment,
    required String confirmedById,
    required String reason,
  }) async {
    final schedule =
        await loanScheduleRepository.get(id: payment.loanScheduleId);
    final loan = await loanRepository.get(id: schedule.loanId);
    rejectSettled(loan);

    payment.markRejected(confirmedById: confirmedById, reason: reason);
    await paymentRepository.update(data: payment);

    schedule
      ..paidAt = null
      ..paymentId = null
      // Unpaid again: no longer settled for the overdue stretch.
      ..collectedAt = null
      ..status = revertedStatus(dueAt: schedule.lateFrom);
    await loanScheduleRepository.update(data: schedule);

    await _advanceLoanStatus(
      await loanRepository.get(id: schedule.loanId),
      schedule.status,
    );
  }

  Future<void> _advanceLoanStatus(Loan loan, LoanStatus status) async {
    var newStatus = status;

    // A fixed-term loan auto-completes once every scheduled payment is paid, so
    // the borrower can review and the pay buttons hide. (This advance runs
    // AFTER the just-paid schedule is persisted, so the count is correct.)
    if (loan.period != 0 &&
        _fixedTermFullyPaid(loan, await _loadLoanSchedules(loan.id))) {
      newStatus = LoanStatus.completed;
    }

    await loanRepository.update(
      data: loan..status = newStatus,
      updateView: true,
    );
  }

  /// Marks the loan [LoanStatus.completed] if every scheduled payment is now
  /// paid. Use from flows that set the loan status themselves BEFORE persisting
  /// the paid schedule (e.g. the teller Payment Center) — call this AFTER the
  /// schedule has been persisted so the paid count is accurate. No-op for
  /// open-term loans or loans already completed.
  Future<void> completeLoanIfFullyPaid(String loanId) async {
    final loan = await loanRepository.get(id: loanId);
    if (loan.period == 0 || loan.status == LoanStatus.completed) return;
    if (_fixedTermFullyPaid(loan, await _loadLoanSchedules(loanId))) {
      await loanRepository.update(
        data: loan..status = LoanStatus.completed,
        updateView: true,
      );
    }
  }

  Future<List<LoanSchedule>> _loadLoanSchedules(String loanId) {
    return loanScheduleRepository.load(
      reset: true,
      limit: null,
      statements: [
        QueryStatement(field: 'loan_id', isEqualTo: loanId),
      ],
    );
  }

  /// True when a fixed-term loan has all of its scheduled payments paid.
  /// Open-term loans (period == 0) are indefinite and never "fully paid" here.
  /// 15-day-term loans have twice the period's number of schedules.
  bool _fixedTermFullyPaid(Loan loan, List<LoanSchedule> schedules) {
    if (loan.period == 0) return false;
    final paidCount = schedules
        .where(
          (s) =>
              s.status == LoanStatus.paid_on_time ||
              s.status == LoanStatus.paid_late,
        )
        .length;
    final expectedSchedules = loan.period * (loan.term == '15d' ? 2 : 1);
    return paidCount >= expectedSchedules;
  }
}
