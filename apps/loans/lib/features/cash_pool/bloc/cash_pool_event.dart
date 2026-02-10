part of 'cash_pool_bloc.dart';

@immutable
sealed class CashPoolEvent {}

final class AddCashPoolRecordEvent extends CashPoolEvent {

  AddCashPoolRecordEvent({
    required this.amount,
    required this.userId,
    required this.option,
    this.comment,
  });
  final double amount;
  final String userId;
  String? comment;
  final ButtonOption option;
}

final class AcknowledgePaymentEvent extends CashPoolEvent {

  AcknowledgePaymentEvent({
    required this.paymentId,
    required this.loanId,
    required this.userId,
    required this.amount,
    this.comment,
  });
  final String paymentId;
  final String loanId;
  final String userId;
  final double amount;
  String? comment;
}

final class DeleteCashPoolEvent extends CashPoolEvent {

  DeleteCashPoolEvent({
    required this.id,
    required this.cashPool,
  });
  final String id;
  final CashPool cashPool;
}

final class GetCashPoolListEvent extends CashPoolEvent {

  GetCashPoolListEvent({
    required this.userId,
  });
  final String userId;
}
