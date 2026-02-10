import 'package:loooans_helpers/data_helpers.dart';
import 'package:review_repository/src/data/database/review_firestore_service.dart';
import 'package:review_repository/src/model/review.dart';

/// {@template company_repository}
/// A Very Good Project created by Very Good CLI.
/// {@endtemplate}
final class ReviewRepository implements BaseRepository<Review> {
  /// constructor
  ReviewRepository() : _firestoreService = ReviewFirestoreService();

  late final ReviewFirestoreService _firestoreService;

  @override
  Future<Review> add({required Review data}) async {
    return _firestoreService
        .add(data: data.toEntity())
        .then((value) => value.toReview());
  }

  @override
  Future<Review> delete({required Review data}) async {
    return _firestoreService
        .delete(data: data.toEntity())
        .then((value) => value.toReview());
  }

  @override
  Future<Review> get({required String id}) async {
    return _firestoreService
        .get(id: id)
        .timeout(
          timeoutDuration,
          onTimeout: () => _firestoreService.get(id: id, isCache: true),
        )
        .then((value) => value.toReview());
  }

  @override
  Future<List<Review>> load({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) {
    return _firestoreService
        .load(
          statements: statements,
          limit: limit,
          page: page,
          reset: reset,
        )
        .then((value) => value.map((result) => result.toReview()).toList());
  }

  @override
  Future<Review> update({required Review data}) async {
    return _firestoreService
        .update(data: data.toEntity())
        .then((value) => value.toReview());
  }

  @override
  Stream<List<Review>> get dataStream => _firestoreService.dataStream
      .map((value) => value.map((result) => result.toReview()).toList());

  @override
  void loadNext(
      {List<QueryStatement>? statements,
      int? limit = defaultDataLimit,
      int? page,
      bool reset = false,}) {
    _firestoreService.loadNext(
      statements: statements,
      limit: limit,
      page: page,
      reset: reset,
    );
  }
}
