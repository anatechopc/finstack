import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:storage_repository/storage_repository.dart';
import 'package:user_loan_view_repository/user_loan_view_repository.dart';
import 'package:user_repository/user_repository.dart';

class _MockUserRepo extends Mock implements UserRepository {}

class _MockStorage extends Mock implements StorageRepository {}

// UserLoanViewRepository is `final`, so mock the base interface (the bloc never
// calls a non-base method on it).
class _MockUserLoanViewRepo extends Mock
    implements BaseRepository<UserLoanView> {}

class _MockAuthService extends Mock implements AuthenticationService {}

void main() {
  late _MockUserRepo users;
  late _MockStorage storage;
  late _MockUserLoanViewRepo userLoanViews;
  late _MockAuthService auth;

  setUp(() {
    users = _MockUserRepo();
    storage = _MockStorage();
    userLoanViews = _MockUserLoanViewRepo();
    auth = _MockAuthService();
  });

  // addressRepository is intentionally omitted: it's a `final` class (can't be
  // mocked) and the resend-invite path never touches it.
  UserBloc build() => UserBloc.withDependencies(
        userRepository: users,
        userLoanViewRepository: userLoanViews,
        storageRepository: storage,
        authService: auth,
      );

  blocTest<UserBloc, UserState>(
    'resendInvite → calls sendPasswordSetupLink and emits success',
    setUp: () {
      when(() => users.sendPasswordSetupLink(email: any(named: 'email')))
          .thenAnswer((_) async {});
    },
    build: build,
    act: (b) => b.resendInvite('jane@example.com'),
    expect: () => [
      isA<UserState>()
          .having((s) => s.status, 'status', UserStatus.loading)
          .having((s) => s.isLoading, 'isLoading', true),
      isA<UserState>()
          .having((s) => s.status, 'status', UserStatus.loading)
          .having((s) => s.isLoading, 'isLoading', false),
      isA<UserState>().having((s) => s.status, 'status', UserStatus.success),
    ],
    verify: (_) {
      verify(() => users.sendPasswordSetupLink(email: 'jane@example.com'))
          .called(1);
    },
  );

  blocTest<UserBloc, UserState>(
    'resendInvite → emits error when sendPasswordSetupLink throws',
    setUp: () {
      when(() => users.sendPasswordSetupLink(email: any(named: 'email')))
          .thenThrow(Exception('network down'));
    },
    build: build,
    act: (b) => b.resendInvite('jane@example.com'),
    expect: () => [
      isA<UserState>()
          .having((s) => s.status, 'status', UserStatus.loading)
          .having((s) => s.isLoading, 'isLoading', true),
      isA<UserState>()
          .having((s) => s.status, 'status', UserStatus.loading)
          .having((s) => s.isLoading, 'isLoading', false),
      isA<UserState>().having((s) => s.status, 'status', UserStatus.error),
    ],
    verify: (_) {
      verify(() => users.sendPasswordSetupLink(email: 'jane@example.com'))
          .called(1);
    },
  );
}
