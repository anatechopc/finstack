part of 'chat_bloc.dart';

enum ChatStatus { initial, loading, loaded, error }

final class ChatState extends Equatable {
  const ChatState({
    this.status = ChatStatus.initial,
    this.messages = const [],
    this.room,
    this.sending = false,
    this.message,
  });

  final ChatStatus status;
  final List<Message> messages;
  final ChatRoom? room;
  final bool sending;
  final String? message;

  ChatState copyWith({
    ChatStatus? status,
    List<Message>? messages,
    ChatRoom? room,
    bool? sending,
    String? message,
  }) {
    return ChatState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      room: room ?? this.room,
      sending: sending ?? this.sending,
      message: message,
    );
  }

  @override
  List<Object?> get props => [status, messages, room, sending, message];
}
