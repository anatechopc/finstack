import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:loooans_helpers/logging_helpers.dart';

part 'loan_settlement_event.dart';
part 'loan_settlement_state.dart';

final _log = Logger('loan_settlement_bloc');

class LoanSettlementBloc
    extends Bloc<LoanSettlementEvent, LoanSettlementState> {
  LoanSettlementBloc(BuildContext context)
      : loanRepository = context.read<LoanRepository>(),
        loanScheduleRepository = context.read<LoanScheduleRepository>(),
        super(const LoanSettlementState()) {
    on<SettleAccountEvent>(_handleSettleLoanAccountEvent);
    on<ConfirmLoanAccountSettlementEvent>(
      _handleConfirmLoanAccountSettlementEvent,
    );
  }

  final LoanRepository loanRepository;
  final LoanScheduleRepository loanScheduleRepository;

  void settleLoanAccount({
    required String userId,
    required String loanId,
  }) {
    add(SettleAccountEvent(userId: userId, loanId: loanId));
  }

  void confirmLoanAccountSettlement({
    required String userId,
    required String loanId,
  }) {
    add(
      ConfirmLoanAccountSettlementEvent(userId: userId, loanId: loanId),
    );
  }

  Future<void> _handleSettleLoanAccountEvent(
    SettleAccountEvent event,
    Emitter<LoanSettlementState> emit,
  ) async {
    try {
      emit(const LoanSettlementState.loading(isLoading: true));
      final allLoans = <Loan>[];
      final loan = await loanRepository.get(id: event.loanId);

      allLoans.add(loan);

      final specialLoans = await loanRepository.load(
        limit: null,
        page: 0,
        reset: true,
        statements: [
          QueryStatement(field: 'user_id', isEqualTo: event.userId),
          QueryStatement(
            field: 'status',
            whereNotIn: [
              LoanStatus.pending.name,
              LoanStatus.declined.name,
              LoanStatus.completed.name,
              LoanStatus.bad_debt.name,
            ],
          ),
          QueryStatement(
            field: 'parent_id',
            isEqualTo: loan.id,
          ),
        ],
      );

      allLoans.addAll(specialLoans);

      final loanSchedules = await loanScheduleRepository.load(
        limit: null,
        page: 0,
        reset: true,
        statements: [
          QueryStatement(
            field: 'loan_id',
            whereIn: allLoans.map((loan) => loan.id),
          ),
          const QueryStatement(
            field: 'payment_id',
            isNull: false,
          ),
        ],
      );

      var totalLoanAmount = 0.0;
      var totalLoanPayment = 0.0;

      for (final loan in allLoans) {
        totalLoanAmount += (loan.amount + loan.additionalCharges) -
            (loan.deductions + loan.additionalChargeUpfrontCollection);
      }

      for (final schedule in loanSchedules) {
        totalLoanPayment = (schedule.isOpenTerm
                ? schedule.interestCharge
                : schedule.interestPayment) +
            schedule.principalPayment +
            schedule.extraPayment;
      }

      final remainingBalance = totalLoanAmount - totalLoanPayment;

      _log.fine('remainingBalance: $remainingBalance');

      emit(const LoanSettlementState.loading());
      emit(LoanSettlementState.confirmSettlement(
        remainingBalance,
        event.userId,
      ));
    } catch (err) {
      _log.severe('Cannot settle loan account: $err', err);
      emit(const LoanSettlementState.loading());
      emit(
        LoanSettlementState.error('Unable to settle loan account: $err'),
      );
    }
  }

  Future<void> _handleConfirmLoanAccountSettlementEvent(
    ConfirmLoanAccountSettlementEvent event,
    Emitter<LoanSettlementState> emit,
  ) async {
    try {
      emit(const LoanSettlementState.loading(isLoading: true));
      final allLoans = <Loan>[];
      final loan = await loanRepository.get(id: event.loanId);
      final loans = await loanRepository.load(
        limit: null,
        page: 0,
        reset: true,
        statements: [
          QueryStatement(
            field: 'user_id',
            isEqualTo: event.userId,
          ),
          QueryStatement(
            field: 'status',
            whereNotIn: [
              LoanStatus.pending.name,
              LoanStatus.declined.name,
              LoanStatus.completed.name,
              LoanStatus.bad_debt.name,
            ],
          ),
          QueryStatement(
            field: 'parent_id',
            isEqualTo: event.loanId,
          ),
        ],
      );
      allLoans
        ..add(loan)
        ..addAll(loans);

      await Future.wait(
        allLoans.map((loan) async {
          return loanRepository.update(
            data: loan..status = LoanStatus.completed,
            updateView: true,
          );
        }),
      );

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
