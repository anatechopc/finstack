import 'dart:async';

import 'package:collection/collection.dart';
import 'package:company_repository/company_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/loans/model/loan_simple.dart';
import 'package:loooans/features/loans/model/principal_borrower.dart';
import 'package:loooans/features/products/requirement_temp_container.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/charge_calculator.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:loooans_helpers/logging_helpers.dart';
import 'package:product_repository/product_repository.dart';
import 'package:product_view_repository/product_view_repository.dart';
import 'package:review_repository/review_repository.dart';
import 'package:storage_repository/storage_repository.dart';
import 'package:user_loan_view_repository/user_loan_view_repository.dart';
import 'package:user_repository/user_repository.dart';

part 'loans_event.dart';
part 'loans_functions.dart';
part 'loans_state.dart';

class LoansBloc extends Bloc<LoansEvent, LoansState> {
  LoansBloc(BuildContext context)
      : authService = AuthenticationService.instance,
        loanRepository = context.read<LoanRepository>(),
        loanScheduleRepository = context.read<LoanScheduleRepository>(),
        userLoanViewRepository = context.read<UserLoanViewRepository>(),
        storageRepository = context.read<StorageRepository>(),
        productViewRepository = context.read<ProductViewRepository>(),
        companyRepository = context.read<CompanyRepository>(),
        reviewRepository = context.read<ReviewRepository>(),
        productRepository = context.read<ProductRepository>(),
        userRepository = context.read<UserRepository>(),
        super(const LoansState()) {
    on(_handleSelectLoanEvent);
    on(_handleAddLoanEvent);
    on(_handleAddRequirementEvent);
    on(_handleRemoveRequirementEvent);
    on(_handleAddReviewEvent);
    on(_handleUpdateLoanStatusEvent);
    on(_handleGetLoansByUser);
    on(_handleGetPrincipalBorrowersEvent);
  }

  final AuthenticationService authService;
  final LoanRepository loanRepository;
  final LoanScheduleRepository loanScheduleRepository;
  final UserLoanViewRepository userLoanViewRepository;
  final StorageRepository storageRepository;
  final ProductViewRepository productViewRepository;
  final CompanyRepository companyRepository;
  final ReviewRepository reviewRepository;
  final ProductRepository productRepository;
  final UserRepository userRepository;

  List<LoanSchedule> get clientLoanSchedules => _clientLoanSchedules;

  double get monthlyAmortization => _monthlyAmortization;

  double get totalLoanPayment => _totalLoanPayment;

  double get totalLoanAmountReceivable => _totalLoanAmountReceivable;

  List<RequirementTempContainer>? _submittedRequirements;

  List<RequirementTempContainer> get submittedRequirements =>
      _submittedRequirements ?? <RequirementTempContainer>[];

  Stream<List<UserLoanView>> get userLoanViews =>
      userLoanViewRepository.dataStream.handleError((Object error) {
        log.severe('UserLoanViews error: $error');
      });

  UserLoanView? _selectedUserLoanView;

  UserLoanView get selectedUserLoanView => _selectedUserLoanView!;

  /// Null-safe view of the same field. [selectedUserLoanView] throws when
  /// nothing is selected — reachable state, guarded against elsewhere in this
  /// bloc — so callers that can run before a selection should use this.
  UserLoanView? get selectedUserLoanViewOrNull => _selectedUserLoanView;

  final List<UserLoanView> _selectedBorrowerLoanViews = [];

  List<UserLoanView> get selectedBorrowerLoanViews =>
      _selectedBorrowerLoanViews;

  final List<RequirementSubmission> _selectedBorrowerLoanFiles = [];

  List<RequirementSubmission> get selectedBorrowerLoanFiles =>
      _selectedBorrowerLoanFiles;

  final List<PrincipalBorrower> _selectedBorrowerPrincipalBorrowers = [];

  List<PrincipalBorrower> get selectedBorrowerPrincipalBorrowers =>
      _selectedBorrowerPrincipalBorrowers;

  Loan? _selectedLoan;

  Loan get selectedLoan => _selectedLoan!;

