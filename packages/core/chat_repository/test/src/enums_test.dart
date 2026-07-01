// ignore_for_file: prefer_const_constructors
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enum names are stable (used as JSON values)', () {
    expect(ParticipantType.values.map((e) => e.name), ['user', 'company']);
    expect(MessageType.values.map((e) => e.name), ['text', 'image', 'file']);
    expect(MessageStatus.values.map((e) => e.name),
        ['sending', 'sent', 'delivered', 'read']);
  });
}
