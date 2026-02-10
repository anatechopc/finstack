import 'package:company_repository/company_repository.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:product_repository/product_repository.dart';
import 'package:product_view_repository/src/data/database/product_view_firestore_service.dart';
import 'package:product_view_repository/src/model/product_view.dart';

/// {@template company_repository}
/// A Very Good Project created by Very Good CLI.
/// {@endtemplate}
final class ProductViewRepository implements BaseRepository<ProductView> {
  /// constructor
  ProductViewRepository() : _firestoreService = ProductViewFirestoreService();

  late final ProductViewFirestoreService _firestoreService;

  @override
  Future<ProductView> add({required ProductView data}) async {
    return _firestoreService
        .add(data: data.toEntity())
        .then((value) => value.toProductView());
  }

  @override
  Future<ProductView> delete({required ProductView data}) async {
    return _firestoreService
        .delete(data: data.toEntity())
        .then((value) => value.toProductView());
  }

  @override
  Future<ProductView> get({required String id}) async {
    return _firestoreService
        .get(id: id)
        .timeout(
          timeoutDuration,
          onTimeout: () => _firestoreService.get(id: id, isCache: true),
        )
        .then((value) => value.toProductView());
  }

  @override
  Future<List<ProductView>> load({
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
            (value) => value.map((result) => result.toProductView()).toList(),);
  }

  @override
  Future<ProductView> update({required ProductView data}) async {
    return _firestoreService
        .update(data: data.toEntity())
        .then((value) => value.toProductView());
  }

  void updateProductData(Product product) {
    _firestoreService.updateProductData(product);
  }

  void updateCompanyData(Company company) {
    _firestoreService.updateCompanyData(company);
  }

  @override
  Stream<List<ProductView>> get dataStream => _firestoreService.dataStream
      .map((value) => value.map((result) => result.toProductView()).toList());

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