  final List<LoanSimple> _userLoans = [];

  List<LoanSimple> get userLoans => _userLoans;

  final List<User> _selectedLoanCoMakers = [];

  List<User> get selectedLoanCoMakers => _selectedLoanCoMakers;

  void clear() {
    _clientLoanSchedules.clear();
    _monthlyAmortization = 0;
    _totalLoanPayment = 0;
    _submittedRequirements?.clear();
    _selectedLoanCoMakers.clear();
    _selectedBorrowerLoanFiles.clear();
    _selectedBorrowerLoanViews.clear();
    _selectedBorrowerPrincipalBorrowers.clear();
  }

  void loadNext({int limit = defaultDataLimit}) {
    userLoanViewRepository.loadNext(
      statements: [
        QueryStatement(
          field: 'user_id',
          isEqualTo: authService.user.id,
        ),
      ],
      limit: limit,
    );
  } 

  void clientsLoadNext({int limit = defaultDataLimit}) {
    userLoanViewRepository.loadNext(
      statements: [
        QueryStatement(
          field: 'company_id',
          isEqualTo: authService.company.id,
        ),
      ],
      limit: limit,
    );
  }

  void selectLoan(String loanId, {UserLoanView? userLoanView}) {
    add(SelectLoanEvent(
      id: loanId,
      view: userLoanView,
    ),);
  }

  void unselectLoan() {
    clear();
    emit(const LoansState.unselected());
  }

  void getLoansByUser({
    required String userId,
    bool allStatus = false,
    bool userIsBorrower = false,
  }) {
    add(
      GetLoansByUser(
        userId: userId,
        allStatus: allStatus,
        userIsBorrower: userIsBorrower,
      ),
    );
  }

  void getPrincipalBorrowers(String userId) {
    add(GetPrincipalBorrowersEvent(userId: userId));
  }

  void addRequirement({
    required Requirement requirement,
    required List<SimpleFileData> data,
  }) {
    add(AddRequirementEvent(requirement: requirement, data: data));
  }

  void removeRequirement({
    required String requirementId,
    required int index,
  }) {
    add(RemoveRequirementEvent(requirementId: requirementId, index: index));
  }

  void calculateLoan({
    required Map<String, dynamic> fields,
    required String term,
    required double interestRate,
    User? user,
    List<Charge> additionalCharges = const [],
    List<Charge> deductions = const [],
  }) {
    add(
      AddLoanEvent(
        fields: fields,
        term: term,
        interestRate: interestRate,
        additionalCharges: additionalCharges,
        deductions: deductions,
        user: user,
      ),
    );
  }

  void addLoan({
    required Map<String, dynamic> fields,
    required String term,
    required double interestRate,
    required Product product,
    User? user,
    List<User> coMakers = const [],
    String? parentId,
  }) {
    add(
      AddLoanEvent(
        fields: fields,
        term: term,
        interestRate: interestRate,
        storeLoan: true,
        product: product,
        user: user,
        coMakers: coMakers,
        parentId: parentId,
      ),
    );
  }

  void addReview({
    required String review,
    required int rating,
    required ProductView productView,
  }) {
    add(AddReviewEvent(
      review: review,
      rating: rating,
      productView: productView,
    ),);
  }

  void updateLoanStatus({
    required LoanStatus status,
    required Loan loan,
  }) {
    add(UpdateLoanStatusEvent(
      loanStatus: status,
      loan: loan,
    ),);
  }

  bool isSubmittedRequestCompleted(Product product) {
    if (_submittedRequirements == null) {
      return false;
    }

    final requirements = product.requirements;

    if (requirements.length != _submittedRequirements!.length) {
      return false;
    }

    for (final requirement in requirements) {
      final submitted = _submittedRequirements!.singleWhereOrNull(
        (submitted) => submitted.requirementId == requirement.id,
      );

      if (submitted == null) {
        return false;
      }

      if (submitted.fileData.length != requirement.quantity) {
        return false;
      }
    }

    return true;
  }

