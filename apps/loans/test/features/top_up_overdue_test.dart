import 'dart:typed_data';

import 'package:company_repository/company_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
// Top-ups are read back through this entity, which the package does not
// export.
// ignore: implementation_imports
import 'package:loan_repository/src/model/additional_loan_amount_entity.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/loans/bloc/additional_loan_bloc.dart';
import 'package:loooans/features/loans/screens/loan_details.dart';
import 'package:loooans/features/loans/widget/top_up_overdue_dialogs.dart';
import 'package:loooans/features/payment_center/bloc/payment_center_bloc.dart';
import 'package:loooans/features/products/requirement_temp_container.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans/services/top_up_overdue_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:payment_repository/payment_repository.dart';
import 'package:storage_repository/storage_repository.dart';
import 'package:user_repository/user_repository.dart';

import '../helpers/helpers.dart';

// The owner's soft block for a top-up on an overdue open-term loan
// (2026-11-19) through the real AdditionalLoanBloc and the real dialogs.
//
// Loan: 40,000 open term at 5%, term '15d', created 20 days ago (D-20).
// Bills: D-5 (15 days, 1,000, missed) and D+10 (the current bill). Penalties
// "Late fee" 100 once + "Daily 0.1%" of the balance in force each day.
// Today: the D-5 bill is 5 days late -> 100 + 5 x 40 = 300. Pay now =
// 1,300. Top-up 10,000, no charges: proceeds 10,000.
//
// Deduct, approved today: claimed in a transaction (plan, 1,300, payment id
// topup-1-1), then one payment and one row at id topup-1-1 (D-5, paid_late,
// collected today, 5 days late, penalty 300, interest 1,000, principal 0,
// balance 40,000), then approved; 8,700 released; no cash-pool entry (the
// bloc has no cash-pool dependency). Next bill D+10: D-5..D on 40,000
// (5 days, 333.33) + D..D+10 on 50,000 (10 days, 833.33) = 1,166.67.
// Add to the next bill, top-up added yesterday (D-1) and approved today:
// the balance moves on the approval day (review of #149), so D+10 is still
// 333.33 + 833.33 = 1,166.67 (from the creation day it would be 4 days on
// 40,000 + 11 on 50,000 = 266.67 + 916.67 = 1,183.33). Today the borrower
// owes 1,300. On D+10: 1,000 + 1,166.67 + penalty over 15 days: 100 once
// + 5 x 40 (D-5..D-1) + 10 x 50 (D..D+9) = 800 (from the creation day:
// 100 + 4 x 40 + 11 x 50 = 810) -> 2,966.67.
// A day later: a top-up added yesterday and approved today deducts today's
// 1,300 (yesterday it showed 1,260 = 1,000 + 100 + 4 x 40).
// Two missed bills (loan created D-35): D-20 and D-5, 1,000 each; the
// stretch from D-20: 100 + 20 x 40 = 900 once, on D-20 -> 2,900; 7,100
// released.

const lateFee100 = Penalty(id: 'late-fee', name: 'Late fee', amount: 100);
const daily01pct = Penalty(
  id: 'daily-01',
  name: 'Daily 0.1%',
  amount: 0.1,
  isPercentage: true,
  frequency: PenaltyFrequency.daily,
);

DateTime get today => DateUtils.dateOnly(DateTime.now());

DateTime daysFromToday(int days) => DateUtils.addDaysToDate(today, days);

Loan loan40k({
  List<AdditionalLoanAmount> topUps = const [],
  int createdDaysAgo = 20,
}) =>
    Loan.create(
      userId: 'u1',
      companyId: 'co-1',
      productId: 'pr-1',
      amount: 40000,
      additionalCharges: 0,
      deductions: 0,
      period: 0,
      requirements: const [],
      isForceCollect: false,
      status: LoanStatus.approved,
      dueAt: null,
      reason: 'open term',
      interestRate: 5,
      term: '15d',
      amortization: 1000,
      penalties: const [lateFee100, daily01pct],
    )
      ..id = 'loan-1'
      ..createdAt = daysFromToday(-createdDaysAgo)
      ..additionalLoanAmounts = List.of(topUps);

