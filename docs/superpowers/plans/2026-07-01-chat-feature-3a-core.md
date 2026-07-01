# Chat Feature — Plan 3a (Core: inbox + text messaging)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the working core of the chat UI in `apps/loans/`: a conversations inbox, a room screen that sends/receives **text** messages in real time, routing/DI wiring, the entry-point buttons, and mark-read — on top of `chat_repository` (Plan 1) and the `message_written` trigger (Plan 2).

**Architecture:** Two BLoCs — `ConversationsBloc` (streams `ChatRoomRepository.dataStream`, computes unread) and `ChatBloc` (per-room; subscribes to the message subcollection stream + a new single-room stream, sends text, marks read). Screens mirror `PaymentCenterScreen`/`loan_details`. Room-scoped `ChatBloc` is provided at the `/chat/:roomId` route; `ConversationsBloc` is a global provider. Adds a `watchRoom(roomId)` single-doc stream to `chat_repository`.

**Tech Stack:** flutter_bloc 8.x, go_router 14, equatable, gap, jiffy, `chat_repository`, `AppWidgets`/`AppColors`. Tests: bloc_test + mocktail + `StreamController` fakes. Commands use `fvm`.

**Deferred to Plan 3b:** delivered/read status ticks, typing indicators, edit/delete UI, attachments, team-inbox handled/aggregate UI, FCM tap-routing + background delivered-ack. **3a hardcodes strings (no l10n — matches the codebase).**

### Conventions baked in (from codebase)
- **State**: `final class XState extends Equatable` — single const ctor + `copyWith` + a `status` enum + `props`. `message` (error) is reset each `copyWith` (not `??`).
- **Event**: `sealed class XEvent extends Equatable`.
- **Bloc**: `XBloc(BuildContext context, {injected...})` reads repos via `context.read<R>()`; add a `XBloc.withDependencies({...})` named ctor for tests. Do **not** touch `AuthenticationService.instance` inside a bloc — inject `authService`.
- **Streaming bloc**: subscribe via `StreamSubscription`s that dispatch internal events; `emit` only inside handlers; cancel in `close()` (model on `AuthenticationBloc`).
- **Nav**: `GoRouter.of(context).go(Paths.chatRoom.replaceFirst(':roomId', roomId))`.
- **Green bg → black text** for empty/loading text; `Gap(N)` for spacing (but `SizedBox` inside dialog `actions`).
- **Timestamps**: `Jiffy.parseFromDateTime(dt).fromNow()`.
- **Avatar**: `AppWidgets.profileIcon(context, avatarOnly: true, avatarDimension: N, user:/company:)` or a `CircleAvatar` with `name.initials`.

---

### Task 1: Add `watchRoom(roomId)` single-room stream to `chat_repository`

`ChatBloc` needs a live stream of one room doc (for room metadata + later read-receipts). This augments Plan 1.

**Files:**
- Modify: `packages/core/chat_repository/lib/src/data/database/chat_room_firestore_service.dart`
- Modify: `packages/core/chat_repository/lib/src/repository/chat_room_repository.dart`
- Test: `packages/core/chat_repository/test/src/watch_room_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// ignore_for_file: prefer_const_constructors
import 'package:chat_repository/chat_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('watchRoom emits the room doc and updates on change', () async {
    final fs = FakeFirebaseFirestore();
    final repo = ChatRoomRepository(firestore: fs);
    final created = await repo.add(
      data: ChatRoom.create(
        participants: [
          Participant(id: 'u1', type: ParticipantType.user),
          Participant(id: 'c1', type: ParticipantType.company),
        ],
        createdBy: 'u1',
      ),
    );

    final emissions = <ChatRoom?>[];
    final sub = repo.watchRoom(created.id).listen(emissions.add);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await repo.markRead(roomId: created.id, userId: 'u1', seq: 2);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await sub.cancel();

    expect(emissions.first!.id, created.id);
    expect(emissions.last!.reads['u1']!.lastReadSeq, 2);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test test/src/watch_room_test.dart`
Expected: FAIL — `watchRoom` undefined.

- [ ] **Step 3: Add `watchRoom` to the service**

Append to `ChatRoomFirestoreService` (in `chat_room_firestore_service.dart`):
```dart
  /// Live stream of a single room document.
  Stream<ChatRoomEntity> watchRoom(String roomId) {
    return root.doc(roomId).snapshots().where((s) => s.exists).map(
          (s) => ChatRoomEntity.fromJson(s.data()! as Map<String, dynamic>),
        );
  }
```

