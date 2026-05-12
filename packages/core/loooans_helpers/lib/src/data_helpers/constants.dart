import 'package:loooans_helpers/data_helpers.dart';

const NO_ID = 'no-id';
const timeoutDuration = Duration(seconds: 60);
const defaultDataLimit = 10;

num? handleDateTimeToJson(DateTime? dateTime) {
  return dateTime?.millisecondsSinceEpoch;
}

DateTime handleDateTimeFromJson(dynamic value) {
  final dt = _parseDateTime(value);
  if (dt == null) {
    throw ArgumentError(
      'Expected num millis or Firestore Timestamp, got: ${value.runtimeType}',
    );
  }
  return dt;
}

DateTime? handleDateTimeNullableFromJson(dynamic value) {
  if (value == null) return null;
  return _parseDateTime(value);
}

/// Accepts either:
///   - a numeric milliseconds-since-epoch value (the legacy convention
///     written by the Flutter client and most Go backend code), or
///   - a Firestore [Timestamp] object (returned by cloud_firestore when
///     a document field was written from the server-side Go SDK as a
///     time.Time, since the SDK serialises Go time.Time as Firestore
///     Timestamp rather than millis).
///
/// Returns null on unrecognised input rather than throwing — callers that
/// require non-null should use [handleDateTimeFromJson] which surfaces an
/// ArgumentError.
DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  if (value is DateTime) return value;
  // Duck-type the Firestore Timestamp without taking a cloud_firestore
  // dependency in loooans_helpers.
  try {
    final result = (value as dynamic).toDate();
    if (result is DateTime) return result;
  } catch (_) {
    // fall through
  }
  return null;
}

List<Map<String, dynamic>>? handleImageUrlsToJson(List<ImageUrl>? urls) {
  return urls?.map((e) => handleImageUrlToJson(e)!).toList();
}

Map<String, dynamic>? handleImageUrlToJson(ImageUrl? url) {
  return url?.toJson();
}

Map<String, dynamic>? handleFileUrlToJson(FileUrl? url) {
  return url?.toJson();
}

List<Map<String, dynamic>>? handleFileUrlsToJson(List<FileUrl>? urls) {
  return urls?.map((e) => handleFileUrlToJson(e)!).toList();
}
