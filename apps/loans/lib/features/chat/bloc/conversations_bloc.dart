import 'dart:async';

import 'package:chat_repository/chat_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:loooans_helpers/logging_helpers.dart';

part 'conversations_event.dart';
part 'conversations_state.dart';

final _log = Logger('conversations_bloc');

class ConversationsBloc extends Bloc<ConversationsEvent, ConversationsState> {
  // Reads the auth singleton ONCE and delegates to the injectable path (per the
  // "no AuthenticationService.instance in BLoCs" rule in apps/loans/CLAUDE.md).
  factory ConversationsBloc(BuildContext context) {
    final user = AuthenticationService.instance.user;
    return ConversationsBloc.withDependencies(
      chatRoomRepository: context.read<ChatRoomRepository>(),
      myUserId: user.id,
      myCompanyId: user.companyId,
    );
  }

  ConversationsBloc.withDependencies({
    required ChatRoomRepository chatRoomRepository,
    required String myUserId,
    required String? myCompanyId,
  })  : _repo = chatRoomRepository,
        _myUserId = myUserId,
        _myCompanyId = myCompanyId,
        super(
          ConversationsState(myUserId: myUserId, myCompanyId: myCompanyId),
        ) {
    _wire();
  }

  final ChatRoomRepository _repo;
  final String _myUserId;
  final String? _myCompanyId;
  StreamSubscription<List<ChatRoom>>? _sub;

  // Highest delivered seq we've already written per room (avoids re-writes in
  // the window before the room stream reflects the mark).
  final Map<String, int> _deliveredUpTo = {};

  void _wire() {
    // Register handlers before subscribing so all event types are ready.
    on<SubscribeConversations>(_onSubscribe);
    on<_ConversationsUpdated>(_onConversationsUpdated);
    on<_ConversationsErrored>(
      (e, emit) => emit(
        state.copyWith(
          status: ConversationsStatus.error,
          message: e.message,
        ),
      ),
    );

    // Subscribe immediately so the app-bar unread badge is populated on cold
    // start — not only after the Messages screen is opened for the first time.
    add(const SubscribeConversations());
  }

  Future<void> _onConversationsUpdated(
    _ConversationsUpdated event,
    Emitter<ConversationsState> emit,
  ) async {
    emit(
      state.copyWith(
        status: ConversationsStatus.loaded,
        rooms: event.rooms,
      ),
    );
    // Advance the personal delivered watermark for rooms with a new incoming
    // message the user hasn't read yet — so the sender's "delivered" tick works
    // while the recipient is on the inbox (not inside the room). Coalesced, and
    // skipped for our own last message. Never lowers the watermark (target is
    // room.lastSeq, always >= the current delivered seq).
    for (final room in event.rooms) {
      final target = room.lastSeq;
      final current = room.reads[_myUserId]?.lastDeliveredSeq ?? 0;
      final floor = current > (_deliveredUpTo[room.id] ?? 0)
          ? current
          : (_deliveredUpTo[room.id] ?? 0);
      if (target <= floor) continue;
      final senderPid = room.lastMessage?.senderParticipantId;
      if (senderPid == _myUserId || senderPid == _myCompanyId) continue;
      _deliveredUpTo[room.id] = target;
      try {
        await _repo.markDelivered(
          roomId: room.id,
          userId: _myUserId,
          seq: target,
        );
      } catch (err) {
        _log.warning('markDelivered failed for ${room.id}: $err');
      }
    }
  }

  void _onSubscribe(
    SubscribeConversations event,
    Emitter<ConversationsState> emit,
  ) {
    // close() drains pending events — a handler running after close would
    // attach a subscription nothing ever cancels.
    if (isClosed) return;
    emit(state.copyWith(status: ConversationsStatus.loading));
    final ids = <Object?>[_myUserId, if (_myCompanyId != null) _myCompanyId];
    // Cancel first, then loadNext, then listen — all in one synchronous turn.
    // loadNext (every call in the chat services) calls resetStreamController(),
    // which REPLACES the controller backing `dataStream` — a subscription taken
    // before loadNext (e.g. in the constructor, as this bloc originally did) is
    // left attached to the old, dead controller and never receives a single
    // emission. Working blocs (LoansBloc/ProductBloc) avoid this by exposing
    // dataStream as a getter consumed at build time.
    _sub?.cancel();
    _repo.loadNext(
      statements: [QueryStatement(field: 'member_ids', arrayContainsAny: ids)],
      reset: true,
    );
    _sub = _repo.dataStream.listen(
      (rooms) => add(_ConversationsUpdated(rooms)),
      onError: (Object err) {
        _log.severe('conversations stream error: $err');
        add(const _ConversationsErrored('Failed to load conversations'));
      },
    );
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
