import 'dart:async';

import 'package:cash_pool_repository/src/model/cash_pool_entity.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:loooans_helpers/data_helpers.dart';

/// address firestore database service
final class CashPoolFirestoreService
    extends BaseFirestoreService<CashPoolEntity> {
  CashPoolFirestoreService() {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  @override
  String get collectionName => 'cash_pool';

  @override
  Future<CashPoolEntity> add({required CashPoolEntity data}) async {
    final doc = root.doc();
    final updatedData = data..id = doc.id;
    await doc.set(updatedData.toJson());

    return updatedData;
  }

  @override
  Future<CashPoolEntity> delete({required CashPoolEntity data}) async {
    final updatedData = data..deletedAt = DateTime.timestamp();

    await root.doc(data.id).update(updatedData.toJson());

    return updatedData;
  }

  @override
  Future<CashPoolEntity> get({required String id, bool isCache = false}) async {
    final doc = await root
        .doc(id)
        .get(!isCache ? null : const GetOptions(source: Source.cache));

    return CashPoolEntity.fromJson(doc.data()! as Map<String, dynamic>);
  }

  @override
  Future<CashPoolEntity> update({required CashPoolEntity data}) async {
    final updatedAtNow = DateTime.timestamp();
    data.updatedAt = updatedAtNow;
    await root.doc(data.id).update(data.toJson());

    return data;
  }

  @override
  Future<List<CashPoolEntity>> load({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
    bool isCache = false,
  }) async {
    if (reset) {
      lastDocumentSnapshot = null;
    }

    var query = root
        .where('deleted_at', isNull: true)
        .orderBy('updated_at', descending: true);

    if (lastDocumentSnapshot != null) {
      query = query.startAfterDocument(lastDocumentSnapshot!);
    }

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

    final data = await query
        .get(!isCache ? null : const GetOptions(source: Source.cache));

    if (data.docs.isNotEmpty) {
      lastDocumentSnapshot = data.docs.first;
    }

    return data.docs
        .map(
          (doc) => CashPoolEntity.fromJson(doc.data()! as Map<String, dynamic>),
        )
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
    query = query.orderBy('created_at', descending: true);

    // for now, disabled pagination and just load all data from the stream
    // anyways, the data are not that large for a particular user.
    // and combined with persistent cache, it should be fine... I guess...
    // if (!switchStream) {
    //   final data = await Future.value(query.get()).timeout(
    //     timeoutDuration,
    //     onTimeout: () => query.get(const GetOptions(source: Source.cache)),
    //   );
    //   // print(data);
    //
    //   final mappedData = data.docs
    //       .map(
    //         (doc) =>
    //             CashPoolEntity.fromJson(doc.data()! as Map<String, dynamic>),
    //       )
    //       .toList();
    //
    //   if (mappedData.length < (limit ?? defaultDataLimit)) {
    //     switchStream = true;
    //   }
    //   // debugPrint('switchStream: $switchStream');
    //
    //   controller.add(mappedData);
    //
    //   if (!switchStream) {
    //     return;
    //   }
    // }

    // debugPrint('stream naaa!');
    // set lastDocumentSnapshot to null to get all data
    // from here on, it is assumed that we have pulled all
    // data from firestore and that it is already cached locally
    lastDocumentSnapshot = null;
    resetStreamController();
    unawaited(
      controller.addStream(
        query.snapshots().map((snapshot) {
          return snapshot.docs.map(
            (doc) {
              debugPrint('something is going here');
              return CashPoolEntity.fromJson(
                  doc.data()! as Map<String, dynamic>,);
            },
          ).toList();
        }),
      ),
    );
  }

  Stream<List<CashPoolEntity>> stream({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) {
    lastDocumentSnapshot = null;
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
    query = query.orderBy('created_at', descending: true);

    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map(
            (doc) =>
                CashPoolEntity.fromJson(doc.data()! as Map<String, dynamic>),
          )
          .toList();
    });
  }

  @override
  Stream<List<CashPoolEntity>> get dataStream => controller.stream;
}
