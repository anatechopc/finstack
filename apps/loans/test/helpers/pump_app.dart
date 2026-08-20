import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/l10n/arb/app_localizations.dart';

extension PumpApp on WidgetTester {
  /// Pumps [widget] inside the app's MaterialApp shell.
  ///
  /// Pass [theme] when the widget under test depends on app styling — the
  /// AppBar's `centerTitle: true` and `headlineLarge` title, for instance.
  /// Without it the widget renders against default Material styling, which is
  /// how a two-line app-bar title went untested.
  Future<void> pumpApp(Widget widget, {ThemeData? theme}) {
    return pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme,
        home: widget,
      ),
    );
  }
}
