import 'package:equatable/equatable.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:payment_repository/payment_repository.dart';

/// A borrower payment submission awaiting lender confirm/reject.
///
/// A single submission may cover multiple loan schedules (a "pay in full"
/// submission) — all payments sharing the same [submissionId] are grouped
/// here so the lender confirms/rejects them as ONE item.
class PendingSubmission extends Equatable {
  const PendingSubmission({
    required this.submissionId,
    required this.payments,
    required this.loan,
    required this.schedules,
    this.totalAmount,
  });

  final String submissionId;
  final List<Payment> payments;

  /// The loan and the submitted rows, in the same order as [payments], so the
  /// confirm dialog can preview lateness without another round trip.
  final Loan loan;
  final List<LoanSchedule> schedules;

  /// Sum of the linked schedules' amounts, if it could be resolved while
  /// loading. Null when amounts were unavailable.
  final double? totalAmount;

  @override
  List<Object?> get props =>
      [submissionId, payments, loan, schedules, totalAmount];
}
