import 'package:company_repository/company_repository.dart';
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

// finstack#138: approval stores an open-term loan's principal release for
// app-managed companies as a plain row (whole principal as
// principal_payment, nothing to collect; isPlaceholder is not stored).
// Recording it as a payment books the whole loan as repaid on the day it was
// released. No teller path may record it: client detail (PaymentBloc) and
// the Payment Center single and bulk payments refuse it and write nothing.

class _Users extends Mock implements UserRepository {}

class _Loans extends Mock implements LoanRepository {}

class _Schedules extends Mock implements LoanScheduleRepository {}

class _Payments extends Mock implements PaymentRepository {}

class _Storage extends Mock implements StorageRepository {}

class _Auth extends Mock implements AuthenticationService {}

/// The principal release as approval stores it.
LoanSchedule storedRelease() => LoanSchedule()
  ..id = 'planned'
  ..loanId = 'loan-1'
  ..companyId = 'co-1'
  ..createdAt = DateTime(2026, 7, 2)
  ..updatedAt = DateTime(2026, 7, 2)
  ..dueAt = DateTime(2026, 7, 2)
  ..status = LoanStatus.not_paid_overdue
  ..isOpenTerm = true
  ..outstandingBalance = 0
  ..principalPayment = 10000
  ..interestPayment = 0
  ..interestCharge = 0
  ..amortization = 0
  ..extraPayment = 0
  ..advanceInterestPayments = 0
  ..interestDayMultiplier = 1;

Loan openTermLoan() => Loan()
  ..id = 'loan-1'
  ..userId = 'u1'
  ..createdAt = DateTime(2026, 7, 2)
  ..status = LoanStatus.approved
  ..period = 0
  ..term = '1m'
  ..penalties = []
  ..allowLatePayments = false
  ..additionalLoanAmounts = [];

