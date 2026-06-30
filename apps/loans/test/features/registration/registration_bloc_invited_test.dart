import 'package:address_repository/address_repository.dart';
import 'package:authentication_repository/authentication_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:company_repository/company_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/registration/bloc/registration_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:storage_repository/storage_repository.dart';
import 'package:user_repository/user_repository.dart';

class _MockUserRepo extends Mock implements UserRepository {}

class _MockStorage extends Mock implements StorageRepository {}

// AddressRepository/CompanyRepository are `final`, so mock the base interface
// (the bloc only uses BaseRepository methods on them).
class _MockAddressRepo extends Mock implements BaseRepository<Address> {}

class _MockAuthRepo extends Mock implements AuthenticationRepository {}

class _MockCompanyRepo extends Mock implements BaseRepository<Company> {}

class _MockAuthService extends Mock implements AuthenticationService {}

class _MockCompany extends Mock implements Company {}

void main() {
  late _MockUserRepo users;
  late _MockStorage storage;
  late _MockAddressRepo addresses;
  late _MockAuthRepo authRepo;
  late _MockCompanyRepo companyRepo;
  late _MockAuthService auth;

  setUp(() {
    users = _MockUserRepo();
    storage = _MockStorage();
    addresses = _MockAddressRepo();
    authRepo = _MockAuthRepo();
    companyRepo = _MockCompanyRepo();
    auth = _MockAuthService();
    final company = _MockCompany();
    when(() => company.id).thenReturn('co-1');
    when(() => auth.company).thenReturn(company);
    when(() => auth.idToken).thenReturn('id-token');
    when(
      () => users.createUser(
        role: any(named: 'role'),
        user: any(named: 'user'),
        address: any(named: 'address'),
        idToken: any(named: 'idToken'),
      ),
    ).thenAnswer((_) async => (uid: 'uid-new', inviteSent: true));
  });

  RegistrationBloc build() => RegistrationBloc.withDependencies(
        authenticationRepository: authRepo,
        userRepository: users,
        storageRepository: storage,
        companyRepository: companyRepo,
        addressRepository: addresses,
        authService: auth,
      );

  Map<String, dynamic> fields() => {
        'first_name': 'Jane',
        'last_name': 'Doe',
        'mobile_number': '+639170000000',
        'email_address': 'jane@example.com',
        'birth_date': DateTime(1990),
        'sex': Sex.female,
        'employment_status': EmploymentStatus.employed,
        'line_1': '1 Main St',
        'barangay': 'B',
        'city': 'C',
        'province': 'P',
        'country': 'PH',
        'zip': '1000',
      };

  blocTest<RegistrationBloc, RegistrationState>(
    'invited user → calls createUser with the role name and emits success',
    build: build,
    act: (b) => b.registerInvitedUser(fields(), role: UserRole.teller),
    expect: () => [
      isA<RegistrationLoadingState>(),
      isA<RegistrationLoadingState>(),
      isA<RegistrationSuccessState>(),
    ],
    verify: (_) {
      final captured = verify(
        () => users.createUser(
          role: captureAny(named: 'role'),
          user: any(named: 'user'),
          address: any(named: 'address'),
          idToken: 'id-token',
        ),
      ).captured;
      expect(captured.single, 'teller');
    },
  );
}
