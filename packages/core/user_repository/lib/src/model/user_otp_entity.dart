import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:user_repository/src/model/user_otp.dart';

part 'user_otp_entity.g.dart';

@JsonSerializable()
class UserOtpEntity implements BaseEntity {

  UserOtpEntity();

  UserOtpEntity._({
    required this.createdAt,
    required this.updatedAt,
    required this.id,
    required this.expireAt,
    required this.otp,
    required this.userId,
  });

  factory UserOtpEntity.fromJson(Map<String, dynamic> json) =>
      _$UserOtpEntityFromJson(json);
  @JsonKey(
    name: 'deleted_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  @override
  DateTime? deletedAt;

  // this is token
  @override
  late String id;

  @JsonKey(
    name: 'updated_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  @override
  late DateTime updatedAt;

  @JsonKey(
    name: 'created_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  @override
  late DateTime createdAt;

  @JsonKey(
    name: 'expire_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  late DateTime expireAt;

  late String otp;

  late String userId;

  @override
  List<Object?> get props => [
        createdAt,
        updatedAt,
        deletedAt,
        id,
        expireAt,
        otp,
        userId,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() => _$UserOtpEntityToJson(this);

  UserOtp toUserOtp() {
    return UserOtp()
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..deletedAt = deletedAt
      ..id = id
      ..expireAt = expireAt
      ..otp = otp
      ..userId = userId;
  }
}
