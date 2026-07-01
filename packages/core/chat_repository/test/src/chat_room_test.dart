// ignore_for_file: prefer_const_constructors
import 'package:chat_repository/chat_repository.dart';
import 'package:chat_repository/src/model/chat_room_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans_helpers/data_helpers.dart';

void main() {
  final borrower = Participant(id: 'u1', type: ParticipantType.user, displayName: 'Bob');
  final company = Participant(id: 'c1', type: ParticipantType.company, displayName: 'Acme');

  test('ChatRoom.create derives member_ids, NO_ID, empty reads, lastSeq 0', () {
    final room = ChatRoom.create(
      participants: [borrower, company],
      createdBy: 'u1',
      contextType: 'product',
      contextId: 'p1',
    );
    expect(room.id, NO_ID);
    expect(room.memberIds, ['u1', 'c1']);
    expect(room.lastSeq, 0);
    expect(room.reads, isEmpty);
    expect(room.teamReads, isEmpty);
    expect(room.createdAt, room.updatedAt);
  });

  test('ChatRoom round-trips participants, reads map, team_reads map, last_message', () {
    final room = ChatRoom.create(
      participants: [borrower, company],
      createdBy: 'u1',
    )
      ..lastSeq = 3
      ..lastMessage = LastMessage(
        senderParticipantId: 'u1',
        type: MessageType.text,
        seq: 3,
        createdAt: DateTime.utc(2026, 7, 1, 9),
        text: 'hi',
      )
      ..reads = {'u1': ReadState(lastReadSeq: 3, lastDeliveredSeq: 3)}
      ..teamReads = {'c1': TeamReadState(lastHandledSeq: 1, handledBy: 'staff1')};

    final json = room.toJson();
    expect((json['participants'] as List).length, 2);
    expect(json['member_ids'], ['u1', 'c1']);
    expect(json['last_seq'], 3);
    expect((json['reads'] as Map)['u1']['last_read_seq'], 3);
    expect((json['team_reads'] as Map)['c1']['last_handled_seq'], 1);
    expect(json['last_message']['seq'], 3);

    final entity = ChatRoomEntity.fromJson(json);
    expect(entity.participants.map((p) => p.id), ['u1', 'c1']);
    expect(entity.reads['u1']!.lastReadSeq, 3);
    expect(entity.teamReads['c1']!.handledBy, 'staff1');
    expect(entity.lastMessage!.seq, 3);
  });

  test('reads/team_reads survive Firestore-style Map<Object?,Object?> input', () {
    final room = ChatRoom.create(participants: [borrower, company], createdBy: 'u1')
      ..reads = {'u1': ReadState(lastReadSeq: 2)};
    final json = Map<String, dynamic>.from(room.toJson());
    json['reads'] = <Object?, Object?>{
      'u1': <Object?, Object?>{'last_read_seq': 2, 'last_delivered_seq': 0},
    };
    final entity = ChatRoomEntity.fromJson(json);
    expect(entity.reads['u1']!.lastReadSeq, 2);
  });
}
