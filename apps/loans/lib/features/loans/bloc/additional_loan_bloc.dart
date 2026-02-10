import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/products/requirement_temp_container.dart';
import 'package:loooans/services/charge_calculator.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans_helpers/logging_helpers.dart';
import 'package:product_repository/product_repository.dart';
import 'package:storage_repository/storage_repository.dart';

part 'additional_loan_event.dart';
part 'additional_loan_state.dart';

final _log = Logger('additional_loan_bloc');

class AdditionalLoanBloc
    extends Bloc<AdditionalLoanEvent, AdditionalLoanState> {
  AdditionalLoanBloc(BuildContext context)
      : loanRepository = context.read<LoanRepository>(),
        loanScheduleRepository = context.read<LoanScheduleRepository>(),
        storageRepository = context.read<StorageRepository>(),
        super(const AdditionalLoanState()) {
    on<AddLoanAmountEvent>(_handleAddLoanAmountEvent);
    on<UpdateAdditionalLoanAmountEvent>(
      _handleUpdateAdditionalLoanAmountEvent,
    );
  }

  final LoanRepository loanRepository;
  final LoanScheduleRepository loanScheduleRepository;
  final StorageRepository storageRepository;

  void addLoanAmount(
    String loanId,
    String amountStr, {
    required SimpleFileData selfiePhoto,
    required Uint8List signatureBytes,
    String? description,
    List<Charge> additionalCharges = const [],
    List<Charge> deductions = const [],
  }) {
    add(
      AddLoanAmountEvent(
        loanId: loanId,
        amount: double.parse(amountStr),
        additionalCharges: additionalCharges,
        deductions: deductions,
        selfiePhoto: selfiePhoto,
        signatureBytes: signatureBytes,
        description: description,
      ),
    );
  }

  void updateAdditionalLoanAmount({
    required String loanId,
    required String additionalLoanAmountId,
    required LoanStatus status,
  }) {
    add(
      UpdateAdditionalLoanAmountEvent(
        loanId: loanId,
        additionalLoanAmountId: additionalLoanAmountId,
        status: status,
      ),
    );
  }

  Future<void> _handleAddLoanAmountEvent(
    AddLoanAmountEvent event,
    Emitter<AdditionalLoanState> emit,
  ) async {
    try {
      emit(const AdditionalLoanState.loading(isLoading: true));
      final result = await Future.wait([
        loanRepository.get(id: event.loanId),
        loanScheduleRepository.allByLoanId(
          loanId: event.loanId,
          onlyPaid: false,
        ),
      ]);

      final loan = result[0] as Loan;
      final (
        :totalAmount,
        :totalUpfrontCollection,
        :totalAdditionalCharges,
        :totalDeductions,
      ) = ChargeCalculator.applyChargesAndDeductionsDetailed(
        baseAmount: event.amount,
        charges: event.additionalCharges,
        deductions: event.deductions,
      );

      await Future.wait([
        // Upload selfie photo and signature
        Future.wait([
          storageRepository.upload(
            data: event.selfiePhoto.data,
            folder: 'users/${loan.userId}/loans/${loan.id}',
            fileName: 'additional_loan_amount_${event.selfiePhoto.name}',
          ),
          storageRepository.upload(
            data: event.signatureBytes,
            folder: 'users/${loan.userId}/loans/${loan.id}',
            fileName:
                'additional_loan_amount_signature_${DateTime.timestamp().toDefaultDateFormat()}.png',
          ),
        ]).then((values) async {
          final selfiePhotoUrl = values[0];
          final signatureUrl = values[1];

          final updatedLoan = loan
            ..additionalLoanAmounts = [
              ...loan.additionalLoanAmounts,
              AdditionalLoanAmount.create(
                loanId: loan.id,
                amount: event.amount,
                additionalCharges: totalAdditionalCharges,
                advanceCharges: totalUpfrontCollection,
                deductions: totalDeductions,
                selfiePhotoUrl: selfiePhotoUrl,
                signatureUrl: signatureUrl,
                description: event.description,
              ),
            ];

          final updated2 = await loanRepository.update(
            data: updatedLoan,
            updateView: true,
          );

          return updated2;
        }),
        Future.microtask(() async {
          final schedules = result[1] as List<LoanSchedule>;
          final lastSchedule = schedules.last;
          _log.info('i am updated');

          return loanScheduleRepository.update(
            data: lastSchedule..outstandingBalance += totalAmount,
          );
        }),
      ]);

      emit(const AdditionalLoanState.loading());
      emit(const AdditionalLoanState.success(null));
    } catch (err) {
      _log.severe('Add loan amount error: $err', err);
      emit(const AdditionalLoanState.loading());
      emit(AdditionalLoanState.error('Cannot add loan: $err'));
    }
  }

  Future<void> _handleUpdateAdditionalLoanAmountEvent(
    UpdateAdditionalLoanAmountEvent event,
    Emitter<AdditionalLoanState> emit,
  ) async {
    try {
      emit(const AdditionalLoanState.loading(isLoading: true));
      final loan = await loanRepository.get(id: event.loanId);
      final additionalLoanAmount = loan.additionalLoanAmounts
          .firstWhereOrNull((loan) => loan.id == event.additionalLoanAmountId);
      if (additionalLoanAmount == null) {
        throw Exception('Additional loan amount not found');
      }
      additionalLoanAmount.status = event.status;
      await loanRepository.update(data: loan);
      emit(const AdditionalLoanState.loading());
      emit(
        const AdditionalLoanState.success(
          'Additional loan amount updated successfully',
        ),
      );
    } catch (e) {
      emit(const AdditionalLoanState.loading());
      _log.severe(
        'Something went wrong while updating additional loan amount: $e',
        e,
      );
      emit(
        const AdditionalLoanState.error(
          'Something went wrong while updating additional loan amount',
        ),
      );
    }
  }
}
