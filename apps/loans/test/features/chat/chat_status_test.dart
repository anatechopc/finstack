import 'package:chat_repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/chat/chat_status.dart';

ChatRoom _room(Map<String, ReadState> reads, List<Participant> parts) =>
    ChatRoom.create(participants: parts, createdBy: 'u1')..reads = reads;

void main() {
  final borrower = Participant(id: 'u1', type: ParticipantType.user);
  final company = Participant(id: 'c1', type: ParticipantType.company);

  test('borrower viewing: counterpart = all staff read states (not mine)', () {
    final room = _room({
      'u1': ReadState(lastReadSeq: 9),
      'staff1': ReadState(lastDeliveredSeq: 3, lastReadSeq: 3),
    }, [borrower, company]);
    final states =
        counterpartReadStates(room, myUserId: 'u1', myCompanyId: null);
    expect(states.length, 1);
    expect(states.first.lastReadSeq, 3);
  });

  test('staff viewing: counterpart = the borrower read state only', () {
    final room = _room({
      'u1': ReadState(lastDeliveredSeq: 4, lastReadSeq: 4),
      'staff1': ReadState(lastReadSeq: 9),
      'staff2': ReadState(lastReadSeq: 9),
    }, [company, borrower]);
    final states =
        counterpartReadStates(room, myUserId: 'staff1', myCompanyId: 'c1');
    expect(states.length, 1);
    expect(states.first.lastReadSeq, 4);
  });
}
