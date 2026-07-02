import 'package:chat_repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/chat/chat_participants.dart';

void main() {
  test('borrowerToCompany builds [user, company] + context', () {
    final r = ChatParticipants.borrowerToCompany(
      userId: 'u1', userName: 'Bob', userPhotoUrl: null,
      companyId: 'c1', companyName: 'Acme', companyPhotoUrl: 'http://logo',
      contextType: 'product', contextId: 'p1',
    );
    expect(r.participants.map((p) => p.id), ['u1', 'c1']);
    expect(r.participants[0].type, ParticipantType.user);
    expect(r.participants[1].type, ParticipantType.company);
    expect(r.participants[1].displayName, 'Acme');
    expect(r.contextType, 'product');
    expect(r.contextId, 'p1');
  });

  test('staffToBorrower builds [company, user]', () {
    final r = ChatParticipants.staffToBorrower(
      companyId: 'c1', companyName: 'Acme', companyPhotoUrl: null,
      borrowerId: 'u9', borrowerName: 'Jane', borrowerPhotoUrl: null,
      contextType: 'loan', contextId: 'l3',
    );
    expect(r.participants.map((p) => p.id), ['c1', 'u9']);
    expect(r.participants[0].type, ParticipantType.company);
    expect(r.contextId, 'l3');
  });
}
