import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/authentication/bloc/authentication_bloc.dart';
import 'package:loooans/features/capital/bloc/capital_bloc.dart';
import 'package:loooans/features/main/screen/main_screen_top_body.dart';
import 'package:loooans/features/products/screen/loan_offers_widget.dart';
import 'package:loooans/features/reports/screen/full_reports_screen.dart';
import 'package:loooans/features/reports/widgets/credit_karma_widget.dart';
import 'package:loooans/features/reports/widgets/karma_history_widget.dart';
import 'package:loooans/features/users/screens/borrowers_screen.dart';
import 'package:loooans/features/users/screens/loan_clients_screen.dart';
import 'package:loooans/features/users/screens/users_screen.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/settings_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class MainScreen extends StatefulWidget {

  const MainScreen({
    super.key,
    this.section,
    this.id,
  });
  final String? section;
  final String? id;

  @override
  State<MainScreen> createState() {
    return _MainScreenState();
  }
}

class _MainScreenState extends State<MainScreen> {
  final _loanOfferKey = GlobalKey(debugLabel: 'loan_offer_screen');
  final _loanClientsKey = GlobalKey(debugLabel: 'loan_clients_screen');
  double _sheetPosition = 0.5;

  final double _dragSensitivity = 1000;

  final sheetController = DraggableScrollableController();

