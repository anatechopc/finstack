import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/products/widget/loan_offer_detail/loan_offer_reviews_section.dart';
import 'package:review_repository/review_repository.dart';

import '../../../../helpers/helpers.dart';

Review _review({bool withResponse = false}) {
  final review = Review.create(
    providerId: 'company-1',
    userId: 'user-1',
    userFullName: 'Ada Lovelace',
    message: 'Great service, fast approval!',
    rating: 5,
  );
  if (withResponse) {
    review.setResponse(
      response: 'Thank you for trusting us, Ada!',
      respondedById: 'admin-1',
      respondedByName: 'Acme Capital',
    );
  }
  return review;
}

void main() {
  group('LoanOfferReviewItem', () {
    testWidgets('always renders the borrower review message', (tester) async {
      await tester.pumpApp(LoanOfferReviewItem(review: _review()));

      expect(find.text('Great service, fast approval!'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsOneWidget);
    });

    testWidgets('does not render a response block when none is set',
        (tester) async {
      await tester.pumpApp(LoanOfferReviewItem(review: _review()));

      expect(find.byKey(const Key('review_response_block')), findsNothing);
    });

    testWidgets('renders the company response block when a response is set',
        (tester) async {
      await tester.pumpApp(
        LoanOfferReviewItem(review: _review(withResponse: true)),
      );

      expect(
        find.byKey(const Key('review_response_block')),
        findsOneWidget,
      );
      expect(find.text('Thank you for trusting us, Ada!'), findsOneWidget);
      expect(find.textContaining('Acme Capital'), findsOneWidget);
    });
  });
}