  Future<void> _handleSelectLoanEvent(
    SelectLoanEvent event,
    Emitter<LoansState> emit,
  ) async {
    try {
      emit(const LoansState.loading(isLoading: true));
      final loanUserLoanViewResult = await Future.wait([
        loanRepository.get(id: event.id),
        if (event.view == null)
          userLoanViewRepository
              .load(
                reset: true,
                statements: [
                  QueryStatement(
                    field: 'loan_id',
                    isEqualTo: event.id,
                  ),
                ],
                limit: 1,
              )
              .then((value) => value.first),
      ]);

      if (event.view == null) {
        _selectedUserLoanView = loanUserLoanViewResult[1] as UserLoanView;
      } else {
        _selectedUserLoanView = event.view;
      }

      final loan = loanUserLoanViewResult[0] as Loan;
      final r2 = await Future.wait([
        loanScheduleRepository.load(
          reset: true,
          statements: [
            QueryStatement(
              field: 'loan_id',
              isEqualTo: loan.id,
            ),
          ],
        ),
        productRepository.get(id: loan.productId),
        if (loan.coMakerUserIds.isNotEmpty)
          userRepository.load(
            limit: null,
            reset: true,
            statements: [
              QueryStatement(
                field: 'id',
                whereIn: loan.coMakerUserIds,
              ),
            ],
          ),
      ]);
      _selectedLoan = loan;
      final loanSchedules = r2[0] as List<LoanSchedule>;
      final product = r2[1] as Product;
      final additionalCharges = product.additionalCharges;
      final deductions = product.deductions;

      if (r2.length > 2) {
        _selectedLoanCoMakers
          ..clear()
          ..addAll(r2[2] as List<User>);
      }

      final (:totalAmount, :totalUpfrontCollection) =
          ChargeCalculator.applyChargesAndDeductions(
        baseAmount: loan.amount,
        charges: additionalCharges,
        deductions: deductions,
      );
      final totalUpfrontCollectionCharge = totalUpfrontCollection;

      log.finest('totalAmount: $totalAmount');

      if (loan.period != 0) {
        _calculateLoan(
          amount: totalAmount,
          monthsToPay: loan.period,
          date: loan.createdAt,
          interestRate: loan.interestRate,
          term: loan.term,
          paidSchedules: loanSchedules,
          companyId: loan.companyId,
        );
      } else {
        _calculateLoanOpen(
          amount: totalAmount,
          date: loan.createdAt,
          term: loan.term,
          interestRate: loan.interestRate,
          paidSchedules: loanSchedules,
          companyId: loan.companyId,
          loan: loan,
        );
      }

      _totalLoanAmountReceivable = totalAmount - totalUpfrontCollectionCharge;

      emit(const LoansState.loading());
      emit(LoansState.selected(loan: loan, schedules: _clientLoanSchedules));
    } catch (err) {
      log.severe('ERROR: $err', err);
      emit(const LoansState.loading());
      emit(LoansState.error('Cannot select loan: $err'));
    }
  }

  Future<void> _handleAddRequirementEvent(
      AddRequirementEvent event, Emitter<LoansState> emit,) async {
    try {
      final requirement = event.requirement;
      final data = event.data;

      _submittedRequirements ??= [];

      final submittedRequirement = _submittedRequirements!
          .singleWhereOrNull((req) => req.requirementId == requirement.id);

      if (submittedRequirement != null) {
        submittedRequirement.fileData.addAll(data);
      } else {
        _submittedRequirements!.add(
          RequirementTempContainer(
            requirement.id,
            requirement.name,
            data,
          ),
        );
      }

      emit(LoansState.refresh());
    } catch (err) {
      log.severe(err.toString(), err);
      emit(LoansState.error('Add requirement error: $err'));
    }
  }

  Future<void> _handleRemoveRequirementEvent(
    RemoveRequirementEvent event,
    Emitter<LoansState> emit,
  ) async {
    try {
      if (_submittedRequirements == null) {
        return;
      }

      final requirementId = event.requirementId;
      final index = event.index;

      final submittedRequirement = _submittedRequirements!
          .singleWhere((req) => req.requirementId == requirementId);

      submittedRequirement.fileData.removeAt(index);
      emit(LoansState.refresh());
    } catch (err) {
      log.severe(err.toString(), err);
      emit(LoansState.error('Add requirement error: $err'));
    }
  }

