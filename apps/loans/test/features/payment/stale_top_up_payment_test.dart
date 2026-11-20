import 'dart:typed_data';

import 'package:company_repository/company_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/loans/bloc/additional_loan_bloc.dart';
import 'package:loooans/features/loans/bloc/payment_bloc.dart';
import 'package:loooans/features/payment_center/bloc/payment_center_bloc.dart';
import 'package:loooans/features/products/requirement_temp_container.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:payment_repository/payment_repository.dart';
import 'package:storage_repository/storage_repository.dart';
import 'package:user_repository/user_repository.dart';

// Review of finstack#149: LoanRepository.update wrote back every top-up the
// caller had loaded. A teller payment from a screen opened while a top-up was
// pending, made after it was approved, reset it to pending; an unapproved
// top-up is not billed, so the bill shrank. The loan repository here is the
// real one on a fake Firestore; the mock in front of it only drops the loan
// view write (its repository needs the real Firestore).

class _Users extends Mock implements UserRepository {}

class _Loans extends Mock implements LoanRepository {}

class _Schedules extends Mock implements LoanScheduleRepository {}

class _Payments extends Mock implements PaymentRepository {}

class _Storage extends Mock implements StorageRepository {}

class _Auth extends Mock implements AuthenticationService {}

final approvedAt = DateTime.utc(2026, 11, 19, 1);

Loan newLoan() => Loan.create(
      userId: 'u1',
      companyId: 'co-1',
      productId: 'p-1',
      amount: 10000,
      additionalCharges: 0,
      deductions: 0,
      period: 0,
      requirements: [],
      isForceCollect: false,
      status: LoanStatus.approved,
      dueAt: null,
      reason: '',
      interestRate: 5,
      term: '1m',
      amortization: 500,
    );

AdditionalLoanAmount newTopUp(String loanId, double amount) =>
    AdditionalLoanAmount.create(
      loanId: loanId,
      amount: amount,
      additionalCharges: 0,
      advanceCharges: 0,
      deductions: 0,
      selfiePhotoUrl: ImageUrl(name: 'selfie'),
      signatureUrl: ImageUrl(name: 'signature'),
    );

/// An open-term bill due in five days: 500 interest on 10,000.
LoanSchedule bill(String loanId) => LoanSchedule()
  ..id = 'sched-1'
  ..loanId = loanId
  ..companyId = 'co-1'
  ..createdAt = DateTime.now()
  ..updatedAt = DateTime.now()
  ..dueAt = DateTime.now().add(const Duration(days: 5))
  ..status = LoanStatus.approved
  ..isOpenTerm = true
  ..outstandingBalance = 10000
  ..principalPayment = 0
  ..interestPayment = 0
  ..interestCharge = 500
  ..amortization = 500
  ..extraPayment = 0
  ..advanceInterestPayments = 0
  ..interestDayMultiplier = 1;

