import 'package:json_annotation/json_annotation.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:transaction_view_repository/src/model/transaction_view.dart';

part 'transaction_view_entity.g.dart';

@JsonSerializable()
class TransactionViewEntity implements BaseEntity {

  TransactionViewEntity();

  TransactionViewEntity._({
    required this.createdAt,
    required this.updatedAt,
    required this.id,
    required this.transactionId,
    required this.userFullName,
    required this.providerCompanyName,
    required this.loanType,
    required this.loanStatus,
  });

  factory TransactionViewEntity.fromJson(Map<String, dynamic> json) {
    return _$TransactionViewEntityFromJson(json);
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

  @JsonKey(name: 'transaction_id')
  late String transactionId;

  @JsonKey(name: 'user_full_name')
  late String userFullName;

  @JsonKey(name: 'provider_company_name')
  late String providerCompanyName;

  @JsonKey(name: 'loan_type')
  late String loanType;

  @JsonKey(name: 'loan_status')
  LoanStatus? loanStatus;

  @JsonKey(name: 'payment_amount')
  double? paymentAmount;

  double? karma;

  @override
  List<Object?> get props => [
        createdAt,
        updatedAt,
        deletedAt,
        id,
        transactionId,
        userFullName,
        providerCompanyName,
        loanType,
        loanStatus,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$TransactionViewEntityToJson(this);
  }

  TransactionView toTransactionView() {
    return TransactionView()
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..deletedAt = deletedAt
      ..id = id
      ..transactionId = transactionId
      ..userFullName = userFullName
      ..providerCompanyName = providerCompanyName
      ..loanType = loanType
      ..loanStatus = loanStatus;
  }
}
