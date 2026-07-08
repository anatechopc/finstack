// ignore_for_file: prefer_const_constructors
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Attachment round-trips with snake_case keys', () {
    final a = Attachment(
      name: 'receipt.pdf',
      url: 'https://x/receipt.pdf',
      contentType: 'application/pdf',
      size: 1024,
    );
    final json = a.toJson();
    expect(json['content_type'], 'application/pdf');
    expect(json['thumbnail_url'], isNull);
    final back = Attachment.fromJson(json);
    expect(back.name, 'receipt.pdf');
    expect(back.size, 1024);
  });

  test('Participant round-trips and defaults unknown type to user', () {
    final p = Participant(
      id: 'c1',
      type: ParticipantType.company,
      displayName: 'Acme',
    );
    final json = p.toJson();
    expect(json['type'], 'company');
    expect(json['display_name'], 'Acme');
    final back = Participant.fromJson(json);
    expect(back.type, ParticipantType.company);

    final unknown = Participant.fromJson({'id': 'x', 'type': 'alien'});
    expect(unknown.type, ParticipantType.user);
  });
}
