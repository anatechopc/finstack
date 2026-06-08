import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/reviews/bloc/reviews_bloc.dart';
import 'package:loooans/features/reviews/widget/reviews_dialog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:review_repository/review_repository.dart';

import '../../../helpers/helpers.dart';

class _MockReviewsBloc extends MockBloc<ReviewsEvent, ReviewsState>
    implements ReviewsBloc {}

Review _review({String id = 'review-1', bool withResponse = false}) {
  final review = Review.create(
    providerId: 'company-1',
    userId: 'user-1',
    userFullName: 'Ada Lovelace',
    message: 'Great service!',
    rating: 5,
  )..id = id;
  if (withResponse) {
    review.setResponse(
      response: 'Existing reply',
      respondedById: 'admin-1',
      respondedByName: 'Acme Capital',
    );
  }
  return review;
}

void main() {
  late ReviewsBloc bloc;

  setUp(() {
    bloc = _MockReviewsBloc();
  });

  Widget subject() => BlocProvider<ReviewsBloc>.value(
        value: bloc,
        child: const ReviewsDialog(summary: 'You have 5 reviews'),
      );

  testWidgets('renders the summary header', (tester) async {
    when(() => bloc.state).thenReturn(const ReviewsState());
    await tester.pumpApp(subject());

    expect(find.text('You have 5 reviews'), findsOneWidget);
  });

  testWidgets('shows a loading spinner while loading with no reviews yet',
      (tester) async {
    when(() => bloc.state)
        .thenReturn(const ReviewsState(status: ReviewsStatus.loading));
    await tester.pumpApp(subject());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows empty state when loaded with no reviews', (tester) async {
    when(() => bloc.state)
        .thenReturn(const ReviewsState(status: ReviewsStatus.loaded));
    await tester.pumpApp(subject());

    expect(find.text('No reviews to show.'), findsOneWidget);
  });

  testWidgets('lists reviews with a Respond action when unanswered',
      (tester) async {
    when(() => bloc.state).thenReturn(
      ReviewsState(status: ReviewsStatus.loaded, reviews: [_review()]),
    );
    await tester.pumpApp(subject());

    expect(find.text('Great service!'), findsOneWidget);
    expect(find.text('Respond'), findsOneWidget);
    expect(find.text('Edit response'), findsNothing);
  });

  testWidgets('shows Edit response when a review already has a response',
      (tester) async {
    when(() => bloc.state).thenReturn(
      ReviewsState(
        status: ReviewsStatus.loaded,
        reviews: [_review(withResponse: true)],
      ),
    );
    await tester.pumpApp(subject());

    expect(find.text('Edit response'), findsOneWidget);
    // The existing response is rendered via the reused borrower widget.
    expect(find.text('Existing reply'), findsOneWidget);
  });
}
