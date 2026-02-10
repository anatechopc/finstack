import 'package:capital_repository/src/data/database/capital_firestore_service.dart';
import 'package:capital_repository/src/model/capital.dart';
import 'package:loooans_helpers/data_helpers.dart';

/// {@template company_repository}
/// A Very Good Project created by Very Good CLI.
/// {@endtemplate}
final class CapitalRepository implements BaseRepository<Capital> {
  /// constructor
  CapitalRepository()
      : _firestoreService = CapitalFirestoreService();

  late final CapitalFirestoreService _firestoreService;

  @override
  Future<Capital> add({required Capital data}) async {
    return _firestoreService
        .add(data: data.toEntity())
        .then((value) => value.toCapital());
  }

  @override
  Future<Capital> delete({required Capital data}) async {
    return _firestoreService
        .delete(data: data.toEntity())
        .then((value) => value.toCapital());
  }

  @override
  Future<Capital> get({required String id}) async {
    return _firestoreService
        .get(id: id)
        .timeout(
          timeoutDuration,
          onTimeout: () => _firestoreService.get(id: id, isCache: true),
        )
        .then((value) => value.toCapital());
  }

  @override
  Future<List<Capital>> load({
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
        .then((value) => value.map((result) => result.toCapital()).toList());
  }

  @override
  Future<Capital> update({required Capital data}) async {
    return _firestoreService
        .update(data: data.toEntity())
        .then((value) => value.toCapital());
  }

  @override
  Stream<List<Capital>> get dataStream => _firestoreService.dataStream
      .map((value) => value.map((result) => result.toCapital()).toList());

  @override
  void loadNext({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) {
    _firestoreService.loadNext(
      statements: statements,
      limit: limit,
      page: page,
      reset: reset,
    );
  }
}
