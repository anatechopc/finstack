import 'package:loooans_helpers/data_helpers.dart';
import 'package:notification_repository/notification_repository.dart';
import 'package:notification_repository/src/model/notification_data_entity.dart';

class NotificationData extends NotificationDataEntity implements BaseModel<NotificationDataEntity> {
  NotificationData() : super();

  factory NotificationData.create({
    required NotificationDataType type,
    String? companyId,
    String? productId,
    String? userId,
    String? paymentId,
    String? capitalId,
    String? loanId,
    String? reviewId,
    String? karmaId,
  }) {
    final now = DateTime.now().toUtc();

    return NotificationData()
      ..type = type
      ..companyId = companyId
      ..productId = productId
      ..userId = userId
      ..createdAt = now
      ..updatedAt = now
      ..paymentId = paymentId
      ..id = NO_ID
      ..capitalId = capitalId
      ..loanId = loanId
      ..reviewId = reviewId
      ..karmaId = karmaId;
  }

  @override
  NotificationDataEntity toEntity() {
    return this;
  }
}
