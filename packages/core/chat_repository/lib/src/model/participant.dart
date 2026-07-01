import 'package:chat_repository/src/model/participant_type.dart';
import 'package:json_annotation/json_annotation.dart';

part 'participant.g.dart';

@JsonSerializable()
class Participant {
  Participant({
    required this.id,
    required this.type,
    this.displayName,
    this.photoUrl,
  });

  factory Participant.fromJson(Map<String, dynamic> json) =>
      _$ParticipantFromJson(json);

  final String id;

  @JsonKey(unknownEnumValue: ParticipantType.user)
  final ParticipantType type;

  @JsonKey(name: 'display_name')
  final String? displayName;

  @JsonKey(name: 'photo_url')
  final String? photoUrl;

  Map<String, dynamic> toJson() => _$ParticipantToJson(this);
}
