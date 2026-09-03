
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
import 'package:loooans/features/users/model/user_address.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/settings_service.dart';
import 'package:loooans/utils/constants.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

class BorrowerScreen extends StatefulWidget {
  const BorrowerScreen({
    super.key,
    this.scrollController,
    this.initialBorrowerId,
  });

  final ScrollController? scrollController;

  /// From `/?sec=borrowers&id=<userId>`. The URL owns the dialog: this
  /// screen opens that borrower's dialog when the id is there — on first
  /// frame, or when it arrives later — and closes it when the id leaves.
  /// That is what makes the dialog deep-linkable, what search navigates to,
  /// and what keeps browser Back honest. Wide screens only: on
  /// compact/medium, `MainScreen` has already redirected the same URL to the
  /// full-screen route before this widget mounts, and a dialog there would
  /// race that navigation.
  final String? initialBorrowerId;

  /// Every way of opening a borrower goes through the URL — a table row, a
  /// compact list item, or a search result — so all three present identically
  /// and every one of them is a link. Calling `showDialog` here directly would
  /// open the same dialog with the address bar still saying `/?sec=borrowers`.
  ///
  /// Wide classic UI: `/?sec=borrowers&id=`, the dialog over this section.
  /// Everywhere else the profile is its own screen, `/borrowers/:id`, and
  /// the navigation goes there DIRECTLY: the non-classic UI has no
  /// Borrowers section for a dialog to sit over (its clients panel opens the
  /// loan-scoped LoanClientDetail), and a compact screen has no room for
  /// one. Routing a compact tap through `/?sec=borrowers&id=` and
  /// `MainScreen`'s build-time redirect was a back trap: Back landed on a
  /// URL whose build pushed the profile again. `goSafe` pushes on
  /// Android/iOS so the profile's back arrow has a page to return to; `go`
  /// left it the only page, and popping threw.
  static void openBorrower(BuildContext context, String userId) {
    // `maybeOf`: widget tests that render a tile or a row without a router
    // are asserting other things (dismissal, layout) and must not throw here.
    final router = GoRouter.maybeOf(context);
    if (router == null) return;

    final fullScreen = !SettingsService.instance.appUseClassicUI ||
        getScreenSize(context: context).index <= ScreenSize.medium.index;
    if (fullScreen) {
      router.goSafe(Paths.borrowersAction.replaceAll(':action', userId));
      return;
    }
    router.go('${Paths.index}?sec=borrowers&id=$userId');
  }

  @override
  State<BorrowerScreen> createState() => _BorrowerScreenState();
}

class _BorrowerScreenState extends State<BorrowerScreen> {
  /// The borrower whose dialog this screen opened and has not yet seen close.
  String? _openBorrowerId;

  @override
  void initState() {
    super.initState();
    context.read<UserBloc>().loadNext(
          companyId: AuthenticationService.instance.company.id,
          customerOnly: true,
        );
    _syncDialog(widget.initialBorrowerId);
  }