  Future<void> _handleAddLoanEvent(
      AddLoanEvent event, Emitter<LoansState> emit,) async {
    try {
      emit(const LoansState.loading(isLoading: true));
      final fields = event.fields;
      // do loan calculations here
      final amount = double.parse(fields['amount'] as String);
      var period = double.parse(fields['period'] as String);
      final product = event.product;
      final additionalCharges =
          product?.additionalCharges ?? event.additionalCharges;
      final deductions = product?.deductions ?? event.deductions;
      if (event.term == '15d') {
        // divided by 2 to make it seem that period is in
        // months
        period /= 2;
      }

      final (:totalAmount, :totalUpfrontCollection) =
          ChargeCalculator.applyChargesAndDeductions(
        baseAmount: amount,
        charges: additionalCharges,
        deductions: deductions,
      );

      log.finest('totalAmount: $totalAmount');

      _totalLoanAmountReceivable = totalAmount - totalUpfrontCollection;

      var paymentFrequency = fields['payment_frequency'] as String?;

      if (paymentFrequency == 'salary_days') {
        final salaryDays = event.user?.employmentDetails.salaryDays;

        if (salaryDays == null || salaryDays.isEmpty) {
          throw Exception(
              'Cannot proceed loan processing with payment frequency "Salary days". User have not entered salary days in their profile.',);
        }

        paymentFrequency = salaryDays.join(',');
      }

      void calculateLoan() {
        if (period != 0) {
          _calculateLoan(
            amount: totalAmount,
            monthsToPay: period.toInt(),
            date: DateTime.now(),
            interestRate: event.interestRate,
            term: event.term,
            companyId: product?.providerId ?? '',
          );
        } else {
          _calculateLoanOpen(
            amount: totalAmount,
            date: DateTime.now(),
            term: paymentFrequency ?? event.term,
            interestRate: event.interestRate,
            companyId: product?.providerId ?? '',
          );
        }
      }

      if (event.storeLoan && product != null) {
        // do storage here
        if (product.requiredCoMakerCount > 0 &&
            product.requiredCoMakerCount != event.coMakers.length) {
          throw Exception(
              'Please add ${product.requiredCoMakerCount} co-makers',);
        }

        calculateLoan();
        final user = event.user ?? authService.user;
        final tempLoan = Loan.create(
          userId: user.id,
          companyId: product.providerId,
          productId: product.id,
          amount: amount,
          additionalCharges: additionalCharges.fold(0, (prev, charge) {
            var totalAdditionalCharge = prev;

            if (charge.isUpfrontCollection) {
              return totalAdditionalCharge;
            }

            if (charge.isPercentage) {
              final amount = charge.amount / 100;
              totalAdditionalCharge += amount * totalAmount;
            } else {
              totalAdditionalCharge += charge.amount;
            }

            return totalAdditionalCharge;
          }),
          deductions: deductions.fold(0, (prev, charge) {
            var totalDeductions = prev;
            if (charge.isPercentage) {
              final amount = charge.amount / 100;
              totalDeductions += amount * totalAmount;
            } else {
              totalDeductions += charge.amount;
            }

            return totalDeductions;
          }),
          period: period.toInt(),
          requirements: [],
          isForceCollect: product.forceCollect,
          status: LoanStatus.pending,
          dueAt: period <= 0 ? null : _clientLoanSchedules.lastOrNull?.dueAt,
          reason: fields['reason'] as String,
          interestRate: product.interestRate,
          term: period != 0 ? product.term : paymentFrequency ?? product.term,
          amortization: _monthlyAmortization,
          additionalChargeUpfrontCollection: totalUpfrontCollection,
          coMakerUserIds: event.coMakers.map((e) => e.id).toList(),
          parentId: event.parentId,
        );

        final loan =
            await loanRepository.add(data: tempLoan).then((loan) async {
          unawaited(
            loanRepository.setDatabaseBasePath(loan.companyId).then((_) {
              return loanRepository.addLoanProductTypePair(
                loanId: loan.id,
                productType: product.loanType,
              );
            }),
          );
          return loanRepository
              .update(
            data: loan
              ..requirements = await Future.wait(
                _submittedRequirements?.map(
                      (submitted) {
                        return submitted.fileData.map(
                          (file) => storageRepository
                              .uploadFile(
                            data: file.data,
                            folder: 'users/${loan.userId}/loans/${loan.id}',
                            fileName: file.name,
                          )
                              .then((value) {
                            return RequirementSubmission(
                              url: value,
                              name: submitted.requirementName,
                              requirementId: submitted.requirementId,
                            );
                          }),
                        );
                      },
                    ).flattened ??
                    [],
              ),
          );
        });
        final tempUserLoanView = UserLoanView.create(
          userId: user.id,
          loanId: loan.id,
          loanType: product.loanType,
          userFullName: user.completeNameEasternOrder,
          loanDueAt: loan.dueAt,
          loanCreatedAt: loan.createdAt,
          loanStatus: loan.status,
          productId: product.id,
          companyName: fields['company_name'] as String,
          companyId: product.providerId,
          amount: loan.amount,
          amortization: loan.amortization,
        );

        await userLoanViewRepository.add(data: tempUserLoanView);
      } else {
        calculateLoan();
      }
      emit(const LoansState.loading());
      if (event.storeLoan) {
        emit(const LoansState.success(
            'Your loan request is successfully created and is pending for approval. You will receive a notification about the status of your loan.',),);
      } else {
        emit(LoansState.refresh());
      }
    } catch (err) {
      log.severe(err.toString(), err);
      emit(const LoansState.loading());
      emit(LoansState.error('Cannot add loan: $err'));
    }
  }

