import 'package:authentication_repository/authentication_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/authentication/bloc/authentication_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:user_repository/user_repository.dart';

class _MockAuthRepo extends Mock implements AuthenticationRepository {}

class _MockUserRepo extends Mock implements UserRepository {}

class _MockAuthService extends Mock implements AuthenticationService {}

void main() {
  late _MockAuthRepo authRepo;
  late _MockUserRepo users;
  late _MockAuthService auth;

  setUp(() {
    authRepo = _MockAuthRepo();
    users = _MockUserRepo();
    auth = _MockAuthService();
  });

  // company/address/settings repositories are intentionally omitted: they are
  // `final` classes (can't be mocked) and the forgot-password path never uses
  // them.
  AuthenticationBloc build() => AuthenticationBloc.withDependencies(
        authenticationRepository: authRepo,
        userRepository: users,
        authService: auth,
      );

  blocTest<AuthenticationBloc, AuthenticationState>(
    'forgotPassword → sends the reset link and emits a neutral success',
    setUp: () {
      when(() => users.sendPasswordSetupLink(email: any(named: 'email')))
          .thenAnswer((_) async {});
    },
    build: build,
    act: (b) => b.forgotPassword('jane@example.com'),
    expect: () => [
      isA<AuthenticationState>()
          .having((s) => s.status, 'status',
              AuthenticationStateStatus.loading,)
          .having((s) => s.isLoading, 'isLoading', true),
      isA<AuthenticationState>()
          .having((s) => s.status, 'status',
              AuthenticationStateStatus.loading,)
          .having((s) => s.isLoading, 'isLoading', false),
      isA<AuthenticationState>()
          .having((s) => s.status, 'status',
              AuthenticationStateStatus.success,),
    ],
    verify: (_) {
      verify(() => users.sendPasswordSetupLink(email: 'jane@example.com'))
          .called(1);
    },
  );

  blocTest<AuthenticationBloc, AuthenticationState>(
    'forgotPassword → still emits neutral success when the repo throws '
    '(never leaks whether the account exists)',
    setUp: () {
      when(() => users.sendPasswordSetupLink(email: any(named: 'email')))
          .thenThrow(Exception('user not found'));
    },
    build: build,
    act: (b) => b.forgotPassword('ghost@example.com'),
    expect: () => [
      isA<AuthenticationState>()
          .having((s) => s.status, 'status',
              AuthenticationStateStatus.loading,)
          .having((s) => s.isLoading, 'isLoading', true),
      isA<AuthenticationState>()
          .having((s) => s.status, 'status',
              AuthenticationStateStatus.loading,)
          .having((s) => s.isLoading, 'isLoading', false),
      isA<AuthenticationState>()
          .having((s) => s.status, 'status',
              AuthenticationStateStatus.success,),
    ],
    verify: (_) {
      verify(() => users.sendPasswordSetupLink(email: 'ghost@example.com'))
          .called(1);
    },
  );
}
