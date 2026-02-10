part of 'loan_settlement_bloc.dart';

sealed class LoanSettlementEvent extends Equatable {
  const LoanSettlementEvent();
}

final class SettleAccountEvent extends LoanSettlementEvent {
  const SettleAccountEvent({
    required this.userId,
    required this.loanId,
  });

  final String userId;
  final String loanId;

  @override
  List<Object?> get props => [userId, loanId];
}

final class ConfirmLoanAccountSettlementEvent extends LoanSettlementEvent {
  const ConfirmLoanAccountSettlementEvent({
    required this.userId,
    required this.loanId,
  });

  final String userId;
  final String loanId;

  @override
  List<Object?> get props => [userId, loanId];
}
