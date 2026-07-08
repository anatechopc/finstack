import 'package:chat_repository/chat_repository.dart';

/// The read states of the *counterpart* side of a room, relative to me.
/// - counterpart is a company  -> every reader who isn't me (its staff)
/// - counterpart is a user      -> just that user's read state
Iterable<ReadState> counterpartReadStates(
  ChatRoom room, {
  required String myUserId,
  String? myCompanyId,
}) {
  final counterpart = room.participants.firstWhere(
    (p) => p.id != myUserId && p.id != myCompanyId,
    orElse: () => room.participants.first,
  );
  if (counterpart.type == ParticipantType.user) {
    final rs = room.reads[counterpart.id];
    return rs == null ? const [] : [rs];
  }
  return room.reads.entries
      .where((e) => e.key != myUserId)
      .map((e) => e.value);
}
