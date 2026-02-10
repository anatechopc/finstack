import 'package:loooans_helpers/data_helpers.dart';
import 'package:transaction_repository/src/data/database/transaction_firestore_service.dart';
import 'package:transaction_repository/src/model/transaction.dart';

/// {@template company_repository}
/// A Very Good Project created by Very Good CLI.
/// {@endtemplate}
final class TransactionRepository implements BaseRepository<Transaction> {
  /// constructor
  TransactionRepository() : _firestoreService = TransactionFirestoreService();

  late final TransactionFirestoreService _firestoreService;

  @override
  Future<Transaction> add({required Transaction data}) async {
    return _firestoreService
        .add(data: data.toEntity())
        .then((value) => value.toTransaction());
  }

  @override
  Future<Transaction> delete({required Transaction data}) async {
    return _firestoreService
        .delete(data: data.toEntity())
        .then((value) => value.toTransaction());
  }

  @override
  Future<Transaction> get({required String id}) async {
    return _firestoreService
        .get(id: id)
        .timeout(
          timeoutDuration,
          onTimeout: () => _firestoreService.get(id: id, isCache: true),
        )
        .then((value) => value.toTransaction());
  }

  @override
  Future<List<Transaction>> load({
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
        .then((value) => value.map((result) => result.toTransaction()).toList());
  }

  @override
  Future<Transaction> update({required Transaction data}) async {
    return _firestoreService
        .update(data: data.toEntity())
        .then((value) => value.toTransaction());
  }

  @override
  Stream<List<Transaction>> get dataStream => _firestoreService.dataStream
      .map((value) => value.map((result) => result.toTransaction()).toList());

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
