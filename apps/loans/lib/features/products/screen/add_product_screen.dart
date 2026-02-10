import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_svg/svg.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/bloc/product_status.dart';
import 'package:loooans/features/products/screen/preview_detail.dart';
import 'package:loooans/features/products/widget/add_product/add_ons_section.dart';
import 'package:loooans/features/products/widget/add_product/add_product_button.dart';
import 'package:loooans/features/products/widget/add_product/additional_loans_docs_section.dart';
import 'package:loooans/features/products/widget/add_product/charges_section.dart';
import 'package:loooans/features/products/widget/add_product/co_maker_count_section.dart';
import 'package:loooans/features/products/widget/add_product/interest_rate_field.dart';
import 'package:loooans/features/products/widget/add_product/loan_term_section.dart';
import 'package:loooans/features/products/widget/add_product/loan_type_section.dart';
import 'package:loooans/features/products/widget/add_product/max_loanable_amount_field.dart';
import 'package:loooans/features/products/widget/add_product/max_period_field.dart';
import 'package:loooans/features/products/widget/add_product/preview_section.dart';
import 'package:loooans/features/products/widget/add_product/requirements_section.dart';
import 'package:loooans/features/products/widget/add_product/upload_terms_conditions_field.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:product_repository/product_repository.dart';
import 'package:product_view_repository/product_view_repository.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({
    super.key,
    this.isFullScreen = false,
    this.productId,
  });

  final bool isFullScreen;
  final String? productId;

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey =
      GlobalKey<FormBuilderState>(debugLabel: 'add_product_screen');
  ProductView? _productView;
  Product? _product;
  bool triggerTermReload = false;

  @override
  void initState() {
    final bloc = context.read<ProductBloc>()
      ..initializeAddProduct(widget.productId);
    _productView = bloc.tempProductView;
    _product = bloc.selectedProduct;
    super.initState();
  }

  @override
  void dispose() {
    context.read<ProductBloc>().disposeAddProduct();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ProductBloc, ProductState>(
      listener: _onProductStateChanged,
      child: BlocBuilder<ProductBloc, ProductState>(
        builder: (context, state) {
          return FormBuilder(
            key: _formKey,
            onChanged: _onFormChanged,
            child:
                !widget.isFullScreen ? _body(context) : _bodyPortrait(context),
          );
        },
      ),
    );
  }

  void _onProductStateChanged(BuildContext context, ProductState state) {
    if (state.status == ProductStatus.error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(state.message!)));
    } else if (state.status == ProductStatus.loading) {
      if (state.isLoading) {
        AppWidgets.showDefaultLoadingDialog(context);
      } else {
        Navigator.of(context, rootNavigator: true).pop();
      }
    } else if (state.status == ProductStatus.success) {
      if (state.message != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(state.message!)));
      }
      if (!widget.isFullScreen) {
        Navigator.of(context, rootNavigator: true).pop();
      } else {
        GoRouter.of(context).pop();
      }
    } else if (state.status == ProductStatus.selected) {
      _product = state.product;
      debugPrint('_product == null? ${_product == null}');
    }
  }

  void _onFormChanged() {
    if (_formKey.currentState != null) {
      context
          .read<ProductBloc>()
          .updatePreview(_formKey.currentState!.simplifiedFields());

      // added run the code after 100 ms to prevent
      // setState while building
      Timer(const Duration(milliseconds: 100), () {
        if (triggerTermReload) {
          final tempProductView =
              context.read<ProductBloc>().tempProductView;
          if (tempProductView.maxPeriod <= 0) {
            _formKey.currentState!.fields['term']?.didChange(
              tempProductView.term,
            );
          }
          triggerTermReload = false;
        }
      });
    }
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            widget.productId == null ? 'Add product' : 'Update product',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(32),
            onTap: () {
              if (widget.isFullScreen) {
                GoRouter.of(context).popSafe('${Paths.index}?sec=offers');
              } else {
                Navigator.of(context, rootNavigator: true).pop();
              }
            },
            child: SvgPicture.asset(
              'svg/close.svg'.assetSafe,
              colorFilter: const ColorFilter.mode(
                AppColors.black,
                BlendMode.srcIn,
              ),
            ),
          ),
        ],
      ),
    );
  }

  MaxPeriodField _maxPeriodField() {
    return MaxPeriodField(
      formKey: _formKey,
      productView: _productView,
      onTriggerTermReload: () {
        triggerTermReload = true;
      },
    );
  }

  Widget _additionalLoansDocsConditional() {
    return BlocBuilder<ProductBloc, ProductState>(
      buildWhen: (prev, next) => next.status == ProductStatus.refresh,
      builder: (context, state) {
        final tempProductView = context.read<ProductBloc>().tempProductView;
        if (tempProductView.maxPeriod <= 0) {
          return AdditionalLoansDocsSection(product: _product);
        }
        return Container();
      },
    );
  }

  // --- Portrait (full-screen) layout ---

  Widget _bodyPortrait(BuildContext context) {
    return ListView.separated(
      itemBuilder: (context, index) {
        return switch (index) {
          0 => _header(context),
          1 => LoanTypeSection(formKey: _formKey, productView: _productView),
          2 => LoanTermSection(productView: _productView),
          3 => AdditionalChargesSection(isFullScreen: widget.isFullScreen),
          4 => DeductionsSection(isFullScreen: widget.isFullScreen),
          5 => InterestRateField(productView: _productView),
          6 => MaxLoanableAmountField(
              formKey: _formKey,
              productView: _productView,
            ),
          7 => _maxPeriodField(),
          8 => _additionalLoansDocsConditional(),
          // TODO(deibeeed): https://github.com/anatechopc/loooans/issues/58
          9 => Container(),
          10 => Container(),
          11 => UploadTermsConditionsField(product: _product),
          12 => CoMakerCountSection(product: _product),
          13 => const RequirementsSection(),
          14 => const Text(
              'Preview',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          15 => const Text('How clients sees your loan offer'),
          16 => BlocBuilder<ProductBloc, ProductState>(
              buildWhen: (prev, next) =>
                  next.status == ProductStatus.refresh,
              builder: (context, state) => PreviewDetail(
                productView: context.read<ProductBloc>().tempProductView,
              ),
            ),
          17 => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: AddProductButton(
                formKey: _formKey,
                productId: widget.productId,
              ),
            ),
          _ => Container(),
        };
      },
      separatorBuilder: (context, index) {
        if (index == 8) return Container();
        return const Gap(16);
      },
      itemCount: 18,
      padding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }

  // --- Desktop (dialog) layout ---

  Widget _body(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 16, left: 16, right: 16),
      constraints: const BoxConstraints(maxWidth: 1200, maxHeight: 1064),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(context),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Gap(24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _inputCol1()),
                      const Gap(24),
                      Expanded(child: _inputCol2()),
                      const Gap(24),
                      const Expanded(child: PreviewSection()),
                    ],
                  ),
                  const Gap(24),
                ],
              ),
            ),
          ),
          AddProductButton(formKey: _formKey, productId: widget.productId),
        ],
      ),
    );
  }

  Widget _inputCol1() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LoanTypeSection(formKey: _formKey, productView: _productView),
        const Gap(16),
        LoanTermSection(productView: _productView),
        const Gap(16),
        AdditionalChargesSection(isFullScreen: widget.isFullScreen),
        const Gap(16),
        DeductionsSection(isFullScreen: widget.isFullScreen),
        const Gap(16),
        InterestRateField(productView: _productView),
        const Gap(16),
        MaxLoanableAmountField(formKey: _formKey, productView: _productView),
        const Gap(16),
        _maxPeriodField(),
        // TODO(deibeeed): https://github.com/anatechopc/loooans/issues/58
        // _allowRequestMaxLoanAmountExtension() and _enforceAutoCollect()
        // are currently no-op (return Container)
        const Gap(16),
        UploadTermsConditionsField(product: _product),
      ],
    );
  }

  Widget _inputCol2() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoMakerCountSection(product: _product),
        const Gap(24),
        BlocBuilder<ProductBloc, ProductState>(
          buildWhen: (prev, next) => next.status == ProductStatus.refresh,
          builder: (context, state) {
            final tempProductView =
                context.read<ProductBloc>().tempProductView;
            if (tempProductView.maxPeriod <= 0) {
              return Column(
                children: [
                  AdditionalLoansDocsSection(product: _product),
                  const Gap(24),
                ],
              );
            }
            return Container();
          },
        ),
        AddOnsSection(product: _product),
        const Gap(24),
        const RequirementsSection(),
      ],
    );
  }
}
