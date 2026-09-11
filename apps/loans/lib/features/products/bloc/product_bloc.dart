import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loooans/features/products/bloc/product_status.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/charge_calculator.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:loooans_helpers/logging_helpers.dart';
import 'package:loooans_helpers/loooans_helpers.dart';
import 'package:product_repository/product_repository.dart';
import 'package:product_view_repository/product_view_repository.dart';
import 'package:review_repository/review_repository.dart';
import 'package:storage_repository/storage_repository.dart';

part 'product_event.dart';

part 'product_state.dart';

class ProductBloc extends Bloc<ProductEvent, ProductState> {
  ProductBloc(BuildContext context)
      : authService = AuthenticationService.instance,
        viewRepository = context.read<ProductViewRepository>(),
        productRepository = context.read<ProductRepository>(),
        storageRepository = context.read<StorageRepository>(),
        reviewRepository = context.read<ReviewRepository>(),
        super(const ProductState()) {
    on(_handleAddChargeEvent);
    on(_handleRemoveChargeEvent);
    on(_handleAddDeductionEvent);
    on(_handleRemoveDeductionEvent);
    on(_handleAddPenaltyEvent);
    on(_handleRemovePenaltyEvent);
    on(_handleResetPenaltiesEvent);
    on(_handleAddRequirementEvent);
    on(_handleRemoveRequirementEvent);
    on(_handleUpdateRequirementEvent);
    on(_handleAddProductEvent);
    on(_handleUpdatePreviewEvent);
    on(_handleSelectProductEvent);
    on(_handleUpdateProductEvent);
  }

  final AuthenticationService authService;
  final ProductViewRepository viewRepository;
  final ProductRepository productRepository;
  final StorageRepository storageRepository;
  final ReviewRepository reviewRepository;

  final log = Logger('product_bloc');

  final List<Charge> _charges = [];

  List<Charge> get charges => _charges;

  final List<Charge> _deductions = [];

  List<Charge> get deductions => _deductions;

  final List<Penalty> _penalties = [];

  List<Penalty> get penalties => _penalties;

  final List<Requirement> _requirements = [];

  List<Requirement> get requirements => _requirements;

  ProductView? _tempProductView;

  ProductView get tempProductView =>
      _tempProductView ?? _createTempProductView();

  Product? _selectedProduct;

  Product? get selectedProduct => _selectedProduct;

  Stream<List<ProductView>> get products => viewRepository.dataStream;

  final List<Review> _selectedProductReviews = [];

  List<Review> get selectedProductReviews => _selectedProductReviews;

  Map<String, Uint8List>? tempTermsAndConditions;

  void selectProduct(
    String productId, {
    ProductView? productView,
    bool forLoans = false,
  }) {
    add(
      SelectProductEvent(
        productId: productId,
        productView: productView,
        forLoans: forLoans,
      ),
    );
  }

  void refresh() {
    emit(ProductState.refresh());
  }

  void unselectProduct() {
    _tempProductView = null;
    _selectedProduct = null;
    _selectedProductReviews.clear();
    _penalties.clear();
    emit(const ProductState.unselected());
  }

  void initializeAddProduct(String? productId) {
    if (productId != null) {
      return;
    }

    _tempProductView = _createTempProductView();
    // A new product starts from the company defaults (copy-on-create).
    _penalties
      ..clear()
      ..addAll(authService.company.defaultPenalties);
  }

  void disposeAddProduct() {
    _charges.clear();
    _deductions.clear();
    _penalties.clear();
    _requirements.clear();
    _tempProductView = null;
    _selectedProduct = null;
    tempTermsAndConditions = null;
  }

  Future<void> loadNext({
    int limit = defaultDataLimit,
    bool? allowAddOns,
  }) async {
    var isAdmin = false;

    try {
      isAdmin = authService.isAdmin;
    } catch (err) {
      log.warning(
        'isAdmin will throw an error if not logged in. This will trigger when we show products to the index screen. This is expected',
      );
    }

    viewRepository.loadNext(
      limit: limit,
      statements: [
        if (isAdmin)
          QueryStatement(
            field: 'company_id',
            isEqualTo: authService.company.id,
          ),
        if (allowAddOns != null)
          QueryStatement(
            field: 'allow_add_ons',
            isEqualTo: allowAddOns,
          ),
      ],
    );
  }

  // void testAdd100(ProductView prod) async {
  //   log.finest('testAdd100 called');
  //
  //   for (var i = 0; i < 50; i++) {
  //     log.finest('added $i');
  //     await viewRepository.add(data: prod);
  //   }
  //   log.finest('finish test add');
  // }

