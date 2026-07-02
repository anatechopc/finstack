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
  ConversationsBloc(BuildContext context)
      : _repo = context.read<ChatRoomRepository>(),
        _myUserId = AuthenticationService.instance.user.id,
        _myCompanyId = AuthenticationService.instance.user.companyId,
        super(ConversationsState(myUserId: AuthenticationService.instance.user.id)) {
    _wire();
  }

  ConversationsBloc.withDependencies({
    required ChatRoomRepository chatRoomRepository,
    required String myUserId,
    required String? myCompanyId,
  })  : _repo = chatRoomRepository,
        _myUserId = myUserId,
        _myCompanyId = myCompanyId,
        super(ConversationsState(myUserId: myUserId)) {
    _wire();
  }

  final ChatRoomRepository _repo;
  final String _myUserId;
  final String? _myCompanyId;
  StreamSubscription<List<ChatRoom>>? _sub;

  void _wire() {
    // Register handlers before subscribing so all event types are ready.
    on<SubscribeConversations>(_onSubscribe);
    on<_ConversationsUpdated>(
      (e, emit) => emit(
        state.copyWith(
          status: ConversationsStatus.loaded,
          rooms: e.rooms,
        ),
      ),
    );
    on<_ConversationsErrored>(
      (e, emit) => emit(
        state.copyWith(
          status: ConversationsStatus.error,
          message: e.message,
        ),
      ),
    );

    // Subscribe to the stream synchronously so test-side events emitted
    // in the same act callback are captured even before _onSubscribe runs.
    _sub = _repo.dataStream.listen(
      (rooms) => add(_ConversationsUpdated(rooms)),
      onError: (Object err) {
        _log.severe('conversations stream error: $err');
        add(const _ConversationsErrored('Failed to load conversations'));
      },
    );
  }

  void _onSubscribe(
    SubscribeConversations event,
    Emitter<ConversationsState> emit,
  ) {
    emit(state.copyWith(status: ConversationsStatus.loading));
    final ids = <Object?>[_myUserId, if (_myCompanyId != null) _myCompanyId];
    _repo.loadNext(
      statements: [QueryStatement(field: 'member_ids', arrayContainsAny: ids)],
      reset: true,
    );
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
