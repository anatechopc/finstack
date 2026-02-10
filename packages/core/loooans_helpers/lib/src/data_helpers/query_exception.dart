/// exception thrown when query format is not correct
class QueryException implements Exception {

  /// public constructor
  const QueryException(this.message);
  /// message of the error
  final String message;
}