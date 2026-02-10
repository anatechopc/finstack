import 'package:json_annotation/json_annotation.dart';
import 'package:karma_transaction_repository/src/model/karma_transaction.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'karma_transaction_entity.g.dart';

@JsonSerializable()
class KarmaTransactionEntity implements BaseEntity {

  KarmaTransactionEntity();

  KarmaTransactionEntity._({
    required this.createdAt,
    required this.updatedAt,
    required this.id,
    required this.userId,
    required this.karma,
    required this.description,
  });

  factory KarmaTransactionEntity.fromJson(Map<String, dynamic> json) {
    return _$KarmaTransactionEntityFromJson(json);
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

  late double karma;

  late String description;

  @override
  List<Object?> get props => [
        createdAt,
        updatedAt,
        deletedAt,
        id,
        userId,
        karma,
        description,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$KarmaTransactionEntityToJson(this);
  }

  KarmaTransaction toKarmaTransaction() {
    return KarmaTransaction()
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..deletedAt = deletedAt
      ..id = id
      ..userId = userId
      ..karma = karma
      ..description = description;
  }
}
