import 'dart:async';
import 'dart:typed_data';

import 'package:cash_pool_repository/cash_pool_repository.dart';
import 'package:company_repository/company_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/cash_pool/bloc/cash_pool_functions.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/settings_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:loooans_helpers/logging_helpers.dart';
import 'package:payment_repository/payment_repository.dart';
import 'package:storage_repository/storage_repository.dart';

part 'payment_event.dart';
part 'payment_state.dart';

final _log = Logger('payment_bloc');

class PaymentBloc extends Bloc<PaymentEvent, PaymentState> {
  PaymentBloc(BuildContext context)
      : authService = AuthenticationService.instance,
        settingsService = SettingsService.instance,
        loanRepository = context.read<LoanRepository>(),
        loanScheduleRepository = context.read<LoanScheduleRepository>(),
        storageRepository = context.read<StorageRepository>(),
        paymentRepository = context.read<PaymentRepository>(),
        cashPoolRepository = context.read<CashPoolRepository>(),
        super(const PaymentState()) {
    on<PayLoanScheduleEvent>(_handlePayLoanScheduleEvent);
  }

  final AuthenticationService authService;
  final SettingsService settingsService;
  final LoanRepository loanRepository;
  final LoanScheduleRepository loanScheduleRepository;
  final StorageRepository storageRepository;
  final PaymentRepository paymentRepository;
  final CashPoolRepository cashPoolRepository;

  void makePayment({
    required Loan loan,
    required LoanSchedule schedule,
    required String interestPayment,
    required String payment,
    String? fileName,
    Uint8List? fileBytes,
    Uint8List? signatureBytes,
    bool force = false,
  }) {
    add(
      PayLoanScheduleEvent(
        loan: loan,
        schedule: schedule,
        payment: double.parse(payment),
        interestPayment: double.parse(interestPayment),
        fileName: fileName,
        fileBytes: fileBytes,
        signatureBytes: signatureBytes,
        force: force,
      ),
    );
  }

