import 'package:capital_repository/src/model/capital.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'capital_entity.g.dart';

@JsonSerializable()
class CapitalEntity implements BaseEntity {
  CapitalEntity();

  CapitalEntity._({
    required this.createdAt,
    required this.updatedAt,
    required this.id,
    required this.providerId,
    required this.amount,
  });

  factory CapitalEntity.fromJson(Map<String, dynamic> json) {
    return _$CapitalEntityFromJson(json);
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

  @JsonKey(name: 'provider_id')
  late String providerId;

  late double amount;

  @override
  List<Object?> get props => [
        createdAt,
        updatedAt,
        id,
        providerId,
        amount,
        deletedAt,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$CapitalEntityToJson(this);
  }

  Capital toCapital() {
    return Capital()
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..id = id
      ..providerId = providerId
      ..amount = amount
      ..deletedAt = deletedAt;
  }
}