  double _getCorrectBottomScreenHeight(double screenHeight) {
    if (SettingsService.instance.appUseClassicUI) {
      return 1;
    }

    if (screenHeight < 1120) {
      return 0.6 - (screenHeight * 0.0001);
    }

    if (screenHeight < 1200) {
      return 0.6 - (screenHeight * 0.00005);
    }

    return 0.6 - (screenHeight * 0.00002);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    int? positionBottom;

    if (getScreenSize(context: context).index <= ScreenSize.medium.index) {
      positionBottom = (screenHeight * 0.15).toInt();

      if (widget.id != null) {
        if (widget.section == 'offers') {
          GoRouter.of(context)
              .goSafe(Paths.offersAction.replaceAll(':action', widget.id!));
        } else if (widget.section == 'loans') {
          GoRouter.of(context)
              .goSafe(Paths.loansAction.replaceAll(':action', widget.id!));
        }
      }
    }

    if (widget.section == 'loans') {
      positionBottom = (MediaQuery.sizeOf(context).height * 0.2).toInt();
    }

    if (!SettingsService.instance.appUseClassicUI) {
      Timer(const Duration(milliseconds: 500), () {
        if (sheetController.isAttached) {
          if (widget.section != null && widget.section != 'loans') {
            sheetController.animateTo(
              1,
              duration: const Duration(
                seconds: 1,
              ),
              curve: Curves.fastEaseInToSlowEaseOut,
            );
          } else if (widget.section != null && widget.section == 'loans') {
            // 0.25 is minChildSize of DraggableScrollableSheet
            sheetController.animateTo(
              0.20,
              duration: const Duration(
                seconds: 1,
              ),
              curve: Curves.fastEaseInToSlowEaseOut,
            );
          } else {
            sheetController.animateTo(
              screenHeight >= 1300
                  ? 0.6
                  : _getCorrectBottomScreenHeight(screenHeight),
              duration: const Duration(
                seconds: 1,
              ),
              curve: Curves.fastEaseInToSlowEaseOut,
            );
          }

          if (widget.section == 'karma' &&
              getScreenSize(context: context).index <=
                  ScreenSize.medium.index) {
            sheetController.animateTo(
              0.20,
              duration: const Duration(
                seconds: 1,
              ),
              curve: Curves.fastEaseInToSlowEaseOut,
            );
          }
        }
      });
    }

    return MultiBlocListener(
      listeners: [
        BlocListener<AuthenticationBloc, AuthenticationState>(
          listener: (context, state) {
            if (state.status == AuthenticationStateStatus.loading) {
              if (state.isLoading) {
                AppWidgets.showDefaultLoadingDialog(context);
              } else {
                Navigator.of(context, rootNavigator: true).pop();
              }
            } else if (state.status == AuthenticationStateStatus.logout) {
              GoRouter.of(context).go(Paths.index);
            }
          },
        ),
        BlocListener<CapitalBloc, CapitalState>(
          listener: (context, state) {
            if (state.status == CapitalStateStatus.loading) {
              if (state.isLoading) {
                AppWidgets.showDefaultLoadingDialog(context);
              } else {
                Navigator.of(context, rootNavigator: true).pop();
              }
            } else if (state.status == CapitalStateStatus.error) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(state.message ?? 'Cannot add capital'),),);
            } else if (state.status == CapitalStateStatus.success) {
              Navigator.of(context, rootNavigator: true).pop();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content:
                      Text(state.message ?? 'Added capital successfully'),),);
            }
          },
        ),
      ],
      child: Stack(
        children: [
          if (!SettingsService.instance.appUseClassicUI)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: positionBottom?.toDouble(),
              child: MainScreenTopBody(
                section: widget.section,
                id: widget.id,
              ),
            ),
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            right: 0,
            child: DraggableScrollableSheet(
              controller: sheetController,
              initialChildSize: _getCorrectBottomScreenHeight(screenHeight),
              minChildSize: 0.20,
              builder: (context, scrollController) {
                return _bottomBody(
                  context: context,
                  screenHeight: screenHeight,
                  onVerticalDragUpdate: (details) {
                    if (AuthenticationService.instance.user.isPlaceholder) {
                      return;
                    }

                    _sheetPosition -= details.delta.dy / _dragSensitivity;
                    if (widget.section == 'loans' ||
                        widget.section == 'karma') {
                      if (_sheetPosition < 0.2) {
                        _sheetPosition = 0.2;
                      }
                    } else {
                      if (_sheetPosition <
                          _getCorrectBottomScreenHeight(screenHeight)) {
                        _sheetPosition =
                            _getCorrectBottomScreenHeight(screenHeight);
                      }
                    }

                    if (_sheetPosition > 1.0) {
                      _sheetPosition = 1.0;
                    }

                    if (sheetController.isAttached) {
                      sheetController.jumpTo(_sheetPosition);
                    }
                  },
                  scrollController: scrollController,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBody({
    required BuildContext context,
    required double screenHeight,
    ValueChanged<DragUpdateDetails>? onVerticalDragUpdate,
    ScrollController? scrollController,
  }) {
    var renderHistory = true;
    if (getScreenSize(context: context).index <= ScreenSize.medium.index) {
      renderHistory = false;
    }

    return GestureDetector(
      onVerticalDragUpdate: onVerticalDragUpdate,
      onTap: () {
        if (AuthenticationService.instance.user.isPlaceholder) {
          return;
        }

        if (!SettingsService.instance.appUseClassicUI) {
          if (widget.id != null) {
            return;
          }

          if (widget.section != null) {
            GoRouter.of(context).go('/');
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 24,
        ),
        decoration: BoxDecoration(
          color: AppColors.black,
          borderRadius: const BorderRadius.only(
            topLeft: defaultRadius,
            topRight: defaultRadius,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.white.withValues(alpha: 0.5),
              offset: const Offset(0, 1), //(x,y)
              blurRadius: 16,
            ),
          ],
        ),
        child: AppWidgets.rootConstraints(
          child: LayoutBuilder(builder: (context, constraints) {
            return CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverList.list(
                  children: [
                    SvgPicture.asset('svg/handle.svg'.assetSafe),
                    const Gap(32),
                    SizedBox(
                      height: constraints.maxHeight - 64,
                      // padding: const EdgeInsets.all(32),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (AuthenticationService.instance.user
                              .isCustomer()) ...[
                            if (widget.section == null ||
                                widget.section == 'karma')
                              if (renderHistory) ...[
                                const Expanded(
                                  child: KarmaHistoryWidget(),
                                ),
                                const Gap(48),
                              ],
                            if (widget.section == 'offers' ||
                                widget.section == 'loans' ||
                                widget.section == null ||
                                !renderHistory)
                              Expanded(
                                child: LoanOffersWidget(
                                  key: _loanOfferKey,
                                  parentMaxWidthConstraint:
                                      constraints.maxWidth / 2 - 24,
                                  expanded: widget.section == 'offers',
                                  scrollController: isMobilePlatform
                                      ? scrollController
                                      : null,
                                ),
                              ),
                            if (widget.section == 'karma' && renderHistory)
                              const Expanded(
                                child: CreditKarmaWidget(),
                              ),
                          ] else ...[
                            if (widget.section == 'reports')
                              Expanded(
                                child: FullReportsScreen(
                                  scrollController: isMobilePlatform
                                      ? scrollController
                                      : null,
                                ),
                              )
                            else ...[
                              if ((widget.section == null ||
                                      widget.section == 'clients') &&
                                  !AuthenticationService.instance.user
                                      .isCustomer())
                                Expanded(
                                  child: LoanClientsScreen(
                                    key: _loanClientsKey,
                                    scrollController: isMobilePlatform
                                        ? scrollController
                                        : null,
                                    loadAllColumns: widget.section == 'clients',
                                  ),
                                ),
                              if ((widget.section == null ||
                                      widget.section == 'borrowers') &&
                                  !AuthenticationService.instance.user
                                      .isCustomer() &&
                                  SettingsService.instance.appUseClassicUI)
                                Expanded(
                                  child: BorrowerScreen(
                                          scrollController: isMobilePlatform
                                              ? scrollController
                                              : null,
                                        ),
                                ),
                                if ((widget.section == null ||
                                      widget.section == 'users') &&
                                  !AuthenticationService.instance.user
                                      .isCustomer() &&
                                  SettingsService.instance.appUseClassicUI)
                                Expanded(
                                  child: UsersScreen(
                                          scrollController: isMobilePlatform
                                              ? scrollController
                                              : null,
                                        ),
                                ),
                              if (widget.section == null) const Gap(48),
                              if (widget.section == null ||
                                  widget.section == 'offers')
                                Expanded(
                                  child: LoanOffersWidget(
                                    key: _loanOfferKey,
                                    scrollController: isMobilePlatform
                                        ? scrollController
                                        : null,
                                    parentMaxWidthConstraint:
                                        constraints.maxWidth / 2 - 24,
                                    expanded: widget.section == 'offers',
                                  ),
                                ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            );
          },),
        ),
      ),
    );
  }
}