- [ ] **Step 4: Add `watchRoom` to the repository**

Append to `ChatRoomRepository` (in `chat_room_repository.dart`):
```dart
  /// Live stream of a single room, mapped to the model.
  Stream<ChatRoom> watchRoom(String roomId) =>
      _service.watchRoom(roomId).map((e) => e.toChatRoom());
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test test/src/watch_room_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/core/chat_repository
git commit -m "feat(chat_repository): add watchRoom single-room stream"
```

---

### Task 2: Wire the package + DI + routing paths

**Files:**
- Modify: `apps/loans/pubspec.yaml`
- Modify: `apps/loans/lib/app/di/repository_providers.dart`
- Modify: `apps/loans/lib/app/routing/paths.dart`

- [ ] **Step 1: Add the path dependency**

In `apps/loans/pubspec.yaml`, under `dependencies:` (mirror the sibling path-dep form):
```yaml
  chat_repository:
    path: "../../packages/core/chat_repository"
```

- [ ] **Step 2: Resolve**

Run: `cd apps/loans && fvm flutter pub get`
Expected: `Got dependencies!`.

- [ ] **Step 3: Register `ChatRoomRepository`**

In `apps/loans/lib/app/di/repository_providers.dart`, add the import and a provider entry (alongside the others):
```dart
import 'package:chat_repository/chat_repository.dart';
```
```dart
        RepositoryProvider(create: (context) => ChatRoomRepository()),
```
(`MessageRepository` is per-room, so it is **not** registered globally — `ChatBloc` builds it with its `roomId`.)

- [ ] **Step 4: Add the route paths**

In `apps/loans/lib/app/routing/paths.dart`, add to the `Paths` class:
```dart
  static const PathTemplate chat = '/chat';
  static const PathTemplate chatRoom = '/chat/:roomId';
```

- [ ] **Step 5: Verify it still analyzes/builds**

Run: `cd apps/loans && CI=true fvm flutter analyze lib/app`
Expected: no new issues (the providers/paths compile; screens/blocs added next).

- [ ] **Step 6: Commit**

```bash
git add apps/loans/pubspec.yaml apps/loans/lib/app/di/repository_providers.dart apps/loans/lib/app/routing/paths.dart
git commit -m "chore(chat): add chat_repository dep, ChatRoomRepository provider, chat routes"
```

---

### Task 3: `ChatParticipants` builder helper (pure)

Builds the participant set + context anchor for a room from the current user and a counterpart. Pure and unit-tested.

**Files:**
- Create: `apps/loans/lib/features/chat/chat_participants.dart`
- Test: `apps/loans/test/features/chat/chat_participants_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/chat/chat_participants.dart';

void main() {
  test('borrowerToCompany builds [user, company] + context', () {
    final r = ChatParticipants.borrowerToCompany(
      userId: 'u1', userName: 'Bob', userPhotoUrl: null,
      companyId: 'c1', companyName: 'Acme', companyPhotoUrl: 'http://logo',
      contextType: 'product', contextId: 'p1',
    );
    expect(r.participants.map((p) => p.id), ['u1', 'c1']);
    expect(r.participants[0].type, ParticipantType.user);
    expect(r.participants[1].type, ParticipantType.company);
    expect(r.participants[1].displayName, 'Acme');
    expect(r.contextType, 'product');
    expect(r.contextId, 'p1');
  });

  test('staffToBorrower builds [company, user]', () {
    final r = ChatParticipants.staffToBorrower(
      companyId: 'c1', companyName: 'Acme', companyPhotoUrl: null,
      borrowerId: 'u9', borrowerName: 'Jane', borrowerPhotoUrl: null,
      contextType: 'loan', contextId: 'l3',
    );
    expect(r.participants.map((p) => p.id), ['c1', 'u9']);
    expect(r.participants[0].type, ParticipantType.company);
    expect(r.contextId, 'l3');
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd apps/loans && CI=true fvm flutter test test/features/chat/chat_participants_test.dart`
Expected: FAIL — type not defined.

- [ ] **Step 3: Create `chat_participants.dart`**

```dart
import 'package:chat_repository/chat_repository.dart';

/// Immutable result of building a room's participant set + context anchor.
class RoomSeed {
  const RoomSeed({
    required this.participants,
    this.contextType,
    this.contextId,
  });
  final List<Participant> participants;
  final String? contextType;
  final String? contextId;
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
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/loans && CI=true fvm flutter test test/features/chat/chat_participants_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/loans/lib/features/chat/chat_participants.dart apps/loans/test/features/chat/chat_participants_test.dart
git commit -m "feat(chat): add ChatParticipants room-seed builder"
```

