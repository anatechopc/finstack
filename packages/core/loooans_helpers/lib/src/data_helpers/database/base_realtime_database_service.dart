import 'package:firebase_database/firebase_database.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:loooans_helpers/loooans_helpers.dart';

abstract class BaseRealtimeDatabaseService<T extends BaseEntity>
    extends BaseDatabaseService<T> {
  DatabaseReference get dbRef {
    var rootPath = 'dev/$basePath';

    if (const String.fromEnvironment('ENVIRONMENT') ==
        Environments.staging.name) {
      rootPath = 'stg/$basePath';
    } else if (const String.fromEnvironment('ENVIRONMENT') ==
        Environments.production.name) {
      rootPath = basePath;
    }

    return FirebaseDatabase.instance.ref(rootPath);
  }

  String? _basePath;

  String get basePath {
    if (_basePath == null) {
      throw Exception('Set basePath first. Call `repository.init()`');
    }

    return _basePath!;
  }

  set basePath(String path) {
    _basePath = path;
  }
}
