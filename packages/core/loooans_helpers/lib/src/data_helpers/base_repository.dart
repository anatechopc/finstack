import 'package:loooans_helpers/data_helpers.dart';

/// base class for all repository
abstract class BaseRepository<T extends BaseModel> {
  /// adds the [data] to data sources
  Future<T> add({required T data});

  /// updates the [data] to data sources
  Future<T> update({required T data});

  /// deletes the [data] to data sources
  Future<T> delete({required T data});

  /// gets the data to [data] sources
  Future<T> get({required String id});

  /// gets all the data from data sources
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

  Stream<List<T>> get dataStream;

  void loadNext({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  });
}
