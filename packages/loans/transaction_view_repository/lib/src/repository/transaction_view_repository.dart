import 'package:loooans_helpers/data_helpers.dart';
import 'package:transaction_view_repository/src/data/database/transaction_view_firestore_service.dart';
import 'package:transaction_view_repository/src/model/transaction_view.dart';

/// {@template company_repository}
/// A Very Good Project created by Very Good CLI.
/// {@endtemplate}
final class TransactionViewRepository implements BaseRepository<TransactionView> {
  /// constructor
  TransactionViewRepository() : _firestoreService = TransactionViewFirestoreService();

  late final TransactionViewFirestoreService _firestoreService;

  @override
  Future<TransactionView> add({required TransactionView data}) async {
    return _firestoreService
        .add(data: data.toEntity())
        .then((value) => value.toTransactionView());
  }

  @override
  Future<TransactionView> delete({required TransactionView data}) async {
    return _firestoreService
        .delete(data: data.toEntity())
        .then((value) => value.toTransactionView());
  }

  @override
  Future<TransactionView> get({required String id}) async {
    return _firestoreService
        .get(id: id)
        .timeout(
          timeoutDuration,
          onTimeout: () => _firestoreService.get(id: id, isCache: true),
        )
        .then((value) => value.toTransactionView());
  }

  @override
  Future<List<TransactionView>> load({
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
        .then((value) => value.map((result) => result.toTransactionView()).toList());
  }

  @override
  Future<TransactionView> update({required TransactionView data}) async {
    return _firestoreService
        .update(data: data.toEntity())
        .then((value) => value.toTransactionView());
  }

  @override
  Stream<List<TransactionView>> get dataStream => _firestoreService.dataStream
      .map((value) => value.map((result) => result.toTransactionView()).toList());

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