  Future<void> _handlePayLoanScheduleEvent(
    PayLoanScheduleEvent event,
    Emitter<PaymentState> emit,
  ) async {
    try {
      emit(const PaymentState.loading(isLoading: true));
      final loan = event.loan;

      /// for now, payment is only supported for self managed company types.
      if (authService.company.managementType ==
          CompanyManagementType.selfManaged) {
        final schedule = event.schedule
          ..paidAt = DateTime.timestamp()
          ..loanId = loan.id;

        final now = DateTime.now();
        var status = LoanStatus.payment_submitted;

        if (schedule.dueAt.toLocal().isBefore(now)) {
          status = LoanStatus.paid_late;
        } else {
          status = LoanStatus.paid_on_time;
        }

        ImageUrl? transactionPhotoUrl;
        ImageUrl? signatureUrl;
        String? comment;

        if (!event.force) {
          if (event.fileName == null ||
              event.fileBytes == null ||
              event.signatureBytes == null) {
            throw Exception('Transaction photo and signature are required');
          }

          transactionPhotoUrl = await storageRepository.upload(
            data: event.fileBytes!,
            folder: 'users/${loan.userId}/loans/${loan.id}',
            fileName: event.fileName!,
            includeOriginal: true,
          );

          signatureUrl = await storageRepository.upload(
            data: event.signatureBytes!,
            folder: 'users/${loan.userId}/loans/${loan.id}',
            fileName:
                'signature_${DateTime.timestamp().toDefaultDateFormat()}.png',
            forceDecodeToImage: true,
            includeOriginal: true,
          );
          comment = '''
          Manual payment confirmed by:
          user:id: ${authService.user.id}
          user:name: ${authService.user.completeNameEasternOrder}
          user:email: ${authService.user.emailAddress}
          confirmed_at: ${DateTime.timestamp().toDefaultDateFormatExtended()}''';
        } else {
          if (!settingsService.forcePaymentConfirmation) {
            throw Exception('Enable force payment confirmation in settings');
          }

          comment = '''
          Force payment confirmed by:
          user:id: ${authService.user.id}
          user:name: ${authService.user.completeNameEasternOrder}
          user:email: ${authService.user.emailAddress}
          confirmed_at: ${DateTime.timestamp().toDefaultDateFormatExtended()}''';
        }

        final tempPayment = Payment.create(
          userId: loan.userId,
          loanScheduleId: schedule.id,
          transactionPhotoUrl: transactionPhotoUrl,
          signatureUrl: signatureUrl,
          bypassPaymentProof: event.force,
          comment: comment,
          confirmedBy: authService.user.id,
          confirmedAt: DateTime.timestamp(),
        );

        if (!schedule.isOpenTerm) {
          final extraPayment = event.payment - schedule.principalPayment;
          if (extraPayment > 0.0) {
            schedule
              ..extraPayment = extraPayment
              ..outstandingBalance -= extraPayment;
          }
        }

        schedule
          ..interestPayment = event.interestPayment
          ..principalPayment = event.payment
          ..outstandingBalance -= (event.payment - schedule.extraPayment)
          ..loanId = loan.id
          ..status = status;

        await Future.wait([
          loanRepository.update(
            data: loan..status = status,
            updateView: true,
          ),
        ]);

        Payment? loanPayment;
        if (schedule.id == NO_ID) {
          await paymentRepository.add(data: tempPayment).then((payment) {
            loanPayment = payment;
            return loanScheduleRepository
                .add(data: schedule..paymentId = payment.id)
                .then((schedule) {
              return paymentRepository
                  .update(data: payment..loanScheduleId = schedule.id);
            });
          });
        } else {
          await paymentRepository.add(data: tempPayment).then((payment) {
            loanPayment = payment;
            return loanScheduleRepository.update(
              data: schedule..paymentId = payment.id,
            );
          });
        }

        if (loanPayment == null) {
          _log.warning('Loan payment is null. Please check.');
        }

        final cashPoolList = await cashPoolRepository.load(
          reset: true,
          limit: null,
          statements: [
            QueryStatement(
              field: 'user_id',
              isEqualTo: loan.userId,
            ),
          ],
        );
        final cashPoolDisplay = await processCashPoolDisplay(cashPoolList);
        final totalPayment = event.interestPayment + event.payment;
        var cashPoolComment = '';
        var cashPoolBalanceDeduction = 0.0;

        if (totalPayment > cashPoolDisplay.balance) {
          cashPoolComment = '''
          Loan payment exceeds cash pool balance.
          Loan payment: $totalPayment
          Cash pool balance: ${cashPoolDisplay.balance}
          Excess payment is collected from user in person.

          Teller: ${authService.user.completeNameEasternOrder}
          ''';
          cashPoolBalanceDeduction = cashPoolDisplay.balance;
        } else if (totalPayment < cashPoolDisplay.balance) {
          cashPoolComment = '''
          Loan payment is less than cash pool balance.
          Loan payment: $totalPayment
          Cash pool balance: ${cashPoolDisplay.balance}
          Full payment is deducted from the cash pool.

          Teller: ${authService.user.completeNameEasternOrder}
          ''';
          cashPoolBalanceDeduction = totalPayment;
        } else {
          cashPoolComment = '''
          Loan payment is equal to cash pool balance.
          Loan payment: $totalPayment
          Cash pool balance: ${cashPoolDisplay.balance}
          Full payment is deducted from the cash pool.

          Teller: ${authService.user.completeNameEasternOrder}
          ''';
          cashPoolBalanceDeduction = totalPayment;
        }

        final tempCashPool = CashPool.create(
          userId: loan.userId,
          amount: cashPoolBalanceDeduction,
          status: CashPoolStatus.acknowledged_payment,
          paymentId:
              loanPayment?.id ?? 'Loan payment is null. Report to app admin',
          loanId: loan.id,
          comment: cashPoolComment,
        );

        await cashPoolRepository.add(data: tempCashPool);

        emit(const PaymentState.loading());
        emit(const PaymentState.success('Successfully paid loan schedule'));
      } else {
        throw Exception('This action is not supported');
      }
    } catch (err) {
      _log.severe('Pay loan error: $err', err);
      emit(const PaymentState.loading());
      emit(
        const PaymentState.error(
          'Something went wrong while paying schedule',
        ),
      );
    }
  }
}
