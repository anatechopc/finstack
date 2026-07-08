// ignore_for_file: prefer_const_constructors
import 'package:chat_repository/chat_repository.dart';
import 'package:chat_repository/src/model/message_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans_helpers/data_helpers.dart';

void main() {
  test('Message.create sets NO_ID, null seq, equal timestamps, empty attachments', () {
    final m = Message.create(
      roomId: 'r1',
      senderId: 'u1',
      senderParticipantId: 'u1',
      type: MessageType.text,
      text: 'hello',
    );
    expect(m.id, NO_ID);
    expect(m.seq, isNull);
    expect(m.createdAt, m.updatedAt);
    expect(m.attachments, isEmpty);
  });

  test('Message round-trips with snake_case + int-millis dates + attachments', () {
    final m = Message.create(
      roomId: 'r1',
      senderId: 'u1',
      senderParticipantId: 'c1',
      type: MessageType.file,
      attachments: [
        Attachment(name: 'a.pdf', url: 'u', contentType: 'application/pdf', size: 9),
      ],
    );
    final json = m.toJson();
    expect(json['room_id'], 'r1');
    expect(json['sender_participant_id'], 'c1');
    expect(json['type'], 'file');
    expect(json['created_at'], isA<num>());
    expect(
      ((json['attachments'] as List).first as Map<String, dynamic>)['content_type'],
      'application/pdf',
    );

    final entity = MessageEntity.fromJson(json);
    expect(entity.roomId, 'r1');
    expect(entity.attachments.single.name, 'a.pdf');
    expect(entity.type, MessageType.file);
  });
}