  /// `MainScreen` is keyed by section, so a change to `&id=` alone arrives
  /// here as a prop change, not a remount: a row tap or a search result
  /// (null → id) opens the dialog, and browser Back (id → null) closes the
  /// one it reopened. The list is NOT reloaded — that is what the remount
  /// used to do, twice per dialog.
  @override
  void didUpdateWidget(BorrowerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialBorrowerId != oldWidget.initialBorrowerId) {
      _syncDialog(widget.initialBorrowerId);
    }
  }

  /// Makes the open dialog match [id]: closes one for another borrower,
  /// opens one for [id]. Post-frame, because neither `showDialog` nor a pop
  /// may run during build; the pattern here is
  /// `_PaymentOtpDialogState.initState`.
  void _syncDialog(String? id) {
    if (id == null && _openBorrowerId == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_openBorrowerId != null && _openBorrowerId != id) {
        // Everything above this section is a dialog — this one, or a loan
        // detail opened from it — so pop until a page is on top again.
        Navigator.of(context, rootNavigator: true)
            .popUntil((route) => route is! PopupRoute);
      }
      // The URL moved on again before the frame; the next sync owns it.
      if (id == null || widget.initialBorrowerId != id) return;
      // Wide screens only: on compact/medium, `MainScreen` has already
      // redirected the same URL to the full-screen route, and a dialog here
      // would race that navigation.
      if (getScreenSize(context: context).index <= ScreenSize.medium.index) {
        return;
      }
      _showDialog(id);
    });
  }

  void _showDialog(String userId) {
    _openBorrowerId = userId;
    // The router is captured before the gap: after it, only `this.context`
    // is known-valid, and only once `mounted` says so.
    final router = GoRouter.of(context);
    AppWidgets.showBorrowerDetailsDialog(
      context,
      userId,
      onClosed: () {
        if (_openBorrowerId == userId) _openBorrowerId = null;
        if (!mounted) return;
        // Once closed, drop the id: the URL says a dialog is open, so it
        // should stop saying so. It also makes tapping the same borrower
        // again a URL change, which is what reopens the dialog. Unless the
        // URL has already moved on — browser Back closed this dialog, and
        // that URL is the newer truth.
        if (widget.initialBorrowerId == userId) {
          router.go('${Paths.index}?sec=borrowers');
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompactOrMedium =
        getScreenSize(context: context).index <= ScreenSize.medium.index;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header(context, maxAxisSize: true),
        const Gap(16),
        Expanded(
          child: StreamBuilder(
            stream: context.read<UserBloc>().userAddresses,
            builder: (context, snapshot) {
              if (snapshot.data == null) {
                return Container();
              }

              final data = snapshot.data!;
              final showData = data;
              // +1 for header
              final rowCount = data.length + 1;

              if (!isCompactOrMedium) {
                return TableView.builder(
                  cellBuilder: (context, vicinity) {
                    return _buildCell(context, vicinity, showData);
                  },
                  columnCount: Constants.borrowerHeaders.length,
                  columnBuilder: _buildColumnSpan,
                  rowCount: rowCount,
                  rowBuilder: (index) => _buildRowSpan(
                    context,
                    index,
                    showData,
                  ),
                );
              }

              return ListView.separated(
                itemBuilder: (context, index) {
                  final item = data[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () =>
                        BorrowerScreen.openBorrower(context, item.user.id),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.user.completeNameEasternOrder,
                              style: const TextStyle(
                                color: AppColors.white,
                                // fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              item.address.completeAddress1Line,
                              style: TextStyle(
                                color: AppColors.white.withValues(alpha: 0.6),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              item.user.mobileNumber,
                              style: TextStyle(
                                color: AppColors.white.withValues(alpha: 0.6),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              item.user.emailAddress,
                            ),
                            Text(
                              item.user.createdAt
                                  .toDefaultDateFormatWithDayExtended(),
                              style: TextStyle(
                                color: AppColors.white.withValues(alpha: 0.6),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
                separatorBuilder: (context, index) {
                  return const Gap(16);
                },
                // if not load add, 5 data and 1 button
                itemCount: data.length,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget header(
    BuildContext context, {
    bool maxAxisSize = false,
  }) {
    return Row(
      mainAxisSize: !maxAxisSize ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: !maxAxisSize
          ? MainAxisAlignment.start
          : MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Borrowers',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: AppColors.white,
          ),
        ),
        const Gap(8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (AuthenticationService.instance.allowAddClients &&
                (AuthenticationService.instance.user.isAdmin() ||
                    AuthenticationService.instance.user.isAppAdmin())) ...[
              AppWidgets.defaultOutlinedButton(
                foregroundColor: AppColors.white,
                child: const Text('Add Borrower'),
                onPressed: () {
                  AppWidgets.showAddUserWidget(
                    context,
                    withExtendedUserDetailInputs: true,
                    scrollable: true,
                  );
                },
              ),
              const Gap(16),
            ],
            if (!SettingsService.instance.appUseClassicUI)
              InkWell(
                onTap: () {
                  GoRouter.of(context).goSafe(Paths.index);
                },
                child: SvgPicture.asset(
                  'svg/icon_arrow_down.svg'.assetSafe,
                  colorFilter: const ColorFilter.mode(
                    AppColors.white,
                    BlendMode.srcIn,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  TableViewCell _buildCell(
    BuildContext context,
    TableVicinity vicinity,
    List<UserAddress> users,
  ) {
    Widget defaultCellDisplay = Container();

    if (vicinity.row == 0) {
      final cellHeaders = Constants.borrowerHeaders;
      defaultCellDisplay = Text(
        cellHeaders[vicinity.column],
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.white,
        ),
      );
    } else {
      final item = users[vicinity.row - 1];
      if (vicinity.column == 0) {
        defaultCellDisplay = Text(
          item.user.completeNameEasternOrder,
          style: const TextStyle(
            color: AppColors.white,
          ),
        );
      } else if (vicinity.column == 1) {
        defaultCellDisplay = Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Text(
            item.address.completeAddress1Line,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.white,
            ),
          ),
        );
      } else if (vicinity.column == 2) {
        defaultCellDisplay = Text(
          item.user.mobileNumber,
          style: const TextStyle(
            color: AppColors.white,
          ),
        );
      } else if (vicinity.column == 3) {
        defaultCellDisplay = Text(
          item.user.emailAddress,
          style: const TextStyle(
            color: AppColors.white,
          ),
        );
      } else if (vicinity.column == 4) {
        defaultCellDisplay = Text(
          item.user.createdAt.toDefaultDateFormatWithDayExtended(),
          style: const TextStyle(
            color: AppColors.white,
          ),
        );
      }
    }

    return TableViewCell(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: defaultCellDisplay,
      ),
    );
  }

  TableSpan _buildColumnSpan(int index) {
    const decoration = TableSpanDecoration(
      border: TableSpanBorder(
          // leading: index == 0 ? BorderSide() : BorderSide.none,
          // trailing: index == 3 ? BorderSide() : BorderSide.none,
          ),
    );

    if (index == 0) {
      return const TableSpan(
        foregroundDecoration: decoration,
        extent: FractionalSpanExtent(0.22),
      );
    } else if (index == 1) {
      return const TableSpan(
        foregroundDecoration: decoration,
        extent: FractionalSpanExtent(0.25),
      );
    } else if (index == 2) {
      return const TableSpan(
        foregroundDecoration: decoration,
        extent: FractionalSpanExtent(0.16),
      );
    }

    return const TableSpan(
      foregroundDecoration: decoration,
      extent: FractionalSpanExtent(0.18),
    );
  }

  TableSpan _buildRowSpan(
    BuildContext context,
    int index,
    List<UserAddress> items,
  ) {
    const decoration = TableSpanDecoration();

    if (index == 0) {
      return const TableSpan(
        backgroundDecoration: decoration,
        extent: FixedTableSpanExtent(48),
      );
    }

    return TableSpan(
      backgroundDecoration: decoration,
      extent: const FixedTableSpanExtent(48),
      cursor: SystemMouseCursors.click,
      recognizerFactories: <Type, GestureRecognizerFactory>{
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          TapGestureRecognizer.new,
          (TapGestureRecognizer t) => t.onTap = () =>
              BorrowerScreen.openBorrower(context, items[index - 1].user.id),
        ),
      },
      // onEnter: (_) {
      //   decoration = TableSpanDecoration(
      //     color: AppColors.white,
      //   );
      // }
    );
  }
}