---

### Task 4: `ConversationsBloc`

Streams `ChatRoomRepository.dataStream` and exposes rooms + a per-user unread total.

**Files:**
- Create: `apps/loans/lib/features/chat/bloc/conversations_bloc.dart`
- Create: `apps/loans/lib/features/chat/bloc/conversations_event.dart`
- Create: `apps/loans/lib/features/chat/bloc/conversations_state.dart`
- Test: `apps/loans/test/features/chat/conversations_bloc_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/chat/bloc/conversations_bloc.dart';
import 'package:mocktail/mocktail.dart';

class _MockChatRoomRepo extends Mock implements ChatRoomRepository {}

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
    act: (bloc) {
      bloc.add(const SubscribeConversations());
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
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd apps/loans && CI=true fvm flutter test test/features/chat/conversations_bloc_test.dart`
Expected: FAIL — types not defined.

- [ ] **Step 3: Create `conversations_event.dart`**

```dart
part of 'conversations_bloc.dart';

sealed class ConversationsEvent extends Equatable {
  const ConversationsEvent();
  @override
  List<Object?> get props => [];
}

final class SubscribeConversations extends ConversationsEvent {
  const SubscribeConversations();
}

final class _ConversationsUpdated extends ConversationsEvent {
  const _ConversationsUpdated(this.rooms);
  final List<ChatRoom> rooms;
  @override
  List<Object?> get props => [rooms];
}

final class _ConversationsErrored extends ConversationsEvent {
  const _ConversationsErrored(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}
```

- [ ] **Step 4: Create `conversations_state.dart`**

```dart
part of 'conversations_bloc.dart';

enum ConversationsStatus { initial, loading, loaded, error }

final class ConversationsState extends Equatable {
  const ConversationsState({
    this.status = ConversationsStatus.initial,
    this.rooms = const [],
    this.myUserId = '',
    this.message,
  });

  final ConversationsStatus status;
  final List<ChatRoom> rooms;
  final String myUserId;
  final String? message;

  /// Sum of the current user's unread across all rooms.
  int get totalUnread =>
      rooms.fold(0, (sum, r) => sum + unreadFor(r, myUserId));

  ConversationsState copyWith({
    ConversationsStatus? status,
    List<ChatRoom>? rooms,
    String? myUserId,
    String? message,
  }) {
    return ConversationsState(
      status: status ?? this.status,
      rooms: rooms ?? this.rooms,
      myUserId: myUserId ?? this.myUserId,
      message: message,
    );
  }

  @override
  List<Object?> get props => [status, rooms, myUserId, message];
}
```

- [ ] **Step 5: Create `conversations_bloc.dart`**

```dart
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
    on<SubscribeConversations>(_onSubscribe);
    on<_ConversationsUpdated>(
      (e, emit) => emit(state.copyWith(
        status: ConversationsStatus.loaded,
        rooms: e.rooms,
      )),
    );
    on<_ConversationsErrored>(
      (e, emit) => emit(state.copyWith(
        status: ConversationsStatus.error,
        message: e.message,
      )),
    );
  }

  Future<void> _onSubscribe(
    SubscribeConversations event,
    Emitter<ConversationsState> emit,
  ) async {
    emit(state.copyWith(status: ConversationsStatus.loading));
    await _sub?.cancel();
    _sub = _repo.dataStream.listen(
      (rooms) => add(_ConversationsUpdated(rooms)),
      onError: (Object err) {
        _log.severe('conversations stream error: $err');
        add(const _ConversationsErrored('Failed to load conversations'));
      },
    );
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
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd apps/loans && CI=true fvm flutter test test/features/chat/conversations_bloc_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add apps/loans/lib/features/chat/bloc/ apps/loans/test/features/chat/conversations_bloc_test.dart
git commit -m "feat(chat): add ConversationsBloc (inbox stream + unread total)"
```

---

### Task 5: `ConversationsScreen` (inbox)

