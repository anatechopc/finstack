import 'package:loooans_helpers/data_helpers.dart';
import 'package:user_repository/src/model/user_otp_entity.dart';

class UserOtp extends UserOtpEntity implements BaseModel<UserOtpEntity> {
  @override
  UserOtpEntity toEntity() {
    return this;
  }
}