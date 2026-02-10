import 'package:karma_transaction_repository/src/model/karma_transaction_entity.dart';
import 'package:loooans_helpers/data_helpers.dart';

class KarmaTransaction extends KarmaTransactionEntity implements BaseModel<KarmaTransactionEntity> {
  KarmaTransaction() : super();

  factory KarmaTransaction.create({
    required String userId,
    required double karma,
    required String description,
  }) {
    final now = DateTime.timestamp();
    return KarmaTransaction()
      ..createdAt = now
      ..updatedAt = now
      ..id = NO_ID
      ..userId = userId
      ..karma = karma
      ..description = description;
  }

  @override
  KarmaTransactionEntity toEntity() {
    return this;
  }
}
