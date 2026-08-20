// ignore_for_file: prefer_const_constructors
import 'package:chat_repository/chat_repository.dart';
import 'package:chat_repository/src/data/database/chat_room_firestore_service.dart';
import 'package:chat_repository/src/model/chat_room_entity.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore fs;
  late ChatRoomFirestoreService service;

  final borrower = Participant(id: 'u1', type: ParticipantType.user);
  final company = Participant(id: 'c1', type: ParticipantType.company);

  setUp(() {
    fs = FakeFirebaseFirestore();
    service = ChatRoomFirestoreService(firestore: fs);
  });

  ChatRoomEntity newRoom() => ChatRoom.create(
        participants: [borrower, company],
        createdBy: 'u1',
        contextType: 'loan',
        contextId: 'l1',
      ).toEntity();

  test('add assigns a doc id and persists under dev_chat_rooms', () async {
    final saved = await service.add(data: newRoom());
    expect(saved.id, isNotEmpty);
    expect(saved.id, isNot('no-id'));
    final doc = await fs.collection('dev_chat_rooms').doc(saved.id).get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['member_ids'], ['u1', 'c1']);
  });

  test('findAnchoredRoom returns an existing match, null otherwise', () async {
    final saved = await service.add(data: newRoom());
    final found = await service.findAnchoredRoom(
      currentId: 'u1',
      memberIds: {'u1', 'c1'},
      contextType: 'loan',
      contextId: 'l1',
    );
    expect(found, isNotNull);
    expect(found!.id, saved.id);

    final miss = await service.findAnchoredRoom(
      currentId: 'u1',
      memberIds: {'u1', 'c1'},
      contextType: 'product',
      contextId: 'p9',
    );
    expect(miss, isNull);
  });

  test('markRead advances only that user reads entry (others intact)', () async {
    final saved = await service.add(
      data: newRoom()
        ..lastSeq = 5
        ..reads = {'c1': ReadState(lastReadSeq: 1)},
    );
    await service.markRead(roomId: saved.id, userId: 'u1', seq: 5);
    final doc = await fs.collection('dev_chat_rooms').doc(saved.id).get();
    final reads = doc.data()!['reads'] as Map<String, dynamic>;
    expect((reads['u1'] as Map<String, dynamic>)['last_read_seq'], 5);
    expect((reads['u1'] as Map<String, dynamic>)['last_delivered_seq'], 5);
    expect((reads['c1'] as Map<String, dynamic>)['last_read_seq'], 1); // untouched
  });

  test('markHandled advances team_reads for the company', () async {
    final saved = await service.add(data: newRoom()..lastSeq = 4);
    await service.markHandled(
      roomId: saved.id,
      companyId: 'c1',
      userId: 'staff1',
      seq: 4,
    );
    final doc = await fs.collection('dev_chat_rooms').doc(saved.id).get();
    final team = doc.data()!['team_reads'] as Map<String, dynamic>;
    expect((team['c1'] as Map<String, dynamic>)['last_handled_seq'], 4);
    expect((team['c1'] as Map<String, dynamic>)['handled_by'], 'staff1');
  });

  test('update() cannot erase the anchor — it is the dedup key', () async {
    // Erasing context_type/context_id makes findAnchoredRoom miss and forks a
    // duplicate room per product: corruption, not a cosmetic pill. Nothing
    // asserted this before, so a change to _protectedRoomFields would have
    // compiled and passed.
    final fs = FakeFirebaseFirestore();
    final service = ChatRoomFirestoreService(firestore: fs);
    final saved = await service.add(
      data: ChatRoom.create(
        participants: [
          Participant(id: 'u1', type: ParticipantType.user),
          Participant(id: 'c1', type: ParticipantType.company),
        ],
        createdBy: 'u1',
        contextType: 'product',
        contextId: 'p1',
        contextLabel: 'Offer · Business loan',
      ),
    );

    // A stale client model, as a caller of the generic update() would hold.
    final stale = saved.toChatRoom()
      ..contextType = null
      ..contextId = null
      ..contextLabel = null;
    await service.update(data: stale);

    final doc =
        (await fs.collection('dev_chat_rooms').doc(saved.id).get()).data()!;
    expect(doc['context_type'], 'product');
    expect(doc['context_id'], 'p1');
    expect(doc['context_label'], 'Offer · Business loan');
  });

  test('setContextLabel writes only that field', () async {
    final fs = FakeFirebaseFirestore();
    final service = ChatRoomFirestoreService(firestore: fs);
    final saved = await service.add(
      data: ChatRoom.create(
        participants: [Participant(id: 'u1', type: ParticipantType.user)],
        createdBy: 'u1',
        contextType: 'loan',
        contextId: 'l1',
      ),
    );
    final before =
        (await fs.collection('dev_chat_rooms').doc(saved.id).get()).data()!;

    await service.setContextLabel(roomId: saved.id, label: 'Loan ₱50k');

    final after =
        (await fs.collection('dev_chat_rooms').doc(saved.id).get()).data()!;
    expect(after['context_label'], 'Loan ₱50k');
    // updated_at must NOT move: the inbox orders by updated_at desc, so a
    // backfill would otherwise float old rooms to the top of every inbox.
    expect(after['updated_at'], before['updated_at']);
    expect(after['last_seq'], before['last_seq']);
  });
}
