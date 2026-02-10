import 'package:cash_pool_repository/src/data/database/cash_pool_firestore_service.dart';
import 'package:cash_pool_repository/src/model/cash_pool.dart';
import 'package:loooans_helpers/data_helpers.dart';

/// {@template company_repository}
/// A Very Good Project created by Very Good CLI.
/// {@endtemplate}
final class CashPoolRepository implements BaseRepository<CashPool> {
  /// constructor
  CashPoolRepository() : _firestoreService = CashPoolFirestoreService();

  late final CashPoolFirestoreService _firestoreService;

  @override
  Future<CashPool> add({required CashPool data}) async {
    return _firestoreService
        .add(data: data.toEntity())
        .then((value) => value.toCashPool());
  }

  @override
  Future<CashPool> delete({required CashPool data}) async {
    return _firestoreService
        .delete(data: data.toEntity())
        .then((value) => value.toCashPool());
  }

  @override
  Future<CashPool> get({required String id}) async {
    return _firestoreService
        .get(id: id)
        .timeout(
          timeoutDuration,
          onTimeout: () => _firestoreService.get(id: id, isCache: true),
        )
        .then((value) => value.toCashPool());
  }

  @override
  Future<List<CashPool>> load({
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
        .then((value) => value.map((result) => result.toCashPool()).toList());
  }

  @override
  Future<CashPool> update({required CashPool data}) async {
    return _firestoreService
        .update(data: data.toEntity())
        .then((value) => value.toCashPool());
  }

  @override
  Stream<List<CashPool>> get dataStream => _firestoreService.dataStream
      .map((value) => value.map((result) => result.toCashPool()).toList());

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

  Stream<List<CashPool>> stream({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) {
    return _firestoreService
        .stream(
          statements: statements,
          limit: limit,
          page: page,
          reset: reset,
        )
        .map((value) => value.map((result) => result.toCashPool()).toList());
  }
}
