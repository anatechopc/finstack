import 'package:loooans_helpers/data_helpers.dart';
import 'package:settings_repository/src/data/database/settings_firestore_service.dart';
import 'package:settings_repository/src/model/settings.dart';

/// {@template company_repository}
/// A Very Good Project created by Very Good CLI.
/// {@endtemplate}
final class SettingsRepository implements BaseRepository<Settings> {
  /// constructor
  SettingsRepository()
      : _firestoreService = SettingsFirestoreService();

  late final SettingsFirestoreService _firestoreService;

  @override
  Future<Settings> add({required Settings data}) async {
    return _firestoreService
        .add(data: data.toEntity())
        .then((value) => value.toSettings());
  }

  @override
  Future<Settings> delete({required Settings data}) async {
    return _firestoreService
        .delete(data: data.toEntity())
        .then((value) => value.toSettings());
  }

  @override
  Future<Settings> get({required String id}) async {
    return _firestoreService
        .get(id: id)
        .timeout(
          timeoutDuration,
          onTimeout: () => _firestoreService.get(id: id, isCache: true),
        )
        .then((value) => value.toSettings());
  }

  @override
  Future<List<Settings>> load({
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
        .then((value) => value.map((result) => result.toSettings()).toList());
  }

  @override
  Future<Settings> update({required Settings data}) async {
    return _firestoreService
        .update(data: data.toEntity())
        .then((value) => value.toSettings());
  }

  @override
  Stream<List<Settings>> get dataStream => _firestoreService.dataStream
      .map((value) => value.map((result) => result.toSettings()).toList());

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
