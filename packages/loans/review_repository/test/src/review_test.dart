// ignore_for_file: prefer_const_constructors

import 'package:flutter_test/flutter_test.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:review_repository/review_repository.dart';
import 'package:review_repository/src/model/review_entity.dart';

void main() {
  group('Review JSON round-trip', () {
    Review makeReview() {
      final at = DateTime.utc(2026, 5, 1, 12);
      return Review()
        ..createdAt = at
        ..updatedAt = at
        ..id = 'r1'
        ..providerId = 'company-1'
        ..productId = 'product-1'
        ..userId = 'user-1'
        ..userFullName = 'Kana Kirisaki'
        ..message = 'Fast approval!'
        ..rating = 5;
    }

    test('round-trip without response preserves fields and leaves response '
        'fields null', () {
      final review = makeReview();

      final entity = ReviewEntity.fromJson(review.toJson());

      expect(entity.id, 'r1');
      expect(entity.providerId, 'company-1');
      expect(entity.productId, 'product-1');
      expect(entity.userId, 'user-1');
      expect(entity.userFullName, 'Kana Kirisaki');
      expect(entity.message, 'Fast approval!');
      expect(entity.rating, 5);
      expect(entity.createdAt, review.createdAt);
      expect(entity.updatedAt, review.updatedAt);
      expect(entity.response, isNull);
      expect(entity.respondedAt, isNull);
      expect(entity.respondedById, isNull);
      expect(entity.respondedByName, isNull);
    });

    test('round-trip with response preserves all response fields', () {
      final review = makeReview()
        ..setResponse(
          response: 'Thanks for your feedback!',
          respondedById: 'admin-1',
          respondedByName: 'Admin Anne',
        );
      final respondedAt = review.respondedAt;

      final entity = ReviewEntity.fromJson(review.toJson());

      expect(entity.response, 'Thanks for your feedback!');
      expect(entity.respondedById, 'admin-1');
      expect(entity.respondedByName, 'Admin Anne');
      // Compare at millis precision — JSON convention is int64 millis, so a
      // microsecond-precision DateTime.timestamp() gets truncated on round-trip
      // (see date-convention memory).
      expect(
        entity.respondedAt?.millisecondsSinceEpoch,
        respondedAt?.millisecondsSinceEpoch,
      );
    });

    test('JSON uses snake_case keys for response fields', () {
      final review = makeReview()
        ..setResponse(
          response: 'Thanks!',
          respondedById: 'admin-1',
          respondedByName: 'Admin Anne',
        );

      final json = review.toJson();

      expect(json.containsKey('response'), isTrue);
      expect(json.containsKey('responded_at'), isTrue);
      expect(json.containsKey('responded_by_id'), isTrue);
      expect(json.containsKey('responded_by_name'), isTrue);
      // responded_at is serialised as millis since epoch (int64 millis
      // convention — see date-convention memory).
      expect(json['responded_at'], isA<num>());
    });

    test('toReview copies response fields from entity', () {
      final at = DateTime.utc(2026, 5, 1, 12);
      final entity = ReviewEntity()
        ..createdAt = at
        ..updatedAt = at
        ..id = 'r1'
        ..providerId = 'company-1'
        ..userId = 'user-1'
        ..userFullName = 'Kana Kirisaki'
        ..message = 'Great!'
        ..rating = 5
        ..response = 'Thanks!'
        ..respondedAt = at
        ..respondedById = 'admin-1'
        ..respondedByName = 'Admin Anne';

      final review = entity.toReview();

      expect(review.response, 'Thanks!');
      expect(review.respondedAt, at);
      expect(review.respondedById, 'admin-1');
      expect(review.respondedByName, 'Admin Anne');
    });
  });

  group('Review.setResponse / clearResponse / hasResponse', () {
    test('setResponse populates all four response fields', () {
      final review = Review.create(
        providerId: 'company-1',
        userId: 'user-1',
        userFullName: 'Kana Kirisaki',
        message: 'Fast approval!',
        rating: 5,
      );
      final before = DateTime.timestamp();

      review.setResponse(
        response: 'Thanks for your feedback!',
        respondedById: 'admin-1',
        respondedByName: 'Admin Anne',
      );

      expect(review.response, 'Thanks for your feedback!');
      expect(review.respondedById, 'admin-1');
      expect(review.respondedByName, 'Admin Anne');
      expect(
        review.respondedAt!.isBefore(before.subtract(const Duration(seconds: 1))),
        isFalse,
        reason: 'respondedAt should be set to ~now, not in the past',
      );
      expect(review.hasResponse, isTrue);
    });

    test('clearResponse nulls all four response fields', () {
      final review = Review.create(
        providerId: 'company-1',
        userId: 'user-1',
        userFullName: 'Kana Kirisaki',
        message: 'Fast approval!',
        rating: 5,
      )
        ..setResponse(
          response: 'Thanks!',
          respondedById: 'admin-1',
          respondedByName: 'Admin Anne',
        )
        ..clearResponse();

      expect(review.response, isNull);
      expect(review.respondedAt, isNull);
      expect(review.respondedById, isNull);
      expect(review.respondedByName, isNull);
      expect(review.hasResponse, isFalse);
    });

    test('hasResponse is false when response is null or empty', () {
      final review = Review.create(
        providerId: 'company-1',
        userId: 'user-1',
        userFullName: 'Kana Kirisaki',
        message: 'Fast approval!',
        rating: 5,
      );

      expect(review.hasResponse, isFalse);

      review.response = '';
      expect(
        review.hasResponse,
        isFalse,
        reason: 'empty string should not count as a response',
      );
    });
  });

  group('Review.create', () {
    test('uses NO_ID and sets createdAt == updatedAt', () {
      final review = Review.create(
        providerId: 'company-1',
        userId: 'user-1',
        userFullName: 'Kana Kirisaki',
        message: 'Fast approval!',
        rating: 5,
      );

      expect(review.id, NO_ID);
      expect(review.createdAt, review.updatedAt);
      expect(review.hasResponse, isFalse);
    });
  });
}
