part of 'chat_bloc.dart';

sealed class ChatEvent extends Equatable {
  const ChatEvent();
  @override
  List<Object?> get props => [];
}

final class SubscribeChat extends ChatEvent {
  const SubscribeChat();
}

final class SendTextMessage extends ChatEvent {
  const SendTextMessage(this.text);
  final String text;
  @override
  List<Object?> get props => [text];
}

final class MarkRoomRead extends ChatEvent {
  const MarkRoomRead();
}

final class _MessagesUpdated extends ChatEvent {
  const _MessagesUpdated(this.messages);
  final List<Message> messages;
  @override
  List<Object?> get props => [messages];
}

final class _RoomUpdated extends ChatEvent {
  const _RoomUpdated(this.room);
  final ChatRoom room;
  @override
  List<Object?> get props => [room];
}

final class _ChatErrored extends ChatEvent {
  const _ChatErrored(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}
