import 'dart:math';

import 'package:address_repository/address_repository.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/loans/model/principal_borrower.dart';
import 'package:loooans/features/search/search_scope.dart';
import 'package:loooans/features/search/search_scope_resolver.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
import 'package:loooans/features/users/widget/cash_pool_information_widget.dart';
import 'package:loooans/utils/constants.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans/widgets/file_viewer_widget.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';
import 'package:user_loan_view_repository/user_loan_view_repository.dart';
import 'package:user_repository/user_repository.dart';

class BorrowerDetailScreen extends StatefulWidget {
  const BorrowerDetailScreen({
    required this.userId, super.key,
  });

  final String userId;

  /// Who may open a borrower's profile. `SearchScopeResolver.scopesFor` is
  /// the one statement of which roles may read client PII; reusing it here
  /// means search, the `/borrowers/:id` route and `MainScreen`'s compact
  /// redirect can never disagree. A placeholder user is refused explicitly
  /// even though its role is `customer`: `isCustomer()` is false for it, so
  /// the `!isCustomer()` gates elsewhere let it through.
  static bool permits(User user) =>
      !user.isPlaceholder &&
      SearchScopeResolver.scopesFor(user.userRole)
          .contains(SearchScope.clients);

  @override
  State<StatefulWidget> createState() {
    return _BorrowerDetailScreenState();
  }
}

class _BorrowerDetailScreenState extends State<BorrowerDetailScreen> {
  /// The width the loans table was designed for: its columns are fractions
  /// of the viewport (`_buildColumnSpan`), so at phone width every cell is
  /// an ellipsis. On a phone it is scrolled sideways at this width.
  static const _designedWidth = 1000.0;

  @override
  void initState() {
    super.initState();

    context.read<UserBloc>().selectUser(widget.userId);
    context.read<LoansBloc>().getLoansByUser(
          userId: widget.userId,
          allStatus: true,
          userIsBorrower: true,
        );
    context.read<LoansBloc>().getPrincipalBorrowers(widget.userId);
  }

  /// Back arrow and Close, everywhere the screen appears. In the dialog the
  /// top route is the dialog itself, so `pop` closes it (`BorrowerScreen`
  /// listens for that and drops `&id=` from the URL). On a pushed full-screen
  /// page — mobile, where `goSafe` pushes — `pop` returns to the list. A
  /// full-screen page reached by `go` is the only page on the stack: popping
  /// it left a blank screen, and off mobile the arrow did nothing at all.
  /// `GoRouter.canPop` sees dialogs too; they sit on the same root navigator.
  void _exit(BuildContext context) {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(Paths.index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UserBloc, UserState>(
      buildWhen: (prev, next) {
        return next.status == UserStatus.selected;
      },
      builder: (context, state) {
        if (state.status != UserStatus.selected) {
          return Container();
        }

        final user = context.read<UserBloc>().user;

        return Scaffold(
          appBar: AppBar(
            // Arrow (24) plus avatar (40) do not fit the default 56.
            leadingWidth: 80,
            leading: InkWell(
              onTap: () => _exit(context),
              child: Padding(
                padding: const EdgeInsets.only(
                  left: 8,
                  top: 16,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.arrow_back_ios_new_rounded),
                    AppWidgets.profileIcon(
                      context,
                      avatarOnly: true,
                      avatarDimension: 32,
                      user: user,
                    ),
                  ],
                ),
              ),
            ),
            title: Padding(
              padding: const EdgeInsets.only(
                top: 16,
              ),
              child: Text(
                user.completeNameEasternOrder,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            centerTitle: false,
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: _body(context),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    final isCompactOrMedium =
        getScreenSize(context: context).index <= ScreenSize.medium.index;
    return BlocBuilder<LoansBloc, LoansState>(
      builder: (context, state) {
        final userLoanViews =
            context.read<LoansBloc>().selectedBorrowerLoanViews;
        final principalBorrowers =
            context.read<LoansBloc>().selectedBorrowerPrincipalBorrowers;
        final user = context.read<UserBloc>().selectedUser;
        final address = context.read<UserBloc>().address;
        final uploadedFiles =
            context.read<LoansBloc>().selectedBorrowerLoanFiles;
        final hasRows =
            principalBorrowers.isNotEmpty || userLoanViews.isNotEmpty;

        if (isCompactOrMedium) {
          // The wide body, stacked: every section, one column, scrolling.
          return ListView(
            children: [
              if (user != null) ...[
                _basicInformation(user, address, stacked: true),
                const Gap(24),
              ],
              if (uploadedFiles.isNotEmpty) ...[
                _uploadedFilesButton(context, uploadedFiles),
                const Gap(24),
              ],
              // Stacks its own two columns at this width.
              CashPoolInformationWidget(userId: widget.userId),
              const Gap(24),
              if (hasRows) ...[
                _sideways(
                  height: _tableHeight(principalBorrowers, userLoanViews),
                  child: _buildTable(context, inert: true),
                ),
                const Gap(24),
              ],
              _closeButton(context),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 1200 * 0.4,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (user != null)
                          _basicInformation(user, address, stacked: false),
                        const Gap(24),
                        if (uploadedFiles.isNotEmpty)
                          _uploadedFilesButton(context, uploadedFiles),
                      ],
                    ),
                  ),
                  const Gap(24),
                  Expanded(
                    flex: 2,
                    child: CashPoolInformationWidget(
                      userId: widget.userId,
                    ),
                  ),
                ],
              ),
            ),
            const Gap(24),
            if (hasRows) ...[
              Expanded(
                child: _buildTable(context),
              ),
              const Gap(24),
            ] else
              const Spacer(),
            _closeButton(context),
          ],
        );
      },
    );
  }