void main() {
  late _Payments payments;
  late _Schedules schedules;
  late _Users users;
  late _Loans loans;
  late _Auth auth;

  setUpAll(() {
    registerFallbackValue(Payment());
    registerFallbackValue(LoanSchedule());
    registerFallbackValue(Loan());
  });

  setUp(() {
    payments = _Payments();
    schedules = _Schedules();
    users = _Users();
    loans = _Loans();
    auth = _Auth();
    // Without the guard every path would get as far as writing the row.
    when(() => users.get(id: any(named: 'id'))).thenAnswer(
      (_) async => User()
        ..id = 'u1'
        ..firstName = 'Bea'
        ..lastName = 'Borrower'
        ..emailAddress = 'bea@example.com',
    );
    when(() => payments.add(data: any(named: 'data'))).thenAnswer(
      (i) async => (i.namedArguments[#data] as Payment)..id = 'pay-1',
    );
    when(() => payments.update(data: any(named: 'data'))).thenAnswer(
      (i) async => i.namedArguments[#data] as Payment,
    );
    when(() => schedules.add(data: any(named: 'data'))).thenAnswer(
      (i) async => i.namedArguments[#data] as LoanSchedule,
    );
    when(() => schedules.update(data: any(named: 'data'))).thenAnswer(
      (i) async => i.namedArguments[#data] as LoanSchedule,
    );
    when(
      () => schedules.allByLoanId(
        loanId: any(named: 'loanId'),
        onlyPaid: any(named: 'onlyPaid'),
      ),
    ).thenAnswer((_) async => []);
    when(
      () => loans.update(
        data: any(named: 'data'),
        updateView: any(named: 'updateView'),
      ),
    ).thenAnswer((i) async => i.namedArguments[#data] as Loan);
    when(() => auth.company).thenReturn(
      Company()
        ..id = 'co-1'
        ..managementType = CompanyManagementType.selfManaged,
    );
    when(() => auth.user).thenReturn(
      User()
        ..id = 'teller-1'
        ..firstName = 'Tess'
        ..lastName = 'Teller'
        ..emailAddress = 'teller@example.com',
    );
  });

  test('the stored principal release is recognised; a bill is not', () {
    expect(storedRelease().isPrincipalRelease, isTrue);
    final bill = storedRelease()
      ..principalPayment = 0
      ..interestCharge = 500
      ..amortization = 500;
    expect(bill.isPrincipalRelease, isFalse);
    final billPaidWithPrincipal = storedRelease()
      ..principalPayment = 1000
      ..interestCharge = 500
      ..amortization = 500;
    expect(billPaidWithPrincipal.isPrincipalRelease, isFalse);

    // A 0% loan's bill paid with principal: nothing charged or due, like the
    // release, but a balance left, or interest recorded (a teller must
    // enter interest above 0) when it was paid off.
    final zeroRateBill = storedRelease()
      ..status = LoanStatus.paid_on_time
      ..principalPayment = 1000
      ..outstandingBalance = 9000
      ..interestPayment = 1;
    expect(zeroRateBill.isPrincipalRelease, isFalse);
    final zeroRatePaidOff = zeroRateBill
      ..principalPayment = 10000
      ..outstandingBalance = 0;
    expect(zeroRatePaidOff.isPrincipalRelease, isFalse);
    // Overpaid: balance 10,000, 12,000 paid -> -2,000, not minus the
    // principal paid (a teller-paid release ends at exactly -principal).
    final zeroRateOverpaid = storedRelease()
      ..status = LoanStatus.paid_on_time
      ..principalPayment = 12000
      ..outstandingBalance = -2000
      ..interestPayment = 1;
    expect(zeroRateOverpaid.isPrincipalRelease, isFalse);
    final zeroRateOverpaidNoInterest = storedRelease()
      ..status = LoanStatus.paid_on_time
      ..principalPayment = 12000
      ..outstandingBalance = -2000;
    expect(zeroRateOverpaidNoInterest.isPrincipalRelease, isFalse);

    // The release confirmed from a submission before #138, or paid by a
    // teller (balance -10,000 and the interest they had to enter).
    expect(
      (storedRelease()..status = LoanStatus.paid_on_time).isPrincipalRelease,
      isTrue,
    );
    expect(
      (storedRelease()
            ..status = LoanStatus.paid_on_time
            ..outstandingBalance = -10000
            ..interestPayment = 1)
          .isPrincipalRelease,
      isTrue,
    );
  });

  test('client detail (PaymentBloc) refuses it and writes nothing', () async {
    final bloc = PaymentBloc.withDependencies(
      userRepository: users,
      loanRepository: loans,
      loanScheduleRepository: schedules,
      storageRepository: _Storage(),
      paymentRepository: payments,
      authService: auth,
    );
    addTearDown(bloc.close);

    bloc.makePayment(
      loan: openTermLoan(),
      schedule: storedRelease(),
      interestPayment: '0',
      payment: '10000',
      otpVerified: true,
    );
    final state = await bloc.stream.firstWhere(
      (s) => s.message != null && s.message!.isNotEmpty,
    );

    expect(state.message, 'Something went wrong while paying schedule');
    verifyNever(() => payments.add(data: any(named: 'data')));
    verifyNever(() => schedules.update(data: any(named: 'data')));
  });

  for (final bulk in [false, true]) {
    test(
        'the Payment Center ${bulk ? 'bulk' : 'single'} payment refuses it '
        'and writes nothing', () async {
      final bloc = PaymentCenterBloc.withDependencies(
        userRepository: users,
        loanRepository: loans,
        loanScheduleRepository: schedules,
        paymentRepository: payments,
        storageRepository: _Storage(),
        authService: auth,
      );
      addTearDown(bloc.close);

      bloc.add(
        bulk
            ? MakeOverduePaymentEvent(
                loan: openTermLoan(),
                schedules: [storedRelease()],
                totalPrincipalPayment: 10000,
                totalInterestPayment: 1,
                otpVerified: true,
              )
            : MakePaymentEvent(
                loan: openTermLoan(),
                schedule: storedRelease(),
                payment: 10000,
                otpVerified: true,
              ),
      );
      final state = await bloc.stream.firstWhere(
        (s) => s.status == PaymentCenterStatus.error,
      );

      expect(state.status, PaymentCenterStatus.error);
      verifyNever(() => payments.add(data: any(named: 'data')));
      verifyNever(() => schedules.add(data: any(named: 'data')));
      verifyNever(() => schedules.update(data: any(named: 'data')));
    });
  }
}
