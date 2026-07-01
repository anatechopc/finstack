import 'package:chat_repository/src/model/chat_room_entity.dart';
import 'package:chat_repository/src/model/last_message.dart';
import 'package:chat_repository/src/model/participant.dart';
import 'package:chat_repository/src/model/read_state.dart';
import 'package:chat_repository/src/model/team_read_state.dart';
import 'package:loooans_helpers/data_helpers.dart';

class ChatRoom extends ChatRoomEntity implements BaseModel<ChatRoomEntity> {
  ChatRoom() : super();

  factory ChatRoom.create({
    required List<Participant> participants,
    required String createdBy,
    String? contextType,
    String? contextId,
  }) {
    final now = DateTime.timestamp();
    return ChatRoom()
      ..id = NO_ID
      ..participants = participants
      ..memberIds = participants.map((p) => p.id).toList()
      ..contextType = contextType
      ..contextId = contextId
      ..lastSeq = 0
      ..lastMessage = null
      ..reads = <String, ReadState>{}
      ..teamReads = <String, TeamReadState>{}
      ..createdBy = createdBy
      ..createdAt = now
      ..updatedAt = now;
  }

  @override
  ChatRoomEntity toEntity() => this;
}
