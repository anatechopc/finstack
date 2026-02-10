import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:loooans_helpers/logging_helpers.dart';
import 'package:storage_repository/src/base_storage_service.dart';

/// storage service for firebase cloud storage
class FirebaseStorageService implements BaseStorageService {
  final log = Logger('firebase_storage_service');
  @override
  Future<void> delete({required String fullPath}) {
    final ref = FirebaseStorage.instance.refFromURL(fullPath);

    return ref.delete();
  }

  @override
  Future<String> upload({
    required Uint8List data,
    required String folder,
    required String fileName,
  }) async {
    log.config('cloud storage: uploading');
    final ref = FirebaseStorage.instance.ref('$folder/$fileName');
    // SettableMetadata meta = SettableMetadata(contentType: 'image/jpg');
    await ref.putData(data);
    log.config('cloud storage: uploading complete');

    return ref.getDownloadURL();
  }
}
