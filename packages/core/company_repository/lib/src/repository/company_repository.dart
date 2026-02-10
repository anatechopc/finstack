import 'package:company_repository/src/data/database/company_firestore_service.dart';
import 'package:company_repository/src/model/company.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:product_view_repository/product_view_repository.dart';

/// {@template company_repository}
/// A Very Good Project created by Very Good CLI.
/// {@endtemplate}
final class CompanyRepository implements BaseRepository<Company> {
  /// constructor
  CompanyRepository() : _firestoreService = CompanyFirestoreService();

  late final CompanyFirestoreService _firestoreService;

  @override
  Future<Company> add({required Company data}) async {
    return _firestoreService
        .add(data: data.toEntity())
        .then((value) => value.toCompany());
  }

  @override
  Future<Company> delete({required Company data}) async {
    return _firestoreService
        .delete(data: data.toEntity())
        .then((value) => value.toCompany());
  }

  @override
  Future<Company> get({required String id}) async {
    return _firestoreService
        .get(id: id)
        .timeout(
          timeoutDuration,
          onTimeout: () => _firestoreService.get(id: id, isCache: true),
        )
        .then((value) => value.toCompany());
  }

  @override
  Future<List<Company>> load({
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
        .then((value) => value.map((result) => result.toCompany()).toList());
  }

  /// updateProdctView set to true when name, tagLine profilePhotoUrl,
  /// total rating and review count gets updated
  @override
  Future<Company> update({
    required Company data,
    bool updateProductView = false,
  }) async {
    if (updateProductView) {
      ProductViewRepository().updateCompanyData(data);
    }

    return _firestoreService
        .update(data: data.toEntity())
        .then((value) => value.toCompany());
  }

  @override
  Stream<List<Company>> get dataStream => _firestoreService.dataStream
      .map((value) => value.map((result) => result.toCompany()).toList());

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
