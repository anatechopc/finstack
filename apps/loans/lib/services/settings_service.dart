import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:loooans_helpers/logging_helpers.dart';
import 'package:settings_repository/settings_repository.dart';

class SettingsService {
  SettingsService._internal();

  static SettingsService? _instance;
  static SettingsRepository? _settingsRepository;
  static String? _userId;

  static final log = Logger('settings_service.dart');

  static SettingsService get instance {
    if (_instance == null) {
      log.severe('Cannot get instance. Please call initialize first');
      throw Exception('Please initialize settings');
    }

    return _instance!;
  }

  static void initialize() {
    _instance ??= SettingsService._internal();
  }

  static void initializeForUser({
    required SettingsRepository repository,
    required String userId,
  }) {
    _instance ??= SettingsService._internal();

    _settingsRepository = repository;
    _userId = userId;

    _settingsRepository!.loadNext(
      statements: [
        QueryStatement(field: 'user_id', isEqualTo: userId),
      ],
      limit: null,
      reset: true,
    );

    // AFTER loadNext, deliberately: its synchronous prefix calls
    // `resetStreamController()`, which REPLACES the repository's broadcast
    // controller, so a subscription taken before the call listens to a
    // controller nothing will ever write to. Feed every listener that
    // subscribed before this ran — the shell's StreamBuilder subscribes on a
    // cold load, before the session is restored, and used to be handed a
    // one-shot default stream that the real settings never reached.
    _instance!._repoSubscription?.cancel();
    _instance!._repoSubscription = repository.dataStream
        .handleError((Object error) {
          log.severe('error when listening to settings: $error');
        })
        .map(_instance!._settingsOf)
        .listen(_instance!._settingsController.add);
    log.info('listening settings for user: $userId');
  }

  Settings? _currentSettings;

  /// One live stream for the whole app. `initializeForUser` pipes the
  /// repository into it, whenever that happens relative to subscribers.
  final _settingsController = StreamController<Settings>.broadcast();
  StreamSubscription<Settings>? _repoSubscription;

  /// The current settings first, then every change — including the first
  /// real settings if the user's session is restored after subscribing.
  Stream<Settings> listen() {
    if (_settingsRepository == null || _userId == null) {
      log.warning(
          'SettingsRepository and user is not initialized. Disregard if this is intentional.',);
      _currentSettings ??= Settings.create(userId: 'userId');
    }

    return Stream<Settings>.multi((controller) {
      final current = _currentSettings;
      if (current != null) controller.add(current);
      controller.addStream(_settingsController.stream);
    });
  }

  Settings _settingsOf(List<Settings> settings) {
    if (settings.isNotEmpty) {
      if (settings.length > 1) {
        log.warning(
            'There are more than 1 settings for this user. The app only gets the first setting for this user.',);
      }
      _currentSettings = settings.first;
    } else {
      _currentSettings = Settings.create(userId: 'userId');
    }
    return _currentSettings!;
  }

  /// Tests only: stand in for the repository stream without Firestore.
  @visibleForTesting
  void feedSettingsForTest(Stream<List<Settings>> stream) {
    _repoSubscription?.cancel();
    _repoSubscription = stream.map(_settingsOf).listen(_settingsController.add);
  }

  /// There is now a classic version of the UI.
  /// The classic version is characterized by
  bool get appUseClassicUI => _currentSettings?.useClassicUI ?? false;

  /// Tests only. Production reaches this through the settings stream; a test
  /// has no repository and would otherwise be pinned to the non-classic
  /// default, silently asserting only one of the two UI modes.
  @visibleForTesting
  void setClassicUIForTest({required bool enabled}) {
    _currentSettings = Settings.create(
      userId: _userId ?? 'test',
      useClassicUI: enabled,
    );
  }

  bool get forcePaymentConfirmation =>
      _currentSettings?.forcePaymentConfirmation ?? false;

  bool get enableProductAddOns =>
      _currentSettings?.enableProductAddOns ?? false;

  // bool get forcePaymentConfirmation => true;

  void _settingsGuard() {
    if (_settingsRepository == null ||
        _currentSettings == null ||
        _userId == null) {
      log.warning(
          'Cannot update Classic UI setting. SettingsRepository OR currentSettings OR userId is null',);
    }
  }

  void updateUseClassicUI(bool useClassicUI) {
    _settingsGuard();

    if (_currentSettings!.id == NO_ID) {
      _settingsRepository!.add(
        data: _currentSettings!
          ..useClassicUI = useClassicUI
          ..userId = _userId!,
      );
      return;
    }

    _settingsRepository!
        .update(data: _currentSettings!..useClassicUI = useClassicUI);
  }

  void updateForcePaymentConfirmation(bool force) {
    _settingsGuard();

    if (_currentSettings!.id == NO_ID) {
      _settingsRepository!.add(
        data: _currentSettings!
          ..forcePaymentConfirmation = force
          ..userId = _userId!,
      );
      return;
    }

    _settingsRepository!
        .update(data: _currentSettings!..forcePaymentConfirmation = force);
  }

  void updateEnableProductAddOns(bool enable) {
    _settingsGuard();

    if (_currentSettings!.id == NO_ID) {
      _settingsRepository!.add(
        data: _currentSettings!
          ..enableProductAddOns = enable
          ..userId = _userId!,
      );
      return;
    }

    _settingsRepository!
        .update(data: _currentSettings!..enableProductAddOns = enable);
  }

  Future<void> updateSettings(Map<String, dynamic> fields) async {
    _settingsGuard();

    if (_currentSettings!.id == NO_ID) {
      await _settingsRepository!.add(
        data: _currentSettings!
          ..useClassicUI = fields['enable_classic_ui'] as bool? ?? false
          ..forcePaymentConfirmation =
              fields['enable_force_payment_confirmation'] as bool? ?? false
          ..enableProductAddOns =
              fields['enable_product_add_ons'] as bool? ?? false
          ..userId = _userId!,
      );
      return;
    }

    await _settingsRepository!.update(
      data: _currentSettings!
        ..forcePaymentConfirmation =
            fields['enable_force_payment_confirmation'] as bool? ?? false
        ..useClassicUI = fields['enable_classic_ui'] as bool? ?? false
        ..enableProductAddOns =
            fields['enable_product_add_ons'] as bool? ?? false,
    );
  }
}