**Files:**
- Create: `apps/loans/lib/features/chat/screen/conversations_screen.dart`
- Test: `apps/loans/test/features/chat/conversations_screen_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/chat/bloc/conversations_bloc.dart';
import 'package:loooans/features/chat/screen/conversations_screen.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/helpers.dart';

class _MockConversationsBloc
    extends MockBloc<ConversationsEvent, ConversationsState>
    implements ConversationsBloc {}

void main() {
  late ConversationsBloc bloc;
  setUp(() => bloc = _MockConversationsBloc());

  Widget subject() => BlocProvider<ConversationsBloc>.value(
        value: bloc,
        child: const ConversationsScreen(),
      );

  testWidgets('shows empty state when there are no rooms', (tester) async {
    when(() => bloc.state).thenReturn(
      const ConversationsState(status: ConversationsStatus.loaded),
    );
    await tester.pumpApp(subject());
    expect(find.text('No conversations yet'), findsOneWidget);
  });

  testWidgets('lists a conversation with its counterpart name', (tester) async {
    final room = ChatRoom.create(
      participants: [
        Participant(id: 'u1', type: ParticipantType.user, displayName: 'Me'),
        Participant(id: 'c1', type: ParticipantType.company, displayName: 'Acme'),
      ],
      createdBy: 'u1',
    )..id = 'r1';
    when(() => bloc.state).thenReturn(
      ConversationsState(
        status: ConversationsStatus.loaded,
        rooms: [room],
        myUserId: 'u1',
      ),
    );
    await tester.pumpApp(subject());
    expect(find.text('Acme'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd apps/loans && CI=true fvm flutter test test/features/chat/conversations_screen_test.dart`
Expected: FAIL — `ConversationsScreen` undefined.

- [ ] **Step 3: Create `conversations_screen.dart`**

```dart
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:jiffy/jiffy.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/chat/bloc/conversations_bloc.dart';
import 'package:loooans/utils/screen_helpers.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<ConversationsBloc>().add(const SubscribeConversations());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        backgroundColor: AppColors.green1,
        centerTitle: false,
      ),
      body: BlocBuilder<ConversationsBloc, ConversationsState>(
        builder: (context, state) {
          if (state.status == ConversationsStatus.loading && state.rooms.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.rooms.isEmpty) {
            return const Center(
              child: Text(
                'No conversations yet',
                style: TextStyle(color: AppColors.black, fontSize: 16),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: state.rooms.length,
            separatorBuilder: (_, __) => const Gap(8),
            itemBuilder: (context, index) {
              final room = state.rooms[index];
              return _ConversationRow(room: room, myUserId: state.myUserId);
            },
          );
        },
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({required this.room, required this.myUserId});

  final ChatRoom room;
  final String myUserId;

  @override
  Widget build(BuildContext context) {
    final counterpart = room.participants.firstWhere(
      (p) => p.id != myUserId,
      orElse: () => room.participants.first,
    );
    final unread = unreadFor(room, myUserId);
    final preview = room.lastMessage?.text ?? '';
    final time = room.lastMessage == null
        ? ''
        : Jiffy.parseFromDateTime(room.lastMessage!.createdAt).fromNow();

    return Card(
      color: AppColors.white,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.green1,
          child: Text(
            (counterpart.displayName ?? '?').initialsSafe,
            style: const TextStyle(color: AppColors.black),
          ),
        ),
        title: Text(counterpart.displayName ?? 'Conversation'),
        subtitle: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(time, style: const TextStyle(fontSize: 11)),
            if (unread > 0) ...[
              const Gap(4),
              _UnreadBadge(count: unread),
            ],
          ],
        ),
        onTap: () => GoRouter.of(context)
            .go(Paths.chatRoom.replaceFirst(':roomId', room.id)),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.green1_6,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: AppColors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

extension _Initials on String {
  String get initialsSafe {
    final parts = trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/loans && CI=true fvm flutter test test/features/chat/conversations_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/loans/lib/features/chat/screen/conversations_screen.dart apps/loans/test/features/chat/conversations_screen_test.dart
git commit -m "feat(chat): add ConversationsScreen (inbox list with unread badge)"
```

---

### Task 6: `ChatBloc`

Subscribes to the room's message stream + the single-room stream; sends text; marks read.

