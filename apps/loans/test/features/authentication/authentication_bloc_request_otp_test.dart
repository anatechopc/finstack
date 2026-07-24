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
    when(() => auth.idToken).thenReturn('id-token');
  });

  AuthenticationBloc build() => AuthenticationBloc.withDependencies(
        authenticationRepository: authRepo,
        userRepository: users,
        authService: auth,
      );

  blocTest<AuthenticationBloc, AuthenticationState>(
    'requestOtp → surfaces the server 400 reason verbatim',
    setUp: () {
      when(
        () => users.requestOtp(
          idToken: any(named: 'idToken'),
          purpose: any(named: 'purpose'),
        ),
      ).thenThrow(
        RequestOtpException(
          400,
          "Cannot determine the country for the user's mobile number. "
          "Please complete the user's address record.",
        ),
      );
    },
    build: build,
    act: (b) => b.requestOtp(purpose: 'mobile_number'),
    expect: () => [
      isA<AuthenticationState>()
          .having((s) => s.isLoading, 'isLoading', true),
      isA<AuthenticationState>()
          .having((s) => s.isLoading, 'isLoading', false),
      isA<AuthenticationState>()
          .having((s) => s.status, 'status', AuthenticationStateStatus.error)
          .having(
            (s) => s.message,
            'message',
            "Cannot determine the country for the user's mobile number. "
            "Please complete the user's address record.",
          ),
    ],
  );

  blocTest<AuthenticationBloc, AuthenticationState>(
    'requestOtp → keeps the generic message for unexpected errors',
    setUp: () {
      when(
        () => users.requestOtp(
          idToken: any(named: 'idToken'),
          purpose: any(named: 'purpose'),
        ),
      ).thenThrow(Exception('socket closed'));
    },
    build: build,
    act: (b) => b.requestOtp(purpose: 'mobile_number'),
    expect: () => [
      isA<AuthenticationState>()
          .having((s) => s.isLoading, 'isLoading', true),
      isA<AuthenticationState>()
          .having((s) => s.isLoading, 'isLoading', false),
      isA<AuthenticationState>()
          .having((s) => s.status, 'status', AuthenticationStateStatus.error)
          .having((s) => s.message, 'message', 'Cannot request OTP'),
    ],
  );
}
