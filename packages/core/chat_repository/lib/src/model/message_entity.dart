import 'package:chat_repository/src/model/attachment.dart';
import 'package:chat_repository/src/model/message.dart';
import 'package:chat_repository/src/model/message_type.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'message_entity.g.dart';

@JsonSerializable()
class MessageEntity implements BaseEntity {
  MessageEntity();

  factory MessageEntity.fromJson(Map<String, dynamic> json) =>
      _$MessageEntityFromJson(json);

  @override
  late String id;

  @JsonKey(name: 'room_id')
  late String roomId;

  /// Assigned by the Go trigger on create; null while pending.
  int? seq;

  @JsonKey(name: 'sender_id')
  late String senderId;

  @JsonKey(name: 'sender_participant_id')
  late String senderParticipantId;

  @JsonKey(unknownEnumValue: MessageType.text)
  late MessageType type;

  String? text;

  @JsonKey(toJson: MessageEntity._attachmentsToJson, defaultValue: <Attachment>[])
  late List<Attachment> attachments;

  @JsonKey(
    name: 'created_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  @override
  late DateTime createdAt;

  @JsonKey(
    name: 'updated_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  @override
  late DateTime updatedAt;

  @JsonKey(
    name: 'edited_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  DateTime? editedAt;

  @JsonKey(
    name: 'deleted_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  @override
  DateTime? deletedAt;

  @override
  List<Object?> get props => [
        id, roomId, seq, senderId, senderParticipantId, type, text,
        attachments, createdAt, updatedAt, editedAt, deletedAt,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() => _$MessageEntityToJson(this);

  Message toMessage() {
    return Message()
      ..id = id
      ..roomId = roomId
      ..seq = seq
      ..senderId = senderId
      ..senderParticipantId = senderParticipantId
      ..type = type
      ..text = text
      ..attachments = attachments
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..editedAt = editedAt
      ..deletedAt = deletedAt;
  }

  static List<Map<String, dynamic>> _attachmentsToJson(List<Attachment> items) =>
      items.map((a) => a.toJson()).toList();
}