**Files:**
- Create: `apps/loans/lib/features/chat/bloc/chat_bloc.dart`
- Create: `apps/loans/lib/features/chat/bloc/chat_event.dart`
- Create: `apps/loans/lib/features/chat/bloc/chat_state.dart`
- Test: `apps/loans/test/features/chat/chat_bloc_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/chat/bloc/chat_bloc.dart';
import 'package:mocktail/mocktail.dart';

class _MockChatRoomRepo extends Mock implements ChatRoomRepository {}
class _MockMessageRepo extends Mock implements MessageRepository {}

class _FakeMessage extends Fake implements Message {}

void main() {
  setUpAll(() => registerFallbackValue(_FakeMessage()));

  late _MockChatRoomRepo rooms;
  late _MockMessageRepo messages;
  late StreamController<List<Message>> msgCtrl;
  late StreamController<ChatRoom> roomCtrl;

  setUp(() {
    rooms = _MockChatRoomRepo();
    messages = _MockMessageRepo();
    msgCtrl = StreamController<List<Message>>.broadcast();
    roomCtrl = StreamController<ChatRoom>.broadcast();
    when(() => messages.dataStream).thenAnswer((_) => msgCtrl.stream);
    when(() => messages.loadNext(
          statements: any(named: 'statements'),
          limit: any(named: 'limit'),
          page: any(named: 'page'),
          reset: any(named: 'reset'),
        )).thenReturn(null);
    when(() => rooms.watchRoom(any())).thenAnswer((_) => roomCtrl.stream);
    when(() => rooms.markRead(
          roomId: any(named: 'roomId'),
          userId: any(named: 'userId'),
          seq: any(named: 'seq'),
        )).thenAnswer((_) async {});
    when(() => messages.add(data: any(named: 'data')))
        .thenAnswer((invocation) async =>
            invocation.namedArguments[#data] as Message);
  });

  tearDown(() {
    msgCtrl.close();
    roomCtrl.close();
  });

  ChatBloc build() => ChatBloc.withDependencies(
        roomId: 'r1',
        chatRoomRepository: rooms,
        messageRepository: messages,
        myUserId: 'u1',
        mySenderParticipantId: 'u1',
      );

  blocTest<ChatBloc, ChatState>(
    'subscribe → emits incoming messages',
    build: build,
    act: (bloc) {
      bloc.add(const SubscribeChat());
      msgCtrl.add([
        Message.create(
          roomId: 'r1', senderId: 'c1', senderParticipantId: 'c1',
          type: MessageType.text, text: 'hi',
        )..seq = 1,
      ]);
    },
    wait: const Duration(milliseconds: 20),
    verify: (bloc) {
      expect(bloc.state.status, ChatStatus.loaded);
      expect(bloc.state.messages.single.text, 'hi');
    },
  );

  blocTest<ChatBloc, ChatState>(
    'SendText → calls messageRepository.add with a text message',
    build: build,
    act: (bloc) {
      bloc.add(const SubscribeChat());
      bloc.add(const SendTextMessage('yo'));
    },
    wait: const Duration(milliseconds: 20),
    verify: (_) {
      final captured =
          verify(() => messages.add(data: captureAny(named: 'data'))).captured;
      final sent = captured.single as Message;
      expect(sent.text, 'yo');
      expect(sent.senderParticipantId, 'u1');
      expect(sent.type, MessageType.text);
    },
  );
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd apps/loans && CI=true fvm flutter test test/features/chat/chat_bloc_test.dart`
Expected: FAIL — types not defined.

- [ ] **Step 3: Create `chat_event.dart`**

```dart
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
```

- [ ] **Step 4: Create `chat_state.dart`**

```dart
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
```

- [ ] **Step 5: Create `chat_bloc.dart`**

```dart
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
    required String myUserId,
    required String mySenderParticipantId,
  })  : _roomId = roomId,
        _rooms = chatRoomRepository,
        _messages = messageRepository,
        _myUserId = myUserId,
        _mySenderParticipantId = mySenderParticipantId,
        super(const ChatState()) {
    _wire();
  }

  final String _roomId;
  final ChatRoomRepository _rooms;
  final MessageRepository _messages;
  final String _myUserId;
  final String _mySenderParticipantId;

  StreamSubscription<List<Message>>? _msgSub;
  StreamSubscription<ChatRoom>? _roomSub;

  void _wire() {
    on<SubscribeChat>(_onSubscribe);
    on<SendTextMessage>(_onSendText);
    on<MarkRoomRead>(_onMarkRead);
    on<_MessagesUpdated>(_onMessagesUpdated);
    on<_RoomUpdated>((e, emit) => emit(state.copyWith(room: e.room)));
    on<_ChatErrored>(
      (e, emit) => emit(state.copyWith(status: ChatStatus.error, message: e.message)),
    );
  }

  Future<void> _onSubscribe(SubscribeChat event, Emitter<ChatState> emit) async {
    emit(state.copyWith(status: ChatStatus.loading));
    await _msgSub?.cancel();
    await _roomSub?.cancel();
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
    _messages.loadNext(reset: true);
  }

  Future<void> _onMessagesUpdated(
    _MessagesUpdated event,
    Emitter<ChatState> emit,
  ) async {
    emit(state.copyWith(status: ChatStatus.loaded, messages: event.messages));
    // messages come newest-first (ordered by created_at desc)
    final latestSeq = event.messages
        .map((m) => m.seq ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    if (latestSeq > 0) {
      await _rooms.markRead(roomId: _roomId, userId: _myUserId, seq: latestSeq);
    }
  }

  Future<void> _onSendText(SendTextMessage event, Emitter<ChatState> emit) async {
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

  Future<void> _onMarkRead(MarkRoomRead event, Emitter<ChatState> emit) async {
    final latestSeq = state.messages
        .map((m) => m.seq ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    if (latestSeq > 0) {
      await _rooms.markRead(roomId: _roomId, userId: _myUserId, seq: latestSeq);
    }
  }

  @override
  Future<void> close() {
    _msgSub?.cancel();
    _roomSub?.cancel();
    return super.close();
  }
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd apps/loans && CI=true fvm flutter test test/features/chat/chat_bloc_test.dart`
Expected: PASS (both tests).

