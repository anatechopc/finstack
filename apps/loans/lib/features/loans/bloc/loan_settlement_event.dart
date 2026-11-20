part of 'loan_settlement_bloc.dart';

sealed class LoanSettlementEvent extends Equatable {
  const LoanSettlementEvent();
}

final class SettleAccountEvent extends LoanSettlementEvent {
  const SettleAccountEvent({required this.loanId});

  final String loanId;

  @override
  List<Object?> get props => [loanId];
}

final class ConfirmLoanAccountSettlementEvent extends LoanSettlementEvent {
  const ConfirmLoanAccountSettlementEvent({
    required this.loanId,
    required this.amount,
  });

  final String loanId;

  /// The settlement amount the teller was shown and collected.
  final double amount;

  @override
  List<Object?> get props => [loanId, amount];
}
