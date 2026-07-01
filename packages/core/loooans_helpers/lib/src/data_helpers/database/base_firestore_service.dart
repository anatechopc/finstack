import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:loooans_helpers/loooans_helpers.dart';

/// Base class for all firestore access
abstract class BaseFirestoreService<T extends BaseEntity>
    extends BaseDatabaseService<T> {
  BaseFirestoreService({FirebaseFirestore? firestore})
      : fs = firestore ?? FirebaseFirestore.instance;

  /// A flag which switches to a stream when calling load().
  bool switchStream = false;

  StreamController<List<T>> controller = StreamController.broadcast();

  Stream<List<T>> get dataStream => controller.stream;

  /// the last document snapshot the query was getting (pagination).
  DocumentSnapshot? lastDocumentSnapshot;

  /// Firestore instance; overridable for tests via the constructor.
  final FirebaseFirestore fs;

  /// env-based collection prefix: `dev_`, `stg_`, or '' (production).
  String get collectionPrefix {
    if (const String.fromEnvironment('ENVIRONMENT') ==
        Environments.staging.name) {
      return 'stg_';
    } else if (const String.fromEnvironment('ENVIRONMENT') ==
        Environments.production.name) {
      return '';
    }
    return 'dev_';
  }

  CollectionReference get root => fs.collection('$collectionPrefix$collectionName');

  /// name of the collection or table
  String get collectionName;

  @override
  Future<T> get({required String id, bool isCache = false});

  void loadNext({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  });

  void resetStreamController() {
    controller = StreamController.broadcast();
  }
}
