import 'package:loan_repository/loan_repository.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:product_repository/product_repository.dart';
import 'package:user_loan_view_repository/src/data/database/user_loan_view_firestore_service.dart';
import 'package:user_loan_view_repository/src/model/user_loan_view.dart';
import 'package:user_repository/user_repository.dart';

/// {@template company_repository}
/// A Very Good Project created by Very Good CLI.
/// {@endtemplate}
final class UserLoanViewRepository implements BaseRepository<UserLoanView> {
  /// constructor
  UserLoanViewRepository() : _firestoreService = UserLoanViewFirestoreService();

  late final UserLoanViewFirestoreService _firestoreService;

  @override
  Future<UserLoanView> add({required UserLoanView data}) async {
    return _firestoreService
        .add(data: data.toEntity())
        .then((value) => value.toUserLoanView());
  }

  void updateUserData({required User user}) {
    _firestoreService.updateUserData(user);
  }

  void updateLoanData({
    required Loan loan,
  }) {
    _firestoreService.updateLoanData(loan);
  }

  void updateProductData({
    required Product product,
  }) {
    _firestoreService.updateProductData(product);
  }

  @override
  Future<UserLoanView> delete({required UserLoanView data}) async {
    return _firestoreService
        .delete(data: data.toEntity())
        .then((value) => value.toUserLoanView());
  }

  @override
  Future<UserLoanView> get({required String id}) async {
    return _firestoreService
        .get(id: id)
        .timeout(
          timeoutDuration,
          onTimeout: () => _firestoreService.get(id: id, isCache: true),
        )
        .then((value) => value.toUserLoanView());
  }

  @override
  Future<List<UserLoanView>> load({
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
        .then(
            (value) => value.map((result) => result.toUserLoanView()).toList(),);
  }

  @override
  Future<UserLoanView> update({required UserLoanView data}) async {
    return _firestoreService
        .update(data: data.toEntity())
        .then((value) => value.toUserLoanView());
  }

  @override
  Stream<List<UserLoanView>> get dataStream => _firestoreService.dataStream
      .map((value) => value.map((result) => result.toUserLoanView()).toList());

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
