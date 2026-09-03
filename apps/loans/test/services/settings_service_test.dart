import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/services/settings_service.dart';
import 'package:settings_repository/settings_repository.dart';

void main() {
  setUp(SettingsService.initialize);

  group('SettingsService.listen', () {
    test('a subscriber from before the session loads still gets the settings',
        () async {
      // The shell's StreamBuilder subscribes on a cold load, before
      // initializeForUser has run. This used to be a one-shot default stream:
      // the real settings never reached it, and a cold-loaded /?sec=... stayed
      // in the non-classic layout until some navigation re-ran the builder.
      final seen = <bool>[];
      final sub = SettingsService.instance.listen().listen(
            (s) => seen.add(s.useClassicUI),
          );
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [false], reason: 'the default is emitted first');

      final repo = StreamController<List<Settings>>();
      addTearDown(repo.close);
      SettingsService.instance.feedSettingsForTest(repo.stream);
      repo.add([Settings.create(userId: 'u', useClassicUI: true)]);
      await Future<void>.delayed(Duration.zero);

      expect(seen, [false, true]);
      expect(SettingsService.instance.appUseClassicUI, isTrue);
    });

    test('a subscriber from after the session loads gets the current value',
        () async {
      final repo = StreamController<List<Settings>>();
      addTearDown(repo.close);
      SettingsService.instance.feedSettingsForTest(repo.stream);
      repo.add([Settings.create(userId: 'u', useClassicUI: true)]);
      await Future<void>.delayed(Duration.zero);

      expect(
        await SettingsService.instance.listen().first.then((s) => s.useClassicUI),
        isTrue,
      );
    });
  });
}
