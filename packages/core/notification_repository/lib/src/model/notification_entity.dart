import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:notification_repository/src/model/notification.dart';
import 'package:notification_repository/src/model/notification_data_entity.dart';
import 'package:notification_repository/src/model/notification_priority.dart';

part 'notification_entity.g.dart';

@JsonSerializable()
class NotificationEntity implements BaseEntity {
  NotificationEntity();

  NotificationEntity._({
    required this.id,
    required this.recipientId,
    required this.title,
    required this.read,
    required this.dataEntity,
    required this.priority,
    required this.createdAt,
    required this.updatedAt,
    required this.message,
  });

  factory NotificationEntity.fromJson(Map<String, dynamic> json) {
    return _$NotificationEntityFromJson(json);
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

  /// id of the user receiving the notification.
  @JsonKey(name: 'recipient_id')
  late String recipientId;

  late String title;

  late String message;

  @JsonKey(defaultValue: false)
  late bool read;

  @JsonKey(
    name: 'data',
    toJson: _handleNotificationActionEntityToJson,
    defaultValue: null,
  )
  NotificationDataEntity? dataEntity;

  @JsonKey(
    name: 'priority',
    defaultValue: NotificationPriority.normal,
  )
  late NotificationPriority priority;

  @override
  List<Object?> get props => [
        id,
        recipientId,
        title,
        message,
        read,
        dataEntity,
        priority,
        createdAt,
        updatedAt,
        deletedAt,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$NotificationEntityToJson(this);
  }

  Notification toNotification() {
    return Notification()
      ..id = id
      ..recipientId = recipientId
      ..title = title
      ..message = message
      ..read = read
      ..dataEntity = dataEntity
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..priority = priority
      ..deletedAt = deletedAt;
  }

  static Map<String, dynamic>? _handleNotificationActionEntityToJson(
      NotificationDataEntity? entity,) {
    return entity?.toJson();
  }
}
