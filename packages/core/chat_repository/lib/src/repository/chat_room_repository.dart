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
  Stream<List<ChatRoom>> get dataStream =>
      _service.dataStream.map((list) => list.map((e) => e.toChatRoom()).toList());

  @override
  void loadNext({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) =>
      _service.loadNext(
          statements: statements, limit: limit, page: page, reset: reset);

  /// Reuse the existing anchored room or create a new one (dedup).
  Future<ChatRoom> findOrCreate({
    required List<Participant> participants,
    required String createdBy,
    String? contextType,
    String? contextId,
  }) async {
    final memberIds = memberIdsOf(participants).toSet();
    final existing = await _service.findAnchoredRoom(
      currentId: createdBy,
      memberIds: memberIds,
      contextType: contextType,
      contextId: contextId,
    );
    if (existing != null) return existing.toChatRoom();
    final room = ChatRoom.create(
      participants: participants,
      createdBy: createdBy,
      contextType: contextType,
      contextId: contextId,
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
          roomId: roomId, companyId: companyId, userId: userId, seq: seq);
}
