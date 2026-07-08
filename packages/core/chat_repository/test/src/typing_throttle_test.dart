// ignore_for_file: prefer_const_constructors
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shouldSendTyping throttles within the window', () {
    expect(shouldSendTyping(lastSentMillis: null, nowMillis: 1000), isTrue);
    expect(shouldSendTyping(lastSentMillis: 1000, nowMillis: 2500), isFalse);
    expect(shouldSendTyping(lastSentMillis: 1000, nowMillis: 3001), isTrue);
  });

  test('isActivelyTyping honors the staleness window', () {
    expect(isActivelyTyping(atMillis: 10000, nowMillis: 12000), isTrue);
    expect(isActivelyTyping(atMillis: 10000, nowMillis: 16000), isFalse);
  });
}
