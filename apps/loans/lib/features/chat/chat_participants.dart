import 'package:chat_repository/chat_repository.dart';

/// Immutable result of building a room's participant set + context anchor.
class RoomSeed {
  const RoomSeed({
    required this.participants,
    this.contextType,
    this.contextId,
    this.contextLabel,
  });
  final List<Participant> participants;
  final String? contextType;
  final String? contextId;

  /// Human-readable name of the anchor, shown in the inbox and the room's app
  /// bar so two rooms with the same counterpart are tellable apart.
  final String? contextLabel;
}

/// Builds participant sets for the app's anchored-room entry points.
abstract class ChatParticipants {
  static RoomSeed borrowerToCompany({
    required String userId,
    required String userName,
    required String? userPhotoUrl,
    required String companyId,
    required String companyName,
    required String? companyPhotoUrl,
    String? contextType,
    String? contextId,
    String? contextLabel,
  }) {
    return RoomSeed(
      participants: [
        Participant(
          id: userId,
          type: ParticipantType.user,
          displayName: userName,
          photoUrl: userPhotoUrl,
        ),
        Participant(
          id: companyId,
          type: ParticipantType.company,
          displayName: companyName,
          photoUrl: companyPhotoUrl,
        ),
      ],
      contextType: contextType,
      contextId: contextId,
      contextLabel: contextLabel,
    );
  }

  static RoomSeed staffToBorrower({
    required String companyId,
    required String companyName,
    required String? companyPhotoUrl,
    required String borrowerId,
    required String borrowerName,
    required String? borrowerPhotoUrl,
    String? contextType,
    String? contextId,
    String? contextLabel,
  }) {
    return RoomSeed(
      participants: [
        Participant(
          id: companyId,
          type: ParticipantType.company,
          displayName: companyName,
          photoUrl: companyPhotoUrl,
        ),
        Participant(
          id: borrowerId,
          type: ParticipantType.user,
          displayName: borrowerName,
          photoUrl: borrowerPhotoUrl,
        ),
      ],
      contextType: contextType,
      contextId: contextId,
      contextLabel: contextLabel,
    );
  }
}
