import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/bloc/product_status.dart';
import 'package:loooans/features/products/screen/add_product_screen.dart';
import 'package:loooans/features/products/screen/loan_offer_detail.dart';
import 'package:loooans/features/products/screen/loan_offer_item.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/settings_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans_helpers/data_helpers.dart';

class LoanOffersWidget extends StatefulWidget {
  const LoanOffersWidget({
    super.key,
    this.expanded = false,
    this.parentMaxWidthConstraint = 1200,
    this.scrollController,
    this.buildFromIndex = false,
  });

  final bool expanded;
  final double parentMaxWidthConstraint;
  final ScrollController? scrollController;
  final bool buildFromIndex;

  @override
  State<LoanOffersWidget> createState() => _LoanOffersWidgetState();
}

class _LoanOffersWidgetState extends State<LoanOffersWidget> {
  int _selectedIndex = -1;
  var _selectedColor = AppColors.red;
  double _maxLoanableAmount = 0;
  double _maxPeriod = 0;

  @override
  void initState() {
    context.read<ProductBloc>().loadNext();
    final location = GoRouter.of(context).location;
    // debugPrint('Location: $location');

    _maxLoanableAmount = 0;
    _maxPeriod = 0;

    if (location.contains('maxLoanable')) {
      final uri = Uri.tryParse(GoRouter.of(context).location);

      if (uri != null) {
        if (uri.queryParameters.containsKey(Paths.paramMaxLoanable)) {
          _maxLoanableAmount =
              double.parse(uri.queryParameters[Paths.paramMaxLoanable]!);
        }

        if (uri.queryParameters.containsKey(Paths.paramMaxPeriod)) {
          _maxPeriod = double.parse(uri.queryParameters[Paths.paramMaxPeriod]!);
        }
      }
    }

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = getScreenSize(context: context);
    final isCompactOrMedium =
        getScreenSize(context: context).index <= ScreenSize.medium.index;

    return BlocListener<ProductBloc, ProductState>(
      listener: (context, state) async {
        if (state.status == ProductStatus.selected && state.product != null) {
          if (!AuthenticationService.instance.isAdmin) {
            if (isCompactOrMedium) {
              GoRouter.of(context)
                  .goSafe('${Paths.index}?sec=offers&id=${state.product!.id}');
            }
            return;
          }

          if (!isCompactOrMedium) {
            await showDialog(
              context: context,
              builder: (context) {
                return AlertDialog(
                  backgroundColor: AppColors.green1,
                  content: AddProductScreen(
                    productId: state.product!.id,
                  ),
                );
              },
            );
            _selectedIndex = -1;
            if (context.mounted) {
              context.read<ProductBloc>().unselectProduct();
            }

            return;
          }

          GoRouter.of(context).goSafe(
            Paths.offersAction.replaceAll(':action', Paths.actionCreate),
            extra: {'product_id': state.product?.id},
          );
        } else if (state.status == ProductStatus.unselected) {
          _selectedIndex = -1;
        } else if (state.status == ProductStatus.loading) {
          // if (state.isLoading) {
          //   AppWidgets.showDefaultLoadingDialog(context);
          // } else {
          //   Navigator.of(context, rootNavigator: true).pop();
          // }
        }
      },
      child: Row(
        children: [
          Expanded(
            child: _loanOffers(context),
          ),
          if (!AuthenticationService.instance.isAdmin)
            if (screenSize.index > ScreenSize.medium.index) ...[
              BlocBuilder<ProductBloc, ProductState>(
                buildWhen: (previous, current) {
                  return current.status == ProductStatus.selected ||
                      current.status == ProductStatus.unselected;
                },
                builder: (context, state) {
                  if (state.status == ProductStatus.initial ||
                      state.status == ProductStatus.unselected) {
                    return Container();
                  }

                  return const Gap(56);
                },
              ),
              BlocBuilder<ProductBloc, ProductState>(
                buildWhen: (previous, current) {
                  return current.status == ProductStatus.selected ||
                      current.status == ProductStatus.unselected;
                },
                builder: (context, state) {
                  if (state.status == ProductStatus.selected &&
                      state.product != null) {
                    return Expanded(
                      child: LoanOfferDetail(
                        background: _selectedColor,
                        key: ValueKey(state.product),
                        id: state.product!.id,
                        // tempProductView is populated when
                        // a product is selected
                        productView:
                            context.read<ProductBloc>().tempProductView,
                      ),
                    );
                  }

                  return Container();
                },
              ),
            ],
        ],
      ),
    );
  }

