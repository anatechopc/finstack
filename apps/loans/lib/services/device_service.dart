import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:loooans_helpers/loooans_helpers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user_repository/user_repository.dart';

class DeviceService {
  DeviceService._internal();

  static DeviceService? _instance;

  static DeviceService get instance {
    _instance ??= DeviceService._internal();

    return _instance!;
  }

  // void initialize() {
  //   if (_instance == null) {
  //     return;
  //   }
  //
  //   final prefs = SharedPreferencesAsync();
  // }

  Future<String> get instanceId async {
    final prefs = SharedPreferencesAsync();
    final deviceInstanceId = await prefs.getString('instance_id');

    return deviceInstanceId ?? StringHelper.generateId();
  }

  // the device retrieved from this varialbe is the local
  // device the app is running
  Future<Device> get device async {
    final deviceInfo = DeviceInfoPlugin();

    if (kIsWeb) {
      final webBrowserInfo = await deviceInfo.webBrowserInfo;
      debugPrint('Running on ${webBrowserInfo.userAgent}');
      debugPrint('string on $webBrowserInfo');

      return Device.create(
        instanceId: await instanceId,
        model:
            '${webBrowserInfo.browserName.name}_${DateTime.now().toIso8601String()}',
        os: 'web',
        version: '1',
        token: '',
      );
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidInfo = await deviceInfo.androidInfo;
      debugPrint('Running on ${androidInfo.model}'); // e.g. "Moto G (4)"
      debugPrint('string on $androidInfo');
      // androidInfo.version.sdkInt -- version
      // androidInfo.model -- model
      return Device.create(
        instanceId: await instanceId,
        model: androidInfo.model,
        os: 'android',
        version: androidInfo.version.sdkInt.toString(),
        token: '',
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iosInfo = await deviceInfo.iosInfo;
      debugPrint('Running on ${iosInfo.utsname.machine}'); // e.g. "iPod7,1"
      debugPrint('string on $iosInfo');

      return Device.create(
        instanceId: await instanceId,
        model: iosInfo.model,
        os: 'ios',
        version: iosInfo.systemVersion,
        token: '',
      );
    }

    throw Exception('Current platform not supported');
  }
}