  void addProduct(Map<String, dynamic> fields) {
    add(AddProductEvent(fields: fields));
  }

  void updateProduct(Map<String, dynamic> fields) {
    add(UpdateProductEvent(fields: fields));
  }

  void addAdditionalCharge({required Map<String, dynamic> fields}) {
    add(AddChargeEvent(fields: fields));
  }

  void removeCharge({required String id}) {
    add(RemoveChargeEvent(id: id));
  }

  void addDeduction({required Map<String, dynamic> fields}) {
    add(AddDeductionEvent(fields: fields));
  }

  void removeDeduction({required String id}) {
    add(RemoveDeductionEvent(id: id));
  }

  void addPenalty(Penalty penalty) {
    add(AddPenaltyEvent(penalty: penalty));
  }

  void removePenalty({required String id}) {
    add(RemovePenaltyEvent(id: id));
  }

  void resetPenalties() {
    add(ResetPenaltiesEvent());
  }

  void addRequirement({required String name}) {
    add(AddRequirementEvent(name: name));
  }

  void removeRequirement({required String id}) {
    add(RemoveRequirementEvent(id: id));
  }

  void updateRequirement({
    required String id,
    required int quantity,
  }) {
    add(
      UpdateRequirementEvent(
        id: id,
        quantity: quantity,
      ),
    );
  }

  void updatePreview(Map<String, dynamic> fields) {
    add(UpdatePreviewEvent(fields: fields));
  }

  double computeAdditionalCharge(Product product, String? amountStr) {
    if (amountStr == null || amountStr.isEmpty) {
      return 0;
    }

    var total = 0.0;
    var amount = 0.0;

    try {
      amount = double.parse(amountStr);
    } catch (err) {
      return 0;
    }

    if (product.additionalCharges.isEmpty) {
      return amount;
    }

    for (final charge in product.additionalCharges) {
      if (charge.isPercentage) {
        final chargePercent = charge.amount / 100;

        if (charge.isUpfrontCollection) {
          total -= amount * chargePercent;
        } else {
          total += amount * chargePercent;
        }
      } else {
        if (charge.isUpfrontCollection) {
          total -= charge.amount;
        } else {
          total += charge.amount;
        }
      }
    }

    return total + amount;
  }

  double computeDeductions(Product product, String? amountStr) {
    if (amountStr == null || amountStr.isEmpty) {
      return 0;
    }

    var total = 0.0;
    var amount = 0.0;

    try {
      amount = double.parse(amountStr);
    } catch (err) {
      return 0;
    }

    if (product.deductions.isEmpty) {
      return 0;
    }

    for (final charge in product.deductions) {
      if (charge.isPercentage) {
        final chargePercent = charge.amount / 100;

        total -= amount * chargePercent;
      } else {
        total -= charge.amount;
      }
    }

    return total - amount;
  }

  double computeTotalAdditionalLoanAmount(Product product, String? amountStr) {
    if (amountStr == null || amountStr.isEmpty) {
      return 0;
    }

    return computeAdditionalCharge(product, amountStr) -
        computeDeductions(product, amountStr);
  }

  ProductView _createTempProductView() {
    final company = authService.company;
    _tempProductView = ProductView.create(
      companyId: company.id,
      companyName: company.name,
      productId: NO_ID,
      loanType: 'Personal loan',
      term: '1m',
      interestRate: 0,
      maxLoanableAmount: 0,
      reviewRatingAvg: 0,
      reviewCount: 0,
      maxPeriod: 1,
      allowAddOns: true,
    );

    return _tempProductView!;
  }

  Future<void> _handleAddChargeEvent(
    AddChargeEvent event,
    Emitter<ProductState> emit,
  ) async {
    try {
      final data = event.fields;
      final tempAmount = data['amount'] as String;
      final (:amount, :isPercentage) =
          ChargeCalculator.parseChargeAmount(tempAmount);

      if (isPercentage && (amount > 100 || amount < 0)) {
        throw Exception('Percentage value should only be between 0 and 100');
      }

      final charge = Charge(
        id: StringHelper.generateId(length: 8),
        amount: amount,
        description: data['description'] as String,
        isPercentage: isPercentage,
        isUpfrontCollection: data['is_upfront_collection'] as bool,
      );
      _charges.add(charge);
      emit(ProductState.refresh());
    } catch (err) {
      log.severe(err);
      emit(ProductState.error(err.toString()));
    }
  }

