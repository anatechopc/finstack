import 'package:loan_repository/loan_repository.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:user_loan_view_repository/src/model/user_loan_view_entity.dart';

class UserLoanView extends UserLoanViewEntity
    implements BaseModel<UserLoanViewEntity> {
  UserLoanView() : super();

  factory UserLoanView.create({
    required String userId,
    required String loanId,
    required String loanType,
    required String userFullName,
    required DateTime? loanDueAt,
    required DateTime loanCreatedAt,
    required LoanStatus loanStatus,
    required String productId,
    required String companyName,
    required String companyId,
    required double amount,
    required double amortization,
  }) {
    final now = DateTime.timestamp();
    return UserLoanView()
      ..createdAt = now
      ..updatedAt = now
      ..id = NO_ID
      ..userId = userId
      ..loanId = loanId
      ..loanType = loanType
      ..userFullName = userFullName
      ..loanCreatedAt = loanCreatedAt
      ..loanDueAt = loanDueAt
      ..loanStatus = loanStatus
      ..productId = productId
      ..companyName = companyName
      ..companyId = companyId
      ..amount = amount
      ..amortization = amortization;
  }

  @override
  UserLoanViewEntity toEntity() {
    return this;
  }

  String? _reason;

  String get reason {
    return _reason ?? 'No reason';
  }

  set reason(String reason) {
    _reason = reason;
  }
}
