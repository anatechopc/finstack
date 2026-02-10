import 'package:loooans_helpers/data_helpers.dart';
import 'package:review_repository/src/model/review_entity.dart';

class Review extends ReviewEntity implements BaseModel<ReviewEntity> {
  Review() : super();

  factory Review.create({
    required String providerId,
    required String userId,
    required String userFullName,
    required String message,
    required int rating,
  }) {
    final now = DateTime.timestamp();
    return Review()
      ..createdAt = now
      ..updatedAt = now
      ..id = NO_ID
      ..providerId = providerId
      ..userId = userId
      ..userFullName = userFullName
      ..message = message
      ..rating = rating;
  }

  @override
  ReviewEntity toEntity() {
    return this;
  }
}
