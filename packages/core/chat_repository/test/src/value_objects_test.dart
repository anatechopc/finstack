// ignore_for_file: prefer_const_constructors
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ReadState round-trips; seqs default to 0; dates are int millis', () {
    final at = DateTime.utc(2026, 7, 1, 9);
    final r = ReadState(
      lastDeliveredSeq: 5,
      lastReadSeq: 3,
      lastDeliveredAt: at,
      lastReadAt: at,
    );
    final json = r.toJson();
    expect(json['last_delivered_seq'], 5);
    expect(json['last_read_seq'], 3);
    expect(json['last_read_at'], isA<num>());
    final back = ReadState.fromJson(json);
    expect(back.lastDeliveredSeq, 5);
    expect(back.lastReadAt!.millisecondsSinceEpoch, at.millisecondsSinceEpoch);

    final empty = ReadState.fromJson(<String, dynamic>{});
    expect(empty.lastDeliveredSeq, 0);
    expect(empty.lastReadSeq, 0);
    expect(empty.lastReadAt, isNull);
  });

  test('TeamReadState round-trips', () {
    final t = TeamReadState(
      lastHandledSeq: 4,
      handledBy: 'u1',
      lastHandledAt: DateTime.utc(2026, 7, 1, 9),
    );
    final json = t.toJson();
    expect(json['last_handled_seq'], 4);
    expect(json['handled_by'], 'u1');
    expect(TeamReadState.fromJson(json).lastHandledSeq, 4);
    expect(TeamReadState.fromJson(<String, dynamic>{}).lastHandledSeq, 0);
  });

  test('LastMessage round-trips', () {
    final m = LastMessage(
      text: 'hi',
      senderParticipantId: 'c1',
      type: MessageType.text,
      seq: 7,
      createdAt: DateTime.utc(2026, 7, 1, 9),
    );
    final json = m.toJson();
    expect(json['sender_participant_id'], 'c1');
    expect(json['type'], 'text');
    expect(json['seq'], 7);
    expect(json['created_at'], isA<num>());
    expect(LastMessage.fromJson(json).seq, 7);
  });
}
