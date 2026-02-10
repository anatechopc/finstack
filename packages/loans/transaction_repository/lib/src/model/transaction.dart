import 'package:loooans_helpers/data_helpers.dart';
import 'package:transaction_repository/src/model/transaction_entity.dart';

class Transaction extends TransactionEntity implements BaseModel<TransactionEntity> {
  Transaction() : super();

  factory Transaction.create({
    required String providerId,
    required String userId,
    required String loanId,
    required String paymentId,
    required String karmaId,
  }) {
    final now = DateTime.timestamp();
    return Transaction()
      ..createdAt = now
      ..updatedAt = now
      ..id = NO_ID
      ..providerId = providerId
      ..userId = userId
      ..loanId = loanId
      ..paymentId = paymentId
      ..karmaId = karmaId;
  }

  @override
  TransactionEntity toEntity() {
    return this;
  }
}
