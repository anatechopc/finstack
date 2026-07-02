import 'dart:async';

import 'package:chat_repository/src/logic/chat_read_model.dart';
import 'package:chat_repository/src/model/chat_room_entity.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:loooans_helpers/data_helpers.dart';

final class ChatRoomFirestoreService extends BaseFirestoreService<ChatRoomEntity> {
  ChatRoomFirestoreService({super.firestore});

  @override
  String get collectionName => 'chat_rooms';

  @override
  Future<ChatRoomEntity> add({required ChatRoomEntity data}) async {
    final doc = root.doc();
    final updated = data..id = doc.id;
    await doc.set(updated.toJson());
    return updated;
  }

  @override
  Future<ChatRoomEntity> get({required String id, bool isCache = false}) async {
    final doc = await root
        .doc(id)
        .get(!isCache ? null : const GetOptions(source: Source.cache));
    return ChatRoomEntity.fromJson(doc.data()! as Map<String, dynamic>);
  }

  @override
  Future<ChatRoomEntity> update({required ChatRoomEntity data}) async {
    data.updatedAt = DateTime.timestamp();
    await root.doc(data.id).update(data.toJson());
    return data;
  }

  @override
  Future<ChatRoomEntity> delete({required ChatRoomEntity data}) async {
    final updated = data..deletedAt = DateTime.timestamp();
    await root.doc(data.id).update(updated.toJson());
    return updated;
  }

  @override
  Future<List<ChatRoomEntity>> load({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
    bool isCache = false,
  }) async {
    if (reset) lastDocumentSnapshot = null;
    var query = root
        .where('deleted_at', isNull: true)
        .orderBy('updated_at', descending: true);
    if (lastDocumentSnapshot != null) {
      query = query.startAfterDocument(lastDocumentSnapshot!);
    }
    if (limit != null && limit > 0) query = query.limit(limit);
    if (statements != null) {
      for (final s in statements) {
        query = query.where(
          s.field,
          isEqualTo: s.isEqualTo,
          arrayContains: s.arrayContains,
          arrayContainsAny: s.arrayContainsAny,
          whereIn: s.whereIn,
          isNull: s.isNull,
        );
      }
    }
    final data = await query
        .get(!isCache ? null : const GetOptions(source: Source.cache));
    if (data.docs.isNotEmpty) lastDocumentSnapshot = data.docs.last;
    return data.docs
        .map((d) => ChatRoomEntity.fromJson(d.data()! as Map<String, dynamic>))
        .toList();
  }

  @override
  void loadNext({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) {
    var query = root
        .where('deleted_at', isNull: true)
        .orderBy('updated_at', descending: true);
    if (statements != null) {
      for (final s in statements) {
        query = query.where(
          s.field,
          isEqualTo: s.isEqualTo,
          arrayContains: s.arrayContains,
          arrayContainsAny: s.arrayContainsAny,
          whereIn: s.whereIn,
          isNull: s.isNull,
        );
      }
    }
    if (limit != null && limit > 0) query = query.limit(limit);
    resetStreamController();
    unawaited(
      controller.addStream(
        query.snapshots().map(
          (snap) => snap.docs
              .map(
                (d) => ChatRoomEntity.fromJson(d.data()! as Map<String, dynamic>),
              )
              .toList(),
        ),
      ),
    );
  }

  Future<ChatRoomEntity?> findAnchoredRoom({
    required String currentId,
    required Set<String> memberIds,
    String? contextType,
    String? contextId,
  }) async {
    final snap = await root
        .where('member_ids', arrayContains: currentId)
        .where('deleted_at', isNull: true)
        .get();
    for (final doc in snap.docs) {
      final entity =
          ChatRoomEntity.fromJson(doc.data()! as Map<String, dynamic>);
      if (roomMatchesAnchor(
        entity,
        memberIds: memberIds,
        contextType: contextType,
        contextId: contextId,
      )) {
        return entity;
      }
    }
    return null;
  }

  Future<void> markDelivered({
    required String roomId,
    required String userId,
    required int seq,
  }) async {
    final now = DateTime.timestamp().millisecondsSinceEpoch;
    await root.doc(roomId).update(<String, Object?>{
      'reads.$userId.last_delivered_seq': seq,
      'reads.$userId.last_delivered_at': now,
    });
  }

  Future<void> markRead({
    required String roomId,
    required String userId,
    required int seq,
  }) async {
    final now = DateTime.timestamp().millisecondsSinceEpoch;
    await root.doc(roomId).update(<String, Object?>{
      'reads.$userId.last_read_seq': seq,
      'reads.$userId.last_read_at': now,
      'reads.$userId.last_delivered_seq': seq,
      'reads.$userId.last_delivered_at': now,
    });
  }

  Future<void> markHandled({
    required String roomId,
    required String companyId,
    required String userId,
    required int seq,
  }) async {
    final now = DateTime.timestamp().millisecondsSinceEpoch;
    await root.doc(roomId).update(<String, Object?>{
      'team_reads.$companyId.last_handled_seq': seq,
      'team_reads.$companyId.last_handled_at': now,
      'team_reads.$companyId.handled_by': userId,
    });
  }

  /// Live stream of a single room document.
  Stream<ChatRoomEntity> watchRoom(String roomId) {
    return root.doc(roomId).snapshots().where((s) => s.exists).map(
          (s) => ChatRoomEntity.fromJson(s.data()! as Map<String, dynamic>),
        );
  }
}
