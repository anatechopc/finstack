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
    // One approval at a time: a double tap waits for the first to finish
    // and then finds the top-up no longer pending.
    on<UpdateAdditionalLoanAmountEvent>(
      _handleUpdateAdditionalLoanAmountEvent,
      transformer: (events, mapper) => events.asyncExpand(mapper),
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
      _requirePending(additionalLoanAmount);
      final approve = event.status == LoanStatus.approved;
      final done =
          approve && additionalLoanAmount.overdueChoice == OverdueChoice.deduct
              ? await _approveWithDeduction(
                  loan,
                  additionalLoanAmount,
                  expected: event.expectedDeduction ?? 0,
                )
              : await _transact(additionalLoanAmount.id, (current) {
                  _requirePending(current);
                  _requireUnclaimed(current);
                  return current
                    ..status = event.status
                    // The engine needs to know when the money was released
                    // (review of finstack#146).
                    ..approvedAt = approve ? DateTime.timestamp() : null;
                });
      final released =
          TopUpOverdueService.proceeds(done) - done.overdueDeduction;
      emit(const AdditionalLoanState.loading());
      emit(
        AdditionalLoanState.success(
          done.overdueDeduction > 0
              ? 'Approved: ${done.overdueDeduction.toCurrency()} of overdue '
                  'bills paid from it, ${released.toCurrency()} to release'
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

  /// Reads top-up [id] and writes what [change] returns in one Firestore
  /// transaction: two devices (or two taps) cannot both act on the state
  /// they read.
  Future<AdditionalLoanAmount> _transact(
    String id,
    AdditionalLoanAmount? Function(AdditionalLoanAmount current) change,
  ) =>
      loanRepository.transactAdditionalLoanAmount(id: id, change: change);

  /// A top-up is approved or declined once: approving it again would move
  /// approved_at and could deduct its overdue bills twice.
  static void _requirePending(AdditionalLoanAmount topUp) {
    if (topUp.status != LoanStatus.pending) {
      throw TopUpRefused(
        'This additional loan is already ${topUp.status.label.toLowerCase()}',
      );
    }
  }

  /// A top-up claimed for a deduction has bills being paid from it: only
  /// approving it again (which completes the deduction) is allowed.
  static void _requireUnclaimed(AdditionalLoanAmount topUp) {
    if (topUp.deductionPlan.isNotEmpty) {
      throw const TopUpRefused(
        'An approval of this additional loan is recording its overdue '
        'bills. Approve it again to complete it.',
      );
    }
  }

  /// The lender's "deduct" choice, applied at approval (owner, 2026-11-19).
  ///
  /// 1. Plan: the overdue bills on the approval day, what the borrower's
  ///    "Pay now" shows with [topUp] not yet in the balance, settled now
  ///    with their penalties. Refused, nothing written, unless the amount is
  ///    [expected] (what the approver was shown) and fits the proceeds.
  ///    Nothing overdue any more: approved without a deduction.
  /// 2. Claim, in a transaction: the plan, the amount and the payment ids
  ///    are written on the pending top-up once; a top-up already claimed
  ///    (another device, or an approval that stopped part way) keeps its
  ///    plan and this approval completes it.
  /// 3. Write the plan's payments and rows at their fixed ids (a retry
  ///    overwrites them), then approve in a transaction (approved_at after
  ///    the rows were computed, so the next bill keeps the top-up).
  ///
  /// No cash-pool entry: the proceeds never enter the borrower's prepaid
  /// balance; the released cash is handed over outside the app.
  Future<AdditionalLoanAmount> _approveWithDeduction(
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
    var claimed = topUp;
    if (topUp.deductionPlan.isEmpty) {
      final plan = await _planDeduction(loan, topUp, expected: expected);
      if (plan == null) {
        return _transact(topUp.id, (current) {
          _requirePending(current);
          _requireUnclaimed(current);
          return current
            ..status = LoanStatus.approved
            ..approvedAt = DateTime.timestamp();
        });
      }
      claimed = await _transact(topUp.id, (current) {
        _requirePending(current);
        if (current.deductionPlan.isNotEmpty) {
          return null;
        }
        return current
          ..overdueDeduction = plan.total
          ..deductedAt = plan.collectedAt
          ..deductedPaymentIds = TopUpOverdueService.paymentIdsOf(plan.writes)
          ..deductionPlan = plan.writes;
      });
    }
    if ((claimed.overdueDeduction - expected).abs() >= 0.005) {
      throw TopUpRefused(
        'This additional loan is deducting '
        '${claimed.overdueDeduction.toCurrency()}, not '
        '${expected.toCurrency()}. Open the loan again and approve.',
      );
    }

    await _refuseStalePlan(loan, claimed);
    await TopUpOverdueService(
      loanScheduleRepository: loanScheduleRepository,
      paymentRepository: paymentRepository,
    ).write(claimed.deductionPlan);
    final done = await _transact(topUp.id, (current) {
      _requirePending(current);
      return current
        ..status = LoanStatus.approved
        ..approvedAt = DateTime.timestamp();
    });
    // The loan follows its last bill paid, as the Payment Center's overdue
    // payment sets it. The top-up was written by the transactions above.
    await loanRepository.update(
      data: loan
        ..status = TopUpOverdueService.lastStatusOf(claimed.deductionPlan),
      updateView: true,
      updateAdditionalLoanAmounts: false,
    );

    return done;
  }

  /// A plan whose bills were paid by another payment since it was made
  /// (a teller took the cash while the approval was stopped) is never
  /// written: its amounts were worked out before that payment, which may
  /// have paid principal or left a shortfall for the next bill, and the
  /// approver confirmed a release that no longer holds. With none of its
  /// rows written the claim is released, so the next approval works the
  /// amount out again (or the top-up can be declined); with some written
  /// it is left for an admin. Either way nothing more is paid from it.
  Future<void> _refuseStalePlan(
    Loan loan,
    AdditionalLoanAmount claimed,
  ) async {
    final (:stale, :written) = TopUpOverdueService.check(
      claimed.deductionPlan,
      await loanScheduleRepository.allByLoanId(
        loanId: loan.id,
        onlyPaid: false,
      ),
    );
    if (!stale) {
      return;
    }
    if (written) {
      throw TopUpRefused(
        'While an approval of this additional loan was stopped, some of its '
        'overdue bills were paid from it and others by another payment. It '
        'cannot be completed or declined here: an admin needs to check '
        'payments ${claimed.deductedPaymentIds.join(', ')}.',
      );
    }
    await _transact(claimed.id, (current) {
      _requirePending(current);
      if (current.deductedAt != claimed.deductedAt) {
        return null;
      }
      return current
        ..deductionPlan = []
        ..deductedPaymentIds = []
        ..overdueDeduction = 0
        ..deductedAt = null;
    });
    throw const TopUpRefused(
      'The overdue bills were paid by another payment while this approval '
      'was stopped, so nothing was deducted. Open the loan again and '
      'approve: the overdue amount is worked out again.',
    );
  }

  /// Step 1 of [_approveWithDeduction]: the bills to pay from [topUp] now
  /// and their writes, or null when nothing is overdue.
  Future<
      ({
        List<Map<String, dynamic>> writes,
        double total,
        DateTime collectedAt,
      })?> _planDeduction(
    Loan loan,
    AdditionalLoanAmount topUp, {
    required double expected,
  }) async {
    final now = DateTime.now();
    final schedules = await TopUpOverdueService(
      loanScheduleRepository: loanScheduleRepository,
      paymentRepository: paymentRepository,
    ).schedulesOf(
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
      return null;
    }
    final proceeds = TopUpOverdueService.proceeds(topUp);
    if (total > proceeds) {
      throw TopUpRefused(
        'The overdue amount (${total.toCurrency()}) is more than the cash '
        'this additional loan hands over (${proceeds.toCurrency()}). '
        'Decline it and add it again with another option.',
      );
    }

    return (
      writes: TopUpOverdueService.plan(
        loan: loan,
        topUp: topUp,
        bills: overdue.bills,
        actorId: actorId,
        comment: '''
          Paid from additional loan ${topUp.id} (deducted from its proceeds)
          approved by:
          user:id: $actorId
          user:name: ${authService.user.completeNameEasternOrder}
          deducted: $total of $proceeds handed over
          confirmed_at: ${now.toUtc().toDefaultDateFormatExtended()}''',
      ),
      total: total,
      collectedAt: now,
    );
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
