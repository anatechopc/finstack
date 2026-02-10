import 'package:loooans_helpers/data_helpers.dart';

/// Base class for all database access
abstract class BaseDatabaseService<T extends BaseEntity> {
  /// adds [data] to database and
  /// returns the added data with
  /// id
  Future<T> add({required T data});

  /// updates [data] to database and
  /// returns the updated data
  Future<T> update({required T data});

  /// deletes [data] to database
  /// and returns the deleted data
  Future<T> delete({required T data});

  /// returns data from the database based on
  /// [id]
  Future<T> get({required String id});

  /// gets all the data from the database
  /// based on the query parameters
  ///
  /// Returns a list of data based on  the
  /// query [statements] and the length of the
  /// data is based on the [limit] provided.
  /// the [page] is used to determine what part
  /// of the query you wanted to return.
  Future<List<T>> load({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  });
}
