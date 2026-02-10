import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:review_repository/src/model/review.dart';

part 'review_entity.g.dart';

@JsonSerializable()
class ReviewEntity implements BaseEntity {

  ReviewEntity();

  ReviewEntity._({
    required this.createdAt,
    required this.updatedAt,
    required this.id,
    required this.providerId,
    required this.userId,
    required this.userFullName,
    required this.message,
    required this.rating,
  });

  factory ReviewEntity.fromJson(Map<String, dynamic> json) {
    return _$ReviewEntityFromJson(json);
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

  @JsonKey(name: 'product_id')
  String? productId;

  @JsonKey(name: 'user_id')
  late String userId;

  @JsonKey(name: 'user_full_name')
  late String userFullName;

  late String message;

  late int rating;

  @override
  List<Object?> get props => [
        createdAt,
        updatedAt,
        id,
        providerId,
        deletedAt,
        userId,
        userFullName,
        message,
        rating,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$ReviewEntityToJson(this);
  }

  Review toReview() {
    return Review()
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..id = id
      ..providerId = providerId
      ..deletedAt = deletedAt
      ..userId = userId
      ..userFullName = userFullName
      ..message = message
      ..rating = rating;
  }
}
