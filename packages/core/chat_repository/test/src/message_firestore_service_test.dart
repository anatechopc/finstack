// ignore_for_file: prefer_const_constructors
import 'package:chat_repository/chat_repository.dart';
import 'package:chat_repository/src/data/database/message_firestore_service.dart';
import 'package:chat_repository/src/model/message_entity.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore fs;
  late MessageFirestoreService service;

  setUp(() {
    fs = FakeFirebaseFirestore();
    service = MessageFirestoreService(roomId: 'r1', firestore: fs);
  });

  MessageEntity newMsg({String text = 'hi'}) => Message.create(
        roomId: 'r1',
        senderId: 'u1',
        senderParticipantId: 'u1',
        type: MessageType.text,
        text: text,
      ).toEntity();

  test('add writes under dev_chat_rooms/r1/messages with a doc id', () async {
    final saved = await service.add(data: newMsg());
    expect(saved.id, isNotEmpty);
    final doc = await fs
        .collection('dev_chat_rooms')
        .doc('r1')
        .collection('messages')
        .doc(saved.id)
        .get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['text'], 'hi');
  });

  test('editMessage sets text + edited_at', () async {
    final saved = await service.add(data: newMsg());
    await service.editMessage(messageId: saved.id, text: 'edited');
    final doc = await fs
        .collection('dev_chat_rooms')
        .doc('r1')
        .collection('messages')
        .doc(saved.id)
        .get();
    expect(doc.data()!['text'], 'edited');
    expect(doc.data()!['edited_at'], isA<num>());
  });

  test('deleteMessage soft-deletes (deleted_at set)', () async {
    final saved = await service.add(data: newMsg());
    await service.deleteMessage(messageId: saved.id);
    final doc = await fs
        .collection('dev_chat_rooms')
        .doc('r1')
        .collection('messages')
        .doc(saved.id)
        .get();
    expect(doc.data()!['deleted_at'], isA<num>());
  });
}
