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

  /// Whether the company has posted a response to this review.
  bool get hasResponse => (response ?? '').isNotEmpty;

  /// Set or replace the company response. All four `response*` fields are
  /// written together; [respondedAt] is set to `DateTime.timestamp()`.
  void setResponse({
    required String response,
    required String respondedById,
    required String respondedByName,
  }) {
    this.response = response;
    respondedAt = DateTime.timestamp();
    this.respondedById = respondedById;
    this.respondedByName = respondedByName;
  }

  /// Clear the company response. All four `response*` fields are nulled
  /// together so the document never carries a partial response state.
  void clearResponse() {
    response = null;
    respondedAt = null;
    respondedById = null;
    respondedByName = null;
  }

  @override
  ReviewEntity toEntity() {
    return this;
  }
}
