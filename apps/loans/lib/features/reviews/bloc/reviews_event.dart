part of 'reviews_bloc.dart';

sealed class ReviewsEvent {}

/// Load every review left for the logged-in company (scoped by `provider_id`).
final class LoadCompanyReviewsEvent extends ReviewsEvent {}

/// Set or replace the company response on [review]. The responder id / name are
/// taken from the logged-in user, so edits simply re-issue this event.
final class RespondToReviewEvent extends ReviewsEvent {
  RespondToReviewEvent({required this.review, required this.response});

  final Review review;
  final String response;
}

/// Clear the company response on [review].
final class DeleteReviewResponseEvent extends ReviewsEvent {
  DeleteReviewResponseEvent({required this.review});

  final Review review;
}