  Future<void> _handleRemoveChargeEvent(
    RemoveChargeEvent event,
    Emitter<ProductState> emit,
  ) async {
    try {
      final id = event.id;
      _charges.removeWhere((charge) => charge.id == id);
      emit(ProductState.refresh());
    } catch (err) {
      log.severe(err);
    }
  }

  Future<void> _handleAddDeductionEvent(
    AddDeductionEvent event,
    Emitter<ProductState> emit,
  ) async {
    try {
      final data = event.fields;
      final tempAmount = data['amount'] as String;
      final (:amount, :isPercentage) =
          ChargeCalculator.parseChargeAmount(tempAmount);

      if (isPercentage && (amount > 100 || amount < 0)) {
        throw Exception('Percentage value should only be between 0 and 100');
      }

      final charge = Charge(
        id: StringHelper.generateId(length: 8),
        amount: amount,
        description: data['description'] as String,
        isPercentage: isPercentage,
      );
      _deductions.add(charge);
      emit(ProductState.refresh());
    } catch (err) {
      log.severe(err);
      emit(ProductState.error(err.toString()));
    }
  }

  Future<void> _handleRemoveDeductionEvent(
    RemoveDeductionEvent event,
    Emitter<ProductState> emit,
  ) async {
    try {
      final id = event.id;
      _deductions.removeWhere((charge) => charge.id == id);
      emit(ProductState.refresh());
    } catch (err) {
      log.severe(err);
    }
  }

  Future<void> _handleAddPenaltyEvent(
    AddPenaltyEvent event,
    Emitter<ProductState> emit,
  ) async {
    try {
      _penalties.add(event.penalty);
      emit(ProductState.refresh());
    } catch (err) {
      log.severe(err);
      emit(ProductState.error(err.toString()));
    }
  }

  Future<void> _handleRemovePenaltyEvent(
    RemovePenaltyEvent event,
    Emitter<ProductState> emit,
  ) async {
    try {
      _penalties.removeWhere((penalty) => penalty.id == event.id);
      emit(ProductState.refresh());
    } catch (err) {
      log.severe(err);
      emit(ProductState.error(err.toString()));
    }
  }

  Future<void> _handleResetPenaltiesEvent(
    ResetPenaltiesEvent event,
    Emitter<ProductState> emit,
  ) async {
    try {
      _penalties
        ..clear()
        ..addAll(authService.company.defaultPenalties);
      emit(ProductState.refresh());
    } catch (err) {
      log.severe(err);
      emit(ProductState.error(err.toString()));
    }
  }

  Future<void> _handleAddRequirementEvent(
    AddRequirementEvent event,
    Emitter<ProductState> emit,
  ) async {
    try {
      final id = event.name.toLowerCase().replaceAll(' ', '_');
      _requirements.add(
        Requirement(
          id: id,
          name: event.name,
          quantity: 1,
        ),
      );
      emit(ProductState.refresh());
    } catch (err) {
      log.severe(err);
    }
  }

  Future<void> _handleRemoveRequirementEvent(
    RemoveRequirementEvent event,
    Emitter<ProductState> emit,
  ) async {
    try {
      final id = event.id;
      _requirements.removeWhere((req) => req.id == id);
      emit(ProductState.refresh());
    } catch (err) {
      log.severe(err);
    }
  }

  Future<void> _handleUpdateRequirementEvent(
    UpdateRequirementEvent event,
    Emitter<ProductState> emit,
  ) async {
    try {
      final id = event.id;
      _requirements.singleWhere((req) => req.id == id).quantity = event.quantity;
      emit(ProductState.refresh());
    } catch (err) {
      log.severe(err);
    }
  }

  Future<void> _handleUpdatePreviewEvent(
    UpdatePreviewEvent event,
    Emitter<ProductState> emit,
  ) async {
    try {
      if (_tempProductView == null) {
        _createTempProductView();
      }

      final fields = event.fields;
      // loan_type
      // term
      // interest_rate
      // loanable_amount
      // additional charges
      // deductions

      final interestRateStr = fields['interest_rate'] as String?;
      final interestRate = interestRateStr != null
          ? ChargeCalculator.parseChargeAmount(interestRateStr).amount
          : 0.0;

      var loanType =
          fields['loan_type'] as String? ?? _tempProductView!.loanType;

      if (loanType == 'others') {
        loanType = fields['others_type'] as String;
      }

      _tempProductView!.loanType = loanType;
      _tempProductView!.term =
          fields['term'] as String? ?? _tempProductView!.term;
      _tempProductView?.interestRate = interestRate;
      _tempProductView?.maxLoanableAmount =
          num.parse(fields['loanable_amount'] as String? ?? '0').toDouble();
      _tempProductView!.maxPeriod =
          int.parse(fields['max_period'] as String? ?? '1');

      if (_tempProductView!.maxPeriod <= 0) {
        _tempProductView!.term = '1m';
      }

      final termsConditionsData =
          fields['upload_terms_conditions'] as Map<String, dynamic>?;

      if (termsConditionsData != null &&
          termsConditionsData['name'] != null &&
          termsConditionsData['bytes'] != null) {
        tempTermsAndConditions = {
          termsConditionsData['name'] as String:
              termsConditionsData['bytes'] as Uint8List,
        };
      }

      emit(ProductState.refresh());
    } catch (err) {
      log.severe(err);
    }
  }

