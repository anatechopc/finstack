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
  static LoanStatus applyLateness({
    required LoanSchedule schedule,
    required Loan loan,
    required DateTime collectedAt,
    required String actorId,
    bool waivePenalty = false,
    String? waiveReason,
  }) {
    final lateness = resolveLateness(
      schedule: schedule,
      loan: loan,
      collectedAt: collectedAt,
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
    final loan = await loanRepository.get(id: schedule.loanId);

    // Decided first so a missing waive reason aborts the whole confirmation.
    final status = applyLateness(
      schedule: schedule,
      loan: loan,
      collectedAt: collectedAt ?? payment.createdAt,
      actorId: confirmedById,
      waivePenalty: waivePenalty,
      waiveReason: waiveReason,
    );

    payment.markConfirmed(confirmedById: confirmedById);
    await paymentRepository.update(data: payment);

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
    payment.markRejected(confirmedById: confirmedById, reason: reason);
    await paymentRepository.update(data: payment);

    final schedule =
        await loanScheduleRepository.get(id: payment.loanScheduleId);
    schedule
      ..paidAt = null
      ..paymentId = null
      ..status = revertedStatus(dueAt: schedule.dueAt);
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
