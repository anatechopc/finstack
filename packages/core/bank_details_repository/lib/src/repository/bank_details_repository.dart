import 'package:bank_details_repository/src/data/database/bank_details_firestore_service.dart';
import 'package:bank_details_repository/src/model/bank_details.dart';
import 'package:loooans_helpers/data_helpers.dart';

/// {@template company_repository}
/// A Very Good Project created by Very Good CLI.
/// {@endtemplate}
final class BankDetailsRepository implements BaseRepository<BankDetails> {
  /// constructor
  BankDetailsRepository() : _firestoreService = BankDetailsFirestoreService();

  late final BankDetailsFirestoreService _firestoreService;

  @override
  Future<BankDetails> add({required BankDetails data}) async {
    return _firestoreService
        .add(data: data.toEntity())
        .then((value) => value.toBankDetails());
  }

  @override
  Future<BankDetails> delete({required BankDetails data}) async {
    return _firestoreService
        .delete(data: data.toEntity())
        .then((value) => value.toBankDetails());
  }

  @override
  Future<BankDetails> get({required String id}) async {
    return _firestoreService
        .get(id: id)
        .timeout(
          timeoutDuration,
          onTimeout: () => _firestoreService.get(id: id, isCache: true),
        )
        .then((value) => value.toBankDetails());
  }

  @override
  Future<List<BankDetails>> load({
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
        .then((value) => value.map((result) => result.toBankDetails()).toList());
  }

  @override
  Future<BankDetails> update({required BankDetails data}) async {
    return _firestoreService
        .update(data: data.toEntity())
        .then((value) => value.toBankDetails());
  }

  @override
  Stream<List<BankDetails>> get dataStream => _firestoreService.dataStream
      .map((value) => value.map((result) => result.toBankDetails()).toList());

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