  Future<void> _handleAddProductEvent(
    AddProductEvent event,
    Emitter<ProductState> emit,
  ) async {
    try {
      final fields = event.fields;
      final company = authService.company;
      emit(const ProductState.loading(isLoading: true));
      final interestRateStr = fields['interest_rate'] as String?;
      final interestRate = interestRateStr != null
          ? ChargeCalculator.parseChargeAmount(interestRateStr).amount
          : 0.0;

      var loanType = fields['loan_type'] as String;

      if (loanType == 'others') {
        loanType = fields['others_type'] as String;
      }

      final tempProduct = Product.create(
        providerId: company.id,
        loanType: loanType,
        term: fields['term'] as String,
        interestRate: interestRate,
        maxLoanableAmount: double.parse(fields['loanable_amount'] as String),
        maxPeriod: int.parse(fields['max_period'] as String),
        additionalCharges: _charges,
        deductions: _deductions,
        requirements: _requirements,
        requiredCoMakerCount: fields['required_co_maker_count'] as int? ?? 0,
        penalties: List<Penalty>.of(_penalties),
        allowLatePayments: fields['allow_late_payments'] as bool? ?? false,
      );

      final _ =
          await productRepository.add(data: tempProduct).then((product) async {
        final termsConditionsData =
            fields['upload_terms_conditions'] as Map<String?, dynamic>?;

        if (termsConditionsData != null &&
            termsConditionsData['name'] != null) {
          final file = await storageRepository.uploadFile(
            data: termsConditionsData['bytes'] as Uint8List,
            folder: 'companies/${company.id}/products/${product.id}',
            fileName: termsConditionsData['name'] as String,
          );

          product.termsConditionUrl = file;
        }

        final additionalLoanDocsData =
            fields['additional_loan_docs'] as List<dynamic>?;

        if (additionalLoanDocsData != null &&
            additionalLoanDocsData.isNotEmpty) {
          final uploadFutures = <Future<FileUrl>>[];

          for (final fileData in additionalLoanDocsData) {
            // ignore: avoid_dynamic_calls
            final bytes = fileData['bytes'] as Uint8List?;

            if (bytes == null) {
              continue;
            }

            uploadFutures.add(
              storageRepository.uploadFile(
                data: bytes,
                folder:
                    'companies/${company.id}/products/${product.id}/additional_loan_docs',
                // ignore: avoid_dynamic_calls
                fileName: fileData['name'] as String,
              ),
            );
          }

          final additionalLoanDocs = await Future.wait(uploadFutures);
          product.additionalLoanDocs = additionalLoanDocs;
        }

        return productRepository.update(data: product);
      });

      // once success, uncomment
      _charges.clear();
      _deductions.clear();
      _penalties.clear();
      _requirements.clear();
      emit(const ProductState.loading());
      emit(const ProductState.success());
    } catch (err) {
      log.severe('Add product error: $err', err);
      emit(const ProductState.loading());
      emit(
        const ProductState.error(
          'Something went wrong. Cannot add product.',
        ),
      );
    }
  }

