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

      final loanId = event.schedules.first.loanId;
      final proof = await storageRepository.upload(
        data: event.fileBytes,
        folder: 'users/$userId/loans/$loanId',
        fileName: event.fileName,
        includeOriginal: true,
      );
      final submissionId = _newSubmissionId();

      for (final schedule in event.schedules) {
        final payment = Payment.create(
          userId: userId,
          loanScheduleId: schedule.id,
          transactionPhotoUrl: proof,
          status: PaymentStatus.pending,
          submissionId: submissionId,
        );
        final saved = await paymentRepository.add(data: payment);
        schedule
          ..status = LoanStatus.payment_submitted
          ..paymentId = saved.id;
        await loanScheduleRepository.update(data: schedule);
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
