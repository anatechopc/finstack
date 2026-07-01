import 'package:chat_repository/src/model/message_type.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'last_message.g.dart';

/// Denormalized preview of the latest message, `chat_rooms.last_message`.
@JsonSerializable()
class LastMessage {
  LastMessage({
    required this.senderParticipantId,
    required this.type,
    required this.seq,
    required this.createdAt,
    this.text,
  });

  factory LastMessage.fromJson(Map<String, dynamic> json) =>
      _$LastMessageFromJson(json);

  final String? text;

  @JsonKey(name: 'sender_participant_id')
  final String senderParticipantId;

  @JsonKey(unknownEnumValue: MessageType.text)
  final MessageType type;

  final int seq;

  @JsonKey(
    name: 'created_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  final DateTime createdAt;

  Map<String, dynamic> toJson() => _$LastMessageToJson(this);
}
