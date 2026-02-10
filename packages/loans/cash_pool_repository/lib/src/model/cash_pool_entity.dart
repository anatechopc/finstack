import 'package:cash_pool_repository/src/model/cash_pool.dart';
import 'package:cash_pool_repository/src/model/cash_pool_status.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'cash_pool_entity.g.dart';

@JsonSerializable()
class CashPoolEntity implements BaseEntity {
  CashPoolEntity();

  CashPoolEntity._({
    required this.createdAt,
    required this.updatedAt,
    required this.id,
    required this.amount,
    required this.userId,
    required this.status,
  });

  factory CashPoolEntity.fromJson(Map<String, dynamic> json) {
    return _$CashPoolEntityFromJson(json);
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

  @override
  late String id;

  @JsonKey(
    name: 'updated_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  @override
  late DateTime updatedAt;

  @JsonKey(name: 'user_id')
  late String userId;

  late double amount;

  late CashPoolStatus status;

  /// nullable. If status is acknowledged, this should not be null
  @JsonKey(name: 'loan_id')
  String? loanId;

  /// nullable. If status is acknowledged, this should not be null
  @JsonKey(name: 'payment_id')
  String? paymentId;

  String? comment;

  @override
  List<Object?> get props => [
        createdAt,
        updatedAt,
        id,
        userId,
        amount,
        status,
        loanId,
        paymentId,
        comment,
        deletedAt,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$CashPoolEntityToJson(this);
  }

  CashPool toCashPool() {
    return CashPool()
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..id = id
      ..userId = userId
      ..amount = amount
      ..status = status
      ..loanId = loanId
      ..paymentId = paymentId
      ..comment = comment
      ..deletedAt = deletedAt;
  }
}
