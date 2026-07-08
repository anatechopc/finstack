// ignore_for_file: prefer_const_constructors
import 'package:chat_repository/chat_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ChatRoomRepository.findOrCreate reuses an existing anchored room',
      () async {
    final fs = FakeFirebaseFirestore();
    final repo = ChatRoomRepository(firestore: fs);
    final participants = [
      Participant(id: 'u1', type: ParticipantType.user),
      Participant(id: 'c1', type: ParticipantType.company),
    ];

    final created = await repo.findOrCreate(
      participants: participants,
      createdBy: 'u1',
      contextType: 'loan',
      contextId: 'l1',
    );
    expect(created.id, isNot('no-id'));

    final again = await repo.findOrCreate(
      participants: participants,
      createdBy: 'u1',
      contextType: 'loan',
      contextId: 'l1',
    );
    expect(again.id, created.id); // dedup — same room
  });

  test('findOrCreate dedups even when createdBy is not a member (staff)',
      () async {
    // Staff act as the company: createdBy is the staff user's uid, which is NOT
    // in member_ids ([borrower, company]). Dedup must still find the room.
    final fs = FakeFirebaseFirestore();
    final repo = ChatRoomRepository(firestore: fs);
    final participants = [
      Participant(id: 'borrower1', type: ParticipantType.user),
      Participant(id: 'company1', type: ParticipantType.company),
    ];

    final created = await repo.findOrCreate(
      participants: participants,
      createdBy: 'staff-9', // staff uid, not a member
      contextType: 'loan',
      contextId: 'l1',
    );

    final again = await repo.findOrCreate(
      participants: participants,
      createdBy: 'staff-42', // a different staffer of the same company
      contextType: 'loan',
      contextId: 'l1',
    );
    expect(again.id, created.id); // same room, not a duplicate
  });

  test('MessageRepository.add persists a message model', () async {
    final fs = FakeFirebaseFirestore();
    final repo = MessageRepository(roomId: 'r1', firestore: fs);
    final sent = await repo.add(
      data: Message.create(
        roomId: 'r1',
        senderId: 'u1',
        senderParticipantId: 'u1',
        type: MessageType.text,
        text: 'yo',
      ),
    );
    expect(sent.id, isNot('no-id'));
    expect(sent.text, 'yo');
  });
}
