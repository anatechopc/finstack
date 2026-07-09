import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/chat/bloc/conversations_bloc.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:mocktail/mocktail.dart';

class _MockChatRoomRepo extends Mock implements ChatRoomRepository {}

/// Fake that mirrors the REAL BaseFirestoreService behavior the mocks hide:
/// every `loadNext` REPLACES the controller backing `dataStream`
/// (resetStreamController), orphaning any subscription taken earlier. This is
/// the mechanism behind the dead-subscription bug — a bloc that listens
/// before calling loadNext receives nothing, forever, while staying green
/// under plain mocktail mocks.
class _ResettingFakeRepo extends Fake implements ChatRoomRepository {
  StreamController<List<ChatRoom>> _controller =
      StreamController<List<ChatRoom>>.broadcast();

  @override
  Stream<List<ChatRoom>> get dataStream => _controller.stream;

  @override
  void loadNext({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) {
    _controller = StreamController<List<ChatRoom>>.broadcast();
  }

  /// Emits on the CURRENT (post-reset) controller — exactly where the real
  /// query snapshots land.
  void emitRooms(List<ChatRoom> rooms) => _controller.add(rooms);

  @override
  Future<void> markDelivered({
    required String roomId,
    required String userId,
    required int seq,
  }) async {}
}

ChatRoom _room(String id, {int lastSeq = 0, Map<String, ReadState>? reads}) {
  return ChatRoom.create(
    participants: [
      Participant(id: 'u1', type: ParticipantType.user),
      Participant(id: 'c1', type: ParticipantType.company),
    ],
    createdBy: 'u1',
  )
    ..id = id
    ..lastSeq = lastSeq
    ..reads = reads ?? {};
}

void main() {
  late _MockChatRoomRepo repo;
  late StreamController<List<ChatRoom>> controller;

  setUp(() {
    repo = _MockChatRoomRepo();
    controller = StreamController<List<ChatRoom>>.broadcast();
    when(() => repo.dataStream).thenAnswer((_) => controller.stream);
    when(() => repo.loadNext(
          statements: any(named: 'statements'),
          limit: any(named: 'limit'),
          page: any(named: 'page'),
          reset: any(named: 'reset'),
        )).thenReturn(null);
  });

  tearDown(() => controller.close());

  blocTest<ConversationsBloc, ConversationsState>(
    'emits rooms and computes unread total for the current user',
    build: () => ConversationsBloc.withDependencies(
      chatRoomRepository: repo,
      myUserId: 'u1',
      myCompanyId: null,
    ),
    act: (bloc) async {
      bloc.add(const SubscribeConversations());
      // Drain the event queue so the Subscribe handler runs (it attaches the
      // dataStream listener AFTER loadNext — see _onSubscribe) before
      // emitting on the broadcast controller.
      await pumpEventQueue();
      controller.add([
        _room('r1', lastSeq: 3, reads: {'u1': ReadState(lastReadSeq: 1)}),
        _room('r2', lastSeq: 2, reads: {'u1': ReadState(lastReadSeq: 2)}),
      ]);
    },
    wait: const Duration(milliseconds: 20),
    verify: (bloc) {
      expect(bloc.state.status, ConversationsStatus.loaded);
      expect(bloc.state.rooms.length, 2);
      expect(bloc.state.totalUnread, 2); // (3-1) + (2-2)
    },
  );

  late _ResettingFakeRepo fakeRepo;

  blocTest<ConversationsBloc, ConversationsState>(
    'REGRESSION: receives rooms even though loadNext replaces the stream '
    '(dead-subscription bug — listen must come after loadNext)',
    build: () {
      fakeRepo = _ResettingFakeRepo();
      return ConversationsBloc.withDependencies(
        chatRoomRepository: fakeRepo,
        myUserId: 'u1',
        myCompanyId: null,
      );
    },
    act: (bloc) async {
      // The constructor already auto-dispatched Subscribe; let it (and its
      // loadNext controller-swap) fully process, then emit on the CURRENT
      // controller like the real Firestore query does. A bloc that
      // subscribed before loadNext (the original bug) is attached to the
      // orphaned pre-swap controller and never sees this.
      await pumpEventQueue();
      fakeRepo.emitRooms([_room('r1')]);
    },
    wait: const Duration(milliseconds: 20),
    verify: (bloc) {
      expect(bloc.state.status, ConversationsStatus.loaded);
      expect(bloc.state.rooms.length, 1);
    },
  );
}
