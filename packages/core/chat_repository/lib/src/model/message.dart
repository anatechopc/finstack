import 'package:chat_repository/src/model/attachment.dart';
import 'package:chat_repository/src/model/message_entity.dart';
import 'package:chat_repository/src/model/message_type.dart';
import 'package:loooans_helpers/data_helpers.dart';

class Message extends MessageEntity implements BaseModel<MessageEntity> {
  Message() : super();

  factory Message.create({
    required String roomId,
    required String senderId,
    required String senderParticipantId,
    required MessageType type,
    String? text,
    List<Attachment>? attachments,
  }) {
    final now = DateTime.timestamp();
    return Message()
      ..id = NO_ID
      ..roomId = roomId
      ..seq = null
      ..senderId = senderId
      ..senderParticipantId = senderParticipantId
      ..type = type
      ..text = text
      ..attachments = attachments ?? <Attachment>[]
      ..createdAt = now
      ..updatedAt = now;
  }

  @override
  MessageEntity toEntity() => this;
}
