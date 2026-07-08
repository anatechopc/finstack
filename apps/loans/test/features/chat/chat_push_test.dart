import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/chat/chat_push.dart';

void main() {
  test('isChatPush + chatRoomId + chatSeq', () {
    final data = {'notification_type': 'chat', 'room_id': 'r1', 'seq': '5'};
    expect(isChatPush(data), isTrue);
    expect(chatRoomId(data), 'r1');
    expect(chatSeq(data), 5);
    expect(isChatPush({'notification_type': 'payment'}), isFalse);
    expect(chatSeq({'notification_type': 'chat', 'room_id': 'r1'}), 0);
  });
}
