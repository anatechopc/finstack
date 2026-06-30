import 'package:flutter_test/flutter_test.dart';
import 'package:user_repository/src/model/user_entity.dart';
import 'package:user_repository/user_repository.dart';

void main() {
  Map<String, dynamic> baseJson() => User.createInvited(
        role: UserRole.teller,
        firstName: 'Jane',
        lastName: 'Doe',
        mobileNumber: '+639170000000',
        emailAddress: 'jane@example.com',
        birthDate: DateTime(1990, 6, 15),
        sex: Sex.female,
        employmentDetails: EmploymentDetails.createBlank(),
        companyId: 'co-1',
      ).toEntity().toJson();

  test('invitedByAdmin round-trips from JSON', () {
    final json = baseJson()..['invited_by_admin'] = true;
    final e = UserEntity.fromJson(json);
    expect(e.invitedByAdmin, isTrue);
    expect(e.toJson()['invited_by_admin'], isTrue);
  });

  test('invitedByAdmin defaults to false when key absent', () {
    final e = UserEntity.fromJson(baseJson());
    expect(e.invitedByAdmin, isFalse);
  });
}
