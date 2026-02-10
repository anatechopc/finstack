import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:user_repository/src/model/device.dart';

part 'device_entity.g.dart';

@JsonSerializable()
class DeviceEntity implements BaseEntity {
  DeviceEntity();

  factory DeviceEntity.fromJson(Map<String, dynamic> json) =>
      _$DeviceEntityFromJson(json);

  @override
  @JsonKey(
    name: 'deleted_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  DateTime? deletedAt;

  @override
  @JsonKey(
    name: 'updated_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  late DateTime updatedAt;

  @JsonKey(
    name: 'created_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  @override
  late DateTime createdAt;

  @override
  late String id;

  late String model;

  late String os;

  /// OS version
  late String version;

  /// FCM token used for notification
  late String token;

  @override
  List<Object?> get props => [
        createdAt,
        updatedAt,
        deletedAt,
        model,
        os,
        version,
        token,
        id,
      ];

  @override
  bool? get stringify => true;

  Device toDevice() {
    return Device()
      ..id = id
      ..model = model
      ..os = os
      ..version = version
      ..token = token
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..deletedAt = deletedAt;
  }

  Map<String, dynamic> toJson() => _$DeviceEntityToJson(this);
}
