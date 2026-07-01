import 'package:chat_repository/src/data/database/message_firestore_service.dart';
import 'package:chat_repository/src/model/message.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:loooans_helpers/data_helpers.dart';

class MessageRepository implements BaseRepository<Message> {
  MessageRepository({required String roomId, FirebaseFirestore? firestore})
      : _service = MessageFirestoreService(roomId: roomId, firestore: firestore);

  final MessageFirestoreService _service;

  @override
  Future<Message> add({required Message data}) =>
      _service.add(data: data.toEntity()).then((e) => e.toMessage());

  @override
  Future<Message> update({required Message data}) =>
      _service.update(data: data.toEntity()).then((e) => e.toMessage());

  @override
  Future<Message> delete({required Message data}) =>
      _service.delete(data: data.toEntity()).then((e) => e.toMessage());

  @override
  Future<Message> get({required String id}) =>
      _service.get(id: id).then((e) => e.toMessage());

  @override
  Future<List<Message>> load({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) =>
      _service
          .load(statements: statements, limit: limit, page: page, reset: reset)
          .then((list) => list.map((e) => e.toMessage()).toList());

  @override
  Stream<List<Message>> get dataStream =>
      _service.dataStream.map((list) => list.map((e) => e.toMessage()).toList());

  @override
  void loadNext({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) =>
      _service.loadNext(
          statements: statements, limit: limit, page: page, reset: reset);

  Future<void> editMessage({required String messageId, required String text}) =>
      _service.editMessage(messageId: messageId, text: text);

  Future<void> deleteMessage({required String messageId}) =>
      _service.deleteMessage(messageId: messageId);
}