  Widget _loanOffers(BuildContext context) {
    var gridMainAxisExtent = 261;
    var headerText = 'Loan offers';
    const gotoSection = 'offers';
    var showAddProduct = false;
    final isCompactOrMedium =
        getScreenSize(context: context).index <= ScreenSize.medium.index;

    if (AuthenticationService.instance.isAdmin) {
      gridMainAxisExtent = 212;
      headerText = 'Loan products';
      showAddProduct = true;
    }

    if (widget.buildFromIndex) {
      headerText = 'Our loan partners';
    }

    if (widget.parentMaxWidthConstraint <= 553 &&
        widget.parentMaxWidthConstraint >= 548) {
      gridMainAxisExtent += 21;
    } else if (widget.parentMaxWidthConstraint <= 364) {
      gridMainAxisExtent += 21;
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              headerText,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: AppColors.white,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showAddProduct) ...[
                  // InkWell(
                  //   borderRadius: BorderRadius.circular(32),
                  //   onTap: () {
                  //     if (!isCompactOrMedium) {
                  //       showDialog(
                  //         context: context,
                  //         builder: (context) {
                  //           return AlertDialog(
                  //             backgroundColor: AppColors.green1,
                  //             content: AddProductScreen(),
                  //           );
                  //         },
                  //       );
                  //
                  //       return;
                  //     }
                  //
                  //     GoRouter.of(context).goSafe(
                  //       Paths.offersAction
                  //           .replaceAll(':action', Paths.actionCreate),
                  //     );
                  //   },
                  //   child: SvgPicture.asset('svg/add.svg'.assetSafe),
                  // ),
                  AppWidgets.defaultOutlinedButton(
                      foregroundColor: AppColors.white,
                      child: const Text('Add product'),
                      onPressed: () {
                        if (!isCompactOrMedium) {
                          showDialog(
                            context: context,
                            builder: (context) {
                              return const AlertDialog(
                                backgroundColor: AppColors.green1,
                                content: AddProductScreen(),
                              );
                            },
                          );
                          return;
                        }
                        GoRouter.of(context).goSafe(
                          Paths.offersAction
                              .replaceAll(':action', Paths.actionCreate),
                        );
                      },),
                  const Gap(16),
                ],
                if (widget.buildFromIndex) ...[
                  Text.rich(
                    TextSpan(
                      text: 'Be part as one of our partners!',
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          GoRouter.of(context)
                              .goSafe('${Paths.register}?as=provider');
                        },
                      style: const TextStyle(
                        shadows: [
                          Shadow(color: AppColors.green1, offset: Offset(0, -2)),
                        ],
                        decoration: TextDecoration.underline,
                        decorationThickness: 4,
                        decorationColor: AppColors.green1,
                        color: Colors.transparent,
                        // color: AppColors.green1,
                      ),
                    ),
                  ),
                  const Gap(16),
                ],
                if (!SettingsService.instance.appUseClassicUI)
                  InkWell(
                    borderRadius: BorderRadius.circular(32),
                    onTap: () {
                      if (AuthenticationService.instance.user.isPlaceholder) {
                        return;
                      }

                      if (!widget.expanded) {
                        GoRouter.of(context)
                            .goSafe('${Paths.index}?sec=$gotoSection');
                      } else {
                        GoRouter.of(context).goSafe(Paths.index);
                      }
                    },
                    child: !widget.expanded
                        ? SvgPicture.asset('svg/icon_arrow_up.svg'.assetSafe)
                        : SvgPicture.asset('svg/icon_arrow_down.svg'.assetSafe),
                  ),
              ],
            ),
          ],
        ),
        const Gap(16),
        Expanded(
          child: BlocBuilder<ProductBloc, ProductState>(
            buildWhen: (prev, next) {
              return [
                ProductStatus.refresh,
                ProductStatus.loading,
                ProductStatus.selected,
                ProductStatus.unselected,
                ProductStatus.initial,
              ].contains(next.status);
            },
            builder: (context, state) {
              return StreamBuilder(
                stream: context.read<ProductBloc>().products.map((products) {
                  if (_maxLoanableAmount <= 0) {
                    return products;
                  }

                  return products.where((product) {
                    if (_maxPeriod <= 0) {
                      return product.maxLoanableAmount <= _maxLoanableAmount;
                    }

                    return product.maxLoanableAmount <= _maxLoanableAmount &&
                        product.maxPeriod <= _maxPeriod;
                  }).toList();
                }),
                builder: (context, snapshot) {
                  final data = snapshot.data;

                  if (data == null) {
                    return Container();
                  }

                  return GridView.builder(
                    physics: widget.buildFromIndex
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 258,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      mainAxisExtent: gridMainAxisExtent.toDouble(),
                    ),
                    itemBuilder: (context, index) {
                      // if it's building the 2nd to the last data
                      if (index == data.length - 3) {
                        context
                            .read<ProductBloc>()
                            .loadNext(limit: data.length + defaultDataLimit);
                      }

                      final productView = data[index];
                      const colorList = AppColors.loanItemColorsList;
                      var colorIndex = index;

                      if (colorIndex > colorList.length - 1) {
                        final divisible = index % colorList.length;
                        colorIndex = divisible;
                      }

                      return LoanOfferItem(
                        backgroundColor: colorList[colorIndex],
                        productView: productView,
                        selected: _selectedIndex == index,
                        parentMaxWidthConstraint:
                            widget.parentMaxWidthConstraint,
                        isProduct: AuthenticationService.instance.isAdmin,
                        onSelected: () {
                          if (widget.buildFromIndex) {
                            AppWidgets.showDefaultSimpleDialog(
                              context,
                              content:
                                  'To check for the details of the loan offer, click the register button',
                              title: 'Register now',
                              actions: [
                                AppWidgets.defaultFilledButton(
                                  onPressed: () {
                                    GoRouter.of(context)
                                        .goSafe('${Paths.register}?as=user');
                                  },
                                  child: const Text('Register'),
                                ),
                              ],
                            );
                            return;
                          }

                          if (_selectedIndex == index) {
                            _selectedIndex = -1;
                            context.read<ProductBloc>().unselectProduct();
                          } else {
                            _selectedIndex = index;
                            _selectedColor = colorList[colorIndex];
                            context.read<ProductBloc>().selectProduct(
                                  productView.productId,
                                  productView: productView,
                                );
                          }
                        },
                      );
                    },
                    itemCount: data.length,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
