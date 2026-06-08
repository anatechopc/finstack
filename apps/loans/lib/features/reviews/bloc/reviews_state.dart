part of 'reviews_bloc.dart';

enum ReviewsStatus {
  initial,
  loading,
  loaded,
  responding,
  responseSuccess,
  error,
}

final class ReviewsState extends Equatable {
  const ReviewsState({
    this.status = ReviewsStatus.initial,
    this.reviews = const [],
    this.message,
  });

  final ReviewsStatus status;
  final List<Review> reviews;
  final String? message;

  /// NOTE: `message` is intentionally reset (not preserved) when omitted —
  /// `message: message`, not `message ?? this.message`. Only the `error` status
  /// carries a message; every other transition must drop it so a stale error
  /// banner never leaks into the next loading/loaded/success state. Do not
  /// "fix" this to `?? this.message` — that would reintroduce the leak.
  ReviewsState copyWith({
    ReviewsStatus? status,
    List<Review>? reviews,
    String? message,
  }) {
    return ReviewsState(
      status: status ?? this.status,
      reviews: reviews ?? this.reviews,
      message: message,
    );
  }

  @override
  List<Object?> get props => [status, reviews, message];
}
