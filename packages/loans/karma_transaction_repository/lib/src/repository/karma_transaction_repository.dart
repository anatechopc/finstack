import 'package:karma_transaction_repository/src/data/database/karma_transaction_firestore_service.dart';
import 'package:karma_transaction_repository/src/model/karma_transaction.dart';
import 'package:loooans_helpers/data_helpers.dart';

/// {@template company_repository}
/// A Very Good Project created by Very Good CLI.
/// {@endtemplate}
final class KarmaTransactionRepository implements BaseRepository<KarmaTransaction> {
  /// constructor
  KarmaTransactionRepository() : _firestoreService = KarmaTransactionFirestoreService();

  late final KarmaTransactionFirestoreService _firestoreService;

  @override
  Future<KarmaTransaction> add({required KarmaTransaction data}) async {
    return _firestoreService
        .add(data: data.toEntity())
        .then((value) => value.toKarmaTransaction());
  }

  @override
  Future<KarmaTransaction> delete({required KarmaTransaction data}) async {
    return _firestoreService
        .delete(data: data.toEntity())
        .then((value) => value.toKarmaTransaction());
  }

  @override
  Future<KarmaTransaction> get({required String id}) async {
    return _firestoreService
        .get(id: id)
        .timeout(
          timeoutDuration,
          onTimeout: () => _firestoreService.get(id: id, isCache: true),
        )
        .then((value) => value.toKarmaTransaction());
  }

  @override
  Future<List<KarmaTransaction>> load({
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
        .then((value) => value.map((result) => result.toKarmaTransaction()).toList());
  }

  @override
  Future<KarmaTransaction> update({required KarmaTransaction data}) async {
    return _firestoreService
        .update(data: data.toEntity())
        .then((value) => value.toKarmaTransaction());
  }

  @override
  Stream<List<KarmaTransaction>> get dataStream => _firestoreService.dataStream
      .map((value) => value.map((result) => result.toKarmaTransaction()).toList());

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
