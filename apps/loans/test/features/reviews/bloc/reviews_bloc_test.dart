import 'package:bloc_test/bloc_test.dart';
import 'package:company_repository/company_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/reviews/bloc/reviews_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:review_repository/review_repository.dart';
import 'package:user_repository/user_repository.dart';

class _MockReviewRepository extends Mock implements BaseRepository<Review> {}

class _MockAuthenticationService extends Mock
    implements AuthenticationService {}

class _MockUser extends Mock implements User {}

class _MockCompany extends Mock implements Company {}

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
      response: 'Thanks!',
      respondedById: 'old-admin',
      respondedByName: 'Old Admin',
    );
  }
  return review;
}

void main() {
  late BaseRepository<Review> repository;
  late AuthenticationService authService;
  late Company company;
  late User user;
  // Fresh instances per test so rollback assertions can inspect them post-act.
  late Review respondTarget;
  late Review deleteTarget;

  setUpAll(() {
    registerFallbackValue(_review());
  });

  setUp(() {
    repository = _MockReviewRepository();
    authService = _MockAuthenticationService();
    company = _MockCompany();
    user = _MockUser();
    respondTarget = _review();
    deleteTarget = _review(withResponse: true);

    when(() => company.id).thenReturn('company-1');
    when(() => authService.company).thenReturn(company);
    when(() => authService.user).thenReturn(user);
    when(() => user.id).thenReturn('admin-7');
    when(() => user.completeNameEasternOrder).thenReturn('Doe, Jane');
  });

  ReviewsBloc build() => ReviewsBloc.withDependencies(
        reviewRepository: repository,
        authService: authService,
      );

  group('LoadCompanyReviewsEvent', () {
    blocTest<ReviewsBloc, ReviewsState>(
      'loads reviews scoped by the company provider_id',
      setUp: () {
        when(
          () => repository.load(
            statements: any(named: 'statements'),
            limit: any(named: 'limit'),
            page: any(named: 'page'),
            reset: any(named: 'reset'),
          ),
        ).thenAnswer((_) async => [_review()]);
      },
      build: build,
      act: (bloc) => bloc.add(LoadCompanyReviewsEvent()),
      expect: () => [
        const ReviewsState(status: ReviewsStatus.loading),
        isA<ReviewsState>()
            .having((s) => s.status, 'status', ReviewsStatus.loaded)
            .having((s) => s.reviews.length, 'reviews', 1),
      ],
      verify: (_) {
        final captured = verify(
          () => repository.load(
            statements: captureAny(named: 'statements'),
            limit: any(named: 'limit'),
            page: any(named: 'page'),
            reset: any(named: 'reset'),
          ),
        ).captured.single as List<QueryStatement>;
        expect(captured.single.field, 'provider_id');
        expect(captured.single.isEqualTo, 'company-1');
      },
    );

    blocTest<ReviewsBloc, ReviewsState>(
      'emits error when the repository throws',
      setUp: () {
        when(
          () => repository.load(
            statements: any(named: 'statements'),
            limit: any(named: 'limit'),
            page: any(named: 'page'),
            reset: any(named: 'reset'),
          ),
        ).thenThrow(Exception('boom'));
      },
      build: build,
      act: (bloc) => bloc.add(LoadCompanyReviewsEvent()),
      expect: () => [
        const ReviewsState(status: ReviewsStatus.loading),
        isA<ReviewsState>().having((s) => s.status, 'status', ReviewsStatus.error),
      ],
    );
  });

  group('RespondToReviewEvent', () {
    blocTest<ReviewsBloc, ReviewsState>(
      'sets the response with the logged-in admin id/name and persists it',
      setUp: () {
        when(() => repository.update(data: any(named: 'data'))).thenAnswer(
          (invocation) async => invocation.namedArguments[#data] as Review,
        );
      },
      build: build,
      seed: () => ReviewsState(
        status: ReviewsStatus.loaded,
        reviews: [_review()],
      ),
      act: (bloc) => bloc.add(
        RespondToReviewEvent(review: _review(), response: 'You are welcome'),
      ),
      expect: () => [
        isA<ReviewsState>()
            .having((s) => s.status, 'status', ReviewsStatus.responding),
        isA<ReviewsState>()
            .having((s) => s.status, 'status', ReviewsStatus.responseSuccess),
      ],
      verify: (_) {
        final captured = verify(
          () => repository.update(data: captureAny(named: 'data')),
        ).captured.single as Review;
        expect(captured.response, 'You are welcome');
        expect(captured.respondedById, 'admin-7');
        expect(captured.respondedByName, 'Doe, Jane');
        expect(captured.hasResponse, isTrue);
      },
    );

    blocTest<ReviewsBloc, ReviewsState>(
      'rolls back the in-place response mutation when the update fails',
      setUp: () {
        when(() => repository.update(data: any(named: 'data')))
            .thenThrow(Exception('boom'));
      },
      build: build,
      act: (bloc) => bloc.add(
        RespondToReviewEvent(review: respondTarget, response: 'oops'),
      ),
      expect: () => [
        isA<ReviewsState>()
            .having((s) => s.status, 'status', ReviewsStatus.responding),
        isA<ReviewsState>()
            .having((s) => s.status, 'status', ReviewsStatus.error),
      ],
      verify: (_) {
        // The shared Review instance must be restored to its pre-mutation
        // state so the UI does not show an unpersisted response.
        expect(respondTarget.hasResponse, isFalse);
        expect(respondTarget.response, isNull);
        expect(respondTarget.respondedById, isNull);
        expect(respondTarget.respondedByName, isNull);
        expect(respondTarget.respondedAt, isNull);
      },
    );
  });

  group('DeleteReviewResponseEvent', () {
    blocTest<ReviewsBloc, ReviewsState>(
      'clears all response fields and persists the cleared review',
      setUp: () {
        when(() => repository.update(data: any(named: 'data'))).thenAnswer(
          (invocation) async => invocation.namedArguments[#data] as Review,
        );
      },
      build: build,
      act: (bloc) => bloc.add(
        DeleteReviewResponseEvent(review: _review(withResponse: true)),
      ),
      expect: () => [
        isA<ReviewsState>()
            .having((s) => s.status, 'status', ReviewsStatus.responding),
        isA<ReviewsState>()
            .having((s) => s.status, 'status', ReviewsStatus.responseSuccess),
      ],
      verify: (_) {
        final captured = verify(
          () => repository.update(data: captureAny(named: 'data')),
        ).captured.single as Review;
        expect(captured.hasResponse, isFalse);
        expect(captured.response, isNull);
        expect(captured.respondedById, isNull);
        expect(captured.respondedByName, isNull);
        expect(captured.respondedAt, isNull);
      },
    );

    blocTest<ReviewsBloc, ReviewsState>(
      'restores the existing response when the delete update fails',
      setUp: () {
        when(() => repository.update(data: any(named: 'data')))
            .thenThrow(Exception('boom'));
      },
      build: build,
      act: (bloc) =>
          bloc.add(DeleteReviewResponseEvent(review: deleteTarget)),
      expect: () => [
        isA<ReviewsState>()
            .having((s) => s.status, 'status', ReviewsStatus.responding),
        isA<ReviewsState>()
            .having((s) => s.status, 'status', ReviewsStatus.error),
      ],
      verify: (_) {
        // A failed delete must leave the response intact, not show it removed.
        expect(deleteTarget.hasResponse, isTrue);
        expect(deleteTarget.response, 'Thanks!');
        expect(deleteTarget.respondedById, 'old-admin');
        expect(deleteTarget.respondedByName, 'Old Admin');
      },
    );
  });
}
