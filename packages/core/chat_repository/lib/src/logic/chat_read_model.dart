import 'package:chat_repository/src/model/chat_room_entity.dart';
import 'package:chat_repository/src/model/message_entity.dart';
import 'package:chat_repository/src/model/message_status.dart';
import 'package:chat_repository/src/model/participant.dart';
import 'package:chat_repository/src/model/read_state.dart';

/// Unread message count for [userId] in [room]: lastSeq minus that user's
/// read watermark (0 when they have no watermark yet), clamped at 0.
int unreadFor(ChatRoomEntity room, String userId) {
  final lastRead = room.reads[userId]?.lastReadSeq ?? 0;
  final diff = room.lastSeq - lastRead;
  return diff > 0 ? diff : 0;
}

/// Whether the team has handled the room (caught up to lastSeq).
bool isHandledByTeam(ChatRoomEntity room, String companyId) {
  final handled = room.teamReads[companyId]?.lastHandledSeq ?? 0;
  return handled >= room.lastSeq;
}

/// Inverse of [isHandledByTeam].
bool isAwaitingResponse(ChatRoomEntity room, String companyId) =>
    !isHandledByTeam(room, companyId);

/// Derive the outgoing-message status from the counterpart watermark(s).
/// For a company counterpart, pass every staff member's [ReadState]; the
/// highest watermark wins.
MessageStatus messageStatus({
  required MessageEntity message,
  required Iterable<ReadState> counterpartReadStates,
}) {
  final seq = message.seq;
  if (seq == null) return MessageStatus.sending;
  var delivered = false;
  var read = false;
  for (final rs in counterpartReadStates) {
    if (rs.lastReadSeq >= seq) read = true;
    if (rs.lastDeliveredSeq >= seq) delivered = true;
  }
  if (read) return MessageStatus.read;
  if (delivered) return MessageStatus.delivered;
  return MessageStatus.sent;
}

/// Denormalized `member_ids` for a participant set.
List<String> memberIdsOf(List<Participant> participants) =>
    participants.map((p) => p.id).toList();

/// Dedup predicate: does [room] have exactly [memberIds] and the same anchor?
bool roomMatchesAnchor(
  ChatRoomEntity room, {
  required Set<String> memberIds,
  String? contextType,
  String? contextId,
}) {
  final sameMembers = room.memberIds.toSet().length == memberIds.length &&
      room.memberIds.toSet().containsAll(memberIds);
  return sameMembers &&
      room.contextType == contextType &&
      room.contextId == contextId;
}
