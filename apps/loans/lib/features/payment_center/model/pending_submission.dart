import 'package:equatable/equatable.dart';
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
    this.totalAmount,
  });

  final String submissionId;
  final List<Payment> payments;

  /// Sum of the linked schedules' amounts, if it could be resolved while
  /// loading. Null when amounts were unavailable.
  final double? totalAmount;

  @override
  List<Object?> get props => [submissionId, payments, totalAmount];
}
