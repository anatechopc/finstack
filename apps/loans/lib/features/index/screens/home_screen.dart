import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/authentication/bloc/authentication_bloc.dart';
import 'package:loooans/features/index/screens/index_screen.dart';
import 'package:loooans/features/index/widgets/menu_drawer_widget.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/widgets/app_widgets.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.child, super.key,
    this.isClassicUI = false,
  });

  final Widget child;
  final bool isClassicUI;

  @override
  Widget build(BuildContext context) {
    final authInstance = AuthenticationService.instance;

    return BlocBuilder<AuthenticationBloc, AuthenticationState>(
      builder: (context, state) {
        if (state.status == AuthenticationStateStatus.logout) {
          return const IndexScreen();
        }

        return Row(
          children: [
            if (isClassicUI)
              const SizedBox(
                width: 300,
                height: double.infinity,
                child: const MenuDrawerWidget(),
              ),
            Expanded(
              child: Scaffold(
                appBar: AppWidgets.defaultAppBar(
                  context,
                  showLogin: authInstance.user.isPlaceholder,
                  showSignUp: authInstance.user.isPlaceholder,
                  showMyLoansButton:
                      AuthenticationService.instance.user.isCustomer(),
                  showAddBorrowerButton:
                      AuthenticationService.instance.allowAddClients,
                  showAddCapitalButton: AuthenticationService.instance.isAdmin,
                  showMessagesButton: true,
                  // Not on `/search`: that page carries its own field, and a
                  // second one in the shell app bar fed the same bloc with
                  // the overlay floating over the page's own results. On
                  // compact it was a search icon whose tap went to `/search`
                  // from `/search`.
                  showSearchField:
                      GoRouterState.of(context).uri.path != Paths.search,
                ),
                body: child,
              ),
            ),
          ],
        );
      },
    );
  }
}