AdditionalLoanAmount pendingTopUp({
  OverdueChoice? choice = OverdueChoice.deduct,
  double amount = 10000,
  int createdDaysAgo = 0,
}) =>
    AdditionalLoanAmount.create(
      loanId: 'loan-1',
      amount: amount,
      additionalCharges: 0,
      advanceCharges: 0,
      deductions: 0,
      selfiePhotoUrl: ImageUrl(name: 'selfie'),
      signatureUrl: ImageUrl(name: 'signature'),
      overdueChoice: choice,
    )
      ..id = 'topup-1'
      ..createdAt = DateTime.now().subtract(Duration(days: createdDaysAgo));

/// What client detail lists for [loan] with [stored] rows, on [now].
List<LoanSchedule> clientRows(
  Loan loan, {
  List<LoanSchedule> stored = const [],
  DateTime? now,
}) =>
    LoanCalculationService.calculateOpenTerm(
      amount: 40000,
      date: loan.createdAt,
      interestRate: 5,
      term: '15d',
      companyId: 'co-1',
      paidSchedules: stored,
      loan: loan,
      now: now ?? DateTime.now(),
    ).schedules;

/// [row] as Firestore hands it back.
LoanSchedule roundTrip(LoanSchedule row) => LoanSchedule.fromJson(row.toJson());

AdditionalLoanAmount topUpFrom(Map<String, dynamic> json) =>
    AdditionalLoanAmountEntity.fromJson(json).toAdditionalLoanAmount();

/// A Firestore stand-in: every read returns new objects, a top-up change is
/// one read-modify-write with nothing in between (as in a transaction),
/// documents are keyed by id, and writes can be delayed or made to fail.
class _Store {
  _Store({this.loanCreatedDaysAgo = 20, AdditionalLoanAmount? topUp}) {
    if (topUp != null) {
      topUps[topUp.id] = topUp.toJson();
    }
  }

  final int loanCreatedDaysAgo;
  final topUps = <String, Map<String, dynamic>>{};
  final payments = <String, Payment>{};
  final rows = <String, LoanSchedule>{};
  final storedBefore = <LoanSchedule>[];
  final log = <String>[];
  LoanStatus loanStatus = LoanStatus.approved;
  bool viewUpdated = false;
  int paymentWrites = 0;

  /// The n-th payment write (1-based) throws.
  int? failPaymentWrite;
  Duration delay = Duration.zero;

  AdditionalLoanAmount topUp([String id = 'topup-1']) => topUpFrom(topUps[id]!);

  Loan loan() => loan40k(
        createdDaysAgo: loanCreatedDaysAgo,
        topUps: [for (final json in topUps.values) topUpFrom(json)],
      )..status = loanStatus;
}

class _Loans extends Mock implements LoanRepository {}

class _Schedules extends Mock implements LoanScheduleRepository {}

class _Payments extends Mock implements PaymentRepository {}

class _Storage extends Mock implements StorageRepository {}

class _Users extends Mock implements UserRepository {}

class _Auth extends Mock implements AuthenticationService {}

AuthenticationService officer({
  CompanyManagementType type = CompanyManagementType.selfManaged,
}) {
  final auth = _Auth();
  when(() => auth.company).thenReturn(
    Company()
      ..id = 'co-1'
      ..managementType = type,
  );
  when(() => auth.user).thenReturn(
    User()
      ..id = 'officer-1'
      ..firstName = 'Olive'
      ..lastName = 'Officer'
      ..emailAddress = 'officer@example.com',
  );
  return auth;
}

