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
import 'package:product_view_repository/product_view_repository.dart';

class LoanOffersWidget extends StatefulWidget {
  const LoanOffersWidget({
    super.key,
    this.expanded = false,
    this.parentMaxWidthConstraint = 1200,
    this.scrollController,
    this.buildFromIndex = false,
    this.initialProductId,
  });

  final bool expanded;
  final double parentMaxWidthConstraint;
  final ScrollController? scrollController;
  final bool buildFromIndex;

  /// The `&id=` of `/?sec=offers&id=<productId>`: the offer the URL says is
  /// open. On a wide screen the URL owns the selection — see `_sync`.
  final String? initialProductId;

  /// The one way to open an offer from outside this widget (a search result,
  /// whichever surface shows it), so it opens exactly as a card tap does and
  /// the screen-size decision lives in one place.
  static void openOffer(BuildContext context, ProductView view) {
    final router = GoRouter.maybeOf(context);
    if (getScreenSize(context: context).index > ScreenSize.medium.index) {
      // Wide: write the URL and let `_sync` select when the id arrives — the
      // address bar is then a deep link to this offer, as it is to a borrower.
      router?.go('${Paths.index}?sec=offers&id=${view.productId}');
      return;
    }
    // Compact/medium: the selection drives the navigation instead. The
    // listener in `build` sends it where a card tap goes on these widths (the
    // full-screen detail; the edit screen for admins), so the selection must
    // land AFTER the offers page is mounted to listen. Read before
    // navigating: `go` deactivates this element on the same frame and a
    // deactivated context cannot `read`. Deferred a frame: `LoanDetails`
    // listens to `ProductBloc` and pushes a loading dialog on `loading`, and
    // selecting in the same tick as the navigation reached it still mounted.
    final products = context.read<ProductBloc>();
    router?.go('${Paths.index}?sec=offers');
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => products.selectProduct(view.productId, productView: view),
    );
  }

  @override
  State<LoanOffersWidget> createState() => _LoanOffersWidgetState();
}

class _LoanOffersWidgetState extends State<LoanOffersWidget> {
  int _selectedIndex = -1;
  var _selectedColor = AppColors.red;
  double _maxLoanableAmount = 0;
  double _maxPeriod = 0;

  /// The last list the grid rendered. A card tap finds its view here and
  /// hands it to the bloc; a deep link or a search result from another page
  /// arrives before the grid renders and selects by id alone, which costs the
  /// bloc one extra read (`viewRepository.load` by `product_id`).
  List<ProductView> _views = const [];

  /// The offer this widget last asked the bloc to select.
  String? _selectedFor;

