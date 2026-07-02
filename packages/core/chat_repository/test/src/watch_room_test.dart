// ignore_for_file: prefer_const_constructors
import 'package:chat_repository/chat_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('watchRoom emits the room doc and updates on change', () async {
    final fs = FakeFirebaseFirestore();
    final repo = ChatRoomRepository(firestore: fs);
    final created = await repo.add(
      data: ChatRoom.create(
        participants: [
          Participant(id: 'u1', type: ParticipantType.user),
          Participant(id: 'c1', type: ParticipantType.company),
        ],
        createdBy: 'u1',
      ),
    );

    final emissions = <ChatRoom?>[];
    final sub = repo.watchRoom(created.id).listen(emissions.add);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await repo.markRead(roomId: created.id, userId: 'u1', seq: 2);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await sub.cancel();

    expect(emissions.first!.id, created.id);
    expect(emissions.last!.reads['u1']!.lastReadSeq, 2);
  });
}
