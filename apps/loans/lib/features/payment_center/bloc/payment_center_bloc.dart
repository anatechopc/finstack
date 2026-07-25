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
import 'package:loooans/features/payment_center/model/borrower_loan_group.dart';
import 'package:loooans/features/payment_center/model/pending_submission.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/charge_calculator.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans/services/payment_confirmation_service.dart';
import 'package:loooans/services/settings_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:loooans_helpers/logging_helpers.dart';
import 'package:payment_repository/payment_repository.dart';
import 'package:product_repository/product_repository.dart';
import 'package:storage_repository/storage_repository.dart';
import 'package:user_repository/user_repository.dart';

part 'payment_center_event.dart';
part 'payment_center_state.dart';

final _log = Logger('payment_center_bloc');

class PaymentCenterBloc
    extends Bloc<PaymentCenterEvent, PaymentCenterState> {
  PaymentCenterBloc(
    BuildContext context, {
    AuthenticationService? authService,
    SettingsService? settingsService,
  })  : authService = authService ?? AuthenticationService.instance,
        settingsService = settingsService ?? SettingsService.instance,
        loanRepository = context.read<LoanRepository>(),
        loanScheduleRepository = context.read<LoanScheduleRepository>(),
        paymentRepository = context.read<PaymentRepository>(),
        cashPoolRepository = context.read<CashPoolRepository>(),
        storageRepository = context.read<StorageRepository>(),
        userRepository = context.read<UserRepository>(),
        productRepository = context.read<ProductRepository>(),
        super(const PaymentCenterState()) {
    on<SearchBorrowersEvent>(_handleSearchBorrowersEvent);
    on<SelectBorrowerEvent>(_handleSelectBorrowerEvent);
    on<ClearBorrowerEvent>(_handleClearBorrowerEvent);
    on<ExpandLoanEvent>(_handleExpandLoanEvent);
    on<CollapseLoanEvent>(_handleCollapseLoanEvent);
    on<MakePaymentEvent>(_handleMakePaymentEvent);
    on<MakeOverduePaymentEvent>(_handleMakeOverduePaymentEvent);
    on<RequestOtpEvent>(_handleRequestOtpEvent);
    on<VerifyOtpEvent>(_handleVerifyOtpEvent);
    on<RefreshBorrowerDataEvent>(_handleRefreshBorrowerDataEvent);
    on<ConfirmSubmissionEvent>(_handleConfirmSubmission);
    on<RejectSubmissionEvent>(_handleRejectSubmission);
  }

  final AuthenticationService authService;
  final SettingsService settingsService;
  final LoanRepository loanRepository;
  final LoanScheduleRepository loanScheduleRepository;
  final PaymentRepository paymentRepository;
  final CashPoolRepository cashPoolRepository;
  final StorageRepository storageRepository;
  final UserRepository userRepository;
  final ProductRepository productRepository;

  Future<void> _handleSearchBorrowersEvent(
    SearchBorrowersEvent event,
    Emitter<PaymentCenterState> emit,
  ) async {
    try {
      if (event.query.trim().isEmpty) {
        emit(state.copyWith(
          searchResults: [],
          status: PaymentCenterStatus.initial,
        ));
        return;
      }

      emit(state.copyWith(isLoading: true));

      final users = await userRepository.load(
        limit: null,
        reset: true,
        statements: [
          QueryStatement(
            field: 'company_id',
            isEqualTo: authService.company.id,
          ),
          QueryStatement(
            field: 'user_role',
            isEqualTo: UserRole.customer.name,
          ),
        ],
      );

      final filtered = users
          .where(
            (user) => user.completeNameWesternOrder
                .toLowerCase()
                .contains(event.query.toLowerCase()),
          )
          .toList();

      emit(state.copyWith(
        status: PaymentCenterStatus.searchResults,
        searchResults: filtered,
        isLoading: false,
      ));
    } catch (err) {
      _log.severe('Search borrowers error: $err', err);
      emit(state.copyWith(
        status: PaymentCenterStatus.error,
        message: 'Failed to search borrowers',
        isLoading: false,
      ));
    }
  }

  Future<void> _handleSelectBorrowerEvent(
    SelectBorrowerEvent event,
    Emitter<PaymentCenterState> emit,
  ) async {
    try {
      emit(state.copyWith(
        status: PaymentCenterStatus.loading,
        isLoading: true,
        selectedBorrower: event.borrower,
      ));

      final results = await _loadBorrowerData(event.borrower);

      emit(state.copyWith(
        status: PaymentCenterStatus.borrowerSelected,
        borrowerLoans: results.$1,
        coMakerLoans: results.$2,
        pendingSubmissions: results.$3,
        isLoading: false,
        expandedLoanSchedules: const {},
      ));
    } catch (err) {
      _log.severe('Select borrower error: $err', err);
      emit(state.copyWith(
        status: PaymentCenterStatus.error,
        message: 'Failed to load borrower loans',
        isLoading: false,
      ));
    }
  }

  Future<
      (
        List<BorrowerLoanGroup>,
        List<BorrowerLoanGroup>,
        Map<String, List<PendingSubmission>>,
      )> _loadBorrowerData(User borrower) async {
    final borrowerLoans = await loanRepository.load(
      reset: true,
      limit: null,
      statements: [
        QueryStatement(field: 'user_id', isEqualTo: borrower.id),
      ],
    );

    final coMakerLoans = await loanRepository.load(
      reset: true,
      limit: null,
      statements: [
        QueryStatement(
          field: 'co_maker_user_ids',
          arrayContains: borrower.id,
        ),
      ],
    );

    final borrowerGroups =
        await _buildLoanGroups(borrowerLoans);
    final coMakerGroups =
        await _buildLoanGroups(coMakerLoans, flat: true);

    final pendingSubmissions =
        await _loadPendingSubmissions([...borrowerLoans, ...coMakerLoans]);

    return (borrowerGroups, coMakerGroups, pendingSubmissions);
  }

  /// Resolves borrower-submitted payments awaiting confirm/reject for the
  /// given loans.
  ///
  /// Scope: there is no global "all pending payments for a company" query
  /// (payments aren't tagged with a company), so we mirror the borrower-centric
  /// flow — for each loan we look at its persisted schedules in
  /// [LoanStatus.payment_submitted] carrying a paymentId, load those payments,
  /// keep only the pending ones, and group them by submissionId so a "Pay in
  /// full" submission (N schedules) surfaces/acts as ONE item.
  ///
  /// Returns a map keyed by loanId.
  Future<Map<String, List<PendingSubmission>>> _loadPendingSubmissions(
    List<Loan> loans,
  ) async {
    final result = <String, List<PendingSubmission>>{};

    for (final loan in loans) {
      final persistedSchedules = await loanScheduleRepository.allByLoanId(
        loanId: loan.id,
        onlyPaid: false,
      );

      final submittedSchedules = persistedSchedules
          .where(
            (s) =>
                s.status == LoanStatus.payment_submitted &&
                s.paymentId != null &&
                s.paymentId!.isNotEmpty,
          )
          .toList();

      if (submittedSchedules.isEmpty) continue;

      // Group submissionId -> payments and accumulate schedule amounts.
      final paymentsBySubmission = <String, List<Payment>>{};
      final amountBySubmission = <String, double>{};

      for (final schedule in submittedSchedules) {
        Payment payment;
        try {
          payment = await paymentRepository.get(id: schedule.paymentId!);
        } catch (err) {
          _log.warning(
            'Failed to load payment ${schedule.paymentId} for pending '
            'submission: $err',
          );
          continue;
        }

        if (payment.status != PaymentStatus.pending) continue;

        // Fall back to the payment id when no submissionId is set so a lone
        // submission still surfaces as its own item.
        final key = payment.submissionId ?? payment.id;
        paymentsBySubmission.putIfAbsent(key, () => []).add(payment);
        amountBySubmission.update(
          key,
          (value) => value + schedule.amortization,
          ifAbsent: () => schedule.amortization,
        );
      }

      if (paymentsBySubmission.isEmpty) continue;

      result[loan.id] = paymentsBySubmission.entries
          .map(
            (entry) => PendingSubmission(
              submissionId: entry.key,
              payments: entry.value,
              totalAmount: amountBySubmission[entry.key],
            ),
          )
          .toList();
    }

    return result;
  }

  Future<List<BorrowerLoanGroup>> _buildLoanGroups(
    List<Loan> loans, {
    bool flat = false,
  }) async {
    final parents = loans.where((l) => l.parentId == null).toList();
    final children = loans.where((l) => l.parentId != null).toList();

    final groups = <BorrowerLoanGroup>[];

    for (final parent in parents) {
      final product = await _getProduct(parent.productId);
      final schedules = await _getActionableSchedules(parent, product);

      final childGroups = <BorrowerLoanGroup>[];
      if (!flat) {
        final parentChildren =
            children.where((c) => c.parentId == parent.id).toList();
        for (final child in parentChildren) {
          final childProduct = await _getProduct(child.productId);
          final childSchedules =
              await _getActionableSchedules(child, childProduct);
          childGroups.add(BorrowerLoanGroup(
            loan: child,
            productName: childProduct?.loanType ?? 'Unknown',
            loanType: childProduct?.loanType ?? 'Unknown',
            actionableSchedules: childSchedules,
          ));
        }
      }

      groups.add(BorrowerLoanGroup(
        loan: parent,
        productName: product?.loanType ?? 'Unknown',
        loanType: product?.loanType ?? 'Unknown',
        actionableSchedules: schedules,
        childLoans: childGroups,
      ));
    }

    // Include orphan children (whose parent is not in the list)
    if (flat) {
      for (final child in children) {
        final product = await _getProduct(child.productId);
        final schedules = await _getActionableSchedules(child, product);
        groups.add(BorrowerLoanGroup(
          loan: child,
          productName: product?.loanType ?? 'Unknown',
          loanType: product?.loanType ?? 'Unknown',
          actionableSchedules: schedules,
        ));
      }
    } else {
      final orphans = children.where(
        (c) => !parents.any((p) => p.id == c.parentId),
      );
      for (final orphan in orphans) {
        final product = await _getProduct(orphan.productId);
        final schedules = await _getActionableSchedules(orphan, product);
        groups.add(BorrowerLoanGroup(
          loan: orphan,
          productName: product?.loanType ?? 'Unknown',
          loanType: product?.loanType ?? 'Unknown',
          actionableSchedules: schedules,
        ));
      }
    }

    return groups;
  }

  Future<Product?> _getProduct(String productId) async {
    try {
      return await productRepository.get(id: productId);
    } catch (err) {
      _log.warning('Failed to get product $productId: $err');
      return null;
    }
  }

  /// Generates actionable (payable) schedules for a loan.
  ///
  /// For fixed-term loans: calculates remaining unpaid schedules using
  /// [LoanCalculationService.calculateFixedTerm] with paid schedules.
  /// For open-term loans: generates the next payable schedule using
  /// [LoanCalculationService.calculateOpenTerm].
  ///
  /// Returns all overdue schedules + the next upcoming unpaid schedule.
  Future<List<LoanSchedule>> _getActionableSchedules(
    Loan loan,
    Product? product,
  ) async {
    // No actionable schedules for completed/declined/bad_debt loans
    if (loan.status == LoanStatus.completed ||
        loan.status == LoanStatus.declined ||
        loan.status == LoanStatus.bad_debt) {
      return [];
    }

    // Fetch persisted schedules from Firestore
    final persistedSchedules = await loanScheduleRepository.allByLoanId(
      loanId: loan.id,
      onlyPaid: false,
    );

    // Separate paid from unpaid persisted schedules
    final paidSchedules = persistedSchedules
        .where(
          (s) =>
              s.status != LoanStatus.not_paid &&
              s.status != LoanStatus.not_paid_overdue,
        )
        .toList();

    // Calculate the total loan amount (with charges/deductions)
    var totalAmount = loan.amount;
    if (product != null) {
      final chargeResult = ChargeCalculator.applyChargesAndDeductions(
        baseAmount: loan.amount,
        charges: product.additionalCharges,
        deductions: product.deductions,
      );
      totalAmount = chargeResult.totalAmount;
    }

    List<LoanSchedule> generatedSchedules;

    if (loan.period != 0) {
      // Fixed-term: generate remaining unpaid schedules
      final result = LoanCalculationService.calculateFixedTerm(
        amount: totalAmount,
        monthsToPay: loan.period,
        date: loan.createdAt,
        interestRate: loan.interestRate,
        term: loan.term,
        companyId: loan.companyId,
        paidSchedules: paidSchedules,
      );
      generatedSchedules = result.schedules;
    } else {
      // Open-term: generate next payable schedule
      final result = LoanCalculationService.calculateOpenTerm(
        amount: totalAmount,
        date: loan.createdAt,
        interestRate: loan.interestRate,
        term: loan.term,
        companyId: loan.companyId,
        paidSchedules: paidSchedules,
        loan: loan,
      );
      // Filter out placeholders and additional loan entries —
      // only keep actual payable schedules (id == NO_ID, not placeholder)
      generatedSchedules = result.schedules
          .where(
            (s) =>
                !s.isPlaceholder &&
                !s.isAdditionalLoanAmount &&
                (s.status == LoanStatus.not_paid ||
                    s.status == LoanStatus.not_paid_overdue),
          )
          .toList();
    }

    // Also include any persisted unpaid schedules from Firestore
    final persistedUnpaid = persistedSchedules
        .where(
          (s) =>
              s.status == LoanStatus.not_paid ||
              s.status == LoanStatus.not_paid_overdue,
        )
        .toList();

    // Combine: persisted unpaid + generated, then deduplicate by dueAt
    final allUnpaid = <LoanSchedule>[...persistedUnpaid];
    for (final gen in generatedSchedules) {
      final alreadyExists = allUnpaid.any(
        (s) =>
            s.dueAt.year == gen.dueAt.year &&
            s.dueAt.month == gen.dueAt.month &&
            s.dueAt.day == gen.dueAt.day,
      );
      if (!alreadyExists) {
        allUnpaid.add(gen);
      }
    }

    allUnpaid.sort((a, b) => a.dueAt.compareTo(b.dueAt));

    // Mark overdue schedules
    final now = DateTime.now();
    for (final schedule in allUnpaid) {
      if (schedule.dueAt.toLocal().isBefore(now) &&
          schedule.status == LoanStatus.not_paid) {
        schedule.status = LoanStatus.not_paid_overdue;
      }
    }

    // Return all overdue + next upcoming
    final overdue = allUnpaid
        .where((s) => s.status == LoanStatus.not_paid_overdue)
        .toList();
    final upcoming = allUnpaid
        .where((s) => s.status == LoanStatus.not_paid)
        .toList();

    return [
      ...overdue,
      if (upcoming.isNotEmpty) upcoming.first,
    ];
  }

  Future<void> _handleClearBorrowerEvent(
    ClearBorrowerEvent event,
    Emitter<PaymentCenterState> emit,
  ) async {
    emit(const PaymentCenterState());
  }

  Future<void> _handleExpandLoanEvent(
    ExpandLoanEvent event,
    Emitter<PaymentCenterState> emit,
  ) async {
    try {
      final loan = event.loan;
      final product = await _getProduct(loan.productId);

      // Fetch persisted schedules
      final persistedSchedules = await loanScheduleRepository.allByLoanId(
        loanId: loan.id,
        onlyPaid: false,
      );

      final paidSchedules = persistedSchedules
          .where(
            (s) =>
                s.status != LoanStatus.not_paid &&
                s.status != LoanStatus.not_paid_overdue,
          )
          .toList();

      var totalAmount = loan.amount;
      if (product != null) {
        final chargeResult = ChargeCalculator.applyChargesAndDeductions(
          baseAmount: loan.amount,
          charges: product.additionalCharges,
          deductions: product.deductions,
        );
        totalAmount = chargeResult.totalAmount;
      }

      List<LoanSchedule> fullSchedules;

      if (loan.period != 0) {
        // Fixed-term: paid + remaining calculated schedules
        final result = LoanCalculationService.calculateFixedTerm(
          amount: totalAmount,
          monthsToPay: loan.period,
          date: loan.createdAt,
          interestRate: loan.interestRate,
          term: loan.term,
          companyId: loan.companyId,
          paidSchedules: paidSchedules,
        );
        fullSchedules = [...paidSchedules, ...result.schedules];
      } else {
        // Open-term: use calculateOpenTerm which combines paid + next
        final result = LoanCalculationService.calculateOpenTerm(
          amount: totalAmount,
          date: loan.createdAt,
          interestRate: loan.interestRate,
          term: loan.term,
          companyId: loan.companyId,
          paidSchedules: paidSchedules,
          loan: loan,
        );
        fullSchedules = result.schedules;
      }

      fullSchedules.sort((a, b) => a.dueAt.compareTo(b.dueAt));

      final updated = Map<String, List<LoanSchedule>>.from(
        state.expandedLoanSchedules,
      );
      updated[event.loanId] = fullSchedules;

      emit(state.copyWith(
        status: PaymentCenterStatus.loanExpanded,
        expandedLoanSchedules: updated,
      ));
    } catch (err) {
      _log.severe('Expand loan error: $err', err);
      emit(state.copyWith(
        status: PaymentCenterStatus.error,
        message: 'Failed to load schedule history',
      ));
    }
  }

  Future<void> _handleCollapseLoanEvent(
    CollapseLoanEvent event,
    Emitter<PaymentCenterState> emit,
  ) async {
    final updated = Map<String, List<LoanSchedule>>.from(
      state.expandedLoanSchedules,
    )..remove(event.loanId);

    emit(state.copyWith(
      status: PaymentCenterStatus.borrowerSelected,
      expandedLoanSchedules: updated,
    ));
  }

  void makePayment({
    required Loan loan,
    required LoanSchedule schedule,
    required String interestPayment,
    required String payment,
    String? fileName,
    Uint8List? fileBytes,
    Uint8List? signatureBytes,
    bool force = false,
    bool otpVerified = false,
  }) {
    add(
      MakePaymentEvent(
        loan: loan,
        schedule: schedule,
        payment: double.parse(payment),
        interestPayment: double.parse(interestPayment),
        fileName: fileName,
        fileBytes: fileBytes,
        signatureBytes: signatureBytes,
        force: force,
        otpVerified: otpVerified,
      ),
    );
  }

  Future<void> _handleMakePaymentEvent(
    MakePaymentEvent event,
    Emitter<PaymentCenterState> emit,
  ) async {
    try {
      emit(state.copyWith(
        status: PaymentCenterStatus.paymentLoading,
        isLoading: true,
      ));

      final loan = event.loan;

      if (authService.company.managementType !=
          CompanyManagementType.selfManaged) {
        throw Exception('This action is not supported');
      }

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

      if (event.otpVerified) {
        comment = await _buildOtpComment(loan);
      } else if (event.force) {
        comment = _buildForceComment();
      } else {
        final result = await _uploadPaymentProof(event, loan);
        transactionPhotoUrl = result.$1;
        signatureUrl = result.$2;
        comment = result.$3;
      }

      final tempPayment = Payment.create(
        userId: loan.userId,
        loanScheduleId: schedule.id,
        loanId: loan.id,
        transactionPhotoUrl: transactionPhotoUrl,
        signatureUrl: signatureUrl,
        bypassPaymentProof: event.force || event.otpVerified,
        comment: comment,
        confirmedBy: authService.user.id,
        confirmedAt: DateTime.timestamp(),
        status: PaymentStatus.confirmed,
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

      await loanRepository.update(
        data: loan..status = status,
        updateView: true,
      );

      Payment? loanPayment;
      if (schedule.id == NO_ID) {
        await paymentRepository.add(data: tempPayment).then((payment) {
          loanPayment = payment;
          return loanScheduleRepository
              .add(data: schedule..paymentId = payment.id)
              .then((addedSchedule) {
            return paymentRepository
                .update(data: payment..loanScheduleId = addedSchedule.id);
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

      // Auto-complete the loan if this teller payment was the final schedule.
      // Runs after the schedule is persisted so the paid count is accurate.
      await PaymentConfirmationService(
        loanScheduleRepository: loanScheduleRepository,
        loanRepository: loanRepository,
        paymentRepository: paymentRepository,
      ).completeLoanIfFullyPaid(loan.id);

      await _processCashPool(
        loan: loan,
        loanPayment: loanPayment,
        totalPayment: event.interestPayment + event.payment,
      );

      emit(state.copyWith(
        status: PaymentCenterStatus.paymentSuccess,
        message: 'Successfully paid loan schedule',
        isLoading: false,
      ));

      // Defer refresh to allow BlocListener to process paymentSuccess first.
      // See PR #37: dispatching events immediately after emit causes race
      // conditions on web where the listener misses the intermediate state.
      if (state.selectedBorrower != null) {
        unawaited(Future.microtask(() => add(RefreshBorrowerDataEvent())));
      }
    } catch (err) {
      _log.severe('Make payment error: $err', err);
      emit(state.copyWith(
        status: PaymentCenterStatus.error,
        message: 'Something went wrong while paying schedule',
        isLoading: false,
      ));
    }
  }

  void makeOverduePayment({
    required Loan loan,
    required List<LoanSchedule> schedules,
    required String totalInterestPayment,
    required String totalPrincipalPayment,
    String? fileName,
    Uint8List? fileBytes,
    Uint8List? signatureBytes,
    bool force = false,
    bool otpVerified = false,
  }) {
    add(
      MakeOverduePaymentEvent(
        loan: loan,
        schedules: schedules,
        totalPrincipalPayment: double.parse(totalPrincipalPayment),
        totalInterestPayment: double.parse(totalInterestPayment),
        fileName: fileName,
        fileBytes: fileBytes,
        signatureBytes: signatureBytes,
        force: force,
        otpVerified: otpVerified,
      ),
    );
  }

  Future<void> _handleMakeOverduePaymentEvent(
    MakeOverduePaymentEvent event,
    Emitter<PaymentCenterState> emit,
  ) async {
    try {
      emit(state.copyWith(
        status: PaymentCenterStatus.paymentLoading,
        isLoading: true,
      ));

      final loan = event.loan;

      if (authService.company.managementType !=
          CompanyManagementType.selfManaged) {
        throw Exception('This action is not supported');
      }

      ImageUrl? transactionPhotoUrl;
      ImageUrl? signatureUrl;
      String? comment;

      if (event.otpVerified) {
        comment = await _buildOtpComment(loan);
      } else if (event.force) {
        comment = _buildForceComment();
      } else {
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
      }

      // Process each overdue schedule
      Payment? lastPayment;
      for (final schedule in event.schedules) {
        schedule
          ..paidAt = DateTime.timestamp()
          ..loanId = loan.id;

        final now = DateTime.now();
        final status = schedule.dueAt.toLocal().isBefore(now)
            ? LoanStatus.paid_late
            : LoanStatus.paid_on_time;

        // Distribute payment proportionally per schedule
        final interestPayment = schedule.isOpenTerm
            ? schedule.interestCharge
            : schedule.interestPayment;
        final principalPayment = schedule.principalPayment;

        if (!schedule.isOpenTerm) {
          final extraPayment = principalPayment - schedule.principalPayment;
          if (extraPayment > 0.0) {
            schedule
              ..extraPayment = extraPayment
              ..outstandingBalance -= extraPayment;
          }
        }

        schedule
          ..interestPayment = interestPayment
          ..principalPayment = principalPayment
          ..outstandingBalance -= (principalPayment - schedule.extraPayment)
          ..loanId = loan.id
          ..status = status;

        final tempPayment = Payment.create(
          userId: loan.userId,
          loanScheduleId: schedule.id,
          loanId: loan.id,
          transactionPhotoUrl: transactionPhotoUrl,
          signatureUrl: signatureUrl,
          bypassPaymentProof: event.force || event.otpVerified,
          comment: comment,
          confirmedBy: authService.user.id,
          confirmedAt: DateTime.timestamp(),
          status: PaymentStatus.confirmed,
        );

        if (schedule.id == NO_ID) {
          await paymentRepository.add(data: tempPayment).then((payment) {
            lastPayment = payment;
            return loanScheduleRepository
                .add(data: schedule..paymentId = payment.id)
                .then((addedSchedule) {
              return paymentRepository
                  .update(data: payment..loanScheduleId = addedSchedule.id);
            });
          });
        } else {
          await paymentRepository.add(data: tempPayment).then((payment) {
            lastPayment = payment;
            return loanScheduleRepository.update(
              data: schedule..paymentId = payment.id,
            );
          });
        }
      }

      // Update loan status with the last schedule's status
      final lastStatus = event.schedules.last.status;
      await loanRepository.update(
        data: loan..status = lastStatus,
        updateView: true,
      );

      // Auto-complete the loan if these overdue payments cleared the last
      // remaining schedule. Runs after the schedules are persisted.
      await PaymentConfirmationService(
        loanScheduleRepository: loanScheduleRepository,
        loanRepository: loanRepository,
        paymentRepository: paymentRepository,
      ).completeLoanIfFullyPaid(loan.id);

      // Process cash pool for the total payment
      final totalPayment =
          event.totalInterestPayment + event.totalPrincipalPayment;
      await _processCashPool(
        loan: loan,
        loanPayment: lastPayment,
        totalPayment: totalPayment,
      );

      emit(state.copyWith(
        status: PaymentCenterStatus.paymentSuccess,
        message:
            'Successfully paid ${event.schedules.length} overdue schedule(s)',
        isLoading: false,
      ));

      // Defer refresh to allow BlocListener to process paymentSuccess first.
      if (state.selectedBorrower != null) {
        unawaited(Future.microtask(() => add(RefreshBorrowerDataEvent())));
      }
    } catch (err) {
      _log.severe('Make overdue payment error: $err', err);
      emit(state.copyWith(
        status: PaymentCenterStatus.error,
        message: 'Something went wrong while paying overdue schedules',
        isLoading: false,
      ));
    }
  }

  Future<String> _buildOtpComment(Loan loan) async {
    final borrower = await userRepository.get(id: loan.userId);
    return '''
          Payment confirmed via SMS OTP by:
          user:id: ${borrower.id}
          user:name: ${borrower.completeNameEasternOrder}
          user:email: ${borrower.emailAddress}
          confirmed_at: ${DateTime.timestamp().toDefaultDateFormatExtended()}
          verification_method: SMS OTP
          processed_by: ${authService.user.completeNameEasternOrder} (${authService.user.id})''';
  }

  String _buildForceComment() {
    if (!settingsService.forcePaymentConfirmation) {
      throw Exception('Enable force payment confirmation in settings');
    }
    return '''
          Force payment confirmed by:
          user:id: ${authService.user.id}
          user:name: ${authService.user.completeNameEasternOrder}
          user:email: ${authService.user.emailAddress}
          confirmed_at: ${DateTime.timestamp().toDefaultDateFormatExtended()}''';
  }

  Future<(ImageUrl?, ImageUrl?, String)> _uploadPaymentProof(
    MakePaymentEvent event,
    Loan loan,
  ) async {
    if (event.fileName == null ||
        event.fileBytes == null ||
        event.signatureBytes == null) {
      throw Exception('Transaction photo and signature are required');
    }

    final transactionPhotoUrl = await storageRepository.upload(
      data: event.fileBytes!,
      folder: 'users/${loan.userId}/loans/${loan.id}',
      fileName: event.fileName!,
      includeOriginal: true,
    );

    final signatureUrl = await storageRepository.upload(
      data: event.signatureBytes!,
      folder: 'users/${loan.userId}/loans/${loan.id}',
      fileName:
          'signature_${DateTime.timestamp().toDefaultDateFormat()}.png',
      forceDecodeToImage: true,
      includeOriginal: true,
    );

    final comment = '''
          Manual payment confirmed by:
          user:id: ${authService.user.id}
          user:name: ${authService.user.completeNameEasternOrder}
          user:email: ${authService.user.emailAddress}
          confirmed_at: ${DateTime.timestamp().toDefaultDateFormatExtended()}''';

    return (transactionPhotoUrl, signatureUrl, comment);
  }

  Future<void> _processCashPool({
    required Loan loan,
    required Payment? loanPayment,
    required double totalPayment,
  }) async {
    final cashPoolList = await cashPoolRepository.load(
      reset: true,
      limit: null,
      statements: [
        QueryStatement(field: 'user_id', isEqualTo: loan.userId),
      ],
    );
    final cashPoolDisplay = await processCashPoolDisplay(cashPoolList);
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
  }

  Future<void> _handleRequestOtpEvent(
    RequestOtpEvent event,
    Emitter<PaymentCenterState> emit,
  ) async {
    try {
      emit(state.copyWith(
        status: PaymentCenterStatus.otpLoading,
        isLoading: true,
      ));
      final response = await userRepository.requestOtpForUser(
        idToken: authService.idToken,
        targetUserId: event.borrowerUserId,
      );
      emit(state.copyWith(
        status: PaymentCenterStatus.otpRequested,
        otpToken: response.token,
        otpExpireAt: response.expireAt,
        isLoading: false,
      ));
    } on RequestOtpException catch (err) {
      _log.severe('Request OTP rejected: $err', err);
      emit(
        state.copyWith(
          status: PaymentCenterStatus.error,
          message: err.userMessage,
          isLoading: false,
        ),
      );
    } catch (err) {
      _log.severe('Request OTP error: $err', err);
      emit(state.copyWith(
        status: PaymentCenterStatus.error,
        message: 'Failed to send OTP',
        isLoading: false,
      ));
    }
  }

  Future<void> _handleVerifyOtpEvent(
    VerifyOtpEvent event,
    Emitter<PaymentCenterState> emit,
  ) async {
    try {
      emit(state.copyWith(
        status: PaymentCenterStatus.otpLoading,
        isLoading: true,
      ));
      final verified = await userRepository.verifyOtp(
        idToken: authService.idToken,
        token: event.token,
        otp: event.otp,
      );

      if (verified) {
        emit(state.copyWith(
          status: PaymentCenterStatus.otpVerified,
          isLoading: false,
        ));
      } else {
        emit(state.copyWith(
          status: PaymentCenterStatus.error,
          message: 'Invalid OTP',
          isLoading: false,
        ));
      }
    } catch (err) {
      _log.severe('Verify OTP error: $err', err);
      emit(state.copyWith(
        status: PaymentCenterStatus.error,
        message: 'OTP verification failed: $err',
        isLoading: false,
      ));
    }
  }

  Future<void> _handleRefreshBorrowerDataEvent(
    RefreshBorrowerDataEvent event,
    Emitter<PaymentCenterState> emit,
  ) async {
    if (state.selectedBorrower == null) return;

    try {
      final results = await _loadBorrowerData(state.selectedBorrower!);

      emit(state.copyWith(
        status: PaymentCenterStatus.borrowerSelected,
        borrowerLoans: results.$1,
        coMakerLoans: results.$2,
        pendingSubmissions: results.$3,
        expandedLoanSchedules: const {},
      ));
    } catch (err) {
      _log.severe('Refresh borrower data error: $err', err);
    }
  }

  /// Confirm a borrower payment submission (all schedules under it).
  void confirmSubmission(List<Payment> payments) =>
      add(ConfirmSubmissionEvent(payments: payments));

  /// Reject a borrower payment submission (all schedules under it).
  void rejectSubmission(List<Payment> payments, String reason) =>
      add(RejectSubmissionEvent(payments: payments, reason: reason));

  Future<void> _handleConfirmSubmission(
    ConfirmSubmissionEvent event,
    Emitter<PaymentCenterState> emit,
  ) async {
    final service = PaymentConfirmationService(
      loanScheduleRepository: loanScheduleRepository,
      loanRepository: loanRepository,
      paymentRepository: paymentRepository,
    );

    try {
      if (authService.company.managementType !=
          CompanyManagementType.selfManaged) {
        throw Exception('This action is not supported');
      }

      emit(state.copyWith(
        status: PaymentCenterStatus.paymentLoading,
        isLoading: true,
      ));

      // TODO(payments): atomic multi-schedule confirm — a failure partway
      // through a "pay in full" submission leaves earlier schedules confirmed.
      for (final payment in event.payments) {
        await service.confirm(
          payment: payment,
          confirmedById: authService.user.id,
        );
      }

      emit(state.copyWith(
        status: PaymentCenterStatus.paymentSuccess,
        message: 'Payment submission confirmed',
        isLoading: false,
      ));

      // Defer refresh to allow BlocListener to process paymentSuccess first.
      if (state.selectedBorrower != null) {
        unawaited(Future.microtask(() => add(RefreshBorrowerDataEvent())));
      }
    } catch (err) {
      _log.severe('Confirm submission error: $err', err);
      emit(state.copyWith(
        status: PaymentCenterStatus.error,
        message: 'Something went wrong while confirming the submission',
        isLoading: false,
      ));
    }
  }

  Future<void> _handleRejectSubmission(
    RejectSubmissionEvent event,
    Emitter<PaymentCenterState> emit,
  ) async {
    final service = PaymentConfirmationService(
      loanScheduleRepository: loanScheduleRepository,
      loanRepository: loanRepository,
      paymentRepository: paymentRepository,
    );

    try {
      if (authService.company.managementType !=
          CompanyManagementType.selfManaged) {
        throw Exception('This action is not supported');
      }

      emit(state.copyWith(
        status: PaymentCenterStatus.paymentLoading,
        isLoading: true,
      ));

      // TODO(payments): atomic multi-schedule confirm — a failure partway
      // through a "pay in full" submission leaves earlier schedules reverted.
      for (final payment in event.payments) {
        await service.reject(
          payment: payment,
          confirmedById: authService.user.id,
          reason: event.reason,
        );
      }

      emit(state.copyWith(
        status: PaymentCenterStatus.paymentSuccess,
        message: 'Payment submission rejected',
        isLoading: false,
      ));

      // Defer refresh to allow BlocListener to process paymentSuccess first.
      if (state.selectedBorrower != null) {
        unawaited(Future.microtask(() => add(RefreshBorrowerDataEvent())));
      }
    } catch (err) {
      _log.severe('Reject submission error: $err', err);
      emit(state.copyWith(
        status: PaymentCenterStatus.error,
        message: 'Something went wrong while rejecting the submission',
        isLoading: false,
      ));
    }
  }
}
