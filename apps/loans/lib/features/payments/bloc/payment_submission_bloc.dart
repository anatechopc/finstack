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
    on<SubmitPayNowEvent>(_onPayNow);
    on<SubmitPayInFullEvent>(_onPayInFull);
  }

  final BaseRepository<Payment> paymentRepository;
  final BaseRepository<LoanSchedule> loanScheduleRepository;
  final StorageRepository storageRepository;
  final AuthenticationService authService;
  final String Function() _newSubmissionId;

  Future<void> _onPayNow(
    SubmitPayNowEvent event,
    Emitter<PaymentSubmissionState> emit,
  ) async {
    await _submit(
      event.fileBytes,
      event.fileName,
      payInFull: false,
      emit: emit,
    );
  }

  Future<void> _onPayInFull(
    SubmitPayInFullEvent event,
    Emitter<PaymentSubmissionState> emit,
  ) async {
    await _submit(
      event.fileBytes,
      event.fileName,
      payInFull: true,
      emit: emit,
    );
  }

  Future<void> _submit(
    Uint8List bytes,
    String fileName, {
    required bool payInFull,
    required Emitter<PaymentSubmissionState> emit,
  }) async {
    emit(state.copyWith(status: PaymentSubmissionStatus.submitting));
    try {
      final userId = authService.user.id;
      final targets = await _unpaidSchedules(userId, payInFull: payInFull);
      if (targets.isEmpty) {
        emit(
          state.copyWith(
            status: PaymentSubmissionStatus.error,
            message: 'No schedule to pay.',
          ),
        );
        return;
      }

      final loanId = targets.first.loanId;
      final proof = await storageRepository.upload(
        data: bytes,
        folder: 'users/$userId/loans/$loanId',
        fileName: fileName,
        includeOriginal: true,
      );
      final submissionId = _newSubmissionId();

      for (final schedule in targets) {
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

  /// Returns the schedules to pay: the single next-due one (Pay now), or all
  /// remaining unpaid ones (Pay in full).
  ///
  /// IMPLEMENTATION NOTE: this uses loanScheduleRepository.load directly for now
  /// (kept as a testable seam). Task 6 replaces this with the app's
  /// LoanCalculationService-backed payable-schedule source (schedules are NOT
  /// all pre-stored in Firestore — see apps/loans/MEMORY.md). Keep this return
  /// contract so the tests stand.
  Future<List<LoanSchedule>> _unpaidSchedules(
    String userId, {
    required bool payInFull,
  }) async {
    final all = await loanScheduleRepository.load(
      reset: true,
      limit: null,
      statements: [
        QueryStatement(field: 'user_id', isEqualTo: userId),
      ],
    );
    final unpaid = all
        .where(
          (s) =>
              s.status != LoanStatus.paid_on_time &&
              s.status != LoanStatus.paid_late &&
              s.status != LoanStatus.payment_submitted,
        )
        .toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    if (unpaid.isEmpty) return [];
    return payInFull ? unpaid : [unpaid.first];
  }
}
