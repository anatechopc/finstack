import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:payment_repository/payment_repository.dart';
import 'package:storage_repository/storage_repository.dart';
import 'package:uuid/uuid.dart';

part 'payment_submission_event.dart';
part 'payment_submission_state.dart';

class PaymentSubmissionBloc
    extends Bloc<PaymentSubmissionEvent, PaymentSubmissionState> {
  PaymentSubmissionBloc(BuildContext context)
      : this.withDependencies(
          paymentRepository: context.read<PaymentRepository>(),
          loanScheduleRepository: context.read<LoanScheduleRepository>(),
          storageRepository: context.read<StorageRepository>(),
          authService: AuthenticationService.instance,
        );

  PaymentSubmissionBloc.withDependencies({
    required this.paymentRepository,
    required this.loanScheduleRepository,
    required this.storageRepository,
    required this.authService,
    String Function()? newSubmissionId,
  })  : _newSubmissionId = newSubmissionId ?? (() => const Uuid().v4()),
        super(const PaymentSubmissionState()) {
    on<SubmitPaymentEvent>(_onSubmit);
  }

  final BaseRepository<Payment> paymentRepository;
  final BaseRepository<LoanSchedule> loanScheduleRepository;
  final StorageRepository storageRepository;
  final AuthenticationService authService;
  final String Function() _newSubmissionId;

  Future<void> _onSubmit(
    SubmitPaymentEvent event,
    Emitter<PaymentSubmissionState> emit,
  ) async {
    emit(state.copyWith(status: PaymentSubmissionStatus.submitting));
    try {
      final userId = authService.user.id;
      if (event.schedules.isEmpty) {
        emit(
          state.copyWith(
            status: PaymentSubmissionStatus.error,
            message: 'No schedule to pay.',
          ),
        );
        return;
      }

      final proof = await storageRepository.upload(
        data: event.fileBytes,
        folder: 'users/$userId/loans/${event.loanId}',
        fileName: event.fileName,
        includeOriginal: true,
      );
      final submissionId = _newSubmissionId();

      // TODO(payments): make the pay-in-full writes atomic (WriteBatch) — see
      // review. For now we track how many schedules succeeded so a partial
      // failure surfaces a clear "contact support" message instead of silently
      // duplicating payments on retry.
      final total = event.schedules.length;
      var completed = 0;

      try {
        for (final schedule in event.schedules) {
          schedule
            ..loanId = event.loanId
            ..status = LoanStatus.payment_submitted;

          final payment = Payment.create(
            userId: userId,
            loanScheduleId: schedule.id, // may be NO_ID; fixed for open-term
            loanId: event.loanId,
            transactionPhotoUrl: proof,
            status: PaymentStatus.pending,
            submissionId: submissionId,
          );

          if (schedule.id == NO_ID) {
            // Open-term runtime schedule: persist payment + schedule, then
            // backfill the payment with the newly-created schedule id.
            final savedPayment = await paymentRepository.add(data: payment);
            final addedSchedule = await loanScheduleRepository.add(
              data: schedule..paymentId = savedPayment.id,
            );
            await paymentRepository.update(
              data: savedPayment..loanScheduleId = addedSchedule.id,
            );
          } else {
            final savedPayment = await paymentRepository.add(data: payment);
            await loanScheduleRepository.update(
              data: schedule..paymentId = savedPayment.id,
            );
          }

          completed++;
        }
      } catch (err) {
        if (completed > 0) {
          // Some schedules were already written and the proof uploaded;
          // a naive retry would duplicate payments. Tell the user to stop.
          emit(
            state.copyWith(
              status: PaymentSubmissionStatus.error,
              message: 'Payment partially submitted '
                  '($completed of $total). '
                  'Please contact support before retrying.',
            ),
          );
          return;
        }
        rethrow;
      }

      emit(state.copyWith(status: PaymentSubmissionStatus.success));
    } catch (err) {
      emit(
        state.copyWith(
          status: PaymentSubmissionStatus.error,
          message: err is Exception ? 'Submit failed: $err' : 'Submit failed',
        ),
      );
    }
  }
}
