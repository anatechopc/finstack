import 'dart:typed_data';

abstract class BaseStorageService {
  /// returns a downloadable URL after the data is uploaded
  Future<String> upload({
    required Uint8List data,
    required String folder,
    required String fileName,
  });

  /// deletes the file based on the full url of the photo
  Future<void> delete({ required String fullPath});
}