  Future<void> _handleUpdateProductEvent(
    UpdateProductEvent event,
    Emitter<ProductState> emit,
  ) async {
    try {
      final fields = event.fields;
      emit(const ProductState.loading(isLoading: true));

      if (_selectedProduct == null || _tempProductView == null) {
        throw Exception('Please select product to update');
      }

      final interestRateStr = fields['interest_rate'] as String?;
      final interestRate = interestRateStr != null
          ? ChargeCalculator.parseChargeAmount(interestRateStr).amount
          : 0.0;

      var loanType = fields['loan_type'] as String;

      if (loanType == 'others') {
        loanType = fields['others_type'] as String;
      }

      final tempProduct = _selectedProduct!
        ..loanType = loanType
        ..term = fields['term'] as String
        ..interestRate = interestRate
        ..maxLoanableAmount = double.parse(fields['loanable_amount'] as String)
        ..maxPeriod = int.parse(fields['max_period'] as String)
        ..additionalCharges = _charges
        ..deductions = _deductions
        ..requirements = _requirements
        ..requiredCoMakerCount = fields['required_co_maker_count'] as int? ?? 0
        ..penalties = List<Penalty>.of(_penalties)
        ..allowLatePayments = fields['allow_late_payments'] as bool? ?? false;

      final _ = await productRepository
          .update(data: tempProduct)
          .then((product) async {
        var toUpdate = false;
        final termsConditionsData =
            fields['upload_terms_conditions'] as Map<String?, dynamic>?;

        if (termsConditionsData != null &&
            termsConditionsData['name'] != null) {
          final file = await storageRepository.uploadFile(
            data: termsConditionsData['bytes'] as Uint8List,
            folder: 'companies/${product.providerId}/products/${product.id}',
            fileName: termsConditionsData['name'] as String,
          );

          product.termsConditionUrl = file;
          toUpdate = true;
        }

        final additionalLoanDocsData =
            fields['additional_loan_docs'] as List<dynamic>?;

        if (additionalLoanDocsData != null &&
            additionalLoanDocsData.isNotEmpty) {
          final uploadFutures = <Future<FileUrl>>[];

          for (final fileData in additionalLoanDocsData) {
            // ignore: avoid_dynamic_calls
            final bytes = fileData['bytes'] as Uint8List?;

            if (bytes == null) {
              continue;
            }

            uploadFutures.add(
              storageRepository.uploadFile(
                data: bytes,
                folder:
                    'companies/${product.providerId}/products/${product.id}/additional_loan_docs',
                // ignore: avoid_dynamic_calls
                fileName: fileData['name'] as String,
              ),
            );
          }

          final additionalLoanDocs = await Future.wait(uploadFutures);

          if (additionalLoanDocs.isNotEmpty) {
            product.additionalLoanDocs = additionalLoanDocs;
            toUpdate = true;
          }
        }

        if (toUpdate) {
          return productRepository.update(data: product);
        }

        return product;
      });

      // once success, uncomment
      _charges.clear();
      _deductions.clear();
      _penalties.clear();
      _requirements.clear();
      emit(const ProductState.loading());
      emit(const ProductState.success(message: 'Product update successfully'));
    } catch (err) {
      log.severe('Update product error: $err', err);
      emit(const ProductState.loading());
      emit(
        const ProductState.error(
          'Something went wrong. Cannot update product.',
        ),
      );
    }
  }

  Future<void> _handleSelectProductEvent(
    SelectProductEvent event,
    Emitter<ProductState> emit,
  ) async {
    log.finest('SelectProductEvent start');
    try {
      emit(const ProductState.loading(isLoading: true));
      _tempProductView = event.productView;

      final productViewResult = await Future.wait([
        productRepository.get(id: event.productId),
        if (event.productView == null)
          viewRepository
              .load(
                reset: true,
                statements: [
                  QueryStatement(
                    field: 'product_id',
                    isEqualTo: event.productId,
                  ),
                ],
                limit: 1,
              )
              .then((value) => value.first),
      ]);
      final product = productViewResult[0] as Product;

      // this is to cover dynamic link
      if (event.productView == null) {
        _tempProductView = productViewResult[1] as ProductView;
      }

      _selectedProduct = product;
      _charges
        ..clear()
        ..addAll(product.additionalCharges);
      _deductions
        ..clear()
        ..addAll(product.deductions);
      _penalties
        ..clear()
        ..addAll(product.penalties);
      _requirements
        ..clear()
        ..addAll(product.requirements);
      _selectedProductReviews.clear();

      // Show detail panel immediately with product data
      emit(const ProductState.loading());
      if (!event.forLoans) {
        emit(ProductState.selected(product: product));
      } else {
        emit(ProductState.loanSelected(product: product));
      }

      // Load reviews in background and update when ready
      // TODO: Update review retrieval to use either streams OR pagination loading
      // for efficient review retrieval
      final reviews = await reviewRepository.load(
        reset: true,
        limit: null,
        statements: [
          QueryStatement(
            field: 'provider_id',
            isEqualTo: product.providerId,
          ),
        ],
      );
      _selectedProductReviews.addAll(reviews);
      emit(ProductState.refresh());
    } catch (err) {
      log.severe('Select product error: $err', err);
      emit(const ProductState.loading());
      emit(ProductState.error('Canot select product: $err'));
    }
  }
}
