import 'package:user_repository/src/model/device_entity.dart';

class Device extends DeviceEntity {
  Device() : super();

  factory Device.create({
    required String instanceId,
    required String model,
    required String os,
    required String version,
    required String token,
  }) {
    final now = DateTime.timestamp();

    return Device()
      ..id = instanceId
      ..model = model
      ..os = os
      ..version = version
      ..token = token
      ..createdAt = now
      ..updatedAt = now;
  }

  DeviceEntity toEntity() {
    return this;
  }
}
