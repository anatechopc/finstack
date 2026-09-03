import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loooans/app/di/bloc_providers.dart';
import 'package:loooans/app/di/repository_providers.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/app/routing/router.dart';
import 'package:loooans/app/theme.dart';
import 'package:loooans/app/view/alpha_banner.dart';
import 'package:loooans/features/authentication/bloc/authentication_bloc.dart';
import 'package:loooans/features/search/bloc/search_bloc.dart';
import 'package:loooans/features/search/widget/search_shortcut_wrapper.dart';
import 'package:loooans/l10n/arb/app_localizations.dart';

class App extends StatelessWidget {
  const App({super.key});

  static final _routes = buildAppRoutes();

  @override
  Widget build(BuildContext context) {
    return AppRepositoryProviders(
      child: AppBlocProviders(
        child: ClearSearchOnLogout(
          child: MaterialApp.router(
            builder: (context, child) {
              final data = MediaQuery.of(context);
              return MediaQuery(
                data: data.copyWith(
                  textScaler: const TextScaler.linear(1.2),
                ),
                // Above the `Router`, which is what makes `Ctrl K` work on the
                // screens outside the `ShellRoute` too. `_routes.go` rather
                // than `GoRouter.of(context)`: this builder's context sits
                // above the router, so the inherited widget is not there yet
                // — and the root navigator is reached by key for the same
                // reason.
                child: SearchShortcutWrapper(
                  navigatorKey: _routes.routerDelegate.navigatorKey,
                  onActivate: () => _routes.go(Paths.search),
                  child: Column(
                    children: [
                      Expanded(
                        child: child!,
                      ),
                      const AlphaBanner(),
                    ],
                  ),
                ),
              );
            },
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: _routes,
          ),
        ),
      ),
    );
  }
}

/// Resets the app-lifetime `SearchBloc` when the session ends.
///
/// The bloc is provided above the login route and outlives the account, so
/// without this the next account on the same device found the previous one's
/// client rows on the state — PII — the moment it focused the field. A widget
/// of its own, rather than a line in [App], so it can be pumped without the
/// Firebase-backed repositories.
class ClearSearchOnLogout extends StatelessWidget {
  const ClearSearchOnLogout({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthenticationBloc, AuthenticationState>(
      listenWhen: (_, current) =>
          current.status == AuthenticationStateStatus.logout,
      listener: (context, _) =>
          context.read<SearchBloc>().add(const SearchClearedEvent()),
      child: child,
    );
  }
}