  /// [stacked] puts each value under its label — a phone has no room for
  /// the label-left, value-right row, whose value text has no width to wrap
  /// in and overflows on a real address.
  Widget _basicInformation(
    User user,
    Address? address, {
    required bool stacked,
  }) {
    final entries = <(String, String)>[
      ('Name', user.completeNameEasternOrder),
      ('Address', address?.toString() ?? 'N/A'),
      ('Birthdate', user.birthDate.toDefaultDateFormat()),
      ('Mobile number', user.mobileNumber),
      ('Facebook profile', user.facebookProfileUrl ?? 'N/A'),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Basic Information',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        const Gap(16),
        for (final (i, (name, value)) in entries.indexed) ...[
          if (i > 0) Gap(i == 1 ? 16 : 4),
          if (stacked)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(value),
              ],
            )
          else
            AppWidgets.separatedItem(name: name, description: value),
        ],
      ],
    );
  }

  Widget _uploadedFilesButton(
    BuildContext context,
    List<RequirementSubmission> uploadedFiles,
  ) {
    void showFiles() {
      showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            content: SizedBox(
              width: 1000,
              height: 800,
              child: FileViewerWidget(
                items: uploadedFiles,
              ),
            ),
          );
        },
      );
    }

    return AppWidgets.defaultOutlinedButton(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'View uploaded files',
            maxLines: 2,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: showFiles,
            child: const Icon(Icons.visibility_rounded),
          ),
        ],
      ),
      onPressed: showFiles,
    );
  }

  Widget _closeButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: AppWidgets.defaultFilledButton(
        child: const Text('Close'),
        onPressed: () => _exit(context),
      ),
    );
  }

  /// The table on a phone: the designed width, scrolled sideways.
  Widget _sideways({required double height, required Widget child}) {
    return SizedBox(
      height: height,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _designedWidth,
          child: child,
        ),
      ),
    );
  }

  /// The table's own height, so it can sit inside a scrolling column:
  /// `_buildRowSpan` gives a header 80 and a row 48.
  double _tableHeight(
    List<PrincipalBorrower> principalBorrowers,
    List<UserLoanView> userLoanViews,
  ) {
    var height = 0.0;
    if (principalBorrowers.isNotEmpty) {
      height += 80 + principalBorrowers.length * 48;
    }
    if (userLoanViews.isNotEmpty) {
      height += 80 + userLoanViews.length * 48;
    }
    return height;
  }

  /// [inert]: the table neither scrolls nor claims drags, for when it is
  /// sized to its content inside another scrollable that should.
  TableView _buildTable(BuildContext context, {bool inert = false}) {
    final principalBorrowers =
        context.read<LoansBloc>().selectedBorrowerPrincipalBorrowers;
    final userLoanViews = context.read<LoansBloc>().selectedBorrowerLoanViews;
    // for the columnCount, we need to make sure that we handle the case where
    // one is greater than the other.
    final columnCount = max(
      Constants.borrowerPrincipalBorrowersHeader.length,
      Constants.borrowerLoansHeader.length,
    );

    var rowCount = 0;

    if (principalBorrowers.isNotEmpty) {
      rowCount += principalBorrowers.length + 1; // +1 for the header
    }

    if (userLoanViews.isNotEmpty) {
      rowCount += userLoanViews.length + 1; // +1 for the header
    }

    return TableView.builder(
      verticalDetails: ScrollableDetails.vertical(
        physics: inert ? const NeverScrollableScrollPhysics() : null,
      ),
      horizontalDetails: ScrollableDetails.horizontal(
        physics: inert ? const NeverScrollableScrollPhysics() : null,
      ),
      cellBuilder: _buildCell,
      columnCount: columnCount,
      columnBuilder: _buildColumnSpan,
      rowCount: rowCount,
      // +1 for header
      rowBuilder: (index) => _buildRowSpan(
        context,
        index,
      ),
    );
  }

  TableViewCell _buildCell(
    BuildContext context,
    TableVicinity vicinity,
  ) {
    Widget defaultCellDisplay =
        Text('Tile c: ${vicinity.column}, r: ${vicinity.row}');
    final principalBorrowers =
        context.read<LoansBloc>().selectedBorrowerPrincipalBorrowers;
    final userLoanViews = context.read<LoansBloc>().selectedBorrowerLoanViews;

    if (vicinity.row ==
            _getHeaderIndex(context, indexFor: 'principalBorrowers') &&
        principalBorrowers.isNotEmpty) {
      defaultCellDisplay = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Opacity(
            opacity: vicinity.column == 0 ? 1 : 0,
            child: const Text(
              'Principal borrowers',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Gap(8),
          Text(
            Constants.borrowerPrincipalBorrowersHeader[vicinity.column],
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    } else if (vicinity.row ==
            _getHeaderIndex(context, indexFor: 'userLoanViews') &&
        userLoanViews.isNotEmpty) {
      defaultCellDisplay = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: vicinity.column == 0 ? 1 : 0,
            child: const Text(
              'Loans',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Gap(8),
          Text(
            Constants.borrowerLoansHeader[vicinity.column],
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    } else {
      final data = _getData(context, vicinity.row);

      if (data is PrincipalBorrower) {
        if (vicinity.column == 0) {
          defaultCellDisplay = Text(data.date.toDefaultDateFormat());
        } else if (vicinity.column == 1) {
          defaultCellDisplay = Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              data.userName,
              overflow: TextOverflow.ellipsis,
            ),
          );
        } else if (vicinity.column == 2) {
          defaultCellDisplay = Text(data.loanType);
        } else if (vicinity.column == 3) {
          defaultCellDisplay = Text(data.loanAmount.toCurrency());
        } else if (vicinity.column == 4) {
          defaultCellDisplay = Text(data.status.label);
        }
      } else if (data is UserLoanView) {
        if (vicinity.column == 0) {
          defaultCellDisplay = Text(data.loanCreatedAt.toDefaultDateFormat());
        } else if (vicinity.column == 1) {
          defaultCellDisplay = Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              data.loanType,
              overflow: TextOverflow.ellipsis,
            ),
          );
        } else if (vicinity.column == 2) {
          defaultCellDisplay = Text(data.reason);
        } else if (vicinity.column == 3) {
          defaultCellDisplay = Text(data.amount.toCurrency());
        } else if (vicinity.column == 4) {
          defaultCellDisplay = Text(data.loanStatus.label);
        }
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
      border: TableSpanBorder(),
    );

    // update span extent here based on row index
    SpanExtent spanExtent = const FractionalTableSpanExtent(0.2);

    if (index == 1) {
      // name
      spanExtent = const FractionalTableSpanExtent(0.25);
    }

    return TableSpan(
      foregroundDecoration: decoration,
      extent: spanExtent,
    );
  }

  TableSpan _buildRowSpan(
    BuildContext context,
    int index,
  ) {
    const decoration = TableSpanDecoration();

    // these are headers
    if (index == _getHeaderIndex(context, indexFor: 'principalBorrowers') ||
        index == _getHeaderIndex(context, indexFor: 'userLoanViews')) {
      return const TableSpan(
        backgroundDecoration: decoration,
        extent: FixedTableSpanExtent(80),
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
          (TapGestureRecognizer t) => t.onTap = () {
            final data = _getData(context, index);

            if (data is PrincipalBorrower) {
              AppWidgets.showLoanClientDetailsDialog(
                context,
                userId: data.userId,
                loanId: data.loanId,
              );
            } else if (data is UserLoanView) {
              AppWidgets.showLoanClientDetailsDialog(
                context,
                userId: data.userId,
                loanId: data.loanId,
              );
            }
          },
        ),
      },
    );
  }

  int _getHeaderIndex(BuildContext context, {required String indexFor}) {
    final principalBorrowers =
        context.read<LoansBloc>().selectedBorrowerPrincipalBorrowers;

    if (indexFor == 'principalBorrowers' && principalBorrowers.isNotEmpty) {
      return 0;
    }

    if (indexFor == 'userLoanViews' && principalBorrowers.isNotEmpty) {
      return principalBorrowers.length + 1;
    }

    return 0;
  }

  dynamic _getData(BuildContext context, int index) {
    final principalBorrowers =
        context.read<LoansBloc>().selectedBorrowerPrincipalBorrowers;
    final userLoanViews = context.read<LoansBloc>().selectedBorrowerLoanViews;

    if (principalBorrowers.isNotEmpty &&
        (index < principalBorrowers.length + 1)) {
      // +1 for the header
      final borrower = principalBorrowers[index - 1];
      return borrower;
    }

    if (userLoanViews.isNotEmpty && principalBorrowers.isNotEmpty) {
      final loanView =
          userLoanViews[index - (principalBorrowers.length + 1) - 1];
      return loanView;
    } else {
      final loanView = userLoanViews[index - 1];
      return loanView;
    }
  }
}
