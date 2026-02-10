import 'package:loooans_helpers/data_helpers.dart';
import 'package:product_repository/src/data/database/product_firestore_service.dart';
import 'package:product_repository/src/model/product.dart';
import 'package:user_loan_view_repository/user_loan_view_repository.dart';

/// {@template product_repository}
/// A Very Good Project created by Very Good CLI.
/// {@endtemplate}
final class ProductRepository implements BaseRepository<Product> {
  /// constructor
  ProductRepository() : _firestoreService = ProductFirestoreService();

  late final ProductFirestoreService _firestoreService;

  @override
  Future<Product> add({required Product data}) async {
    return _firestoreService
        .add(data: data.toEntity())
        .then((value) => value.toProduct());
  }

  @override
  Future<Product> delete({required Product data}) async {
    return _firestoreService
        .delete(data: data.toEntity())
        .then((value) => value.toProduct());
  }

  @override
  Future<Product> get({required String id}) async {
    return _firestoreService
        .get(id: id)
        .timeout(
          timeoutDuration,
          onTimeout: () => _firestoreService.get(id: id, isCache: true),
        )
        .then((value) => value.toProduct());
  }

  @override
  Future<List<Product>> load({
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
        .then((value) => value.map((result) => result.toProduct()).toList());
  }

  /// updateProductView set to true when loanType, term,
  /// interestRate, maxLoanableAmount are updated.
  @override
  Future<Product> update({
    required Product data,
    bool updateProductView = false,
  }) async {
    if (updateProductView) {
      UserLoanViewRepository().updateProductData(product: data);
    }
    return _firestoreService
        .update(data: data.toEntity())
        .then((value) => value.toProduct());
  }

  @override
  Stream<List<Product>> get dataStream => _firestoreService.dataStream
      .map((value) => value.map((result) => result.toProduct()).toList());

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
