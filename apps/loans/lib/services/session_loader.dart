import 'package:address_repository/address_repository.dart';
import 'package:company_repository/company_repository.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/device_service.dart';
import 'package:loooans/services/settings_service.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:settings_repository/settings_repository.dart';
import 'package:user_repository/user_repository.dart';

class SessionLoader {
  const SessionLoader._();

  static Future<void> loadSession({
    required User user,
    required UserRepository userRepository,
    required CompanyRepository companyRepository,
    required AddressRepository addressRepository,
    required SettingsRepository settingsRepository,
    AuthenticationService? authService,
    DeviceService? deviceService,
  }) async {
    final auth = authService ?? AuthenticationService.instance;
    final device_ = deviceService ?? DeviceService.instance;

    auth.user = user;

    var device = await userRepository.getDevice(
      userId: user.id,
      deviceInstanceId: await device_.instanceId,
    );
    if (device == null) {
      device = await device_.device;
      await userRepository.addDevice(userId: user.id, device: device);
    }
    auth.device = device;

    if (![UserRole.appAdmin, UserRole.customer].contains(user.userRole) &&
        user.companyId != null) {
      final company = await companyRepository.get(id: user.companyId!);
      auth.company = company;
      final address = await addressRepository.getByDataType(
        id: company.id,
        type: DataType.provider,
      );

      if (address == null) {
        throw Exception('Address is needed for logged in users');
      }

      auth.address = address;
      SettingsService.initializeForUser(
        repository: settingsRepository,
        userId: user.id,
      );
    } else {
      final address = await addressRepository.getByDataType(
        id: user.id,
        type: DataType.user,
      );

      if (address == null) {
        throw Exception('Address is needed for logged in users');
      }

      auth.address = address;
    }
  }
}
