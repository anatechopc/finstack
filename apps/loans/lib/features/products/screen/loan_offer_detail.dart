import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_svg/svg.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/bloc/product_status.dart';
import 'package:loooans/features/products/screen/loan_application.dart';
import 'package:loooans/features/products/widget/loan_offer_detail/loan_offer_details_form.dart';
import 'package:loooans/features/products/widget/loan_offer_detail/loan_offer_reviews_section.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:product_view_repository/product_view_repository.dart';

class LoanOfferDetail extends StatelessWidget {
  LoanOfferDetail({
    required this.id, required this.productView, super.key,
    this.background = AppColors.red,
    this.fullScreen = false,
  });

  final Color background;
  final bool fullScreen;
  final String id;
  final ProductView productView;

  final _formKey =
      GlobalKey<FormBuilderState>(debugLabel: 'loan_offer_details');

  @override
  Widget build(BuildContext context) {
    final screenSize = getScreenSize(context: context);
    final isCompact = screenSize == ScreenSize.compact;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!fullScreen) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Loan details',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: AppColors.white,
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(32),
                onTap: () {
                  context.read<ProductBloc>().unselectProduct();
                },
                child: SvgPicture.asset('svg/close.svg'.assetSafe),
              ),
            ],
          ),
          const Gap(16),
        ],
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(defaultPaddingSize),
            decoration: BoxDecoration(
              color: background,
              borderRadius: !fullScreen ? defaultBorderRadius : null,
            ),
            child: Column(
              children: [
                if (fullScreen && isCompact) ...[
                  Expanded(
                    child: _compactBody(context),
                  ),
                  const Gap(16),
                ] else
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _details(context),
                        ),
                        const Gap(24),
                        Expanded(
                          child: _reviews(context),
                        ),
                      ],
                    ),
                  ),
                _applyButton(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _compactBody(BuildContext context) {
    return BlocBuilder<ProductBloc, ProductState>(
      buildWhen: (previous, current) {
        return current.status == ProductStatus.selected ||
            current.status == ProductStatus.refresh;
      },
      builder: (context, state) {
        final reviews = context.read<ProductBloc>().selectedProductReviews;
        return ListView.separated(
          itemBuilder: (context, index) {
            return switch (index) {
              0 => LoanOfferDetailsForm(
                  formKey: _formKey,
                  productView: productView,
                  background: background,
                ),
              1 => LoanOfferReviewsHeader(
                  reviews: reviews,
                  fullScreen: fullScreen,
                ),
              _ when reviews.isEmpty => const LoanOfferReviewsEmpty(),
              _ => LoanOfferReviewItem(
                  review: reviews[index - 2],
                ),
            };
          },
          separatorBuilder: (context, index) {
            return const Gap(16);
          },
          itemCount: reviews.isEmpty ? 3 : reviews.length + 2,
        );
      },
    );
  }

  Widget _details(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: LoanOfferDetailsForm(
              formKey: _formKey,
              productView: productView,
              background: background,
            ),
          ),
        ),
        const Gap(16),
      ],
    );
  }

  Widget _reviews(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: BlocBuilder<ProductBloc, ProductState>(
            buildWhen: (previous, current) {
              return current.status == ProductStatus.selected ||
                  current.status == ProductStatus.refresh;
            },
            builder: (context, state) {
              final reviews =
                  context.read<ProductBloc>().selectedProductReviews;
              return ListView.separated(
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return LoanOfferReviewsHeader(
                      reviews: reviews,
                      fullScreen: fullScreen,
                    );
                  }

                  if (reviews.isEmpty) {
                    return const LoanOfferReviewsEmpty();
                  }

                  return LoanOfferReviewItem(review: reviews[index - 1]);
                },
                separatorBuilder: (context, index) {
                  return const Gap(16);
                },
                itemCount: reviews.isEmpty ? 2 : reviews.length + 1,
              );
            },
          ),
        ),
        const Gap(16),
      ],
    );
  }

  Widget _applyButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: AppWidgets.defaultFilledButton(
        child: const Text(
          'Apply for a loan!',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        onPressed: () {
          if (_formKey.currentState?.saveAndValidate() ?? false) {
            final amount = double.parse(
                _formKey.currentState!.value['amount'] as String,);
            final period = int.parse(
                _formKey.currentState!.value['period'] as String,);

            if (fullScreen) {
              GoRouter.of(context).goSafe(
                Paths.loansAction
                    .replaceAll(':action', Paths.actionCreate),
                extra: {
                  'amount': amount,
                  'period': period,
                },
              );
            } else {
              showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    backgroundColor: AppColors.green1,
                    title: const Text(
                      'Loan application',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 24,
                      ),
                    ),
                    content: SizedBox(
                      width: 600,
                      height: 812,
                      child: LoanApplication(
                        loanAmount: amount,
                        period: period,
                        productView: productView,
                      ),
                    ),
                  );
                },
              );
            }
          }
        },
      ),
    );
  }
}
