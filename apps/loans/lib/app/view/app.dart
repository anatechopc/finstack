import 'package:flutter/material.dart';
import 'package:loooans/app/di/bloc_providers.dart';
import 'package:loooans/app/di/repository_providers.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/app/routing/router.dart';
import 'package:loooans/app/theme.dart';
import 'package:loooans/app/view/alpha_banner.dart';
import 'package:loooans/features/search/widget/search_shortcut_wrapper.dart';
import 'package:loooans/l10n/arb/app_localizations.dart';

class App extends StatelessWidget {
  const App({super.key});

  static final _routes = buildAppRoutes();

  @override
  Widget build(BuildContext context) {
    return AppRepositoryProviders(
      child: AppBlocProviders(
        child: MaterialApp.router(
          builder: (context, child) {
            final data = MediaQuery.of(context);
            return MediaQuery(
              data: data.copyWith(
                textScaler: const TextScaler.linear(1.2),
              ),
              // Above the `Router`, which is what makes `Ctrl K` work on the
              // screens outside the `ShellRoute` too. `_routes.go` rather than
              // `GoRouter.of(context)`: this builder's context sits above the
              // router, so the inherited widget is not there yet.
              child: SearchShortcutWrapper(
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
    );
  }
}
