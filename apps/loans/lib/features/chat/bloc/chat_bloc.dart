import 'dart:async';

import 'package:chat_repository/chat_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans_helpers/logging_helpers.dart';

part 'chat_event.dart';
part 'chat_state.dart';

final _log = Logger('chat_bloc');

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc(BuildContext context, {required String roomId})
      : _roomId = roomId,
        _rooms = context.read<ChatRoomRepository>(),
        _messages = MessageRepository(roomId: roomId),
        _typing = context.read<TypingService>(),
        _myUserId = AuthenticationService.instance.user.id,
        _mySenderParticipantId =
            AuthenticationService.instance.user.companyId ??
                AuthenticationService.instance.user.id,
        super(const ChatState()) {
    _wire();
  }

  ChatBloc.withDependencies({
    required String roomId,
    required ChatRoomRepository chatRoomRepository,
    required MessageRepository messageRepository,
    required TypingService typingService,
    required String myUserId,
    required String mySenderParticipantId,
  })  : _roomId = roomId,
        _rooms = chatRoomRepository,
        _messages = messageRepository,
        _typing = typingService,
        _myUserId = myUserId,
        _mySenderParticipantId = mySenderParticipantId,
        super(const ChatState()) {
    _wire();
  }

  final String _roomId;
  final ChatRoomRepository _rooms;
  final MessageRepository _messages;
  final TypingService _typing;
  final String _myUserId;
  final String _mySenderParticipantId;

  StreamSubscription<List<Message>>? _msgSub;
  StreamSubscription<ChatRoom>? _roomSub;
  StreamSubscription<List<String>>? _typingSub;

  void _wire() {
    on<SubscribeChat>(_onSubscribe);
    on<SendTextMessage>(_onSendText);
    on<MarkRoomRead>(_onMarkRead);
    on<_MessagesUpdated>(_onMessagesUpdated);
    on<_RoomUpdated>((e, emit) => emit(state.copyWith(room: e.room)));
    on<_ChatErrored>(
      (e, emit) =>
          emit(state.copyWith(status: ChatStatus.error, message: e.message)),
    );
    on<TypingChanged>(_onTyping);
    on<_TypingUsersUpdated>(
      (e, emit) => emit(state.copyWith(typingUserIds: e.userIds)),
    );

    // Subscriptions established synchronously so broadcast-stream tests don't
    // miss emissions fired right after SubscribeChat.
    _msgSub = _messages.dataStream.listen(
      (msgs) => add(_MessagesUpdated(msgs)),
      onError: (Object err) {
        _log.severe('messages stream error: $err');
        add(const _ChatErrored('Failed to load messages'));
      },
    );
    _roomSub = _rooms.watchRoom(_roomId).listen(
      (room) => add(_RoomUpdated(room)),
      onError: (Object err) => _log.severe('room stream error: $err'),
    );
    _typingSub = _typing
        .typingStream(
          roomId: _roomId,
          clock: () => DateTime.now().millisecondsSinceEpoch,
        )
        .listen(
          (ids) => add(
            _TypingUsersUpdated(
              ids.where((id) => id != _myUserId).toList(),
            ),
          ),
        );
  }

  Future<void> _onSubscribe(
    SubscribeChat event,
    Emitter<ChatState> emit,
  ) async {
    emit(state.copyWith(status: ChatStatus.loading));
    _messages.loadNext(reset: true);
  }

  Future<void> _onMessagesUpdated(
    _MessagesUpdated event,
    Emitter<ChatState> emit,
  ) async {
    emit(state.copyWith(status: ChatStatus.loaded, messages: event.messages));
    final latestSeq = event.messages
        .map((m) => m.seq ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    if (latestSeq > 0) {
      await _rooms.markRead(
        roomId: _roomId,
        userId: _myUserId,
        seq: latestSeq,
      );
    }
  }

  Future<void> _onSendText(
    SendTextMessage event,
    Emitter<ChatState> emit,
  ) async {
    final text = event.text.trim();
    if (text.isEmpty) return;
    emit(state.copyWith(sending: true));
    try {
      await _messages.add(
        data: Message.create(
          roomId: _roomId,
          senderId: _myUserId,
          senderParticipantId: _mySenderParticipantId,
          type: MessageType.text,
          text: text,
        ),
      );
      emit(state.copyWith(sending: false));
    } catch (err) {
      _log.severe('send failed: $err');
      emit(state.copyWith(sending: false, message: 'Failed to send'));
    }
  }

  Future<void> _onMarkRead(
    MarkRoomRead event,
    Emitter<ChatState> emit,
  ) async {
    final latestSeq = state.messages
        .map((m) => m.seq ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    if (latestSeq > 0) {
      await _rooms.markRead(
        roomId: _roomId,
        userId: _myUserId,
        seq: latestSeq,
      );
    }
  }

  Future<void> _onTyping(TypingChanged event, Emitter<ChatState> emit) async {
    if (event.isTyping) {
      await _typing.setTyping(
        roomId: _roomId,
        userId: _myUserId,
        nowMillis: DateTime.now().millisecondsSinceEpoch,
      );
    } else {
      await _typing.clearTyping(roomId: _roomId, userId: _myUserId);
    }
  }

  @override
  Future<void> close() {
    _msgSub?.cancel();
    _roomSub?.cancel();
    _typingSub?.cancel();
    return super.close();
  }
}
