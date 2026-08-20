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

  test('findOrCreate backfills a missing context_label without reordering the inbox',
      () async {
    final fs = FakeFirebaseFirestore();
    final repo = ChatRoomRepository(firestore: fs);
    final participants = [
      Participant(id: 'u1', type: ParticipantType.user),
      Participant(id: 'c1', type: ParticipantType.company),
    ];

    // A room as it exists today: created before context_label was introduced.
    final created = await repo.findOrCreate(
      participants: participants,
      createdBy: 'u1',
      contextType: 'product',
      contextId: 'p1',
    );
    expect(created.contextLabel, isNull);

    final doc = fs.collection('dev_chat_rooms').doc(created.id);
    final updatedAtBefore = (await doc.get()).data()!['updated_at'];

    final again = await repo.findOrCreate(
      participants: participants,
      createdBy: 'u1',
      contextType: 'product',
      contextId: 'p1',
      contextLabel: 'Business loan',
    );

    expect(again.id, created.id); // still the same room
    expect(again.contextLabel, 'Business loan'); // rendered immediately

    // The write is deliberately not awaited — let it land before asserting.
    await Future<void>.delayed(Duration.zero);
    final stored = (await doc.get()).data()!;
    expect(stored['context_label'], 'Business loan');
    // The inbox orders by updated_at desc — backfilling must not float old
    // rooms to the top of everyone's list.
    expect(stored['updated_at'], updatedAtBefore);
  });

  test('findOrCreate never overwrites a context_label that is already set',
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
      contextType: 'product',
      contextId: 'p1',
      contextLabel: 'Business loan',
    );

    // The product was renamed since. The label is a creation-time snapshot;
    // rewriting it on every open would churn the document for no benefit.
    final again = await repo.findOrCreate(
      participants: participants,
      createdBy: 'u1',
      contextType: 'product',
      contextId: 'p1',
      contextLabel: 'Business Loan (renamed)',
    );

    expect(again.id, created.id);
    expect(again.contextLabel, 'Business loan');
    await Future<void>.delayed(Duration.zero);
    final stored =
        (await fs.collection('dev_chat_rooms').doc(created.id).get()).data()!;
    expect(stored['context_label'], 'Business loan');
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
