import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:company_repository/company_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/products/requirement_temp_container.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/charge_calculator.dart';
import 'package:loooans/services/top_up_overdue_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans_helpers/logging_helpers.dart';
import 'package:payment_repository/payment_repository.dart';
import 'package:product_repository/product_repository.dart';
import 'package:storage_repository/storage_repository.dart';

part 'additional_loan_event.dart';
part 'additional_loan_state.dart';

final _log = Logger('additional_loan_bloc');

class AdditionalLoanBloc
    extends Bloc<AdditionalLoanEvent, AdditionalLoanState> {
  AdditionalLoanBloc(BuildContext context)
      : authService = AuthenticationService.instance,
        loanRepository = context.read<LoanRepository>(),
        storageRepository = context.read<StorageRepository>(),
        loanScheduleRepository = context.read<LoanScheduleRepository>(),
        paymentRepository = context.read<PaymentRepository>(),
        super(const AdditionalLoanState()) {
    productRepository = context.read<ProductRepository>();
    _registerHandlers();
  }

  /// Test seam: collaborators injected without a [BuildContext].
  /// [productRepository] is optional because it is a `final` class and so
  /// cannot be mocked; without it the loan's balance has no product
  /// charges, as in the Payment Center's seam.
  AdditionalLoanBloc.withDependencies({
    required this.authService,
    required this.loanRepository,
    required this.storageRepository,
    required this.loanScheduleRepository,
    required this.paymentRepository,
    ProductRepository? productRepository,
  }) : super(const AdditionalLoanState()) {
    if (productRepository != null) {
      this.productRepository = productRepository;
    }
    _registerHandlers();
  }

  final AuthenticationService authService;
  final LoanRepository loanRepository;
  final StorageRepository storageRepository;
  final LoanScheduleRepository loanScheduleRepository;
  final PaymentRepository paymentRepository;

  /// `late` so the test seam can omit it.
  late final ProductRepository productRepository;

  void _registerHandlers() {
    on<AddLoanAmountEvent>(_handleAddLoanAmountEvent);
    on<UpdateAdditionalLoanAmountEvent>(
      _handleUpdateAdditionalLoanAmountEvent,
    );
  }

  /// [overdueChoice] is the lender's answer to the overdue warning, null
  /// when the loan had no overdue bill.
  void addLoanAmount(
    String loanId,
    String amountStr, {
    required SimpleFileData selfiePhoto,
    required Uint8List signatureBytes,
    String? description,
    List<Charge> additionalCharges = const [],
    List<Charge> deductions = const [],
    OverdueChoice? overdueChoice,
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
        overdueChoice: overdueChoice,
      ),
    );
  }

  /// [expectedDeduction] is the overdue amount the approver was shown for a
  /// top-up whose lender chose to deduct (0 when none was overdue).
  void updateAdditionalLoanAmount({
    required String loanId,
    required String additionalLoanAmountId,
    required LoanStatus status,
    double? expectedDeduction,
  }) {
    add(
      UpdateAdditionalLoanAmountEvent(
        loanId: loanId,
        additionalLoanAmountId: additionalLoanAmountId,
        status: status,
        expectedDeduction: expectedDeduction,
      ),
    );
  }

  Future<void> _handleAddLoanAmountEvent(
    AddLoanAmountEvent event,
    Emitter<AdditionalLoanState> emit,
  ) async {
    try {
      emit(const AdditionalLoanState.loading(isLoading: true));
      final loan = await loanRepository.get(id: event.loanId);
      final (
        totalAmount: _,
        :totalUpfrontCollection,
        :totalAdditionalCharges,
        :totalDeductions,
      ) = ChargeCalculator.applyChargesAndDeductionsDetailed(
        baseAmount: event.amount,
        charges: event.additionalCharges,
        deductions: event.deductions,
      );

      // Upload selfie photo and signature, then update loan document.
      // Note: Do NOT mutate the last schedule's outstandingBalance here —
      // calculateOpenTerm already handles additional loan amounts in its
      // dedicated loop. Mutating the schedule causes double-counting.
      final values = await Future.wait([
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
      ]);

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
            // Only the choice is recorded now; approval applies it.
            overdueChoice: event.overdueChoice,
          ),
        ];

      await loanRepository.update(
        data: updatedLoan,
        updateView: true,
      );

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
      // A top-up releases its money once: approving it again would move
      // approved_at and could deduct its overdue bills twice.
      if (additionalLoanAmount.status != LoanStatus.pending) {
        throw TopUpRefused(
          'This additional loan is already '
          '${additionalLoanAmount.status.label.toLowerCase()}',
        );
      }
      if (additionalLoanAmount.overdueDeduction > 0) {
        throw const TopUpRefused(
          'An earlier approval of this additional loan stopped after its '
          'overdue bills were recorded. Check its payments before approving '
          'or declining it.',
        );
      }
      final approve = event.status == LoanStatus.approved;
      final deducted = approve &&
          additionalLoanAmount.overdueChoice == OverdueChoice.deduct &&
          await _deductOverdue(
            loan,
            additionalLoanAmount,
            expected: event.expectedDeduction ?? 0,
          );
      additionalLoanAmount
        ..status = event.status
        // The engine needs to know when the money was released (review of
        // finstack#146): a bill stored before it does not hold the top-up.
        // Set after the deducted bills are written, so they do not.
        ..approvedAt = approve ? DateTime.timestamp() : null;
      await loanRepository.update(data: loan, updateView: deducted);
      final released = TopUpOverdueService.proceeds(additionalLoanAmount) -
          additionalLoanAmount.overdueDeduction;
      emit(const AdditionalLoanState.loading());
      emit(
        AdditionalLoanState.success(
          deducted
              ? 'Approved: '
                  '${additionalLoanAmount.overdueDeduction.toCurrency()} of '
                  'overdue bills paid from it, ${released.toCurrency()} '
                  'to release'
              : 'Additional loan amount updated successfully',
        ),
      );
    } on TopUpRefused catch (e) {
      _log.warning('Additional loan amount refused: ${e.message}');
      emit(const AdditionalLoanState.loading());
      emit(AdditionalLoanState.error(e.message));
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

  /// The lender's "deduct" choice, applied at approval (owner, 2026-11-19):
  /// the overdue bills on the approval day, what the borrower's "Pay now"
  /// shows with [topUp] not yet in the balance, are recorded paid from its
  /// proceeds, collected now, with their penalties. Bills paid since the
  /// top-up was added are not deducted. No cash-pool entry: the proceeds
  /// never enter the borrower's prepaid balance.
  ///
  /// Throws, writing nothing, when the amount is not [expected] (what the
  /// approver was shown) or is more than the proceeds. Returns whether
  /// anything was deducted.
  Future<bool> _deductOverdue(
    Loan loan,
    AdditionalLoanAmount topUp, {
    required double expected,
  }) async {
    if (authService.company.managementType !=
        CompanyManagementType.selfManaged) {
      throw const TopUpRefused(
        'Payments are only recorded for self-managed companies',
      );
    }
    final service = TopUpOverdueService(
      loanScheduleRepository: loanScheduleRepository,
      paymentRepository: paymentRepository,
    );
    final now = DateTime.now();
    final schedules = await service.schedulesOf(
      loan,
      product: await _productOf(loan.productId),
      now: now,
    );
    final overdue = TopUpOverdueService.overdue(
      loan: loan,
      schedules: schedules,
      asOf: now,
    );
    final actorId = authService.user.id;
    final total = overdue == null
        ? 0.0
        : TopUpOverdueService.settle(
            loan: loan,
            bills: overdue.bills,
            schedules: schedules,
            collectedAt: now,
            actorId: actorId,
          );
    if ((total - expected).abs() >= 0.005) {
      throw TopUpRefused(
        'The overdue amount is now ${total.toCurrency()}, not '
        '${expected.toCurrency()}. Open the loan again and approve.',
      );
    }
    if (overdue == null) {
      return false;
    }
    final proceeds = TopUpOverdueService.proceeds(topUp);
    if (total > proceeds) {
      throw TopUpRefused(
        'The overdue amount (${total.toCurrency()}) is more than the cash '
        'this additional loan hands over (${proceeds.toCurrency()}). '
        'Decline it and add it again with another option.',
      );
    }

    // Recorded before the bills: an approval that stops after writing them
    // cannot be retried into a second deduction or a full release.
    topUp.overdueDeduction = total;
    await loanRepository.update(data: loan);
    topUp.deductedPaymentIds = await service.persist(
      loan: loan,
      bills: overdue.bills,
      actorId: actorId,
      comment: '''
          Paid from additional loan ${topUp.id} (deducted from its proceeds)
          approved by:
          user:id: $actorId
          user:name: ${authService.user.completeNameEasternOrder}
          deducted: $total of $proceeds handed over
          confirmed_at: ${DateTime.timestamp().toDefaultDateFormatExtended()}''',
    );
    // The loan follows its last bill paid, as the Payment Center's overdue
    // payment sets it.
    loan.status = overdue.bills.last.status;

    return true;
  }

  /// The loan's product for its charges, or none (no charges) when it
  /// cannot be read, as the Payment Center reads it. Client detail's
  /// figures use the product's charges, so a missing product makes the
  /// amount differ from what the approver saw and the approval is refused.
  Future<Product?> _productOf(String productId) async {
    try {
      return await productRepository.get(id: productId);
    } catch (err) {
      _log.warning('Failed to get product $productId: $err');
      return null;
    }
  }
}
