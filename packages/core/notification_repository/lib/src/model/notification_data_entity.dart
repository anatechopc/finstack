import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:notification_repository/src/model/notification_data.dart';
import 'package:notification_repository/src/model/notification_data_type.dart';

part 'notification_data_entity.g.dart';

@JsonSerializable()
class NotificationDataEntity implements BaseEntity {
  NotificationDataEntity();

  NotificationDataEntity._({
    required this.type,
    required this.createdAt,
    required this.updatedAt,
  });

  factory NotificationDataEntity.fromJson(Map<String, dynamic> json) {
    return _$NotificationDataEntityFromJson(json);
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

  late NotificationDataType type;

  @JsonKey(name: 'product_id')
  String? productId;

  @JsonKey(name: 'loan_id')
  String? loanId;

  @JsonKey(name: 'payment_id')
  String? paymentId;

  @JsonKey(name: 'capital_id')
  String? capitalId;

  @JsonKey(name: 'company_id')
  String? companyId;

  @JsonKey(name: 'review_id')
  String? reviewId;

  @JsonKey(name: 'user_id')
  String? userId;

  @JsonKey(name: 'karma_id')
  String? karmaId;

  @override
  List<Object?> get props =>
      [
        type,
        companyId,
        productId,
        userId,
        createdAt,
        updatedAt,
        deletedAt,
        id,
        paymentId,
        capitalId,
        loanId,
        reviewId,
        karmaId,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$NotificationDataEntityToJson(this);
  }

  NotificationData toNotificationData() {
    return NotificationData()
      ..type = type
      ..companyId = companyId
      ..productId = productId
      ..userId = userId
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..deletedAt = deletedAt
      ..paymentId = paymentId
      ..id = id
      ..capitalId = capitalId
      ..loanId = loanId
      ..reviewId = reviewId
      ..karmaId = karmaId;
  }
}
