import 'package:bank_details_repository/src/model/bank_details.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'bank_details_entity.g.dart';

@JsonSerializable()
class BankDetailsEntity implements BaseEntity {

  BankDetailsEntity();

  BankDetailsEntity._({
    required this.createdAt,
    required this.updatedAt,
    required this.id,
    required this.dataId,
    required this.dataType,
    required this.bankName,
    required this.accountNumber,
    required this.accountName,
  });

  factory BankDetailsEntity.fromJson(Map<String, dynamic> json) {
    return _$BankDetailsEntityFromJson(json);
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

  late String dataId;

  @JsonKey(name: 'data_type')
  late DataType dataType;

  @JsonKey(name: 'bank_name')
  late String bankName;

  @JsonKey(name: 'account_number')
  late String accountNumber;

  @JsonKey(name: 'account_name')
  late String accountName;

  @override
  List<Object?> get props => [
        createdAt,
        updatedAt,
        id,
        dataId,
        dataType,
        bankName,
        accountNumber,
        accountName,
        deletedAt,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$BankDetailsEntityToJson(this);
  }

  BankDetails toBankDetails() {
    return BankDetails()
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..id = id
      ..dataId = dataId
      ..dataType = dataType
      ..bankName = bankName
      ..accountNumber = accountNumber
      ..accountName = accountName
      ..deletedAt = deletedAt;
  }
}
