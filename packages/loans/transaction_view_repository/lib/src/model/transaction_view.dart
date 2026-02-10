import 'package:loan_repository/loan_repository.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:transaction_view_repository/src/model/transaction_view_entity.dart';

class TransactionView extends TransactionViewEntity implements BaseModel<TransactionViewEntity> {
  TransactionView() : super();

  factory TransactionView.create({
    required String transactionId,
    required String userFullName,
    required String providerCompanyName,
    required LoanStatus loanStatus,
    required String loanType,
  }) {
    final now = DateTime.timestamp();
    return TransactionView()
      ..createdAt = now
      ..updatedAt = now
      ..id = NO_ID
      ..transactionId = transactionId
      ..userFullName = userFullName
      ..providerCompanyName = providerCompanyName
      ..loanType = loanType
      ..loanStatus = loanStatus;
  }

  @override
  TransactionViewEntity toEntity() {
    return this;
  }
}
