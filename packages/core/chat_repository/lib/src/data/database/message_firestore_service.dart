import 'dart:async';

import 'package:chat_repository/src/model/message_entity.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:loooans_helpers/data_helpers.dart';

/// Operates on the `chat_rooms/{roomId}/messages` subcollection.
final class MessageFirestoreService
    extends BaseFirestoreService<MessageEntity> {
  MessageFirestoreService({required this.roomId, super.firestore});

  final String roomId;

  /// Used only to build the prefixed parent path in [root].
  @override
  String get collectionName => 'chat_rooms';

  @override
  CollectionReference get root => fs
      .collection('$collectionPrefix$collectionName')
      .doc(roomId)
      .collection('messages');

  @override
  Future<MessageEntity> add({required MessageEntity data}) async {
    final doc =
        (data.id.isEmpty || data.id == NO_ID) ? root.doc() : root.doc(data.id);
    final updated = data..id = doc.id;
    await doc.set(updated.toJson());
    return updated;
  }

  @override
  Future<MessageEntity> get({required String id, bool isCache = false}) async {
    final doc = await root
        .doc(id)
        .get(!isCache ? null : const GetOptions(source: Source.cache));
    return MessageEntity.fromJson(doc.data()! as Map<String, dynamic>);
  }

  @override
  Future<MessageEntity> update({required MessageEntity data}) async {
    data.updatedAt = DateTime.timestamp();
    // `seq` is assigned by the messageWritten trigger and is null on a locally
    // built entity — never clobber it via a full-entity write. Prefer the
    // surgical [editMessage]/[deleteMessage] for text/edit/delete.
    await root.doc(data.id).update(data.toJson()..remove('seq'));
    return data;
  }

  @override
  Future<MessageEntity> delete({required MessageEntity data}) async {
    final updated = data..deletedAt = DateTime.timestamp();
    await root.doc(data.id).update(updated.toJson()..remove('seq'));
    return updated;
  }

  Future<void> editMessage({
    required String messageId,
    required String text,
  }) async {
    final now = DateTime.timestamp().millisecondsSinceEpoch;
    await root.doc(messageId).update(<String, dynamic>{
      'text': text,
      'edited_at': now,
      'updated_at': now,
    });
  }

  Future<void> deleteMessage({required String messageId}) async {
    final now = DateTime.timestamp().millisecondsSinceEpoch;
    await root.doc(messageId).update(<String, dynamic>{
      'deleted_at': now,
      'updated_at': now,
    });
  }

  @override
  Future<List<MessageEntity>> load({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
    bool isCache = false,
  }) async {
    if (reset) lastDocumentSnapshot = null;
    var query = root.orderBy('created_at', descending: true);
    if (lastDocumentSnapshot != null) {
      query = query.startAfterDocument(lastDocumentSnapshot!);
    }
    if (limit != null && limit > 0) query = query.limit(limit);
    final data = await query
        .get(!isCache ? null : const GetOptions(source: Source.cache));
    if (data.docs.isNotEmpty) lastDocumentSnapshot = data.docs.last;
    return data.docs
        .map((d) => MessageEntity.fromJson(d.data()! as Map<String, dynamic>))
        .toList();
  }

  @override
  void loadNext({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) {
    var query = root.orderBy('created_at', descending: true);
    if (limit != null && limit > 0) query = query.limit(limit);
    resetStreamController();
    unawaited(
      controller.addStream(
        query.snapshots().map(
              (snap) => snap.docs
                  .map(
                    (d) => MessageEntity.fromJson(
                        d.data()! as Map<String, dynamic>),
                  )
                  .toList(),
            ),
      ),
    );
  }
}
