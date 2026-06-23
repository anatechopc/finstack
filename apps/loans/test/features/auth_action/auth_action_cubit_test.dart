import 'package:authentication_repository/authentication_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/auth_action/cubit/auth_action_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthenticationRepository extends Mock
    implements AuthenticationRepository {}

void main() {
  late AuthenticationRepository repository;

  const oobCode = 'oob-123';
  const email = 'jane@example.com';
  const password = 'Password1!';

  setUp(() {
    repository = _MockAuthenticationRepository();
  });

  AuthActionCubit build() => AuthActionCubit(repository);

  group('verify', () {
    blocTest<AuthActionCubit, AuthActionState>(
      'emits verifying then ready(email) on success',
      setUp: () {
        when(() => repository.verifyPasswordResetCode(oobCode))
            .thenAnswer((_) async => email);
      },
      build: build,
      act: (cubit) => cubit.verify(oobCode),
      expect: () => [
        isA<AuthActionState>()
            .having((s) => s.status, 'status', AuthActionStatus.verifying),
        isA<AuthActionState>()
            .having((s) => s.status, 'status', AuthActionStatus.ready)
            .having((s) => s.email, 'email', email),
      ],
    );

    blocTest<AuthActionCubit, AuthActionState>(
      'emits verifying then invalid on failure',
      setUp: () {
        when(() => repository.verifyPasswordResetCode(oobCode)).thenThrow(
          AuthenticationException(message: 'Invalid or expired link'),
        );
      },
      build: build,
      act: (cubit) => cubit.verify(oobCode),
      expect: () => [
        isA<AuthActionState>()
            .having((s) => s.status, 'status', AuthActionStatus.verifying),
        isA<AuthActionState>()
            .having((s) => s.status, 'status', AuthActionStatus.invalid)
            .having(
              (s) => s.errorMessage,
              'errorMessage',
              'Invalid or expired link',
            ),
      ],
    );
  });

  group('submit', () {
    blocTest<AuthActionCubit, AuthActionState>(
      'emits submitting then done(email) on success',
      setUp: () {
        when(() => repository.verifyPasswordResetCode(oobCode))
            .thenAnswer((_) async => email);
        when(
          () => repository.confirmPasswordReset(
            code: oobCode,
            newPassword: password,
          ),
        ).thenAnswer((_) async {});
      },
      build: build,
      // Verify first so the email is preserved across the submit lifecycle.
      act: (cubit) async {
        await cubit.verify(oobCode);
        await cubit.submit(oobCode: oobCode, newPassword: password);
      },
      skip: 2,
      expect: () => [
        isA<AuthActionState>()
            .having((s) => s.status, 'status', AuthActionStatus.submitting)
            .having((s) => s.email, 'email', email),
        isA<AuthActionState>()
            .having((s) => s.status, 'status', AuthActionStatus.done)
            .having((s) => s.email, 'email', email),
      ],
    );

    blocTest<AuthActionCubit, AuthActionState>(
      'emits submitting then error on failure',
      setUp: () {
        when(() => repository.verifyPasswordResetCode(oobCode))
            .thenAnswer((_) async => email);
        when(
          () => repository.confirmPasswordReset(
            code: oobCode,
            newPassword: password,
          ),
        ).thenThrow(
          AuthenticationException(message: 'Could not set password'),
        );
      },
      build: build,
      act: (cubit) async {
        await cubit.verify(oobCode);
        await cubit.submit(oobCode: oobCode, newPassword: password);
      },
      skip: 2,
      expect: () => [
        isA<AuthActionState>()
            .having((s) => s.status, 'status', AuthActionStatus.submitting)
            .having((s) => s.email, 'email', email),
        isA<AuthActionState>()
            .having((s) => s.status, 'status', AuthActionStatus.error)
            .having((s) => s.email, 'email', email)
            .having(
              (s) => s.errorMessage,
              'errorMessage',
              'Could not set password',
            ),
      ],
    );
  });
}
