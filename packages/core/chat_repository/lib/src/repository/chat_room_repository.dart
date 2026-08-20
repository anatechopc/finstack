import 'dart:async';
import 'package:chat_repository/src/data/database/chat_room_firestore_service.dart';
import 'package:chat_repository/src/logic/chat_read_model.dart';
import 'package:chat_repository/src/model/chat_room.dart';
import 'package:chat_repository/src/model/participant.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:loooans_helpers/data_helpers.dart';

class ChatRoomRepository implements BaseRepository<ChatRoom> {
  ChatRoomRepository({FirebaseFirestore? firestore})
      : _service = ChatRoomFirestoreService(firestore: firestore);

  final ChatRoomFirestoreService _service;

  /// Tears down the live rooms query and stream.
  void dispose() => _service.dispose();

  @override
  Future<ChatRoom> add({required ChatRoom data}) =>
      _service.add(data: data.toEntity()).then((e) => e.toChatRoom());

  @override
  Future<ChatRoom> update({required ChatRoom data}) =>
      _service.update(data: data.toEntity()).then((e) => e.toChatRoom());

  @override
  Future<ChatRoom> delete({required ChatRoom data}) =>
      _service.delete(data: data.toEntity()).then((e) => e.toChatRoom());

  @override
  Future<ChatRoom> get({required String id}) => _service
      .get(id: id)
      .timeout(
        timeoutDuration,
        onTimeout: () => _service.get(id: id, isCache: true),
      )
      .then((e) => e.toChatRoom());

  @override
  Future<List<ChatRoom>> load({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) =>
      _service
          .load(statements: statements, limit: limit, page: page, reset: reset)
          .then((list) => list.map((e) => e.toChatRoom()).toList());

  @override
  Stream<List<ChatRoom>> get dataStream => _service.dataStream
      .map((list) => list.map((e) => e.toChatRoom()).toList());

  @override
  void loadNext({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) =>
      _service.loadNext(
        statements: statements,
        limit: limit,
        page: page,
        reset: reset,
      );

  /// Reuse the existing anchored room or create a new one (dedup).
  Future<ChatRoom> findOrCreate({
    required List<Participant> participants,
    required String createdBy,
    String? contextType,
    String? contextId,
    String? contextLabel,
  }) async {
    final memberIds = memberIdsOf(participants).toSet();
    // Pre-filter the dedup query by an actual member id, NOT createdBy: when
    // company staff initiate a chat, createdBy is the staff user's uid, which is
    // not in member_ids (the company id is), so keying the query on it would
    // always miss and create a duplicate room. Any member works — roomMatchesAnchor
    // then narrows to the exact participant set + context.
    final existing = memberIds.isEmpty
        ? null
        : await _service.findAnchoredRoom(
            currentId: memberIds.first,
            memberIds: memberIds,
            contextType: contextType,
            contextId: contextId,
          );
    if (existing != null) {
      final room = existing.toChatRoom();
      // Rooms created before context_label existed would otherwise keep the
      // generic type pill forever: dedup returns them without ever writing.
      // Label them the first time someone opens the conversation from the
      // product or loan page. Best-effort write-once: an already-labelled room
      // is left alone, so a renamed product does not churn the document. (The
      // check is a read-then-write, not an enforced invariant — two clients
      // racing would both write, which is harmless for a cosmetic snapshot.)
      //
      // Deliberately NOT awaited and never allowed to throw. This sits on the
      // "Message lender"/"Message borrower" hot path: awaiting it would add a
      // round-trip to opening a chat, and letting it fail would leave the
      // button doing nothing at all — permanently, since an unwritten label
      // means the next tap retries the same failing write. A missing label
      // costs a generic pill; a thrown one costs the conversation.
      final current = room.contextLabel?.trim() ?? '';
      final incoming = contextLabel?.trim() ?? '';
      if (current.isEmpty && incoming.isNotEmpty) {
        unawaited(
          _service
              .setContextLabel(roomId: room.id, label: incoming)
              .catchError((Object _) {}),
        );
        room.contextLabel = incoming; // render it now regardless
      }
      return room;
    }
    final room = ChatRoom.create(
      participants: participants,
      createdBy: createdBy,
      contextType: contextType,
      contextId: contextId,
      contextLabel: contextLabel,
    );
    return add(data: room);
  }

  Future<void> markDelivered({
    required String roomId,
    required String userId,
    required int seq,
  }) =>
      _service.markDelivered(roomId: roomId, userId: userId, seq: seq);

  Future<void> markRead({
    required String roomId,
    required String userId,
    required int seq,
  }) =>
      _service.markRead(roomId: roomId, userId: userId, seq: seq);

  Future<void> markHandled({
    required String roomId,
    required String companyId,
    required String userId,
    required int seq,
  }) =>
      _service.markHandled(
        roomId: roomId,
        companyId: companyId,
        userId: userId,
        seq: seq,
      );

  /// Live stream of a single room, mapped to the model.
  Stream<ChatRoom> watchRoom(String roomId) =>
      _service.watchRoom(roomId).map((e) => e.toChatRoom());
}
