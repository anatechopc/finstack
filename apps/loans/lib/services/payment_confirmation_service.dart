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

  /// Pure: on confirmation, a schedule is paid_on_time unless its dueAt is
  /// already past, in which case it is paid_late.
  ///
  /// Mirrors the teller flow in `PaymentCenterBloc._handleMakePaymentEvent`,
  /// which compares `schedule.dueAt.toLocal()` against `DateTime.now()`.
  static LoanStatus scheduleStatusForConfirmation({required DateTime dueAt}) {
    return dueAt.toLocal().isBefore(DateTime.now())
        ? LoanStatus.paid_late
        : LoanStatus.paid_on_time;
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
  Future<void> confirm({
    required Payment payment,
    required String confirmedById,
  }) async {
    payment.markConfirmed(confirmedById: confirmedById);
    await paymentRepository.update(data: payment);

    final schedule =
        await loanScheduleRepository.get(id: payment.loanScheduleId);
    schedule
      ..paidAt = DateTime.timestamp()
      ..paymentId = payment.id
      ..status = scheduleStatusForConfirmation(dueAt: schedule.dueAt);
    await loanScheduleRepository.update(data: schedule);

    await _advanceLoanStatus(schedule.loanId, schedule.status);
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

    await _advanceLoanStatus(schedule.loanId, schedule.status);
  }

  Future<void> _advanceLoanStatus(String loanId, LoanStatus status) async {
    final loan = await loanRepository.get(id: loanId);
    var newStatus = status;

    // A fixed-term loan (period != 0) auto-completes once every scheduled
    // payment is paid, so the borrower can review and the pay buttons hide.
    // Open-term loans are indefinite — they only complete via settlement.
    if (loan.period != 0) {
      final schedules = await loanScheduleRepository.load(
        reset: true,
        limit: null,
        statements: [
          QueryStatement(field: 'loan_id', isEqualTo: loanId),
        ],
      );
      final paidCount = schedules
          .where(
            (s) =>
                s.status == LoanStatus.paid_on_time ||
                s.status == LoanStatus.paid_late,
          )
          .length;
      // 15-day-term loans have twice the period's number of schedules.
      final expectedSchedules = loan.period * (loan.term == '15d' ? 2 : 1);
      if (paidCount >= expectedSchedules) {
        newStatus = LoanStatus.completed;
      }
    }

    await loanRepository.update(
      data: loan..status = newStatus,
      updateView: true,
    );
  }
}