  /// The offer whose edit dialog (admins, wide screens) is open.
  String? _dialogFor;

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
    _sync(widget.initialProductId);
  }

  /// `MainScreen` is keyed by section, so a change to `&id=` alone arrives
  /// here as a prop change, not a remount: a card tap or a search result
  /// (null → id) selects, and browser Back (id → null) unselects.
  @override
  void didUpdateWidget(LoanOffersWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialProductId != oldWidget.initialProductId) {
      _sync(widget.initialProductId);
    }
  }

  /// Makes the selection match [id]. Wide screens only: on compact/medium,
  /// `MainScreen` has already redirected the same URL to the full-screen
  /// route, and the selection is what drives that navigation — a second
  /// select here would push a second detail. Post-frame, as
  /// `BorrowerScreen._syncDialog` is: the width needs `MediaQuery`, which
  /// `initState` may not read, and `unselectProduct` and a pop emit
  /// synchronously, which `didUpdateWidget` — during build — may not do.
  void _sync(String? id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The URL moved on again before the frame; the next sync owns it.
      if (!mounted || widget.initialProductId != id) return;
      if (getScreenSize(context: context).index <= ScreenSize.medium.index) {
        return;
      }

      if (_dialogFor != null) {
        if (_dialogFor == id) return;
        // Pop it; its close path in the listener re-syncs to the URL then.
        Navigator.of(context, rootNavigator: true)
            .popUntil((route) => route is! PopupRoute);
        return;
      }

      final products = context.read<ProductBloc>();
      if (id == null) {
        if (products.selectedProduct != null) products.unselectProduct();
        return;
      }

      _selectedFor = id;
      // Always select — even when the bloc still holds this product from an
      // earlier visit. A fresh mount paints from the *state*, and the last
      // state after a selection is `refresh` (reviews loaded), which the
      // panel does not paint; a revisit of `/?sec=offers&id=X` then showed
      // nothing until a third tap. Re-selecting re-emits `selected`.
      final index = _views.indexWhere((view) => view.productId == id);
      products.selectProduct(
        id,
        productView: index >= 0 ? _views[index] : null,
      );
    });
  }

  /// This page's URL with `id` set or dropped, keeping whatever else it
  /// carries (`maxLoanable` and `maxPeriod` from the apply-loan form).
  String _location(GoRouter router, {required String? id}) {
    final params = {
      ...Uri.parse(router.location).queryParameters,
      'sec': 'offers',
    };
    if (id == null) {
      params.remove('id');
    } else {
      params['id'] = id;
    }
    return Uri(path: Paths.index, queryParameters: params).toString();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = getScreenSize(context: context);
    final isCompactOrMedium =
        getScreenSize(context: context).index <= ScreenSize.medium.index;

    return BlocListener<ProductBloc, ProductState>(
      listener: (context, state) async {
        if (state.status == ProductStatus.selected && state.product != null) {
          // The card and the panel colour follow the selection, however it
          // arrived: a deep link or a search result selected before the grid
          // rendered, so the tap handler's bookkeeping never ran for it.
          final index = _views.indexWhere(
            (view) => view.productId == state.product!.id,
          );
          if (index >= 0) {
            _selectedIndex = index;
            _selectedColor = AppColors.loanItemColorsList[
                index % AppColors.loanItemColorsList.length];
          }

          if (!AuthenticationService.instance.isAdmin) {
            if (isCompactOrMedium) {
              GoRouter.of(context)
                  .goSafe('${Paths.index}?sec=offers&id=${state.product!.id}');
            }
            return;
          }

          if (!isCompactOrMedium) {
            final productId = state.product!.id;
            _dialogFor = productId;
            await showDialog(
              context: context,
              builder: (context) {
                return AlertDialog(
                  backgroundColor: AppColors.green1,
                  content: AddProductScreen(
                    productId: productId,
                  ),
                );
              },
            );
            _dialogFor = null;
            _selectedIndex = -1;
            if (!context.mounted) return;
            // The URL moved to another offer while the dialog was up (a
            // programmatic `go`; `_sync` popped this one): select that
            // instead. It replaces this selection with no `unselected` in
            // between — one would strip the newer id from the URL.
            final next = widget.initialProductId;
            if (next != null && next != productId) {
              _sync(next);
              return;
            }
            context.read<ProductBloc>().unselectProduct();

            return;
          }

          GoRouter.of(context).goSafe(
            Paths.offersAction.replaceAll(':action', Paths.actionCreate),
            extra: {'product_id': state.product?.id},
          );
        } else if (state.status == ProductStatus.unselected) {
          _selectedIndex = -1;
          // Closed from inside — the panel's X, the dialog's X: the URL says
          // an offer is open, so it should stop saying so. Unless it already
          // moved on (browser Back closed this one), and that URL is the
          // newer truth. Wide only: on compact/medium the open offer is its
          // own route, and this URL never carries the id.
          final router = GoRouter.of(context);
          if (!isCompactOrMedium &&
              widget.initialProductId != null &&
              widget.initialProductId == _selectedFor) {
            _selectedFor = null;
            router.go(_location(router, id: null));
          }
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
                  _views = data;

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

                          if (isCompactOrMedium) {
                            // The selection drives the navigation here: the
                            // listener above sends it to the full-screen
                            // route, whose URL is the deep link.
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
                            return;
                          }
                          // Wide: the URL owns the selection (`_sync`), so a
                          // tap is a URL change — the address bar is then a
                          // deep link to this offer, as it is to a borrower.
                          final router = GoRouter.of(context);
                          if (_selectedIndex == index) {
                            _selectedIndex = -1;
                            router.go(_location(router, id: null));
                          } else {
                            _selectedIndex = index;
                            _selectedColor = colorList[colorIndex];
                            router.go(
                              _location(router, id: productView.productId),
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