  Future<void> _handleAddReviewEvent(
    AddReviewEvent event,
    Emitter<LoansState> emit,
  ) async {
    try {
      emit(const LoansState.loading(isLoading: true));
      var productView = event.productView;
      final user = authService.user;
      var company = await companyRepository.get(id: productView.companyId);
      final tempReview = Review.create(
        providerId: company.id,
        userId: user.id,
        userFullName: user.completeNameEasternOrder,
        message: event.review,
        rating: event.rating,
      );
      company = company
        ..reviewCount += 1
        ..totalRating += event.rating;
      productView = productView
        ..reviewCount = company.reviewCount
        ..reviewRatingAvg = company.totalRating / company.reviewCount;
      await Future.wait([
        reviewRepository.add(data: tempReview),
        productViewRepository.update(data: productView),
        companyRepository.update(data: company),
      ]);
      emit(const LoansState.loading());
      emit(LoansState.success(
          'Thank you for making ${company.name} become better by submitting a review',),);
    } catch (err) {
      log.severe('Cannot add review: $err', err);
      emit(const LoansState.loading());
      emit(const LoansState.error('Cannot add review'));
    }
  }

  Future<void> _handleUpdateLoanStatusEvent(
    UpdateLoanStatusEvent event,
    Emitter<LoansState> emit,
  ) async {
    try {
      emit(const LoansState.loading(isLoading: true));

      if (_selectedUserLoanView == null) {
        throw Exception('Cannot update loan. No loan selected');
      }

      final loanStatus = event.loanStatus;
      final company = authService.company;

      if (loanStatus == LoanStatus.approved) {
        if (_clientLoanSchedules.isEmpty &&
            company.managementType == CompanyManagementType.app) {
          throw Exception('Cannot approve loan. No schedules created');
        }
      }

      final loan = event.loan..status = loanStatus;
      LoanSchedule? firstLoanSchedule;

      if (loanStatus == LoanStatus.approved &&
          company.managementType == CompanyManagementType.app) {
        firstLoanSchedule = _clientLoanSchedules.first
          ..status = loanStatus
          ..loanId = loan.id;
      }

      await Future.wait([
        loanRepository.update(
          data: loan..status = loanStatus,
          updateView: true,
        ),
        if (firstLoanSchedule != null)
          loanScheduleRepository.add(data: firstLoanSchedule),
      ]);
      emit(const LoansState.loading());
      emit(LoansState.success('Loan status updated to ${loanStatus.label}'));
    } on Exception catch (err) {
      log.severe('ERROR: $err', err);
      emit(const LoansState.loading());
      emit(LoansState.error(err.toString().replaceAll('Exception: ', '')));
    } catch (err) {
      log.severe('ERROR: $err', err);
      emit(const LoansState.loading());
      emit(const LoansState.error('Failed to update status'));
    }
  }

