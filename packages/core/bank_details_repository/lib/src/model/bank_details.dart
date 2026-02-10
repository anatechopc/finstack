import 'package:bank_details_repository/src/model/bank_details_entity.dart';
import 'package:loooans_helpers/data_helpers.dart';

class BankDetails extends BankDetailsEntity
    implements BaseModel<BankDetailsEntity> {
  BankDetails() : super();

  factory BankDetails.create({
    required String dataId,
    required DataType dataType,
    required String bankName,
    required String accountNumber,
    required String accountName,
  }) {
    final now = DateTime.timestamp();
    return BankDetails()
      ..createdAt = now
      ..updatedAt = now
      ..id = NO_ID
      ..dataId = dataId
      ..dataType = dataType
      ..bankName = bankName
      ..accountNumber = accountNumber
      ..accountName = accountName;
  }

  @override
  BankDetailsEntity toEntity() {
    return this;
  }

  @override
  String toString() {
    return 'Bank details: '
        'user: $dataId'
        'type: $dataType'
        'bankName: $bankName'
        'accountNo.: $accountNumber'
        'accountName: $accountName';
  }
}
