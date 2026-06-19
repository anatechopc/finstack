import 'package:flutter_test/flutter_test.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:user_repository/user_repository.dart';

void main() {
  EmploymentDetails blankEmployment() => EmploymentDetails.createBlank();

  test('createInvited builds a uid-less user with the given role', () {
    final user = User.createInvited(
      role: UserRole.teller,
      firstName: 'Jane',
      lastName: 'Doe',
      mobileNumber: '+639170000000',
      emailAddress: 'jane@example.com',
      birthDate: DateTime(1990, 6, 15),
      sex: Sex.female,
      employmentDetails: blankEmployment(),
      companyId: 'co-1',
    );

    expect(user.id, NO_ID);
    expect(user.userRole, UserRole.teller);
    expect(user.emailAddress, 'jane@example.com');
    expect(user.companyId, 'co-1');
  });

  test('createInvited throws when email is empty', () {
    expect(
      () => User.createInvited(
        role: UserRole.customer,
        firstName: 'Jane',
        lastName: 'Doe',
        mobileNumber: '+639170000000',
        emailAddress: '   ',
        birthDate: DateTime(1990, 6, 15),
        sex: Sex.female,
        employmentDetails: blankEmployment(),
        companyId: 'co-1',
      ),
      throwsException,
    );
  });
}