  Future<void> _handleGetLoansByUser(
    GetLoansByUser event,
    Emitter<LoansState> emit,
  ) async {
    try {
      emit(const LoansState.loading(isLoading: true));
      _userLoans.clear();
      final loans = await loanRepository.load(
        reset: true,
        limit: null,
        statements: [
          QueryStatement(
            field: 'user_id',
            isEqualTo: event.userId,
          ),
          if (!event.allStatus)
            QueryStatement(
              field: 'status',
              whereIn: [
                LoanStatus.pending.name,
                LoanStatus.approved.name,
                LoanStatus.not_paid.name,
                LoanStatus.paid_on_time.name,
                LoanStatus.paid_late.name,
                LoanStatus.payment_submitted.name,
              ],
            ),
        ],
      );

      for (final loan in loans) {
        final product = await productRepository.get(id: loan.productId);
        _userLoans.add(
          LoanSimple(
            loanId: loan.id,
            productId: product.id,
            loanType: product.loanType,
            status: loan.status,
          ),
        );
      }

      if (event.userIsBorrower) {
        _selectedBorrowerLoanFiles.clear();
        final userLoanViews = await Future.wait(
          loans.map((loan) {
            _selectedBorrowerLoanFiles.addAll(loan.requirements);
            return userLoanViewRepository
                .load(
                  reset: true,
                  statements: [
                    QueryStatement(
                      field: 'loan_id',
                      isEqualTo: loan.id,
                    ),
                  ],
                  limit: 1,
                )
                .then((value) => value[0]..reason = loan.reason);
          }),
        );

        _selectedBorrowerLoanViews
          ..clear()
          ..addAll(userLoanViews);
      }

      emit(const LoansState.loading());
      emit(const LoansState.allUserLoansRetrieved());
    } catch (err) {
      log.severe('Get loans by user error: $err', err);
      emit(const LoansState.loading());
      emit(LoansState.error('Canot get all loasn by user: $err'));
    }
  }

  Future<void> _handleGetPrincipalBorrowersEvent(
      GetPrincipalBorrowersEvent event, Emitter<LoansState> emit,) async {
    try {
      emit(const LoansState.loading(isLoading: true));
      final loans = await loanRepository.load(
        reset: true,
        limit: null,
        statements: [
          QueryStatement(
            field: 'co_maker_user_ids',
            arrayContains: event.userId,
          ),
        ],
      );

      final principalBorrowers = await Future.wait(
        loans.map((loan) async {
          final user = await userRepository.get(id: loan.userId);

          return PrincipalBorrower(
            date: loan.createdAt,
            userName: user.completeNameEasternOrder,
            // TODO(deibeeed): compute loan amount with charges
            loanAmount: loan.amount,
            status: loan.status,
            loanType: await productRepository.get(id: loan.productId).then(
                  (product) => product.loanType,
                ),
            loanId: loan.id,
            productId: loan.productId,
            userId: loan.userId,
          );
        }),
      );

      _selectedBorrowerPrincipalBorrowers
        ..clear()
        ..addAll(principalBorrowers);
      emit(const LoansState.loading());
      emit(const LoansState.principalBorrowersRetrieved());
    } catch (err) {
      log.severe('Get principal borrowers error: $err', err);
      emit(const LoansState.loading());
      emit(LoansState.error(
          'Cannot get principal borrowers: $err',),);
    }
  }
}
