// ignore_for_file: prefer_const_constructors
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final borrower = Participant(id: 'u1', type: ParticipantType.user);
  final company = Participant(id: 'c1', type: ParticipantType.company);

  ChatRoom room() => ChatRoom.create(
        participants: [borrower, company],
        createdBy: 'u1',
        contextType: 'loan',
        contextId: 'l1',
      );

  test('unreadFor = lastSeq - lastReadSeq, clamped at 0', () {
    final r = room()
      ..lastSeq = 5
      ..reads = {'u1': ReadState(lastReadSeq: 2)};
    expect(unreadFor(r, 'u1'), 3);
    expect(unreadFor(r, 'unknown'), 5); // no read state => all unread
    r.reads = {'u1': ReadState(lastReadSeq: 9)};
    expect(unreadFor(r, 'u1'), 0); // clamp
  });

  test('team handled/awaiting from team_reads[companyId]', () {
    final r = room()..lastSeq = 4;
    expect(isAwaitingResponse(r, 'c1'), isTrue); // no watermark yet
    r.teamReads = {'c1': TeamReadState(lastHandledSeq: 4)};
    expect(isHandledByTeam(r, 'c1'), isTrue);
    expect(isAwaitingResponse(r, 'c1'), isFalse);
    r.teamReads = {'c1': TeamReadState(lastHandledSeq: 3)};
    expect(isAwaitingResponse(r, 'c1'), isTrue);
  });

  test('messageStatus derivation', () {
    final pending = Message.create(
      roomId: 'r',
      senderId: 'u1',
      senderParticipantId: 'u1',
      type: MessageType.text,
    );
    expect(
      messageStatus(message: pending, counterpartReadStates: const []),
      MessageStatus.sending,
    );

    final sent = Message.create(
      roomId: 'r',
      senderId: 'u1',
      senderParticipantId: 'u1',
      type: MessageType.text,
    )..seq = 4;
    expect(
      messageStatus(message: sent, counterpartReadStates: const []),
      MessageStatus.sent,
    );
    expect(
      messageStatus(
        message: sent,
        counterpartReadStates: [ReadState(lastDeliveredSeq: 4)],
      ),
      MessageStatus.delivered,
    );
    expect(
      messageStatus(
        message: sent,
        counterpartReadStates: [ReadState(lastDeliveredSeq: 4, lastReadSeq: 4)],
      ),
      MessageStatus.read,
    );
    expect(
      messageStatus(
        message: sent,
        counterpartReadStates: [
          ReadState(lastDeliveredSeq: 4),
          ReadState(lastDeliveredSeq: 4, lastReadSeq: 4),
        ],
      ),
      MessageStatus.read,
    );
  });

  test('memberIdsOf', () {
    expect(memberIdsOf([borrower, company]), ['u1', 'c1']);
  });

  test('roomMatchesAnchor requires same members + same context', () {
    final r = room();
    expect(
      roomMatchesAnchor(
        r,
        memberIds: {'u1', 'c1'},
        contextType: 'loan',
        contextId: 'l1',
      ),
      isTrue,
    );
    expect(
      roomMatchesAnchor(
        r,
        memberIds: {'u1', 'c1'},
        contextType: 'product',
        contextId: 'p1',
      ),
      isFalse,
    );
    expect(
      roomMatchesAnchor(
        r,
        memberIds: {'u1'},
        contextType: 'loan',
        contextId: 'l1',
      ),
      isFalse,
    );
  });
}