void main() {
  setUpAll(() {
    registerFallbackValue(Loan());
    registerFallbackValue(LoanSchedule());
    registerFallbackValue(Payment());
    registerFallbackValue(Uint8List(0));
    registerFallbackValue((AdditionalLoanAmount _) => null);
  });

  group('AdditionalLoanBloc (the real handlers)', () {
    late _Store store;
    var managementType = CompanyManagementType.selfManaged;

    AdditionalLoanBloc newBloc() {
      final loans = _Loans();
      final schedules = _Schedules();
      final payments = _Payments();
      final storage = _Storage();

      when(() => loans.get(id: any(named: 'id')))
          .thenAnswer((_) async => store.loan());
      when(
        () => loans.transactAdditionalLoanAmount(
          id: any(named: 'id'),
          change: any(named: 'change'),
        ),
      ).thenAnswer((invocation) async {
        await Future<void>.delayed(store.delay);
        final id = invocation.namedArguments[#id] as String;
        final change = invocation.namedArguments[#change]
            as AdditionalLoanAmount? Function(AdditionalLoanAmount);
        // Read, change and write with no await in between.
        final next = change(store.topUp(id));
        if (next != null) {
          store.topUps[id] = next.toJson();
          store.log.add(
            'top-up ${next.status.name}'
            '${next.deductionPlan.isEmpty ? '' : ' claimed'}',
          );
        }
        return store.topUp(id);
      });
      when(
        () => loans.update(
          data: any(named: 'data'),
          updateView: any(named: 'updateView'),
          updateAdditionalLoanAmounts:
              any(named: 'updateAdditionalLoanAmounts'),
        ),
      ).thenAnswer((invocation) async {
        final loan = invocation.namedArguments[#data] as Loan;
        store
          ..loanStatus = loan.status
          ..viewUpdated |=
              invocation.namedArguments[#updateView] as bool? ?? false
          ..log.add('loan ${loan.status.name}');
        if (invocation.namedArguments[#updateAdditionalLoanAmounts] as bool? ??
            true) {
          for (final topUp in loan.additionalLoanAmounts) {
            if (topUp.id == NO_ID) {
              topUp.id = 'topup-new';
            }
            store.topUps[topUp.id] = topUp.toJson();
          }
        }
        return loan;
      });
      when(
        () => schedules.allByLoanId(
          loanId: any(named: 'loanId'),
          onlyPaid: any(named: 'onlyPaid'),
        ),
      ).thenAnswer(
        (_) async => [
          for (final row in [...store.storedBefore, ...store.rows.values])
            roundTrip(row),
        ],
      );
      when(() => schedules.set(data: any(named: 'data'))).thenAnswer(
        (invocation) async {
          await Future<void>.delayed(store.delay);
          final row = invocation.namedArguments[#data] as LoanSchedule;
          store.rows[row.id] = roundTrip(row);
          store.log.add('row ${row.id}');
          return row;
        },
      );
      when(() => payments.set(data: any(named: 'data'))).thenAnswer(
        (invocation) async {
          await Future<void>.delayed(store.delay);
          final payment = invocation.namedArguments[#data] as Payment;
          if (++store.paymentWrites == store.failPaymentWrite) {
            throw Exception('network down');
          }
          store.payments[payment.id] = Payment.fromJson(payment.toJson());
          store.log.add('payment ${payment.id}');
          return payment;
        },
      );
      when(
        () => storage.upload(
          data: any(named: 'data'),
          folder: any(named: 'folder'),
          fileName: any(named: 'fileName'),
        ),
      ).thenAnswer(
        (invocation) async =>
            ImageUrl(name: invocation.namedArguments[#fileName] as String),
      );

      final bloc = AdditionalLoanBloc.withDependencies(
        authService: officer(type: managementType),
        loanRepository: loans,
        storageRepository: storage,
        loanScheduleRepository: schedules,
        paymentRepository: payments,
      );
      addTearDown(bloc.close);
      return bloc;
    }

    setUp(() {
      store = _Store(topUp: pendingTopUp());
      managementType = CompanyManagementType.selfManaged;
    });

    Future<AdditionalLoanState> settled(AdditionalLoanBloc bloc) =>
        bloc.stream.firstWhere(
          (s) =>
              s.status == AdditionalLoanStatus.success ||
              s.status == AdditionalLoanStatus.error,
        );

    void send(
      AdditionalLoanBloc bloc, {
      double? expected,
      LoanStatus status = LoanStatus.approved,
    }) =>
        bloc.updateAdditionalLoanAmount(
          loanId: 'loan-1',
          additionalLoanAmountId: 'topup-1',
          status: status,
          expectedDeduction: expected,
        );

    Future<AdditionalLoanState> approve({
      double? expected,
      LoanStatus status = LoanStatus.approved,
    }) {
      final bloc = newBloc();
      send(bloc, expected: expected, status: status);
      return settled(bloc);
    }

    void expectNothingPaid() {
      expect(store.payments, isEmpty);
      expect(store.rows, isEmpty);
    }

    test('adding with "deduct" stores the choice and nothing else', () async {
      store = _Store();
      final bloc = newBloc()
        ..addLoanAmount(
          'loan-1',
          '10000',
          selfiePhoto: SimpleFileData('selfie.png', Uint8List(1)),
          signatureBytes: Uint8List(1),
          overdueChoice: OverdueChoice.deduct,
        );

      expect((await settled(bloc)).status, AdditionalLoanStatus.success);
      final topUp = store.topUp('topup-new');
      expect(topUp.amount, 10000);
      expect(topUp.status, LoanStatus.pending);
      expect(topUp.overdueChoice, OverdueChoice.deduct);
      expect(topUp.approvedAt, isNull);
      expect(topUp.overdueDeduction, 0);
      expect(topUp.deductionPlan, isEmpty);
      expect(store.loanStatus, LoanStatus.approved);
      expectNothingPaid();
    });

    test(
        'approving "deduct": claimed, the bill paid from the top-up at '
        'fixed ids, approved; 8,700 released', () async {
      final before = DateTime.now();
      final state = await approve(expected: 1300);
      final after = DateTime.now();

      expect(state.status, AdditionalLoanStatus.success, reason: state.message);
      expect(state.message, contains(8700.toCurrency()));
      // The claim comes before any payment or row; approval after them.
      expect(store.log, [
        'top-up pending claimed',
        'payment topup-1-1',
        'row topup-1-1',
        'top-up approved claimed',
        'loan paid_late',
      ]);

      // One confirmed payment per bill, naming the top-up, one push.
      final payment = store.payments.values.single;
      expect(payment.id, 'topup-1-1');
      expect(payment.userId, 'u1');
      expect(payment.loanId, 'loan-1');
      expect(payment.loanScheduleId, 'topup-1-1');
      expect(payment.submissionId, 'topup-1');
      expect(payment.status, PaymentStatus.confirmed);
      expect(payment.confirmedBy, 'officer-1');
      expect(payment.transactionPhotoUrl, isNull);
      expect(payment.comment, contains('Paid from additional loan topup-1'));

      // The row: late, collected now, with its penalty.
      final row = store.rows.values.single;
      expect(row.id, 'topup-1-1');
      expect(DateUtils.dateOnly(row.dueAt.toLocal()), daysFromToday(-5));
      expect(row.status, LoanStatus.paid_late);
      expect(
        row.collectedAt!.millisecondsSinceEpoch,
        inInclusiveRange(
          before.millisecondsSinceEpoch,
          after.millisecondsSinceEpoch,
        ),
      );
      expect(row.daysLate, 5);
      expect(row.penalty, closeTo(300, 0.001));
      expect(row.penalties, [lateFee100, daily01pct]);
      expect(row.interestPayment, closeTo(1000, 0.001));
      expect(row.principalPayment, 0);
      expect(row.outstandingBalance, 40000);
      expect(row.paymentId, 'topup-1-1');
      expect(row.loanId, 'loan-1');

      final topUp = store.topUp();
      expect(topUp.status, LoanStatus.approved);
      expect(topUp.overdueDeduction, 1300);
      expect(topUp.deductedPaymentIds, ['topup-1-1']);
      expect(topUp.deductedAt, row.collectedAt);
      expect(topUp.deductionPlan, hasLength(1));
      expect(
        TopUpOverdueService.proceeds(topUp) - topUp.overdueDeduction,
        8700,
      );
      // Approved after the row was computed: the row does not hold it.
      expect(topUp.approvedAt!.isBefore(row.createdAt), isFalse);
      expect(store.loanStatus, LoanStatus.paid_late);
      expect(store.viewUpdated, isTrue);

      // The next bill splits at the top-up's day; nothing is overdue.
      final approvedLoan = store.loan();
      final rows = clientRows(approvedLoan, stored: [row]);
      final next = rows.lastWhere((r) => r.id == NO_ID && !r.isPlaceholder);
      expect(DateUtils.dateOnly(next.dueAt), daysFromToday(10));
      expect(next.outstandingBalance, 50000);
      expect(next.amortization, closeTo(333.33 + 833.33, 0.01));
      expect(
        TopUpOverdueService.overdue(loan: approvedLoan, schedules: rows),
        isNull,
      );
    });

    test(
        '"add to the next bill", added yesterday, approved today: only the '
        'approval; the balance moves today', () async {
      store = _Store(
        topUp: pendingTopUp(choice: OverdueChoice.nextBill, createdDaysAgo: 1),
      );

      final state = await approve(expected: 0);

      expect(state.status, AdditionalLoanStatus.success, reason: state.message);
      expectNothingPaid();
      expect(store.log, ['top-up approved']);
      final topUp = store.topUp();
      expect(topUp.approvedAt, isNotNull);
      expect(topUp.overdueDeduction, 0);
      expect(store.loanStatus, LoanStatus.approved);

      final approvedLoan = store.loan();
      // Today: the missed bill on the old balance, its penalty running.
      expect(
        TopUpOverdueService.overdue(
          loan: approvedLoan,
          schedules: clientRows(approvedLoan),
        )!
            .amount,
        1300,
      );

      // On the next bill's day: both bills and the stretch's penalty.
      final d10 = daysFromToday(10).add(const Duration(hours: 12));
      final due = borrowerAmountsDue(
        schedules: clientRows(approvedLoan, now: d10),
        loan: approvedLoan,
        asOf: d10,
      );
      expect(
        due.payNow.map((s) => DateUtils.dateOnly(s.dueAt)),
        [daysFromToday(-5), daysFromToday(10)],
      );
      expect(due.payNow.first.amortization, closeTo(1000, 0.001));
      expect(due.payNow.last.amortization, closeTo(1166.67, 0.01));
      expect(due.nextDuePenalty, closeTo(800, 0.001));
      expect(due.nextDueAmount, closeTo(2966.67, 0.01));
    });

    test('overdue amount more than the top-up: refused, nothing written',
        () async {
      store = _Store(topUp: pendingTopUp(amount: 1000));

      final state = await approve(expected: 1300);

      expect(state.status, AdditionalLoanStatus.error);
      expect(state.message, contains('more than the cash'));
      expectNothingPaid();
      expect(store.log, isEmpty);
      expect(store.topUp().deductionPlan, isEmpty);
    });

    test('declining a "deduct" top-up writes only the decline', () async {
      final state = await approve(status: LoanStatus.declined);

      expect(state.status, AdditionalLoanStatus.success);
      expectNothingPaid();
      expect(store.log, ['top-up declined']);
      expect(store.topUp().approvedAt, isNull);
      expect(store.topUp().overdueDeduction, 0);
    });

    test('a second approval is refused: no deduction, approved_at kept',
        () async {
      final approvedAt = DateTime.utc(2026, 1, 2);
      store = _Store(
        topUp: pendingTopUp()
          ..status = LoanStatus.approved
          ..approvedAt = approvedAt,
      );

      for (final status in [LoanStatus.approved, LoanStatus.declined]) {
        final state = await approve(expected: 1300, status: status);
        expect(state.status, AdditionalLoanStatus.error);
        expect(state.message, contains('already approved'));
      }
      expectNothingPaid();
      expect(store.log, isEmpty);
      expect(store.topUp().approvedAt, approvedAt);
    });

    test('approved a day later: deducts the approval day amount', () async {
      store = _Store(topUp: pendingTopUp(createdDaysAgo: 1));

      // What the dialog showed yesterday is refused, nothing written.
      final stale = await approve(expected: 1260);
      expect(stale.status, AdditionalLoanStatus.error);
      expect(stale.message, contains('now ${1300.toCurrency()}'));
      expectNothingPaid();
      expect(store.log, isEmpty);

      final state = await approve(expected: 1300);
      expect(state.status, AdditionalLoanStatus.success, reason: state.message);
      expect(store.rows.values.single.penalty, closeTo(300, 0.001));
      expect(store.topUp().overdueDeduction, 1300);
    });

    test('bills paid since the top-up was added are not deducted', () async {
      store.storedBefore.add(
        clientRows(loan40k()).firstWhere((r) => !r.isPlaceholder)
          ..id = 'paid-1'
          ..status = LoanStatus.paid_late
          ..paidAt = DateTime.now()
          ..collectedAt = DateTime.now()
          ..interestPayment = 1000,
      );

      final stale = await approve(expected: 1300);
      expect(stale.status, AdditionalLoanStatus.error);
      expectNothingPaid();

      final state = await approve(expected: 0);
      expect(state.status, AdditionalLoanStatus.success, reason: state.message);
      expectNothingPaid();
      expect(store.topUp().status, LoanStatus.approved);
      expect(store.topUp().overdueDeduction, 0);
    });

    test('an app-managed company cannot deduct', () async {
      managementType = CompanyManagementType.app;

      final state = await approve(expected: 1300);

      expect(state.status, AdditionalLoanStatus.error);
      expectNothingPaid();
      expect(store.log, isEmpty);
    });

    group('two approvals at once', () {
      setUp(() => store.delay = const Duration(milliseconds: 5));

      test('two devices: one deduction, one approval', () async {
        final a = newBloc();
        final b = newBloc();
        send(a, expected: 1300);
        send(b, expected: 1300);
        final states = await Future.wait([settled(a), settled(b)]);

        expect(
          states.map((s) => s.status),
          unorderedEquals([
            AdditionalLoanStatus.success,
            AdditionalLoanStatus.error,
          ]),
        );
        expect(
          states
              .firstWhere((s) => s.status == AdditionalLoanStatus.error)
              .message,
          contains('already approved'),
        );
        expect(store.payments.keys, ['topup-1-1']);
        expect(store.rows.keys, ['topup-1-1']);
        expect(store.log.where((l) => l.startsWith('top-up')), [
          'top-up pending claimed',
          'top-up approved claimed',
        ]);
        expect(store.topUp().deductedPaymentIds, ['topup-1-1']);
        expect(store.topUp().overdueDeduction, 1300);
      });

      test('approve and decline at once: never declined with bills paid',
          () async {
        final a = newBloc();
        final b = newBloc();
        send(a, expected: 1300);
        send(b, status: LoanStatus.declined);
        final states = await Future.wait([settled(a), settled(b)]);

        expect(
          states.where((s) => s.status == AdditionalLoanStatus.success),
          hasLength(1),
        );
        final topUp = store.topUp();
        if (topUp.status == LoanStatus.declined) {
          expectNothingPaid();
          expect(topUp.deductionPlan, isEmpty);
        } else {
          expect(topUp.status, LoanStatus.approved);
          expect(store.payments.keys, ['topup-1-1']);
        }
      });

      test('a double tap on one device: the second finds it approved',
          () async {
        final bloc = newBloc();
        final states = bloc.stream
            .where(
              (s) =>
                  s.status == AdditionalLoanStatus.success ||
                  s.status == AdditionalLoanStatus.error,
            )
            .take(2)
            .toList();
        send(bloc, expected: 1300);
        send(bloc, expected: 1300);

        final done = await states;
        expect(done.first.status, AdditionalLoanStatus.success);
        expect(done.last.status, AdditionalLoanStatus.error);
        expect(done.last.message, contains('already approved'));
        expect(store.payments.keys, ['topup-1-1']);
        expect(store.rows.keys, ['topup-1-1']);
      });
    });

    group('an approval that stops part way is completed by the next', () {
      test(
          'stopped at the first payment: claimed, nothing paid; decline '
          'refused; approving again completes it', () async {
        store.failPaymentWrite = 1;

        final failed = await approve(expected: 1300);
        expect(failed.status, AdditionalLoanStatus.error);
        expectNothingPaid();
        final claimed = store.topUp();
        expect(claimed.status, LoanStatus.pending);
        expect(claimed.overdueDeduction, 1300);
        expect(claimed.deductedPaymentIds, ['topup-1-1']);
        expect(claimed.deductionPlan, hasLength(1));

        final decline = await approve(status: LoanStatus.declined);
        expect(decline.status, AdditionalLoanStatus.error);
        expect(decline.message, contains('Approve it again'));
        expect(store.topUp().status, LoanStatus.pending);

        final state = await approve(expected: 1300);
        expect(
          state.status,
          AdditionalLoanStatus.success,
          reason: state.message,
        );
        expect(store.payments.keys, ['topup-1-1']);
        expect(store.rows.keys, ['topup-1-1']);
        expect(store.rows['topup-1-1']!.penalty, closeTo(300, 0.001));
        expect(store.topUp().status, LoanStatus.approved);
        expect(store.loanStatus, LoanStatus.paid_late);
      });

      test(
          'stopped after bill 1 of 2: the retry writes bill 2 and '
          'overwrites bill 1, no duplicates', () async {
        store = _Store(loanCreatedDaysAgo: 35, topUp: pendingTopUp())
          ..failPaymentWrite = 2;

        final failed = await approve(expected: 2900);
        expect(failed.status, AdditionalLoanStatus.error);
        expect(store.payments.keys, ['topup-1-1']);
        expect(store.rows.keys, ['topup-1-1']);
        expect(store.topUp().status, LoanStatus.pending);
        expect(store.topUp().deductedPaymentIds, ['topup-1-1', 'topup-1-2']);

        final state = await approve(expected: 2900);
        expect(
          state.status,
          AdditionalLoanStatus.success,
          reason: state.message,
        );
        expect(state.message, contains(7100.toCurrency()));
        expect(store.payments.keys, ['topup-1-1', 'topup-1-2']);
        expect(store.rows.keys, ['topup-1-1', 'topup-1-2']);
        final rows = store.rows.values.toList();
        expect(
          rows.map((r) => DateUtils.dateOnly(r.dueAt.toLocal())),
          [daysFromToday(-20), daysFromToday(-5)],
        );
        expect(rows.map((r) => r.penalty), [closeTo(900, 0.001), 0]);
        expect(rows.map((r) => r.daysLate), [20, 5]);
        final topUp = store.topUp();
        expect(topUp.status, LoanStatus.approved);
        expect(topUp.overdueDeduction, 2900);
        expect(topUp.deductedPaymentIds, ['topup-1-1', 'topup-1-2']);
        expect(
          store.payments.values.map((p) => p.submissionId),
          ['topup-1', 'topup-1'],
        );
      });
    });
  });

  group('Payment Center: the warning reads the loan card rows', () {
    testWidgets('one missed bill: the warning shows 1,300', (tester) async {
      final loans = _Loans();
      final schedules = _Schedules();
      when(
        () => loans.load(
          statements: any(named: 'statements'),
          limit: any(named: 'limit'),
          page: any(named: 'page'),
          reset: any(named: 'reset'),
          includeAdditionalLoanAmounts:
              any(named: 'includeAdditionalLoanAmounts'),
        ),
      ).thenAnswer((invocation) async {
        final statements =
            invocation.namedArguments[#statements] as List<QueryStatement>;
        return statements.first.field == 'user_id'
            ? [
                loan40k(topUps: [pendingTopUp()]),
              ]
            : <Loan>[];
      });
      when(
        () => schedules.allByLoanId(
          loanId: any(named: 'loanId'),
          onlyPaid: any(named: 'onlyPaid'),
        ),
      ).thenAnswer((_) async => <LoanSchedule>[]);
      // Built inside runAsync: the bloc's events then run on the real clock.
      final state = await tester.runAsync(() async {
        final bloc = PaymentCenterBloc.withDependencies(
          userRepository: _Users(),
          loanRepository: loans,
          loanScheduleRepository: schedules,
          paymentRepository: _Payments(),
          storageRepository: _Storage(),
          authService: officer(),
        )..add(SelectBorrowerEvent(borrower: User()..id = 'u1'));
        final selected = await bloc.stream.firstWhere(
          (s) =>
              s.status == PaymentCenterStatus.borrowerSelected ||
              s.status == PaymentCenterStatus.error,
        );
        await bloc.close();
        return selected;
      });
      expect(state!.status, PaymentCenterStatus.borrowerSelected);
      final group = state.borrowerLoans.single;
      final rows = group.scheduleRows;
      expect(
        TopUpOverdueService.overdue(loan: group.loan, schedules: rows)!.amount,
        1300,
      );

      await tester.pumpApp(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => askTopUpOverdueChoice(
                context,
                loan: group.loan,
                schedules: rows,
                proceeds: 10000,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining(1300.toCurrency()), findsOneWidget);
      expect(find.textContaining(8700.toCurrency()), findsOneWidget);
    });
  });

  group('the dialogs', () {
    Future<T?> run<T>(
      WidgetTester tester,
      Future<T> Function(BuildContext context) open, {
      String? tap,
    }) async {
      T? result;
      var done = false;
      await tester.pumpApp(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await open(context);
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      if (tap != null) {
        await tester.tap(find.text(tap));
        await tester.pumpAndSettle();
      }
      expect(done, isTrue);
      return result;
    }

    testWidgets('no bill past due: no warning, the top-up goes ahead',
        (tester) async {
      final loan = loan40k()..createdAt = daysFromToday(-10);
      final answer = await run(
        tester,
        (context) => askTopUpOverdueChoice(
          context,
          loan: loan,
          schedules: clientRows(loan),
          proceeds: 10000,
        ),
      );

      expect(find.byType(AlertDialog), findsNothing);
      expect(answer!.proceed, isTrue);
      expect(answer.choice, isNull);
    });

    for (final (button, choice) in [
      ('Deduct from the top-up', OverdueChoice.deduct),
      ('Add to the next bill', OverdueChoice.nextBill),
      ('Cancel', null),
    ]) {
      testWidgets('overdue: the warning, then "$button"', (tester) async {
        final loan = loan40k();
        late Future<({bool proceed, OverdueChoice? choice})> pending;
        await tester.pumpApp(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => pending = askTopUpOverdueChoice(
                  context,
                  loan: loan,
                  schedules: clientRows(loan),
                  proceeds: 10000,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.text('This loan has overdue bills'), findsOneWidget);
        expect(find.textContaining(1300.toCurrency()), findsOneWidget);
        expect(find.textContaining(8700.toCurrency()), findsOneWidget);

        await tester.tap(find.text(button));
        await tester.pumpAndSettle();
        final answer = await pending;
        expect(answer.proceed, choice != null);
        expect(answer.choice, choice);
      });
    }

    testWidgets('overdue more than the top-up: "Deduct" is not offered',
        (tester) async {
      final loan = loan40k();
      await tester.pumpApp(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => askTopUpOverdueChoice(
                context,
                loan: loan,
                schedules: clientRows(loan),
                proceeds: 1000,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Deduct from the top-up is not available'),
        findsOneWidget,
      );
      final deduct = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Deduct from the top-up'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(deduct.onPressed, isNull);
    });

    testWidgets('approval of "deduct": shows today\'s 1,300 and 8,700',
        (tester) async {
      final topUp = pendingTopUp();
      final loan = loan40k(topUps: [topUp]);
      final shown = await run(
        tester,
        (context) => showTopUpApprovalDialog(
          context,
          topUp: topUp,
          loan: loan,
          schedules: clientRows(loan),
        ),
        tap: 'Approve',
      );

      expect(shown, 1300);
    });

    testWidgets('approval of "deduct": the amounts on screen', (tester) async {
      final topUp = pendingTopUp();
      final loan = loan40k(topUps: [topUp]);
      await tester.pumpApp(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTopUpApprovalDialog(
                context,
                topUp: topUp,
                loan: loan,
                schedules: clientRows(loan),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.textContaining(1300.toCurrency()), findsOneWidget);
      expect(
        find.textContaining('Cash to release: ${8700.toCurrency()}'),
        findsOneWidget,
      );
    });

    testWidgets('approval of "deduct" over the top-up: no Approve',
        (tester) async {
      final topUp = pendingTopUp(amount: 1000);
      final loan = loan40k(topUps: [topUp]);
      await tester.pumpApp(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTopUpApprovalDialog(
                context,
                topUp: topUp,
                loan: loan,
                schedules: clientRows(loan),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Decline it'), findsOneWidget);
      final approveButton = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Approve'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(approveButton.onPressed, isNull);
    });

    testWidgets('approval of "add to the next bill": nothing deducted',
        (tester) async {
      final topUp = pendingTopUp(choice: OverdueChoice.nextBill);
      final loan = loan40k(topUps: [topUp]);
      final shown = await run(
        tester,
        (context) => showTopUpApprovalDialog(
          context,
          topUp: topUp,
          loan: loan,
          schedules: clientRows(loan),
        ),
        tap: 'Approve',
      );

      expect(shown, 0);
    });

    testWidgets('approval of a claimed top-up: shows what it claimed',
        (tester) async {
      final topUp = pendingTopUp()
        ..overdueDeduction = 1300
        ..deductionPlan = [
          {'row': <String, dynamic>{}, 'payment': <String, dynamic>{}},
        ];
      final loan = loan40k(topUps: [topUp]);
      late Future<double?> pending;
      await tester.pumpApp(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => pending = showTopUpApprovalDialog(
                context,
                topUp: topUp,
                loan: loan,
                schedules: clientRows(loan),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'An earlier approval stopped while recording ${1300.toCurrency()}',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Cash to release: ${8700.toCurrency()}'),
        findsOneWidget,
      );
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(await pending, 1300);
    });
  });
}
