import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:review_repository/review_repository.dart';

part 'reviews_event.dart';
part 'reviews_state.dart';

/// Admin-side bloc for the company's reviews: loads the reviews left for the
/// logged-in company and lets an admin / review moderator respond to, edit, or
/// delete a response. Borrower-facing review reading lives in `ProductBloc`.
class ReviewsBloc extends Bloc<ReviewsEvent, ReviewsState> {
  /// Production constructor used by DI in `bloc_providers.dart`. Resolves
  /// dependencies from the widget tree, then delegates to
  /// [ReviewsBloc.withDependencies] so the logic stays unit-testable.
  ReviewsBloc(BuildContext context)
      : this.withDependencies(
          reviewRepository: context.read<ReviewRepository>(),
          authService: AuthenticationService.instance,
        );

  /// Test-friendly constructor with explicit dependencies. The repository is
  /// typed as the [BaseRepository] interface so it can be mocked (the concrete
  /// `ReviewRepository` is a `final class`).
  ReviewsBloc.withDependencies({
    required this.reviewRepository,
    required this.authService,
  }) : super(const ReviewsState()) {
    on<LoadCompanyReviewsEvent>(_onLoad);
    on<RespondToReviewEvent>(_onRespond);
    on<DeleteReviewResponseEvent>(_onDelete);
  }

  final BaseRepository<Review> reviewRepository;
  final AuthenticationService authService;

  /// Upper bound on reviews fetched per load. Generous enough to show all
  /// reviews for the vast majority of companies while capping the worst-case
  /// Firestore read until load-more pagination exists.
  static const int _reviewsLoadLimit = 100;

  Future<void> _onLoad(
    LoadCompanyReviewsEvent event,
    Emitter<ReviewsState> emit,
  ) async {
    emit(state.copyWith(status: ReviewsStatus.loading));
    try {
      // Bound the read: `limit: null` fetched every review for the company on
      // each dialog open (per-document Firestore cost + unwindowed list). Cap
      // it; the repository orders newest-first. TODO(#47): add load-more
      // pagination in the dialog so companies past the cap can see older ones.
      final reviews = await reviewRepository.load(
        reset: true,
        limit: _reviewsLoadLimit,
        statements: [
          QueryStatement(
            field: 'provider_id',
            isEqualTo: authService.company.id,
          ),
        ],
      );
      emit(state.copyWith(status: ReviewsStatus.loaded, reviews: reviews));
    } catch (err) {
      emit(
        state.copyWith(
          status: ReviewsStatus.error,
          message: _messageFrom(err, 'Cannot load reviews'),
        ),
      );
    }
  }

  Future<void> _onRespond(
    RespondToReviewEvent event,
    Emitter<ReviewsState> emit,
  ) async {
    emit(state.copyWith(status: ReviewsStatus.responding));
    // setResponse mutates the Review in place, and that same instance lives in
    // state.reviews, so snapshot the response fields to roll back if the write
    // fails — otherwise the UI shows an unpersisted response as if it saved.
    final review = event.review;
    final snapshot = _ResponseSnapshot.capture(review);
    try {
      final user = authService.user;
      review.setResponse(
        response: event.response,
        respondedById: user.id,
        respondedByName: user.completeNameEasternOrder,
      );
      final updated = await reviewRepository.update(data: review);
      emit(
        state.copyWith(
          status: ReviewsStatus.responseSuccess,
          reviews: _replace(updated),
        ),
      );
    } catch (err) {
      snapshot.restore(review);
      emit(
        state.copyWith(
          status: ReviewsStatus.error,
          message: _messageFrom(err, 'Cannot send response'),
        ),
      );
    }
  }

  Future<void> _onDelete(
    DeleteReviewResponseEvent event,
    Emitter<ReviewsState> emit,
  ) async {
    emit(state.copyWith(status: ReviewsStatus.responding));
    // clearResponse mutates in place; snapshot so a failed delete can be undone
    // rather than leaving the UI showing the response as already removed.
    final review = event.review;
    final snapshot = _ResponseSnapshot.capture(review);
    try {
      review.clearResponse();
      final updated = await reviewRepository.update(data: review);
      emit(
        state.copyWith(
          status: ReviewsStatus.responseSuccess,
          reviews: _replace(updated),
        ),
      );
    } catch (err) {
      snapshot.restore(review);
      emit(
        state.copyWith(
          status: ReviewsStatus.error,
          message: _messageFrom(err, 'Cannot delete response'),
        ),
      );
    }
  }

  /// Returns a new list with [updated] swapped in for the review sharing its id.
  List<Review> _replace(Review updated) =>
      state.reviews.map((r) => r.id == updated.id ? updated : r).toList();

  String _messageFrom(Object err, String fallback) =>
      err is Exception ? '$fallback: $err' : fallback;
}

/// Snapshot of a [Review]'s four `response*` fields so an optimistic in-place
/// mutation (setResponse / clearResponse) can be rolled back when the
/// persistence call fails.
class _ResponseSnapshot {
  _ResponseSnapshot._(
    this._response,
    this._respondedAt,
    this._respondedById,
    this._respondedByName,
  );

  factory _ResponseSnapshot.capture(Review r) => _ResponseSnapshot._(
        r.response,
        r.respondedAt,
        r.respondedById,
        r.respondedByName,
      );

  final String? _response;
  final DateTime? _respondedAt;
  final String? _respondedById;
  final String? _respondedByName;

  void restore(Review r) {
    r
      ..response = _response
      ..respondedAt = _respondedAt
      ..respondedById = _respondedById
      ..respondedByName = _respondedByName;
  }
}
