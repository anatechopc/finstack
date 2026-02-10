import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:loooans_helpers/data_helpers.dart';
import 'package:loooans_helpers/logging_helpers.dart';
import 'package:storage_repository/src/firebase_storage_service.dart';

/// storage repository
class StorageRepository {
  /// initializer
  StorageRepository() : _firebaseStorageService = FirebaseStorageService();

  late final FirebaseStorageService _firebaseStorageService;
  final log = Logger('storage_repository');

  Future<ImageUrl> upload({
    required Uint8List data,
    required String folder,
    required String fileName,
    bool uploadOriginalSize = false,
    bool includeOriginal = false,
    bool forceDecodeToImage = false,
  }) async {
    return compute(
      (message) async {
        if (!uploadOriginalSize) {
          // NOTE: decodeJpg is used for development purposes
          // jpg is the default output image type for android
          // TODO: check with ios what is the default output
          // image format
          img.Command cmd;

          final tempImage = await decodeImageFromList(data);

          if ((fileName.contains('.jpg') || fileName.contains('.jpeg')) && !forceDecodeToImage) {
            cmd = img.Command()
              ..decodeJpg(data)
              ..copyResize(
                width: tempImage.width <= tempImage.height ? 150 : null,
                height: tempImage.height <= tempImage.width ? 150 : null,
              )
              ..encodeJpg();
          } else if (fileName.contains('.png') && !forceDecodeToImage) {
            cmd = img.Command()
              ..decodePng(data)
              ..copyResize(
                width: tempImage.width <= tempImage.height ? 150 : null,
                height: tempImage.height <= tempImage.width ? 150 : null,
              )
              ..encodePng();
          } else {
            cmd = img.Command()
              ..decodeImage(data)
              ..copyResize(
                width: tempImage.width <= tempImage.height ? 150 : null,
                height: tempImage.height <= tempImage.width ? 150 : null,
              )
              ..encodePng();
          }

          log.fine('executing resize');
          final result = await cmd.executeThread();

          log.fine('uploading');
          return ImageUrl(
            name: fileName,
            thumbnail: await _firebaseStorageService.upload(
              data: result.outputBytes!,
              folder: folder,
              fileName: includeOriginal ? 'thumb_$fileName' : fileName,
            ),
            original: includeOriginal
                ? await _firebaseStorageService.upload(
                    data: data,
                    folder: folder,
                    fileName: fileName,
                  )
                : null,
          );
        }

        return ImageUrl(
          name: fileName,
          original: await _firebaseStorageService.upload(
            data: data,
            folder: folder,
            fileName: fileName,
          ),
        );
      },
      'storage_repository',
      debugLabel: 'storage_repository_upload',
    );
  }

  Future<FileUrl> uploadFile({
    required Uint8List data,
    required String folder,
    required String fileName,
  }) async {
    return FileUrl(
      name: fileName,
      url: await _firebaseStorageService.upload(
        data: data,
        folder: folder,
        fileName: fileName,
      ),
    );
  }

  Future<void> delete({required String fullPath}) async {
    return _firebaseStorageService.delete(fullPath: fullPath);
  }
}
