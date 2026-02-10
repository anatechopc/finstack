import 'package:loooans_helpers/data_helpers.dart';
import 'package:notification_repository/src/data/database/notification_firestore_service.dart';
import 'package:notification_repository/src/model/notification.dart';

/// {@template notification_repository}
/// A Very Good Project created by Very Good CLI.
/// {@endtemplate}
class NotificationRepository implements BaseRepository<Notification> {
  /// constructor
  NotificationRepository() : _firestoreService = NotificationFirestoreService();

  late final NotificationFirestoreService _firestoreService;

  @override
  Future<Notification> add({required Notification data}) async {
    return _firestoreService
        .add(data: data.toEntity())
        .then((value) => value.toNotification());
  }

  @override
  Future<Notification> delete({required Notification data}) async {
    return _firestoreService
        .delete(data: data.toEntity())
        .then((value) => value.toNotification());
  }

  @override
  Future<Notification> get({required String id}) async {
    return _firestoreService
        .get(id: id)
        .timeout(
          timeoutDuration,
          onTimeout: () => _firestoreService.get(id: id, isCache: true),
        )
        .then((value) => value.toNotification());
  }

  @override
  Future<List<Notification>> load({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) {
    return _firestoreService
        .load(
          statements: statements,
          limit: limit,
          page: page,
          reset: reset,
        )
        .then(
            (value) => value.map((result) => result.toNotification()).toList(),);
  }

  @override
  Future<Notification> update({required Notification data}) async {
    return _firestoreService
        .update(data: data.toEntity())
        .then((value) => value.toNotification());
  }

  @override
  Stream<List<Notification>> get dataStream => _firestoreService.dataStream
      .map((value) => value.map((result) => result.toNotification()).toList());

  @override
  void loadNext(
      {List<QueryStatement>? statements,
      int? limit = defaultDataLimit,
      int? page,
      bool reset = false,}) {
    _firestoreService.loadNext(
      statements: statements,
      limit: limit,
      page: page,
      reset: reset,
    );
  }
}