- [ ] **Step 7: Commit**

```bash
git add apps/loans/lib/features/chat/bloc/chat_bloc.dart apps/loans/lib/features/chat/bloc/chat_event.dart apps/loans/lib/features/chat/bloc/chat_state.dart apps/loans/test/features/chat/chat_bloc_test.dart
git commit -m "feat(chat): add ChatBloc (message+room streams, send text, mark read)"
```

---

### Task 7: `ChatRoomScreen`

Reversed message list + a text composer.

**Files:**
- Create: `apps/loans/lib/features/chat/screen/chat_room_screen.dart`
- Create: `apps/loans/lib/features/chat/widget/message_bubble.dart`
- Test: `apps/loans/test/features/chat/chat_room_screen_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/chat/bloc/chat_bloc.dart';
import 'package:loooans/features/chat/screen/chat_room_screen.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/helpers.dart';

class _MockChatBloc extends MockBloc<ChatEvent, ChatState> implements ChatBloc {}

void main() {
  late ChatBloc bloc;
  setUp(() => bloc = _MockChatBloc());

  Widget subject() => BlocProvider<ChatBloc>.value(
        value: bloc,
        child: const ChatRoomScreen(roomId: 'r1'),
      );

  testWidgets('renders messages and a composer', (tester) async {
    when(() => bloc.state).thenReturn(
      ChatState(
        status: ChatStatus.loaded,
        messages: [
          Message.create(
            roomId: 'r1', senderId: 'c1', senderParticipantId: 'c1',
            type: MessageType.text, text: 'hello there',
          )..seq = 1,
        ],
      ),
    );
    await tester.pumpApp(subject());
    expect(find.text('hello there'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd apps/loans && CI=true fvm flutter test test/features/chat/chat_room_screen_test.dart`
Expected: FAIL — screen undefined.

- [ ] **Step 3: Create `message_bubble.dart`**

