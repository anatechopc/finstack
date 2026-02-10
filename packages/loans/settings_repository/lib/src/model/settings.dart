import 'package:loooans_helpers/data_helpers.dart';
import 'package:settings_repository/src/model/settings_entity.dart';

class Settings extends SettingsEntity implements BaseModel<SettingsEntity> {
  Settings() : super();

  factory Settings.create({
    required String userId,
    bool useClassicUI = false,
    bool forcePaymentConfirmation = false,
    bool enableProductAddOns = false,
  }) {
    final now = DateTime.timestamp();
    return Settings()
      ..id = NO_ID
      ..createdAt = now
      ..updatedAt = now
      ..userId = userId
      ..useClassicUI = useClassicUI
      ..forcePaymentConfirmation = forcePaymentConfirmation
      ..enableProductAddOns = enableProductAddOns;
  }

  @override
  SettingsEntity toEntity() {
    return this;
  }
}
