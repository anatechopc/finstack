import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/set_password/cubit/set_password_cubit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:user_repository/user_repository.dart';

class _MockUserRepository extends Mock implements UserRepository {}

void main() {
  late UserRepository repository;

  const token = 'token-123';
  const email = 'jane@example.com';
  const password = 'Password1!';

  setUp(() {
    repository = _MockUserRepository();
  });

  SetPasswordCubit build() => SetPasswordCubit(repository);

  group('submit', () {
    blocTest<SetPasswordCubit, SetPasswordState>(
      'emits submitting then done(email) on success',
      setUp: () {
        when(
          () => repository.setPassword(token: token, newPassword: password),
        ).thenAnswer((_) async => email);
      },
      build: build,
      act: (cubit) => cubit.submit(token: token, newPassword: password),
      expect: () => [
        isA<SetPasswordState>()
            .having((s) => s.status, 'status', SetPasswordStatus.submitting),
        isA<SetPasswordState>()
            .having((s) => s.status, 'status', SetPasswordStatus.done)
            .having((s) => s.email, 'email', email),
      ],
    );

    blocTest<SetPasswordCubit, SetPasswordState>(
      'emits submitting then done(empty email) when the 200 body lacks email',
      setUp: () {
        when(
          () => repository.setPassword(token: token, newPassword: password),
        ).thenAnswer((_) async => '');
      },
      build: build,
      act: (cubit) => cubit.submit(token: token, newPassword: password),
      expect: () => [
        isA<SetPasswordState>()
            .having((s) => s.status, 'status', SetPasswordStatus.submitting),
        isA<SetPasswordState>()
            .having((s) => s.status, 'status', SetPasswordStatus.done)
            .having((s) => s.email, 'email', ''),
      ],
    );

    blocTest<SetPasswordCubit, SetPasswordState>(
      'emits submitting then invalidToken on a 400 SetPasswordException',
      setUp: () {
        when(
          () => repository.setPassword(token: token, newPassword: password),
        ).thenThrow(SetPasswordException(400, 'invalid or expired token'));
      },
      build: build,
      act: (cubit) => cubit.submit(token: token, newPassword: password),
      expect: () => [
        isA<SetPasswordState>()
            .having((s) => s.status, 'status', SetPasswordStatus.submitting),
        isA<SetPasswordState>()
            .having((s) => s.status, 'status', SetPasswordStatus.invalidToken)
            .having((s) => s.errorMessage, 'errorMessage', isNotNull),
      ],
    );

    blocTest<SetPasswordCubit, SetPasswordState>(
      'emits submitting then error on a non-400 SetPasswordException '
      '(NOT invalidToken)',
      setUp: () {
        when(
          () => repository.setPassword(token: token, newPassword: password),
        ).thenThrow(SetPasswordException(500, 'internal server error'));
      },
      build: build,
      act: (cubit) => cubit.submit(token: token, newPassword: password),
      expect: () => [
        isA<SetPasswordState>()
            .having((s) => s.status, 'status', SetPasswordStatus.submitting),
        isA<SetPasswordState>()
            .having((s) => s.status, 'status', SetPasswordStatus.error)
            .having((s) => s.errorMessage, 'errorMessage', isNotNull),
      ],
    );

    blocTest<SetPasswordCubit, SetPasswordState>(
      'emits submitting then error on a generic transport exception',
      setUp: () {
        when(
          () => repository.setPassword(token: token, newPassword: password),
        ).thenThrow(Exception('network'));
      },
      build: build,
      act: (cubit) => cubit.submit(token: token, newPassword: password),
      expect: () => [
        isA<SetPasswordState>()
            .having((s) => s.status, 'status', SetPasswordStatus.submitting),
        isA<SetPasswordState>()
            .having((s) => s.status, 'status', SetPasswordStatus.error)
            .having((s) => s.errorMessage, 'errorMessage', isNotNull),
      ],
    );
  });
}
