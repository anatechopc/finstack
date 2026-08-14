import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/loans/bloc/payment_bloc.dart';
import 'package:loooans/features/payment_center/bloc/payment_center_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:payment_repository/payment_repository.dart';
import 'package:storage_repository/storage_repository.dart';
import 'package:user_repository/user_repository.dart';

class _MockUserRepo extends Mock implements UserRepository {}

class _MockLoanRepo extends Mock implements LoanRepository {}

class _MockLoanScheduleRepo extends Mock implements LoanScheduleRepository {}

class _MockPaymentRepo extends Mock implements PaymentRepository {}

class _MockStorageRepo extends Mock implements StorageRepository {}

class _MockAuthService extends Mock implements AuthenticationService {}

void main() {
  late _MockUserRepo users;
  late _MockAuthService auth;

  setUp(() {
    users = _MockUserRepo();
    auth = _MockAuthService();
    when(() => auth.idToken).thenReturn('id-token');
  });

  PaymentBloc buildPaymentBloc() => PaymentBloc.withDependencies(
        userRepository: users,
        loanRepository: _MockLoanRepo(),
        loanScheduleRepository: _MockLoanScheduleRepo(),
        storageRepository: _MockStorageRepo(),
        paymentRepository: _MockPaymentRepo(),
        authService: auth,
      );

  PaymentCenterBloc buildCenterBloc() => PaymentCenterBloc.withDependencies(
        userRepository: users,
        loanRepository: _MockLoanRepo(),
        loanScheduleRepository: _MockLoanScheduleRepo(),
        paymentRepository: _MockPaymentRepo(),
        storageRepository: _MockStorageRepo(),
        authService: auth,
      );

  void stubRequestOtpThrows(Object error) {
    when(
      () => users.requestOtpForUser(
        idToken: any(named: 'idToken'),
        targetUserId: any(named: 'targetUserId'),
      ),
    ).thenThrow(error);
  }

  group('PaymentBloc requestOtp', () {
    blocTest<PaymentBloc, PaymentState>(
      'surfaces the server 400 reason verbatim',
      setUp: () => stubRequestOtpThrows(
        RequestOtpException(400, 'No address is on file for this account.'),
      ),
      build: buildPaymentBloc,
      act: (bloc) => bloc.add(
        const RequestPaymentOtpEvent(borrowerUserId: 'borrower-1'),
      ),
      skip: 2,
      expect: () => [
        const PaymentState.error('No address is on file for this account.'),
      ],
    );

    blocTest<PaymentBloc, PaymentState>(
      "keeps this flow's own copy for a 500 instead of the auth wording",
      setUp: () => stubRequestOtpThrows(RequestOtpException(500, 'boom')),
      build: buildPaymentBloc,
      act: (bloc) => bloc.add(
        const RequestPaymentOtpEvent(borrowerUserId: 'borrower-1'),
      ),
      skip: 2,
      expect: () => [const PaymentState.error('Failed to send OTP')],
    );

    blocTest<PaymentBloc, PaymentState>(
      'never leaks a raw 401 SDK body to the user',
      setUp: () => stubRequestOtpThrows(
        RequestOtpException(
          401,
          'firebase admin initialization error: google: could not find '
          'default credentials',
        ),
      ),
      build: buildPaymentBloc,
      act: (bloc) => bloc.add(
        const RequestPaymentOtpEvent(borrowerUserId: 'borrower-1'),
      ),
      skip: 2,
      expect: () => [
        const PaymentState.error(
          'Your session has expired. Please sign in again.',
        ),
      ],
    );
  });

  group('PaymentCenterBloc requestOtp', () {
    // The screen-level listener pops the topmost root route on
    // PaymentCenterStatus.error — which during this flow is the OTP dialog
    // itself. A recoverable OTP failure must therefore report otpError, or the
    // payment is torn down by the very message telling the user how to fix it.
    blocTest<PaymentCenterBloc, PaymentCenterState>(
      'reports otpError (not error) so the OTP dialog survives',
      setUp: () => stubRequestOtpThrows(
        RequestOtpException(400, 'No address is on file for this account.'),
      ),
      build: buildCenterBloc,
      act: (bloc) => bloc.add(
        const RequestOtpEvent(borrowerUserId: 'borrower-1'),
      ),
      skip: 1,
      verify: (bloc) {
        expect(bloc.state.status, PaymentCenterStatus.otpError);
        expect(bloc.state.status, isNot(PaymentCenterStatus.error));
        expect(bloc.state.message, 'No address is on file for this account.');
        expect(bloc.state.isLoading, isFalse);
      },
    );

    blocTest<PaymentCenterBloc, PaymentCenterState>(
      "falls back to this flow's copy for a 500",
      setUp: () => stubRequestOtpThrows(RequestOtpException(500, 'boom')),
      build: buildCenterBloc,
      act: (bloc) => bloc.add(
        const RequestOtpEvent(borrowerUserId: 'borrower-1'),
      ),
      skip: 1,
      verify: (bloc) {
        expect(bloc.state.status, PaymentCenterStatus.otpError);
        expect(bloc.state.message, 'Failed to send OTP');
      },
    );

    blocTest<PaymentCenterBloc, PaymentCenterState>(
      'reports otpError for an unexpected non-HTTP failure too',
      setUp: () => stubRequestOtpThrows(StateError('unexpected')),
      build: buildCenterBloc,
      act: (bloc) => bloc.add(
        const RequestOtpEvent(borrowerUserId: 'borrower-1'),
      ),
      skip: 1,
      verify: (bloc) {
        expect(bloc.state.status, PaymentCenterStatus.otpError);
        expect(bloc.state.message, 'Failed to send OTP');
      },
    );
  });

  group('PaymentCenterBloc verifyOtp', () {
    blocTest<PaymentCenterBloc, PaymentCenterState>(
      'surfaces the actionable expiry reason and keeps the dialog open',
      setUp: () {
        when(
          () => users.verifyOtp(
            idToken: any(named: 'idToken'),
            token: any(named: 'token'),
            otp: any(named: 'otp'),
          ),
        ).thenThrow(VerifyOtpException(400, 'OTP expired'));
      },
      build: buildCenterBloc,
      act: (bloc) => bloc.add(
        const VerifyOtpEvent(token: 't', otp: '123456'),
      ),
      skip: 1,
      verify: (bloc) {
        expect(bloc.state.status, PaymentCenterStatus.otpError);
        expect(bloc.state.message, 'OTP expired');
      },
    );
  });
}
