import 'dart:math';

import 'package:cash_pool_repository/cash_pool_repository.dart';
import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/cash_pool/bloc/cash_pool_functions.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:loooans_helpers/logging_helpers.dart';
import 'package:payment_repository/payment_repository.dart';

part 'loan_settlement_event.dart';
part 'loan_settlement_state.dart';

final _log = Logger('loan_settlement_bloc');

/// Loans that cannot be settled: not released, or closed already.
const _notActive = {
  LoanStatus.pending,
  LoanStatus.declined,
  LoanStatus.completed,
  LoanStatus.bad_debt,
};

class LoanSettlementBloc
    extends Bloc<LoanSettlementEvent, LoanSettlementState> {
  LoanSettlementBloc(BuildContext context)
      : this.withDependencies(
          loanRepository: context.read<LoanRepository>(),
          loanScheduleRepository: context.read<LoanScheduleRepository>(),
          paymentRepository: context.read<PaymentRepository>(),
          cashPoolRepository: context.read<CashPoolRepository>(),
        );

  /// Test seam: the collaborators without a [BuildContext].
  LoanSettlementBloc.withDependencies({
    required this.loanRepository,
    required this.loanScheduleRepository,
    required this.paymentRepository,
    required this.cashPoolRepository,
    AuthenticationService? authService,
  })  : authService = authService ?? AuthenticationService.instance,
        super(const LoanSettlementState()) {
    on<SettleAccountEvent>(_handleSettleLoanAccountEvent);
    // One at a time: a second confirmation (a double tap) runs after the
    // first has completed the loan, and is refused.
    on<ConfirmLoanAccountSettlementEvent>(
      _handleConfirmLoanAccountSettlementEvent,
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
  }

  final LoanRepository loanRepository;
  final LoanScheduleRepository loanScheduleRepository;
  final PaymentRepository paymentRepository;
  final CashPoolRepository cashPoolRepository;
  final AuthenticationService authService;

  void settleLoanAccount({required String loanId}) {
    add(SettleAccountEvent(loanId: loanId));
  }

  /// Records the settlement of [amount], the figure the teller was shown.
  void confirmLoanAccountSettlement({
    required String loanId,
    required double amount,
  }) {
    add(ConfirmLoanAccountSettlementEvent(loanId: loanId, amount: amount));
  }

  /// [loanId] and its borrower's active special loans of it, with every
  /// stored row of theirs. The borrower is the loan's own: the statement
  /// screen has none for a fixed-term loan. Throws when [loanId] is not an
  /// active loan: a settled loan is never settled again.
  Future<({List<Loan> loans, List<LoanSchedule> rows})> _family({
    required String loanId,
  }) async {
    final loan = await loanRepository.get(id: loanId);
    _refuseInactive(loan);

    final specialLoans = await loanRepository.load(
      limit: null,
      page: 0,
      reset: true,
      // Their top-ups are owed too.
      includeAdditionalLoanAmounts: true,
      statements: [
        QueryStatement(field: 'user_id', isEqualTo: loan.userId),
        QueryStatement(
          field: 'status',
          whereNotIn: _notActive.map((status) => status.name),
        ),
        QueryStatement(field: 'parent_id', isEqualTo: loan.id),
      ],
    );
    final loans = [loan, ...specialLoans];

    // Every row, of any status: the calculation credits only confirmed
    // payments (#116).
    final rows = await loanScheduleRepository.load(
      limit: null,
      page: 0,
      reset: true,
      statements: [
        QueryStatement(
          field: 'loan_id',
          whereIn: loans.map((loan) => loan.id),
        ),
      ],
    );
    _refusePending(rows);

    return (loans: loans, rows: rows);
  }

  static void _refuseInactive(Loan loan) {
    if (_notActive.contains(loan.status)) {
      throw Exception(
        loan.status == LoanStatus.completed
            ? 'This loan is already settled'
            : 'Only an active loan can be settled',
      );
    }
  }

  /// A submission confirmed after the settlement would be collected twice,
  /// and its confirmation or rejection would reopen the loan (review of
  /// #157).
  static void _refusePending(Iterable<LoanSchedule?> rows) {
    if (rows.any((row) => row?.status == LoanStatus.payment_submitted)) {
      throw Exception(
        'A payment is waiting for confirmation. Confirm or reject it first, '
        'then settle.',
      );
    }
  }

  Future<void> _handleSettleLoanAccountEvent(
    SettleAccountEvent event,
    Emitter<LoanSettlementState> emit,
  ) async {
    try {
      emit(const LoanSettlementState.loading(isLoading: true));
      final (:loans, :rows) = await _family(loanId: event.loanId);

      final remainingBalance =
          LoanCalculationService.calculateSettlementBalance(
        loans: loans,
        schedules: rows,
      );

      _log.fine('remainingBalance: $remainingBalance');

      emit(const LoanSettlementState.loading());
      emit(
        LoanSettlementState.confirmSettlement(
          remainingBalance,
          loans.first.userId,
        ),
      );
    } catch (err) {
      _log.severe('Cannot settle loan account: $err', err);
      emit(const LoanSettlementState.loading());
      emit(
        LoanSettlementState.error('Unable to settle loan account: $err'),
      );
    }
  }

  /// Records each loan's settlement as a paid row, its payment and its
  /// cash-pool entry, the way the teller payment paths write them, and
  /// completes the loans, all in one transaction (#116, review of #157):
  /// Go's loanChanges sees the rows when it books the completion.
  Future<void> _handleConfirmLoanAccountSettlementEvent(
    ConfirmLoanAccountSettlementEvent event,
    Emitter<LoanSettlementState> emit,
  ) async {
    try {
      emit(const LoanSettlementState.loading(isLoading: true));
      final now = DateTime.now();
      final (:loans, :rows) = await _family(loanId: event.loanId);
      final settlements = [
        for (final loan in loans)
          (
            loan: loan,
            row: LoanCalculationService.settlementOf(
              loan: loan,
              rows: [
                for (final row in rows)
                  if (row.loanId == loan.id) row,
              ],
              now: now,
            ),
          ),
      ];
      final total = settlements
          .map((s) => LoanCalculationService.settlementAmount(s.row))
          .sum;
      // A payment or a new day since the dialog opened changes the figure:
      // never record an amount the teller was not shown.
      if ((total - event.amount).abs() >= 0.005) {
        throw Exception(
          'The settlement amount is now ${total.toCurrency()}. '
          'Open the settlement again.',
        );
      }

      final teller = authService.user;
      // The borrower's prepaid pool, read once (a query cannot run inside a
      // transaction); the family's loans deduct from it in turn.
      var poolBalance = (await processCashPoolDisplay(
        await cashPoolRepository.load(
          reset: true,
          limit: null,
          statements: [
            QueryStatement(field: 'user_id', isEqualTo: loans.first.userId),
          ],
        ),
      ))
          .balance;
      // One settlement per loan: its row, payment and cash-pool entry share
      // this id and are written only where none exists.
      final documents =
          <({LoanSchedule row, Payment payment, CashPool entry})>[];
      for (final (:loan, :row) in settlements) {
        final amount = LoanCalculationService.settlementAmount(row);
        final id = '${loan.id}-settlement';
        final poolBefore = poolBalance;
        final deducted = min(amount, poolBefore);
        poolBalance -= deducted;
        documents.add(
          (
            row: row
              ..id = id
              ..paymentId = id,
            payment: Payment.create(
              userId: loan.userId,
              loanScheduleId: id,
              loanId: loan.id,
              // The settlement dialog takes no proof; the comment records who
              // confirmed the cash.
              bypassPaymentProof: true,
              comment: '''
          Early settlement confirmed by:
          user:id: ${teller.id}
          user:name: ${teller.completeNameEasternOrder}
          user:email: ${teller.emailAddress}
          amount: $amount
          confirmed_at: ${DateTime.timestamp().toDefaultDateFormatExtended()}''',
              confirmedBy: teller.id,
              confirmedAt: DateTime.timestamp(),
            )..id = id,
            entry: CashPool.create(
              userId: loan.userId,
              amount: deducted,
              status: CashPoolStatus.acknowledged_payment,
              paymentId: id,
              loanId: loan.id,
              comment: '''
          Early settlement: $amount
          Cash pool balance: $poolBefore
          ${deducted < amount ? 'Excess payment is collected from user in person.' : 'Full payment is deducted from the cash pool.'}

          Teller: ${teller.completeNameEasternOrder}
          ''',
            )..id = id,
          ),
        );
      }

      // One transaction (review of #157): it reads each loan, each
      // settlement document and each stored row first, and writes nothing
      // unless every loan is still active, no settlement document exists
      // and no row has been submitted since. Then every row, payment, pool
      // entry and completion lands together or none does: a stop midway
      // leaves nothing, and a second device's transaction, retried by
      // Firestore after the first commits, sees it and stops. Four writes a
      // loan: Firestore's 500-write limit is a family of 125 loans; past it
      // the commit is refused and nothing is written.
      await loanScheduleRepository.runTransaction((transaction) async {
        final current = <Loan>[];
        for (final (:row, payment: _, entry: _) in documents) {
          final loan = await loanRepository.getIn(transaction, row.loanId);
          if (loan == null) {
            throw Exception('Loan ${row.loanId} no longer exists');
          }
          _refuseInactive(loan);
          current.add(loan);
          if (await loanScheduleRepository.getIn(transaction, row.id) != null ||
              await paymentRepository.existsIn(transaction, row.id) ||
              await cashPoolRepository.existsIn(transaction, row.id)) {
            throw Exception('The settlement of this loan is already recorded');
          }
        }
        _refusePending([
          for (final stored in rows)
            await loanScheduleRepository.getIn(transaction, stored.id),
        ]);

        for (final (:row, :payment, :entry) in documents) {
          loanScheduleRepository.setIn(transaction, row);
          paymentRepository.setIn(transaction, payment);
          cashPoolRepository.setIn(transaction, entry);
        }
        for (final loan in current) {
          loanRepository.updateIn(
            transaction,
            loan..status = LoanStatus.completed,
          );
        }
      });

      // The loan lists read the borrower's loan view, which the transaction
      // cannot write; the settlement is recorded whatever happens here.
      for (final loan in loans) {
        try {
          await loanRepository.update(
            data: loan..status = LoanStatus.completed,
            updateView: true,
          );
        } catch (err) {
          _log.warning('Settled loan ${loan.id}: view not refreshed: $err');
        }
      }

      emit(const LoanSettlementState.loading());
      emit(
        const LoanSettlementState.success(
          'Successfully settled account',
          closeDialog: true,
        ),
      );
    } catch (err) {
      _log.severe('Cannot settle loan account: $err', err);
      emit(const LoanSettlementState.loading());
      emit(
        LoanSettlementState.error('Unable to settle loan account: $err'),
      );
    }
  }
}
