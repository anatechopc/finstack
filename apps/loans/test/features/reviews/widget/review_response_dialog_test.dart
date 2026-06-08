import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/reviews/bloc/reviews_bloc.dart';
import 'package:loooans/features/reviews/widget/review_response_dialog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:review_repository/review_repository.dart';

import '../../../helpers/helpers.dart';

class _MockReviewsBloc extends MockBloc<ReviewsEvent, ReviewsState>
    implements ReviewsBloc {}

Review _review({bool withResponse = false}) {
  final review = Review.create(
    providerId: 'company-1',
    userId: 'user-1',
    userFullName: 'Ada Lovelace',
    message: 'Great service!',
    rating: 5,
  )..id = 'review-1';
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

  setUpAll(() {
    registerFallbackValue(_review());
    registerFallbackValue(
      RespondToReviewEvent(review: _review(), response: ''),
    );
  });

  setUp(() {
    bloc = _MockReviewsBloc();
    when(() => bloc.state).thenReturn(const ReviewsState());
  });

  // Present the dialog through a real route so its Navigator.pop has something
  // to pop (mirrors how showReviewResponseDialog is used in the app).
  Future<void> openDialog(WidgetTester tester, Review review) async {
    await tester.pumpApp(
      BlocProvider<ReviewsBloc>.value(
        value: bloc,
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => BlocProvider<ReviewsBloc>.value(
                    value: bloc,
                    child: ReviewResponseDialog(review: review),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the original review and a Send action for a new response',
      (tester) async {
    await openDialog(tester, _review());

    expect(find.text('Respond to review'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Delete response'), findsNothing);
  });

  testWidgets('dispatches RespondToReviewEvent with the typed message',
      (tester) async {
    await openDialog(tester, _review());

    await tester.enterText(find.byType(TextField), 'Thank you!');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    final captured = verify(() => bloc.add(captureAny())).captured;
    final event = captured.whereType<RespondToReviewEvent>().single;
    expect(event.response, 'Thank you!');
    expect(event.review.id, 'review-1');
  });

  testWidgets('shows Delete and Edit title when a response already exists',
      (tester) async {
    await openDialog(tester, _review(withResponse: true));

    expect(find.text('Edit response'), findsOneWidget);
    expect(find.text('Delete response'), findsOneWidget);
  });

  testWidgets('dispatches DeleteReviewResponseEvent when Delete is tapped',
      (tester) async {
    await openDialog(tester, _review(withResponse: true));

    await tester.tap(find.text('Delete response'));
    await tester.pumpAndSettle();

    final captured = verify(() => bloc.add(captureAny())).captured;
    expect(
      captured.whereType<DeleteReviewResponseEvent>().single.review.id,
      'review-1',
    );
  });

  testWidgets('does not dispatch when the message is empty (validation)',
      (tester) async {
    await openDialog(tester, _review());

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    // Dialog stays open and no event is dispatched.
    expect(find.text('Respond to review'), findsOneWidget);
    verifyNever(() => bloc.add(any()));
  });
}
