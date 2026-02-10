import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:transaction_repository/src/model/transaction.dart';

part 'transaction_entity.g.dart';

@JsonSerializable()
class TransactionEntity implements BaseEntity {

  TransactionEntity();

  TransactionEntity._({
    required this.createdAt,
    required this.updatedAt,
    required this.id,
    required this.providerId,
    required this.userId,
    required this.loanId,
    required this.paymentId,
    required this.karmaId,
  });

  factory TransactionEntity.fromJson(Map<String, dynamic> json) {
    return _$TransactionEntityFromJson(json);
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

  @JsonKey(name: 'provider_id')
  late String providerId;

  @JsonKey(name: 'user_id')
  late String userId;

  @JsonKey(name: 'loan_id')
  late String loanId;

  @JsonKey(name: 'payment_id')
  late String paymentId;

  @JsonKey(name: 'karma_id')
  late String karmaId;

  @override
  List<Object?> get props => [
        createdAt,
        updatedAt,
        id,
        providerId,
        deletedAt,
        userId,
        loanId,
        paymentId,
        karmaId,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$TransactionEntityToJson(this);
  }

  Transaction toTransaction() {
    return Transaction()
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..id = id
      ..providerId = providerId
      ..deletedAt = deletedAt
      ..userId = userId
      ..loanId = loanId
      ..paymentId = paymentId
      ..karmaId = karmaId;
  }
}
