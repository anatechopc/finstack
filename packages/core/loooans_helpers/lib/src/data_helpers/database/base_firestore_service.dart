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

  /// Runs [handler] as one Firestore transaction on this service's
  /// instance (every collection of the app shares it): its reads see one
  /// moment and its writes land together or not at all. Reads come first.
  Future<R> runTransaction<R>(
    Future<R> Function(Transaction transaction) handler,
  ) =>
      fs.runTransaction(handler);

  /// Document [id] read inside [transaction], or null when there is none.
  Future<Map<String, dynamic>?> getIn(
    Transaction transaction,
    String id,
  ) async =>
      (await transaction.get(root.doc(id))).data() as Map<String, dynamic>?;

  /// Queues writing [json] as document [id] in [transaction].
  void setIn(Transaction transaction, String id, Map<String, dynamic> json) =>
      transaction.set(root.doc(id), json);

  /// Queues updating document [id] with [json] in [transaction].
  void updateIn(
    Transaction transaction,
    String id,
    Map<String, dynamic> json,
  ) =>
      transaction.update(root.doc(id), json);

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
