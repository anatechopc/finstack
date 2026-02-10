import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:user_repository/src/model/device_entity.dart';
import 'package:user_repository/src/model/user_entity.dart';

/// a firestore database service that accesses users collection
final class UserFirestoreService extends BaseFirestoreService<UserEntity> {
  UserFirestoreService() {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  @override
  String get collectionName => 'users';

  @override
  Future<UserEntity> add({required UserEntity data}) async {
    final doc = root.doc(data.id != NO_ID ? data.id : null);
    final updatedData = data..id = doc.id;
    await doc.set(updatedData.toJson());

    return updatedData;
  }

  Future<void> addDevice({
    required String userId,
    required DeviceEntity device,
  }) {
    return root
        .doc(userId)
        .collection('devices')
        .doc(device.id)
        .set(device.toJson());
  }

  Future<DeviceEntity?> getDevice({
    required String userId,
    required String deviceInstanceId,
  }) async {
    final doc = await root
        .doc(userId)
        .collection('devices')
        .doc(deviceInstanceId)
        .get();
    final data = doc.data();

    return data != null ? DeviceEntity.fromJson(data) : null;
  }

  Future<void> updateDeviceToken({
    required String userId,
    required String deviceInstanceId,
    required String token,
  }) {
    return root.doc(userId).collection('devices').doc(deviceInstanceId).update({
      'token': token,
      'updated_at': DateTime.timestamp().millisecondsSinceEpoch,
    });
  }

  // Future<void> getDevice({ String userId,})

  @override
  Future<UserEntity> delete({required UserEntity data}) async {
    final updatedData = data..deletedAt = DateTime.timestamp();

    await root.doc(data.id).update(updatedData.toJson());

    return updatedData;
  }

  @override
  Future<UserEntity> get({
    required String id,
    bool isCache = false,
  }) async {
    final doc = await root
        .doc(id)
        .get(!isCache ? null : const GetOptions(source: Source.cache));

    final data = doc.data();

    if (!doc.exists || data == null) {
      throw Exception('User not found');
    }

    return UserEntity.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<UserEntity> update({required UserEntity data}) async {
    final updatedAtNow = DateTime.timestamp();
    data.updatedAt = updatedAtNow;
    await root.doc(data.id).update(data.toJson());

    return data;
  }

  @override
  Future<List<UserEntity>> load({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) async {
    if (reset) {
      lastDocumentSnapshot = null;
    }
    debugPrint('lastDocument: $lastDocumentSnapshot');

    var query = root.where('deleted_at', isNull: true);

    if (limit != null && limit > 0) {
      query = query.limit(limit);
    }

    if (statements != null) {
      for (final statement in statements) {
        query = query.where(
          statement.field,
          isEqualTo: statement.isEqualTo,
          arrayContains: statement.arrayContains,
          arrayContainsAny: statement.arrayContainsAny,
          isGreaterThan: statement.isGreaterThan,
          isGreaterThanOrEqualTo: statement.isGreaterThanOrEqualTo,
          isLessThan: statement.isLessThan,
          isLessThanOrEqualTo: statement.isLessThanOrEqualTo,
          isNotEqualTo: statement.isNotEqualTo,
          isNull: statement.isNull,
          whereIn: statement.whereIn,
          whereNotIn: statement.whereNotIn,
        );
      }
    }

    // the final things
    query = query.orderBy('last_name');

    if (lastDocumentSnapshot != null) {
      query = query.startAfterDocument(lastDocumentSnapshot!);
    }

    final data = await Future.value(query.get()).timeout(
      timeoutDuration,
      onTimeout: () => query.get(const GetOptions(source: Source.cache)),
    );

    if (data.docs.isNotEmpty) {
      // we are getting the first one because of the orderBy desc
      // query
      lastDocumentSnapshot = data.docs.first;
    }

    return data.docs
        .map((doc) => UserEntity.fromJson(doc.data()! as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> loadNext({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) async {
    var query = root.where('deleted_at', isNull: true);

    if (limit != null && limit > 0) {
      query = query.limit(limit);
    }

    if (statements != null) {
      for (final statement in statements) {
        query = query.where(
          statement.field,
          isEqualTo: statement.isEqualTo,
          arrayContains: statement.arrayContains,
          arrayContainsAny: statement.arrayContainsAny,
          isGreaterThan: statement.isGreaterThan,
          isGreaterThanOrEqualTo: statement.isGreaterThanOrEqualTo,
          isLessThan: statement.isLessThan,
          isLessThanOrEqualTo: statement.isLessThanOrEqualTo,
          isNotEqualTo: statement.isNotEqualTo,
          isNull: statement.isNull,
          whereIn: statement.whereIn,
          whereNotIn: statement.whereNotIn,
        );
      }
    }

    // the final things
    query = query.orderBy('last_name');

    if (!switchStream) {
      final data = await Future.value(query.get()).timeout(
        timeoutDuration,
        onTimeout: () => query.get(const GetOptions(source: Source.cache)),
      );

      final mappedData = data.docs
          .map(
            (doc) => UserEntity.fromJson(doc.data()! as Map<String, dynamic>),
          )
          .toList();

      if (mappedData.length < (limit ?? defaultDataLimit)) {
        switchStream = true;
      }

      controller.add(mappedData);

      if (!switchStream) {
        return;
      }
    }

    // set lastDocumentSnapshot to null to get all data
    // from here on, it is assumed that we have pulled all
    // data from firestore and that it is already cached locally
    lastDocumentSnapshot = null;
    resetStreamController();
    unawaited(
      controller.addStream(
        query.snapshots().map((snapshot) {
          return snapshot.docs
              .map(
                (doc) =>
                    UserEntity.fromJson(doc.data()! as Map<String, dynamic>),
              )
              .toList();
        }),
      ),
    );
  }

  Future<int> get count {
    return root
        .where('deleted_at', isNull: true)
        .count()
        .get()
        .then((value) => value.count ?? 0);
  }

  @override
  Stream<List<UserEntity>> get dataStream => controller.stream;
}
