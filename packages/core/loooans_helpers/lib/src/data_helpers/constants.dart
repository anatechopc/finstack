import 'package:loooans_helpers/data_helpers.dart';

const NO_ID = 'no-id';
const timeoutDuration = Duration(seconds: 60);
const defaultDataLimit = 10;

num? handleDateTimeToJson(DateTime? dateTime) {
  return dateTime?.millisecondsSinceEpoch;
}

DateTime handleDateTimeFromJson(num dateTimeMillis) {
  return DateTime.fromMillisecondsSinceEpoch(
    dateTimeMillis.toInt(),
    // isUtc: true,
  );
}

DateTime? handleDateTimeNullableFromJson(num? dateTimeMillis) {
  if (dateTimeMillis == null) {
    return null;
  }

  return DateTime.fromMillisecondsSinceEpoch(
    dateTimeMillis.toInt(),
    isUtc: true,
  );
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
