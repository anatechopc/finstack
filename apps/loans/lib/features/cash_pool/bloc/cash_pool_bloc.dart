import 'package:cash_pool_repository/cash_pool_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loooans/features/cash_pool/bloc/cash_pool_functions.dart';
import 'package:loooans/features/cash_pool/model/cash_pool_display.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:loooans_helpers/logging_helpers.dart';
import 'package:payment_repository/payment_repository.dart';
import 'package:user_repository/user_repository.dart';

part 'cash_pool_event.dart';

part 'cash_pool_state.dart';

class CashPoolBloc extends Bloc<CashPoolEvent, CashPoolState> {
  CashPoolBloc(BuildContext context)
      : cashPoolRepository = context.read<CashPoolRepository>(),
        userRepository = context.read<UserRepository>(),
        paymentRepository = context.read<PaymentRepository>(),
        super(const CashPoolState()) {
    on(_handleAddCashToPoolEvent);
    on(_handleAcknowledgePaymentEvent);
    on(_handleDeleteCashPoolEvent);
  }

  final CashPoolRepository cashPoolRepository;
  final UserRepository userRepository;
  final PaymentRepository paymentRepository;

  final log = Logger('cash_pool_bloc');

  CashPoolDisplay _cashPoolDisplay = const CashPoolDisplay(
    totalAcknowledged: 0,
    totalCashPool: 0,
    balance: 0,
    change: 0,
    savings: 0,
  );

  CashPoolDisplay get cashPoolDisplay => _cashPoolDisplay;

  Stream<List<CashPool>> loadCashPoolList2(String userId) {
    return cashPoolRepository.stream(
      statements: [
        QueryStatement(field: 'user_id', isEqualTo: userId),
      ],
      limit: null,
    ).map((data) {
      _processCashPoolDisplay(data);
      return data;
    });
  }

  void addCashPoolRecord({
    required double amount,
    required String userId,
    required ButtonOption option,
    String? comment,
  }) {
    add(
      AddCashPoolRecordEvent(
        amount: amount,
        userId: userId,
        comment: comment,
        option: option,
      ),
    );
  }

  void acknowledgePayment({
    required String paymentId,
    required String loanId,
    required String userId,
    required double amount,
    String? comment,
  }) {
    add(AcknowledgePaymentEvent(
      paymentId: paymentId,
      loanId: loanId,
      userId: userId,
      amount: amount,
      comment: comment,
    ),);
  }

  Future<void> _processCashPoolDisplay(List<CashPool> cashPoolList) async {
    _cashPoolDisplay = await processCashPoolDisplay(cashPoolList);

    emit(CashPoolState.cashPoolDisplayProcessed(_cashPoolDisplay));
  }

  Future<void> _handleAddCashToPoolEvent(
    AddCashPoolRecordEvent event,
    Emitter<CashPoolState> emit,
  ) async {
    try {
      emit(const CashPoolState.loading(isLoading: true));
      final status = switch (event.option.value) {
        'add_cash_pool' => CashPoolStatus.add_to_pool,
        'change' => CashPoolStatus.change,
        'savings' => CashPoolStatus.savings,
        _ => throw Exception('Invalid option:')
      };

      // check userId validity
      await userRepository.get(id: event.userId);

      final cashPool = CashPool.create(
        userId: event.userId,
        amount: event.amount,
        comment: event.comment,
        status: status,
      );
      await cashPoolRepository.add(data: cashPool);
      emit(const CashPoolState.loading());
      emit(const CashPoolState.success('Cash added to pool successfully'));
    } catch (err) {
      log.severe('Error in _handleAddCashToPoolEvent', err);
      emit(const CashPoolState.loading());
      emit(CashPoolState.error('Cannot add cash to pool: $err'));
    }
  }

  Future<void> _handleAcknowledgePaymentEvent(
    AcknowledgePaymentEvent event,
    Emitter<CashPoolState> emit,
  ) async {
    try {
      emit(const CashPoolState.loading(isLoading: true));
      // check userId validity
      await userRepository.get(id: event.userId);

      // check paymentId validity
      await paymentRepository.get(id: event.paymentId);

      final cashPool = CashPool.create(
        userId: event.userId,
        amount: event.amount,
        status: CashPoolStatus.acknowledged_payment,
        paymentId: event.paymentId,
        loanId: event.loanId,
        comment: event.comment,
      );
      await cashPoolRepository.add(data: cashPool);
      emit(const CashPoolState.loading());
      emit(const CashPoolState.success('Payment acknowledged successfully'));
    } catch (err) {
      log.severe('Error in _handleAcknowledgePaymentEvent', err);
      emit(const CashPoolState.loading());
      emit(CashPoolState.error('Cannot acknowledge payment: $err'));
    }
  }

  Future<void> _handleDeleteCashPoolEvent(
    DeleteCashPoolEvent event,
    Emitter<CashPoolState> emit,
  ) async {
    try {
      emit(const CashPoolState.loading(isLoading: true));
      await cashPoolRepository.delete(data: event.cashPool);
      emit(const CashPoolState.loading());
      emit(const CashPoolState.success('Cash pool deleted successfully'));
    } catch (err) {
      log.severe('Error in _handleDeleteCashPoolEvent', err);
      emit(const CashPoolState.loading());
      emit(CashPoolState.error('Cannot delete cash pool: $err'));
    }
  }
}
