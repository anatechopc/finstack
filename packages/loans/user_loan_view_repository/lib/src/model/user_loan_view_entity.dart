import 'package:json_annotation/json_annotation.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:user_loan_view_repository/src/model/user_loan_view.dart';

part 'user_loan_view_entity.g.dart';

@JsonSerializable()
class UserLoanViewEntity implements BaseEntity {
  UserLoanViewEntity();

  UserLoanViewEntity._({
    required this.createdAt,
    required this.updatedAt,
    required this.id,
    required this.userId,
    required this.loanId,
    required this.loanType,
    required this.userFullName,
    required this.loanCreatedAt,
    required this.loanDueAt,
    required this.loanStatus,
    required this.productId,
    required this.companyName,
    required this.amount,
    required this.companyId,
    required this.amortization,
  });

  factory UserLoanViewEntity.fromJson(Map<String, dynamic> json) {
    return _$UserLoanViewEntityFromJson(json);
  }

  @JsonKey(
    name: 'created_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  @override
  late DateTime createdAt;

  @JsonKey(
    name: 'deleted_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  @override
  DateTime? deletedAt;

  @JsonKey(
    name: 'updated_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  @override
  late DateTime updatedAt;

  @override
  late String id;

  @JsonKey(name: 'user_id')
  late String userId;

  @JsonKey(name: 'loan_id')
  late String loanId;

  @JsonKey(name: 'product_id')
  late String productId;

  @JsonKey(name: 'loan_type')
  late String loanType;

  @JsonKey(name: 'user_full_name')
  late String userFullName;

  @JsonKey(
    name: 'loan_created_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  late DateTime loanCreatedAt;

  @JsonKey(
    name: 'loan_due_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  late DateTime? loanDueAt;

  @JsonKey(name: 'loan_status')
  late LoanStatus loanStatus;

  @JsonKey(name: 'company_name')
  late String companyName;

  @JsonKey(name: 'company_id')
  late String companyId;

  late double amount;

  late double amortization;

  @override
  List<Object?> get props => [
        createdAt,
        updatedAt,
        deletedAt,
        id,
        userId,
        loanId,
        loanType,
        userFullName,
        loanCreatedAt,
        loanDueAt,
        loanStatus,
        productId,
        companyName,
        amount,
        companyId,
        amortization,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$UserLoanViewEntityToJson(this);
  }

  UserLoanView toUserLoanView() {
    return UserLoanView()
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..deletedAt = deletedAt
      ..id = id
      ..userId = userId
      ..loanId = loanId
      ..loanType = loanType
      ..userFullName = userFullName
      ..loanCreatedAt = loanCreatedAt
      ..loanDueAt = loanDueAt
      ..loanStatus = loanStatus
      ..productId = productId
      ..companyName = companyName
      ..amount = amount
      ..companyId = companyId
      ..amortization = amortization;
  }
}
