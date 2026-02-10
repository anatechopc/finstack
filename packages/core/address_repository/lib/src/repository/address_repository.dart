import 'package:address_repository/src/data/database/address_firestore_service.dart';
import 'package:address_repository/src/model/address.dart';
import 'package:loooans_helpers/data_helpers.dart';

/// {@template company_repository}
/// A Very Good Project created by Very Good CLI.
/// {@endtemplate}
final class AddressRepository implements BaseRepository<Address> {
  /// constructor
  AddressRepository() : _firestoreService = AddressFirestoreService();

  late final AddressFirestoreService _firestoreService;

  @override
  Future<Address> add({required Address data}) async {
    return _firestoreService
        .add(data: data.toEntity())
        .then((value) => value.toAddress());
  }

  @override
  Future<Address> delete({required Address data}) async {
    return _firestoreService
        .delete(data: data.toEntity())
        .then((value) => value.toAddress());
  }

  @override
  Future<Address> get({required String id}) async {
    return _firestoreService
        .get(id: id)
        .timeout(
          timeoutDuration,
          onTimeout: () => _firestoreService.get(id: id, isCache: true),
        )
        .then((value) => value.toAddress());
  }

  Future<Address?> getByDataType({
    required String id,
    required DataType type,
  }) async {
    return _firestoreService
        .getByDataType(
          id: id,
          type: type,
        )
        .timeout(
          timeoutDuration,
          onTimeout: () => _firestoreService.getByDataType(
            id: id,
            type: type,
            isCache: true,
          ),
        )
        .then((value) => value?.toAddress());
  }

  @override
  Future<List<Address>> load({
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
        .then((value) => value.map((result) => result.toAddress()).toList());
  }

  @override
  Future<Address> update({required Address data}) async {
    return _firestoreService
        .update(data: data.toEntity())
        .then((value) => value.toAddress());
  }

  @override
  Stream<List<Address>> get dataStream => _firestoreService.dataStream
      .map((value) => value.map((result) => result.toAddress()).toList());

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
