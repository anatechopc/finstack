import 'package:flutter/material.dart';
import 'package:loooans/app/di/bloc_providers.dart';
import 'package:loooans/app/di/repository_providers.dart';
import 'package:loooans/app/routing/router.dart';
import 'package:loooans/app/theme.dart';
import 'package:loooans/app/view/alpha_banner.dart';
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
              child: Column(
                children: [
                  Expanded(
                    child: child!,
                  ),
                  const AlphaBanner(),
                ],
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