```dart
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:loooans/utils/screen_helpers.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({required this.message, required this.isMine, super.key});

  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final deleted = message.deletedAt != null;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: isMine ? AppColors.lightBlack : AppColors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          deleted ? 'This message was deleted' : (message.text ?? ''),
          style: TextStyle(
            color: isMine ? AppColors.white : AppColors.black,
            fontStyle: deleted ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Create `chat_room_screen.dart`**

```dart
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/features/chat/bloc/chat_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/features/chat/widget/message_bubble.dart';

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({required this.roomId, super.key});
  final String roomId;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<ChatBloc>().add(const SubscribeChat());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    context.read<ChatBloc>().add(SendTextMessage(text));
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final myUserId = AuthenticationService.instance.user.id;
    final myCompanyId = AuthenticationService.instance.user.companyId;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.green1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => GoRouter.of(context).go('/'),
        ),
        title: BlocBuilder<ChatBloc, ChatState>(
          buildWhen: (a, b) => a.room != b.room,
          builder: (context, state) {
            final counterpart = state.room?.participants
                .where((p) => p.id != myUserId && p.id != myCompanyId)
                .map((p) => p.displayName)
                .firstOrNull;
            return Text(counterpart ?? 'Conversation');
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: BlocBuilder<ChatBloc, ChatState>(
              builder: (context, state) {
                if (state.status == ChatStatus.loading && state.messages.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state.messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'Say hello 👋',
                      style: TextStyle(color: AppColors.black, fontSize: 16),
                    ),
                  );
                }
                // messages are newest-first; reverse:true renders newest at bottom
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: state.messages.length,
                  itemBuilder: (context, index) {
                    final m = state.messages[index];
                    final isMine = m.senderParticipantId == myUserId ||
                        m.senderParticipantId == myCompanyId;
                    return MessageBubble(message: m, isMine: isMine);
                  },
                );
              },
            ),
          ),
          _composer(),
        ],
      ),
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Message',
                  filled: true,
                  fillColor: AppColors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const Gap(8),
            IconButton.filled(
              onPressed: _send,
              style: IconButton.styleFrom(backgroundColor: AppColors.lightBlack),
              icon: const Icon(Icons.send, color: AppColors.white),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd apps/loans && CI=true fvm flutter test test/features/chat/chat_room_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/loans/lib/features/chat/screen/chat_room_screen.dart apps/loans/lib/features/chat/widget/message_bubble.dart apps/loans/test/features/chat/chat_room_screen_test.dart
git commit -m "feat(chat): add ChatRoomScreen (reversed list + composer) and MessageBubble"
```

---

### Task 8: Routes + global bloc provider + side-menu + entry points

**Files:**
- Modify: `apps/loans/lib/app/routing/router.dart`
- Modify: `apps/loans/lib/app/di/bloc_providers.dart`
- Modify: `apps/loans/lib/utils/constants.dart`
- Modify: `apps/loans/lib/features/products/screen/loan_offer_detail.dart`
- Modify: `apps/loans/lib/features/loans/screens/loan_details.dart`
- Modify: `apps/loans/lib/features/users/widget/client_detail/client_detail_action_buttons.dart`

- [ ] **Step 1: Register `ConversationsBloc` globally**

In `apps/loans/lib/app/di/bloc_providers.dart`, add the import and provider:
```dart
import 'package:loooans/features/chat/bloc/conversations_bloc.dart';
```
```dart
        BlocProvider(create: ConversationsBloc.new),
```

- [ ] **Step 2: Add the routes**

In `apps/loans/lib/app/routing/router.dart`:
- add imports for `ConversationsScreen`, `ChatRoomScreen`, `ChatBloc`;
- add `/chat` **inside** the `ShellRoute.routes` list (so it gets the HomeScreen shell):
```dart
    GoRoute(
      path: Paths.chat,
      builder: (context, state) => const ConversationsScreen(),
    ),
```
- add `/chat/:roomId` at **top level** (a full-screen route, outside the shell), providing the room-scoped bloc:
```dart
    GoRoute(
      path: Paths.chatRoom,
      builder: (context, state) {
        final roomId = state.pathParameters['roomId']!;
        return BlocProvider(
          create: (ctx) => ChatBloc(ctx, roomId: roomId),
          child: ChatRoomScreen(roomId: roomId),
        );
      },
    ),
```

- [ ] **Step 3: Add the side-menu "Messages" item**

In `apps/loans/lib/utils/constants.dart`, add to the `allMenu` list (visible to all roles):
```dart
      const MenuModel(
        title: 'Messages',
        logoPath: 'svg/user.svg',
        redirectPath: Paths.chat,
      ),
```
(Reuse an existing SVG asset — `svg/user.svg` — since there is no chat icon asset; a dedicated icon can come later.)

- [ ] **Step 4: Add "Message lender" to `loan_offer_detail.dart`**

Below the existing `_applyButton(context)` in the build column, add an outlined button. Insert a helper and call it after `_applyButton`:
```dart
Widget _messageLenderButton(BuildContext context) {
  return SizedBox(
    width: double.infinity,
    child: AppWidgets.defaultOutlinedButton(
      child: const Text('Message lender'),
      onPressed: () => _openLenderChat(context),
    ),
  );
}

Future<void> _openLenderChat(BuildContext context) async {
  final me = AuthenticationService.instance.user;
  final seed = ChatParticipants.borrowerToCompany(
    userId: me.id,
    userName: me.completeNameWesternOrder,
    userPhotoUrl: me.profilePhotoUrl?.url,
    companyId: productView.companyId,
    companyName: productView.companyName,
    companyPhotoUrl: productView.companyProfilePhotoUrl?.url,
    contextType: 'product',
    contextId: productView.productId,
  );
  final room = await context.read<ChatRoomRepository>().findOrCreate(
        participants: seed.participants,
        createdBy: me.id,
        contextType: seed.contextType,
        contextId: seed.contextId,
      );
  if (!context.mounted) return;
  GoRouter.of(context).go(Paths.chatRoom.replaceFirst(':roomId', room.id));
}
```
Add imports at the top of the file: `chat_repository`, `ChatParticipants`, `AuthenticationService`, `ChatRoomRepository` (via `flutter_bloc` `context.read`), `Paths`, `go_router`. Add the `_messageLenderButton(context)` widget into the button column next to `_applyButton`.

> Confirm the exact field names on `productView` (`companyId`, `companyName`, `companyProfilePhotoUrl`, `productId`) against `ProductView`; adjust if the getters differ.

- [ ] **Step 5: Add "Message lender" to `loan_details.dart`**

Mirror Step 4 using `userLoanView.companyId` / `userLoanView.companyName` / `loan.id` as the `loan` context anchor, placing an `AppWidgets.defaultOutlinedButton('Message lender')` near the existing action buttons (e.g. beside the Review/Pay buttons). Use `contextType: 'loan', contextId: <loan.id>`.

- [ ] **Step 6: Add "Message borrower" to `client_detail_action_buttons.dart`**

Add an `Expanded(child: AppWidgets.defaultOutlinedButton(child: const Text('Message borrower'), onPressed: ...))` to the button `Row`, using `ChatParticipants.staffToBorrower(...)` with the current user's `company` and `userId` (the borrower). Anchor with the selected loan: `contextType: 'loan', contextId: context.read<LoansBloc>().selectedLoan.id`.

- [ ] **Step 7: Analyze + build**

Run: `cd apps/loans && CI=true fvm flutter analyze`
Expected: "No issues found!" (fix any missing imports surfaced).

- [ ] **Step 8: Run the whole chat test suite**

Run: `cd apps/loans && CI=true fvm flutter test test/features/chat/`
Expected: all PASS.

- [ ] **Step 9: Commit**

```bash
git add apps/loans/lib/app apps/loans/lib/utils/constants.dart apps/loans/lib/features/products apps/loans/lib/features/loans apps/loans/lib/features/users
git commit -m "feat(chat): routes, ConversationsBloc provider, Messages menu, entry-point buttons"
```

---

## Self-Review (completed by plan author)

**Spec coverage (3a slice):**
- Inbox `array-contains-any [userId, companyId]`, ordered recency, per-user unread total → Tasks 4/5. ✅
- Room screen: reversed message list, text composer, send → Tasks 6/7. ✅
- Mark read on message update → Task 6 (`_onMessagesUpdated` → `markRead`). ✅
- Dedup room create on entry → Task 3 (`ChatParticipants`) + Task 8 (`findOrCreate`). ✅
- Routing `/chat` (shell) + `/chat/:roomId` (room-scoped bloc) → Task 8. ✅
- Entry points #1 (menu), #3/#4/#5 (detail buttons) → Task 8. ✅
- Single-room live stream (needed for room metadata / later receipts) → Task 1 (`watchRoom`). ✅

**Deferred to 3b (called out, not silently dropped):** app-bar chat icon + global badge (entry #2), status ticks/receipts, typing, edit/delete UI, attachments, team handled/aggregate UI, FCM tap-routing + background delivered-ack.

**Placeholder scan:** none — full code in every step. Steps 4–6 of Task 8 reference real screen fields (`productView.companyId`, `userLoanView.companyId`, `LoansBloc.selectedLoan.id`) surfaced by the UI-conventions pass; each carries a "confirm the getter names" note since those screens weren't quoted field-by-field.

**Type consistency:** `ConversationsBloc`(+`withDependencies`), `ChatBloc`(+`withDependencies`), events (`SubscribeConversations`/`SubscribeChat`/`SendTextMessage`/`MarkRoomRead`), states (`ConversationsState`/`ChatState` with `copyWith`+`status`), `ChatParticipants`/`RoomSeed`, `watchRoom`, `unreadFor` (from chat_repository), and `Paths.chat`/`Paths.chatRoom` are defined once and referenced consistently. `MessageRepository(roomId:)` is built inside `ChatBloc` (not a global provider) because it is room-scoped.

**Net-new test infra introduced:** `StreamController` fakes for `dataStream`/`watchRoom` (`when(() => repo.dataStream).thenAnswer((_) => controller.stream)`) + `MockBloc` widget tests — the app had neither for streams.
