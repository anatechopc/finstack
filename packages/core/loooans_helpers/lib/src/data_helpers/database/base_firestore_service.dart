import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:loooans_helpers/loooans_helpers.dart';

/// Base class for all firestore access
abstract class BaseFirestoreService<T extends BaseEntity>
    extends BaseDatabaseService<T> {
  /// A flag which switches to a stream when calling
  /// load() function.
  bool switchStream = false;

  StreamController<List<T>> controller = StreamController.broadcast();

  Stream<List<T>> get dataStream => controller.stream;
  /// the last document snapshot the query was getting
  /// to be used in pagination.
  DocumentSnapshot? lastDocumentSnapshot;
  final fs = FirebaseFirestore.instance;

  CollectionReference get root {
    var rootPath = 'dev_$collectionName';

    if (const String.fromEnvironment('ENVIRONMENT') ==
        Environments.staging.name) {
      rootPath = 'stg_$collectionName';
    } else if (const String.fromEnvironment('ENVIRONMENT') ==
        Environments.production.name) {
      rootPath = collectionName;
    }

    return fs.collection(rootPath);
  }

  /// name of the collection or table
  String get collectionName;

  @override
  Future<T> get({required String id, bool isCache = false,});

  /// loads the next data to stream
  /// If there's no data yeet, it'll load the
  /// first data
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
