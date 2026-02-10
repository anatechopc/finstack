import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:settings_repository/src/model/settings.dart';

part 'settings_entity.g.dart';

@JsonSerializable()
class SettingsEntity implements BaseEntity {
  SettingsEntity();

  SettingsEntity._({
    required this.createdAt,
    required this.updatedAt,
    required this.id,
    required this.userId,
  });

  factory SettingsEntity.fromJson(Map<String, dynamic> json) {
    return _$SettingsEntityFromJson(json);
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

  @JsonKey(
    name: 'use_classic_ui',
    defaultValue: false,
  )
  late bool useClassicUI;

  @JsonKey(
    name: 'force_payment_confirmation',
    defaultValue: false,
  )
  late bool forcePaymentConfirmation;

  @JsonKey(
    name: 'enable_product_add_ons',
    defaultValue: false,
  )
  late bool enableProductAddOns;

  @override
  List<Object?> get props => [
        createdAt,
        updatedAt,
        id,
        userId,
        useClassicUI,
        deletedAt,
        forcePaymentConfirmation,
        enableProductAddOns,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$SettingsEntityToJson(this);
  }

  Settings toSettings() {
    return Settings()
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..id = id
      ..userId = userId
      ..useClassicUI = useClassicUI
      ..deletedAt = deletedAt
      ..forcePaymentConfirmation = forcePaymentConfirmation
      ..enableProductAddOns = enableProductAddOns;
  }
}
