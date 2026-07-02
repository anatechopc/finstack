part of 'conversations_bloc.dart';

enum ConversationsStatus { initial, loading, loaded, error }

final class ConversationsState extends Equatable {
  const ConversationsState({
    this.status = ConversationsStatus.initial,
    this.rooms = const [],
    this.myUserId = '',
    this.myCompanyId,
    this.message,
  });

  final ConversationsStatus status;
  final List<ChatRoom> rooms;
  final String myUserId;
  final String? myCompanyId;
  final String? message;

  /// Sum of the current user's unread across all rooms.
  int get totalUnread =>
      rooms.fold(0, (sum, r) => sum + unreadFor(r, myUserId));

  /// Number of rooms where the team hasn't responded yet.
  int get awaitingCount {
    final cid = myCompanyId;
    if (cid == null) return 0;
    return rooms.where((r) => isAwaitingResponse(r, cid)).length;
  }

  ConversationsState copyWith({
    ConversationsStatus? status,
    List<ChatRoom>? rooms,
    String? myUserId,
    String? myCompanyId,
    String? message,
  }) {
    return ConversationsState(
      status: status ?? this.status,
      rooms: rooms ?? this.rooms,
      myUserId: myUserId ?? this.myUserId,
      myCompanyId: myCompanyId ?? this.myCompanyId,
      message: message,
    );
  }

  @override
  List<Object?> get props => [status, rooms, myUserId, myCompanyId, message];
}
