import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:review_repository/src/model/review.dart';

part 'review_entity.g.dart';

@JsonSerializable()
class ReviewEntity implements BaseEntity {

  ReviewEntity();

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

  /// Company response to the review. All four `response*` fields are set or
  /// cleared together — see [Review.setResponse] / [Review.clearResponse].
  String? response;

  @JsonKey(
    name: 'responded_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  DateTime? respondedAt;

  @JsonKey(name: 'responded_by_id')
  String? respondedById;

  @JsonKey(name: 'responded_by_name')
  String? respondedByName;

  @override
  List<Object?> get props => [
        createdAt,
        updatedAt,
        id,
        providerId,
        productId,
        deletedAt,
        userId,
        userFullName,
        message,
        rating,
        response,
        respondedAt,
        respondedById,
        respondedByName,
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
      ..productId = productId
      ..deletedAt = deletedAt
      ..userId = userId
      ..userFullName = userFullName
      ..message = message
      ..rating = rating
      ..response = response
      ..respondedAt = respondedAt
      ..respondedById = respondedById
      ..respondedByName = respondedByName;
  }
}
