import 'package:json_annotation/json_annotation.dart';

part 'request_otp_response.g.dart';

@JsonSerializable()
class RequestOtpResponse {

  RequestOtpResponse({
    required this.redirectUrl,
    required this.token,
    required this.expireAt,
  });

  factory RequestOtpResponse.fromJson(Map<String, dynamic> json) =>
      _$RequestOtpResponseFromJson(json);
  @JsonKey(name: 'redirect_url')
  final String redirectUrl;
  final String token;
  @JsonKey(name: 'expire_at')
  final int expireAt;

  Map<String, dynamic> toJson() {
    return _$RequestOtpResponseToJson(this);
  }
}