void main() {
  late LoanRepository real;
  late _Loans loans;
  late _Payments payments;
  late _Schedules schedules;
  late _Users users;
  late _Auth auth;
  late _Storage storage;
  late String loanId;
  late String topUpId;

  setUpAll(() {
    registerFallbackValue(Payment());
    registerFallbackValue(LoanSchedule());
    registerFallbackValue(Loan());
    registerFallbackValue(Uint8List(0));
    registerFallbackValue((AdditionalLoanAmount _) => null);
  });

  setUp(() async {
    real = LoanRepository.withFirestore(FakeFirebaseFirestore());
    final created = await real.add(data: newLoan());
    loanId = created.id;
    final withTopUp = await real.update(
      data: created..additionalLoanAmounts = [newTopUp(loanId, 5000)],
    );
    topUpId = withTopUp.additionalLoanAmounts.single.id;

    loans = _Loans();
    payments = _Payments();
    schedules = _Schedules();
    users = _Users();
    auth = _Auth();
    storage = _Storage();
    when(() => loans.get(id: any(named: 'id'))).thenAnswer(
      (i) => real.get(id: i.namedArguments[#id] as String),
    );
    when(
      () => loans.update(
        data: any(named: 'data'),
        updateView: any(named: 'updateView'),
        updateAdditionalLoanAmounts: any(named: 'updateAdditionalLoanAmounts'),
      ),
    ).thenAnswer((i) {
      final data = i.namedArguments[#data] as Loan;
      final topUps = i.namedArguments[#updateAdditionalLoanAmounts] as bool?;

      return topUps == null
          ? real.update(data: data)
          : real.update(data: data, updateAdditionalLoanAmounts: topUps);
    });
    // Approval and decline write the top-up in a transaction (#149).
    when(
      () => loans.transactAdditionalLoanAmount(
        id: any(named: 'id'),
        change: any(named: 'change'),
      ),
    ).thenAnswer(
      (i) => real.transactAdditionalLoanAmount(
        id: i.namedArguments[#id] as String,
        change: i.namedArguments[#change] as AdditionalLoanAmount? Function(
          AdditionalLoanAmount,
        ),
      ),
    );
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
      () => storage.upload(
        data: any(named: 'data'),
        folder: any(named: 'folder'),
        fileName: any(named: 'fileName'),
        uploadOriginalSize: any(named: 'uploadOriginalSize'),
        includeOriginal: any(named: 'includeOriginal'),
        forceDecodeToImage: any(named: 'forceDecodeToImage'),
      ),
    ).thenAnswer((_) async => ImageUrl(name: 'upload'));
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

  /// The screen's copy, loaded while the top-up was pending; the top-up is
  /// then approved (fresh copy, top-ups written).
  Future<Loan> staleCopyThenApprove() async {
    final stale = await real.get(id: loanId);
    expect(stale.additionalLoanAmounts.single.status, LoanStatus.pending);
    final fresh = await real.get(id: loanId);
    fresh.additionalLoanAmounts.single
      ..status = LoanStatus.approved
      ..approvedAt = approvedAt;
    await real.update(data: fresh, updateAdditionalLoanAmounts: true);

    return stale;
  }

  Future<void> expectTopUpStillApproved() async {
    final loan = await real.get(id: loanId);
    // The payment did write the loan (its status moved).
    expect(loan.status, LoanStatus.paid_on_time);
    final topUp = loan.additionalLoanAmounts.single;
    expect(topUp.id, topUpId);
    expect(topUp.status, LoanStatus.approved);
    expect(topUp.approvedAt?.isAtSameMomentAs(approvedAt), isTrue);
  }

  test('client detail (PaymentBloc): the stale copy keeps the approval',
      () async {
    final stale = await staleCopyThenApprove();
    final bloc = PaymentBloc.withDependencies(
      userRepository: users,
      loanRepository: loans,
      loanScheduleRepository: schedules,
      storageRepository: storage,
      paymentRepository: payments,
      authService: auth,
    );
    addTearDown(bloc.close);

    bloc.makePayment(
      loan: stale,
      schedule: bill(loanId),
      interestPayment: '500',
      payment: '0',
      otpVerified: true,
    );
    // It writes the loan and the row, then stops at the cash pool (not
    // mockable here).
    await bloc.stream.firstWhere((s) => s.message?.isNotEmpty ?? false);

    await expectTopUpStillApproved();
  });

  for (final bulk in [false, true]) {
    test(
        'the Payment Center ${bulk ? 'bulk' : 'single'} payment: the stale '
        'copy keeps the approval', () async {
      final stale = await staleCopyThenApprove();
      final bloc = PaymentCenterBloc.withDependencies(
        userRepository: users,
        loanRepository: loans,
        loanScheduleRepository: schedules,
        paymentRepository: payments,
        storageRepository: storage,
        authService: auth,
      );
      addTearDown(bloc.close);

      bloc.add(
        bulk
            ? MakeOverduePaymentEvent(
                loan: stale,
                schedules: [bill(loanId)],
                totalPrincipalPayment: 0,
                totalInterestPayment: 500,
                otpVerified: true,
              )
            : MakePaymentEvent(
                loan: stale,
                schedule: bill(loanId),
                interestPayment: 500,
                payment: 0,
                otpVerified: true,
              ),
      );
      await bloc.stream.firstWhere(
        (s) =>
            s.status == PaymentCenterStatus.error ||
            s.status == PaymentCenterStatus.paymentSuccess,
      );

      await expectTopUpStillApproved();
    });
  }

  test('approval writes the top-up: approved, with approved_at', () async {
    final bloc = AdditionalLoanBloc.withDependencies(
      loanRepository: loans,
      storageRepository: storage,
    );
    addTearDown(bloc.close);

    bloc.updateAdditionalLoanAmount(
      loanId: loanId,
      additionalLoanAmountId: topUpId,
      status: LoanStatus.approved,
    );
    final state = await bloc.stream.firstWhere(
      (s) =>
          s.status == AdditionalLoanStatus.success ||
          s.status == AdditionalLoanStatus.error,
    );
    expect(state.status, AdditionalLoanStatus.success, reason: state.message);

    final topUp = (await real.get(id: loanId)).additionalLoanAmounts.single;
    expect(topUp.status, LoanStatus.approved);
    expect(topUp.approvedAt, isNotNull);
  });

  test('adding a top-up writes it and leaves the approved one alone', () async {
    await staleCopyThenApprove();
    final bloc = AdditionalLoanBloc.withDependencies(
      loanRepository: loans,
      storageRepository: storage,
    );
    addTearDown(bloc.close);

    bloc.addLoanAmount(
      loanId,
      '3000',
      selfiePhoto: SimpleFileData('selfie.png', Uint8List(1)),
      signatureBytes: Uint8List(1),
    );
    final state = await bloc.stream.firstWhere(
      (s) =>
          s.status == AdditionalLoanStatus.success ||
          s.status == AdditionalLoanStatus.error,
    );
    expect(state.status, AdditionalLoanStatus.success, reason: state.message);

    final topUps = (await real.get(id: loanId)).additionalLoanAmounts;
    expect(topUps, hasLength(2));
    final approved = topUps.singleWhere((t) => t.id == topUpId);
    expect(approved.status, LoanStatus.approved);
    expect(approved.approvedAt?.isAtSameMomentAs(approvedAt), isTrue);
    final added = topUps.singleWhere((t) => t.id != topUpId);
    expect(added.amount, 3000);
    expect(added.status, LoanStatus.pending);
  });
}
