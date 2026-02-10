import 'package:loooans_helpers/data_helpers.dart';
import 'package:notification_repository/src/model/notification_data.dart';
import 'package:notification_repository/src/model/notification_entity.dart';
import 'package:notification_repository/src/model/notification_priority.dart';

class Notification extends NotificationEntity
    implements BaseModel<NotificationEntity> {
  Notification() : super();

  factory Notification.create({
    required String recipientId,
    required String title,
    required NotificationData data,
    required String message,
    NotificationPriority priority = NotificationPriority.normal,
  }) {
    final now = DateTime.timestamp();

    return Notification()
      ..id = NO_ID
      ..recipientId = recipientId
      ..message = message
      ..title = title
      ..message = message
      ..dataEntity = data.toEntity()
      ..priority = priority
      ..read = false
      ..createdAt = now
      ..updatedAt = now;
  }

  @override
  NotificationEntity toEntity() {
    return this;
  }

  NotificationData? get data => dataEntity?.toNotificationData();
}
