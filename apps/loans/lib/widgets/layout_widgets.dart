import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_svg/svg.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loooans/app/model/notification_model.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/capital/bloc/capital_bloc.dart';
import 'package:loooans/features/chat/bloc/conversations_bloc.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/notification_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/button_widgets.dart';
import 'package:loooans/widgets/dialog_widgets.dart';
import 'package:loooans/widgets/form_widgets.dart';
import 'package:loooans/widgets/notification_widgets.dart';
import 'package:loooans/widgets/profile_widgets.dart';
import 'package:user_repository/user_repository.dart';

class LayoutWidgets {
  static Widget rootConstraints({required Widget child}) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1600),
        child: child,
      ),
    );
  }

  static SliverAppBar defaultSliverAppBar(
    BuildContext context, {
    bool showLogin = true,
    bool showSignUp = true,
  }) {
    final isCompact = getScreenSize(context: context) == ScreenSize.compact;

    return SliverAppBar(
      toolbarHeight: 120,
      leadingWidth: 88,
      leading: Center(
        child: InkWell(
          onTap: () {
            GoRouter.of(context).goSafe(Paths.index);
          },
          child: SvgPicture.asset(
            'svg/logo.svg'.assetSafe,
            width: 56,
            height: 56,
          ),
        ),
      ),
      actions: [
        if (showLogin)
          ButtonWidgets.defaultFilledButton(
            child: const Text('Login'),
            onPressed: () {
              GoRouter.of(context).goSafe(Paths.login);
            },
          ),
        if (showSignUp) ...[
          const SizedBox(
            width: defaultPaddingSize,
          ),
          ButtonWidgets.defaultFilledButton(
            child: const Text('Sign up'),
            onPressed: () {
              GoRouter.of(context).goSafe(Paths.register);
            },
          ),
        ],
        SizedBox(
          width: isCompact ? defaultPaddingSize : 32,
        ),
      ],
    );
  }

  static AppBar defaultAppBar(
    BuildContext context, {
    bool showLogin = true,
    bool showSignUp = true,
    bool showMyLoansButton = false,
    bool showAddCapitalButton = false,
    bool showAdvertiseButton = false,
    bool showAddBorrowerButton = false,
    bool showMessagesButton = false,
  }) {
    final isCompact = getScreenSize(context: context) == ScreenSize.compact;

    return AppBar(
      toolbarHeight: 120,
      leadingWidth: 88,
      scrolledUnderElevation: 0,
      leading: Center(
        child: InkWell(
          onTap: () {
            GoRouter.of(context).goSafe(Paths.index);
          },
          child: SvgPicture.asset(
            'svg/logo.svg'.assetSafe,
            width: 56,
            height: 56,
          ),
        ),
      ),
      actions: [
        if (showLogin)
          ButtonWidgets.defaultFilledButton(
            child: const Text('Login'),
            onPressed: () {
              GoRouter.of(context).goSafe(Paths.login);
            },
          ),
        if (showSignUp) ...[
          const SizedBox(
            width: defaultPaddingSize,
          ),
          ButtonWidgets.defaultFilledButton(
            child: const Text('Sign up'),
            onPressed: () {
              GoRouter.of(context).goSafe(Paths.register);
            },
          ),
        ],
        if (!showSignUp && !showLogin) ...[
          if (showMyLoansButton)
            ButtonWidgets.defaultFilledButton(
              child: const Text('My Loans'),
              backgroundColor: AppColors.white,
              foregroundColor: AppColors.black,
              onPressed: () {
                GoRouter.of(context).goSafe('${Paths.index}?sec=loans');
              },
            ),
          if (showMyLoansButton && showAddCapitalButton)
            const SizedBox(
              width: 16,
            ),
          if (showAddCapitalButton)
            ButtonWidgets.defaultFilledButton(
              child: const Text('Add capital'),
              backgroundColor: AppColors.white,
              foregroundColor: AppColors.black,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) {
                    final formKey = GlobalKey<FormBuilderState>(
                        debugLabel: 'add_capital_dialog',);
                    return AlertDialog(
                      content: FormBuilder(
                        key: formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Add capital'),
                            const Gap(16),
                            FormWidgets.defaultFormBuilderTextField(
                              name: 'amount',
                              label: 'Amount',
                              inputFormatters: [
                                FormWidgets.defaultCurrencyInputFormatter(),
                              ],
                              valueTransformer: (value) {
                                if (value == null) {
                                  return null;
                                }

                                try {
                                  return double.parse(value);
                                } catch (err) {
                                  debugPrint('ERROR: $err');
                                  return null;
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        SizedBox(
                          width: double.infinity,
                          child: ButtonWidgets.defaultFilledButton(
                            child: const Text('Add'),
                            onPressed: () {
                              if (formKey.currentState?.saveAndValidate() ??
                                  false) {
                                context.read<CapitalBloc>().addCapital(
                                    amount: formKey.currentState!
                                        .value['amount'] as double,);
                              }
                            },
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          if (showAddCapitalButton && showAdvertiseButton)
            const SizedBox(
              width: 16,
            ),
          if (showAdvertiseButton)
            ButtonWidgets.defaultFilledButton(
              child: const Text('Advertise your product'),
              backgroundColor: AppColors.white,
              foregroundColor: AppColors.black,
              onPressed: () {
                debugPrint('advertise product');
              },
            ),
          if (AuthenticationService.instance.allowAddClients &&
              showAddBorrowerButton &&
              (AuthenticationService.instance.user.isAdmin() ||
                  AuthenticationService.instance.user.isAppAdmin()) &&
              (showAdvertiseButton || showAddCapitalButton))
            const SizedBox(
              width: 16,
            ),
          if (AuthenticationService.instance.allowAddClients &&
              showAddBorrowerButton &&
              (AuthenticationService.instance.user.isAdmin() ||
                  AuthenticationService.instance.user.isAppAdmin()))
            ButtonWidgets.defaultFilledButton(
              child: const Text('Add borrower'),
              backgroundColor: AppColors.white,
              foregroundColor: AppColors.black,
              onPressed: () {
                DialogWidgets.showAddUserWidget(
                  context,
                  scrollable: true,
                  withExtendedUserDetailInputs: true,
                );
              },
            ),
          const SizedBox(
            width: 48,
          ),
          // Payment Center entry for lenders. The classic UI surfaces this via
          // the menu drawer (Constants.allMenu); the non-classic UI has no
          // drawer, so expose it here next to the header icons. Gated to the
          // same roles as the allMenu Payment Center entry (admin / teller).
          if (AuthenticationService.instance.user.userRole == UserRole.admin ||
              AuthenticationService.instance.user.userRole ==
                  UserRole.teller) ...[
            IconButton(
              tooltip: 'Payment Center',
              onPressed: () {
                GoRouter.of(context).go(Paths.paymentCenter);
              },
              style: IconButton.styleFrom(
                backgroundColor: AppColors.white,
                foregroundColor: AppColors.black,
              ),
              icon: const Icon(
                Icons.payments_rounded,
              ),
            ),
            const SizedBox(
              width: 8,
            ),
          ],
          IconButton(
            onPressed: () {
              debugPrint('route location: ${GoRouter.of(context).location}');
            },
            style: IconButton.styleFrom(
              backgroundColor: AppColors.white,
              foregroundColor: AppColors.black,
            ),
            icon: const Icon(
              Icons.search_rounded,
            ),
          ),
          const SizedBox(
            width: 8,
          ),
          if (showMessagesButton) ...[
            BlocBuilder<ConversationsBloc, ConversationsState>(
              builder: (context, state) {
                final n = state.totalUnread;
                final button = IconButton(
                  tooltip: 'Messages',
                  onPressed: () => GoRouter.of(context).go(Paths.chat),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.white,
                    foregroundColor: AppColors.black,
                  ),
                  icon: const Icon(Icons.chat_bubble_outline),
                );
                if (n == 0) return button;
                return Badge(label: Text('$n'), child: button);
              },
            ),
            const SizedBox(
              width: 8,
            ),
          ],
          StreamBuilder(
            stream: NotificationService.instance.notificationStream,
            builder: (context, snapshot) {
              final notifications = <NotificationModel>[];

              if (snapshot.data != null && snapshot.data!.isNotEmpty) {
                notifications.addAll(snapshot.data!);
              }

              return MenuAnchor(
                alignmentOffset: const Offset(0, 16),
                style: MenuStyle(
                  backgroundColor:
                      const WidgetStatePropertyAll(AppColors.lightBlack),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                menuChildren: notifications.map((notification) {
                  return MenuItemButton(
                    child: NotificationWidgets.notificationItem(
                      context,
                      isFirst: true,
                      model: notification,
                    ),
                    onPressed: () => NotificationService.instance
                        .onNotificationPressed(notification),
                  );
                }).toList(),
                builder: (context, controller, child) {
                  return IconButton(
                    onPressed: () {
                      if (notifications.isNotEmpty) {
                        if (controller.isOpen) {
                          controller.close();
                        } else {
                          controller.open();
                        }
                      }
                    },
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.white,
                      foregroundColor: AppColors.black,
                    ),
                    icon: const Icon(
                      Icons.notifications_rounded,
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(
            width: 8,
          ),
          BlocBuilder<UserBloc, UserState>(
            builder: (context, state) {
              return ProfileWidgets.profileIcon(
                context,
                user: AuthenticationService.instance.user,
                triggerIconClick: true,
              );
            },
          ),
        ],
        SizedBox(
          width: isCompact ? defaultPaddingSize : 32,
        ),
      ],
    );
  }

  static Widget separatedItem({
    String? name,
    String? description,
    Widget? child,
    int? index,
    bool showIndexPlaceholder = false,
    bool isHeader = false,
  }) {
    if (description == null && child == null) {
      throw Exception('Either description or child must be provided');
    }

    if (name == null && child == null) {
      throw Exception('Name or child must be provided');
    }

    if (name == null && description == null && child != null) {
      return child;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showIndexPlaceholder) ...[
              if (index != null)
                Text(
                  '$index',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                const Gap(4),
              const Gap(8),
            ],
            if (name != null)
              Text(
                name,
                style: isHeader
                    ? const TextStyle(
                        fontWeight: FontWeight.w600,
                      )
                    : null,
              ),
          ],
        ),
        if (name != null) const Gap(16),
        if (description != null)
          Text(
            description,
            style: isHeader
                ? const TextStyle(
                    fontWeight: FontWeight.w600,
                  )
                : null,
            textAlign: TextAlign.end,
          ),
        if (child != null)
          if (child is Row) child,
      ],
    );
  }

  static Widget legendItem({
    required String title,
    Widget? icon,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon ??
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.black,
              ),
            ),
        const Gap(8),
        Text(
          title,
        ),
      ],
    );
  }

  static Widget iconTextPairWidget({
    required IconData icon,
    required String text,
    double? iconSize,
    double? fontSize,
    FontWeight fontWeight = FontWeight.w500,
}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: iconSize),
        const Gap(8),
        Text(
          text,
          style: GoogleFonts.urbanist(
            fontWeight: fontWeight,
            fontSize: fontSize,
          ),
        ),
      ],
    );
  }
}
