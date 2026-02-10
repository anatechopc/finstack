import 'package:cash_pool_repository/src/model/cash_pool_entity.dart';
import 'package:cash_pool_repository/src/model/cash_pool_status.dart';
import 'package:loooans_helpers/data_helpers.dart';

class CashPool extends CashPoolEntity implements BaseModel<CashPoolEntity> {
  CashPool() : super();

  factory CashPool.create({
    required String userId,
    required double amount,
    CashPoolStatus status = CashPoolStatus.add_to_pool,
    String? paymentId,
    String? loanId,
    String? comment,
  }) {
    if (status == CashPoolStatus.acknowledged_payment) {
      assert(paymentId != null  && loanId != null, 'PaymentId and loanId must not be null');
    }

    final now = DateTime.timestamp();
    return CashPool()
      ..id = NO_ID
      ..createdAt = now
      ..updatedAt = now
      ..amount = amount
      ..userId = userId
      ..status = status
      ..paymentId = paymentId
      ..loanId = loanId
      ..comment = comment;
  }

  @override
  CashPoolEntity toEntity() {
    return this;
  }
}
