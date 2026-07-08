# Chat Feature — Plan 3b (Rich: receipts, typing, edit/delete, attachments, team inbox, FCM)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Depends on Plan 3a (core) being implemented first.**

**Goal:** Layer the rich chat features onto the 3a core: delivered/read status ticks, typing indicators, message edit/delete, file/image attachments, the team-inbox handled/aggregate UI, the app-bar chat icon (entry #2), and FCM tap-routing + delivered-ack.

**Architecture:** Extends `ChatBloc`/`ChatRoomScreen`/`MessageBubble`/`ConversationsBloc` from 3a. Adds `TypingService` (RTDB) and `StorageRepository` to `ChatBloc`. Pure helpers (status derivation, counterpart read-state selection, FCM payload parsing) are unit-tested; RTDB/FCM/Storage wiring is thin and build-verified (matching the codebase, which does not unit-test those layers).

**Tech Stack:** flutter_bloc 8.x, `chat_repository` (`messageStatus`, `isHandledByTeam`, `TypingService`), `storage_repository`, `file_picker` + `image_picker` (via `AppWidgets.defaultMediaChooserDialog`), `firebase_messaging`. Commands use `fvm`.

### Conventions reused (from 3a + codebase)
- `messageStatus({message, counterpartReadStates})`, `isHandledByTeam(room, companyId)`, `isAwaitingResponse(...)`, `unreadFor(...)` are pure fns exported by `chat_repository`.
- `TypingService.setTyping(roomId, userId, nowMillis)` (throttled), `.typingStream(roomId, clock)`, `.clearTyping(...)`; `shouldSendTyping`/`isActivelyTyping` are pure.
- `MessageRepository.editMessage(messageId, text)` / `.deleteMessage(messageId)`; `ChatRoomRepository.markDelivered/markHandled`.
- Attachments: `AppWidgets.defaultMediaChooserDialog(context) → {'name','bytes'}` (image), `file_picker` for arbitrary files; upload via `StorageRepository().upload(...) → ImageUrl` / `.uploadFile(...) → FileUrl`; folder `chat/{roomId}/{msgId}`.
- `notification_service.dart` seams: `onMessage` (foreground), `onMessageOpenedApp`/`getInitialMessage` (tap), plus a **new** top-level `@pragma('vm:entry-point')` background handler.
- Green bg → black text; `Gap` for spacing (but `SizedBox` in dialog `actions`).

---

### Task 1: Delivered/read status ticks

**Files:**
- Create: `apps/loans/lib/features/chat/chat_status.dart` (pure counterpart-selection helper)
- Modify: `apps/loans/lib/features/chat/widget/message_bubble.dart`
- Modify: `apps/loans/lib/features/chat/screen/chat_room_screen.dart` (pass room + identity into bubbles)
- Test: `apps/loans/test/features/chat/chat_status_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/chat/chat_status.dart';

ChatRoom _room(Map<String, ReadState> reads, List<Participant> parts) =>
    ChatRoom.create(participants: parts, createdBy: 'u1')..reads = reads;

void main() {
  final borrower = Participant(id: 'u1', type: ParticipantType.user);
  final company = Participant(id: 'c1', type: ParticipantType.company);

  test('borrower viewing: counterpart = all staff read states (not mine)', () {
    final room = _room({
      'u1': ReadState(lastReadSeq: 9),
      'staff1': ReadState(lastDeliveredSeq: 3, lastReadSeq: 3),
    }, [borrower, company]);
    final states = counterpartReadStates(room, myUserId: 'u1', myCompanyId: null);
    expect(states.length, 1);
    expect(states.first.lastReadSeq, 3);
  });

  test('staff viewing: counterpart = the borrower read state only', () {
    final room = _room({
      'u1': ReadState(lastDeliveredSeq: 4, lastReadSeq: 4), // borrower
      'staff1': ReadState(lastReadSeq: 9),                  // me
      'staff2': ReadState(lastReadSeq: 9),                  // colleague
    }, [company, borrower]);
    final states =
        counterpartReadStates(room, myUserId: 'staff1', myCompanyId: 'c1');
    expect(states.length, 1);
    expect(states.first.lastReadSeq, 4);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd apps/loans && CI=true fvm flutter test test/features/chat/chat_status_test.dart`
Expected: FAIL — function undefined.

- [ ] **Step 3: Create `chat_status.dart`**

```dart
import 'package:chat_repository/chat_repository.dart';

/// The read states of the *counterpart* side of a room, relative to me.
/// - counterpart is a company  → every reader who isn't me (its staff)
/// - counterpart is a user      → just that user's read state
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
  // company counterpart: everyone who has read except me
  return room.reads.entries
      .where((e) => e.key != myUserId)
      .map((e) => e.value);
}
```

- [ ] **Step 4: Render the tick in `MessageBubble`**

Change `MessageBubble` to accept an optional `MessageStatus? status` and render a small trailing tick for own messages. Replace the class with:
```dart
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:loooans/utils/screen_helpers.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.isMine,
    this.status,
    this.senderLabel,
    super.key,
  });

  final Message message;
  final bool isMine;
  final MessageStatus? status;
  final String? senderLabel;

  @override
  Widget build(BuildContext context) {
    final deleted = message.deletedAt != null;
    final edited = message.editedAt != null && !deleted;
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMine && senderLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(senderLabel!,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            Text(
              deleted ? 'This message was deleted' : (message.text ?? ''),
              style: TextStyle(
                color: isMine ? AppColors.white : AppColors.black,
                fontStyle: deleted ? FontStyle.italic : FontStyle.normal,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (edited)
                  Text('edited',
                      style: TextStyle(
                          fontSize: 10,
                          color: (isMine ? AppColors.white : AppColors.black)
                              .withValues(alpha: 0.6))),
                if (isMine && status != null) ...[
                  const SizedBox(width: 6),
                  _StatusTick(status: status!),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusTick extends StatelessWidget {
  const _StatusTick({required this.status});
  final MessageStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      MessageStatus.sending => (Icons.schedule, AppColors.white),
      MessageStatus.sent => (Icons.check, AppColors.white),
      MessageStatus.delivered => (Icons.done_all, AppColors.white),
      MessageStatus.read => (Icons.done_all, AppColors.blue),
    };
    return Icon(icon, size: 14, color: color.withValues(alpha: 0.9));
  }
}
```

- [ ] **Step 5: Feed status from `ChatRoomScreen`**

In `chat_room_screen.dart`, in the `ListView.builder` itemBuilder, compute status for own messages using the room + `counterpartReadStates`:
```dart
import 'package:loooans/features/chat/chat_status.dart';
// ...
final room = state.room;
final status = (isMine && room != null)
    ? messageStatus(
        message: m,
        counterpartReadStates:
            counterpartReadStates(room, myUserId: myUserId, myCompanyId: myCompanyId),
      )
    : null;
final senderLabel = (!isMine && m.senderParticipantId != myUserId)
    ? room?.participants
        .firstWhere((p) => p.id == m.senderParticipantId,
            orElse: () => room.participants.first)
        .displayName
    : null;
return MessageBubble(message: m, isMine: isMine, status: status, senderLabel: senderLabel);
```
(Import `messageStatus` via `package:chat_repository/chat_repository.dart`, already imported.)

- [ ] **Step 6: Run test + analyze**

Run: `cd apps/loans && CI=true fvm flutter test test/features/chat/chat_status_test.dart && CI=true fvm flutter analyze lib/features/chat`
Expected: PASS + no issues.

- [ ] **Step 7: Commit**

```bash
git add apps/loans/lib/features/chat apps/loans/test/features/chat/chat_status_test.dart
git commit -m "feat(chat): delivered/read status ticks + sender label + edited marker"
```

---

### Task 2: Typing indicators

**Files:**
- Modify: `apps/loans/lib/app/di/repository_providers.dart` (register `TypingService`)
- Modify: `apps/loans/lib/features/chat/bloc/chat_bloc.dart` (+ event/state)
- Modify: `apps/loans/lib/features/chat/screen/chat_room_screen.dart`
- Test: `apps/loans/test/features/chat/chat_typing_test.dart`

- [ ] **Step 1: Register `TypingService`**

In `repository_providers.dart`, add:
```dart
        RepositoryProvider(create: (context) => TypingService()),
```

- [ ] **Step 2: Write the failing bloc test**

```dart
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/chat/bloc/chat_bloc.dart';
import 'package:mocktail/mocktail.dart';

class _MockChatRoomRepo extends Mock implements ChatRoomRepository {}
class _MockMessageRepo extends Mock implements MessageRepository {}
class _MockTyping extends Mock implements TypingService {}
class _MockStorage extends Mock implements StorageRepository {}

void main() {
  test('typing stream updates state.typingUserIds', () async {
    final rooms = _MockChatRoomRepo();
    final messages = _MockMessageRepo();
    final typing = _MockTyping();
    final storage = _MockStorage();
    final typingCtrl = StreamController<List<String>>.broadcast();
    final msgCtrl = StreamController<List<Message>>.broadcast();
    final roomCtrl = StreamController<ChatRoom>.broadcast();

    when(() => messages.dataStream).thenAnswer((_) => msgCtrl.stream);
    when(() => messages.loadNext(reset: any(named: 'reset'))).thenReturn(null);
    when(() => rooms.watchRoom(any())).thenAnswer((_) => roomCtrl.stream);
    when(() => typing.typingStream(roomId: any(named: 'roomId'), clock: any(named: 'clock')))
        .thenAnswer((_) => typingCtrl.stream);

    final bloc = ChatBloc.withDependencies(
      roomId: 'r1', chatRoomRepository: rooms, messageRepository: messages,
      typingService: typing, storageRepository: storage,
      myUserId: 'u1', mySenderParticipantId: 'u1',
    );
    bloc.add(const SubscribeChat());
    await Future<void>.delayed(const Duration(milliseconds: 10));
    typingCtrl.add(['c1']);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(bloc.state.typingUserIds, ['c1']);

    await bloc.close();
    await typingCtrl.close();
    await msgCtrl.close();
    await roomCtrl.close();
  });
}
```

- [ ] **Step 3: Extend `ChatBloc`**

- Add to `chat_state.dart`: field `final List<String> typingUserIds;` (default `const []`), in ctor/copyWith/props.
- Add to `chat_event.dart`:
  ```dart
  final class TypingChanged extends ChatEvent {
    const TypingChanged(this.isTyping);
    final bool isTyping;
    @override
    List<Object?> get props => [isTyping];
  }
  final class _TypingUsersUpdated extends ChatEvent {
    const _TypingUsersUpdated(this.userIds);
    final List<String> userIds;
    @override
    List<Object?> get props => [userIds];
  }
  ```
- In `chat_bloc.dart`:
  - accept `TypingService` + `StorageRepository` in both constructors (default: `context.read<TypingService>()` / `context.read<StorageRepository>()`); add fields `_typing`, `_storage`; import `storage_repository`.
  - add `StreamSubscription<List<String>>? _typingSub;`.
  - in `_wire()`: `on<TypingChanged>(_onTyping); on<_TypingUsersUpdated>((e, emit) => emit(state.copyWith(typingUserIds: e.userIds)));`.
  - in `_onSubscribe`, after wiring message/room subs:
    ```dart
    await _typingSub?.cancel();
    _typingSub = _typing
        .typingStream(
          roomId: _roomId,
          clock: () => DateTime.now().millisecondsSinceEpoch,
        )
        .listen((ids) => add(_TypingUsersUpdated(
              ids.where((id) => id != _myUserId).toList(),
            )));
    ```
  - add the handler:
    ```dart
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
    ```
  - in `close()`: `_typingSub?.cancel();`.

- [ ] **Step 4: Show typing + emit typing from the composer**

In `chat_room_screen.dart`:
- add a `TextField` `onChanged: (v) => context.read<ChatBloc>().add(TypingChanged(v.trim().isNotEmpty))`.
- above the composer, a typing row:
```dart
BlocBuilder<ChatBloc, ChatState>(
  buildWhen: (a, b) => a.typingUserIds != b.typingUserIds,
  builder: (context, state) {
    if (state.typingUserIds.isEmpty) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text('typing…',
            style: TextStyle(color: AppColors.black, fontStyle: FontStyle.italic)),
      ),
    );
  },
),
```

- [ ] **Step 5: Run the test + analyze**

Run: `cd apps/loans && CI=true fvm flutter test test/features/chat/chat_typing_test.dart && CI=true fvm flutter analyze lib/features/chat`
Expected: PASS + no issues. (Update the existing `chat_bloc_test.dart` `withDependencies` calls to pass the new `typingService`/`storageRepository` mocks — set that up in its `setUp`.)

- [ ] **Step 6: Commit**

```bash
git add apps/loans/lib apps/loans/test/features/chat
git commit -m "feat(chat): typing indicators via TypingService (RTDB)"
```

---

### Task 3: Message edit / delete

**Files:**
- Modify: `apps/loans/lib/features/chat/bloc/chat_bloc.dart` (+ events)
- Modify: `apps/loans/lib/features/chat/screen/chat_room_screen.dart` (long-press menu + edit dialog)
- Test: `apps/loans/test/features/chat/chat_edit_delete_test.dart`

- [ ] **Step 1: Write the failing bloc test**

```dart
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/chat/bloc/chat_bloc.dart';
import 'package:mocktail/mocktail.dart';
// reuse the mocks from chat_typing_test via a shared file, or redeclare here.

void main() {
  // ... standard mock setup (rooms, messages, typing, storage, controllers) ...
  // (mirror chat_typing_test's setUp)

  blocTest<ChatBloc, ChatState>(
    'EditMessage calls messageRepository.editMessage',
    build: () => /* build with mocks */ throw UnimplementedError(),
    act: (bloc) => bloc.add(const EditMessage('m1', 'new text')),
    verify: (_) {
      // verify(() => messages.editMessage(messageId: 'm1', text: 'new text')).called(1);
    },
  );
}
```
> This test file mirrors `chat_typing_test.dart`'s mock/controller setup (extract a shared `_chatMocks()` helper into `test/features/chat/_chat_test_helpers.dart` and import it in both). Concretely assert: `when(() => messages.editMessage(messageId: any(named: 'messageId'), text: any(named: 'text'))).thenAnswer((_) async {})` then `verify(...).called(1)`; and the same for `deleteMessage(messageId:)`.

- [ ] **Step 2: Run it to see it fail**

Run: `cd apps/loans && CI=true fvm flutter test test/features/chat/chat_edit_delete_test.dart`
Expected: FAIL — `EditMessage`/`DeleteMessage` undefined.

- [ ] **Step 3: Add events + handlers to `ChatBloc`**

- `chat_event.dart`:
  ```dart
  final class EditMessage extends ChatEvent {
    const EditMessage(this.messageId, this.text);
    final String messageId;
    final String text;
    @override
    List<Object?> get props => [messageId, text];
  }
  final class DeleteMessage extends ChatEvent {
    const DeleteMessage(this.messageId);
    final String messageId;
    @override
    List<Object?> get props => [messageId];
  }
  ```
- `chat_bloc.dart` `_wire()`: `on<EditMessage>(_onEdit); on<DeleteMessage>(_onDelete);` and:
  ```dart
  Future<void> _onEdit(EditMessage event, Emitter<ChatState> emit) async {
    final text = event.text.trim();
    if (text.isEmpty) return;
    try {
      await _messages.editMessage(messageId: event.messageId, text: text);
    } catch (err) {
      _log.severe('edit failed: $err');
      emit(state.copyWith(message: 'Failed to edit'));
    }
  }

  Future<void> _onDelete(DeleteMessage event, Emitter<ChatState> emit) async {
    try {
      await _messages.deleteMessage(messageId: event.messageId);
    } catch (err) {
      _log.severe('delete failed: $err');
      emit(state.copyWith(message: 'Failed to delete'));
    }
  }
  ```

- [ ] **Step 4: Long-press menu + edit dialog in `ChatRoomScreen`**

Wrap own bubbles in a `GestureDetector(onLongPress: () => _showMessageActions(context, m))`. Add:
```dart
Future<void> _showMessageActions(BuildContext context, Message m) async {
  if (m.deletedAt != null) return;
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.type == MessageType.text)
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete'),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  if (action == 'edit') {
    final edited = await _editDialog(context, m.text ?? '');
    if (edited != null && context.mounted) {
      context.read<ChatBloc>().add(EditMessage(m.id, edited));
    }
  } else if (action == 'delete') {
    context.read<ChatBloc>().add(DeleteMessage(m.id));
  }
}

Future<String?> _editDialog(BuildContext context, String initial) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Edit message'),
      content: TextField(controller: ctrl, autofocus: true, maxLines: 4),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8), // Gap fails in OverflowBar actions
        TextButton(
          onPressed: () => Navigator.pop(context, ctrl.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
```
(Only attach the long-press to `isMine` bubbles.)

- [ ] **Step 5: Run test + analyze**

Run: `cd apps/loans && CI=true fvm flutter test test/features/chat/chat_edit_delete_test.dart && CI=true fvm flutter analyze lib/features/chat`
Expected: PASS + no issues.

- [ ] **Step 6: Commit**

```bash
git add apps/loans/lib apps/loans/test/features/chat
git commit -m "feat(chat): message edit/delete (long-press menu + tombstone/edited)"
```

---

### Task 4: Attachments (image + file)

**Files:**
- Modify: `apps/loans/lib/features/chat/bloc/chat_bloc.dart` (+ event, uses `StorageRepository`)
- Modify: `apps/loans/lib/features/chat/screen/chat_room_screen.dart` (attach button)
- Modify: `apps/loans/lib/features/chat/widget/message_bubble.dart` (render image thumb / file chip)
- Test: `apps/loans/test/features/chat/chat_attachment_test.dart`

- [ ] **Step 1: Write the failing bloc test**

Assert that `SendAttachment` uploads then adds a message of the right type with an `Attachment`:
```dart
// setUp mirrors _chat_test_helpers.dart
// when(() => storage.upload(data: any(named:'data'), folder: any(named:'folder'),
//   fileName: any(named:'fileName'), includeOriginal: any(named:'includeOriginal')))
//   .thenAnswer((_) async => ImageUrl(name: 'p.jpg', thumbnail: 'thumb', original: 'orig'));
// when(() => messages.add(data: any(named:'data'))).thenAnswer((i)=> i.namedArguments[#data] as Message);
blocTest<ChatBloc, ChatState>(
  'SendAttachment (image) uploads and sends an image message',
  build: build,
  act: (bloc) => bloc.add(SendImageAttachment(
      fileName: 'p.jpg', bytes: Uint8List.fromList([1, 2, 3]))),
  verify: (_) {
    final sent = verify(() => messages.add(data: captureAny(named: 'data')))
        .captured.single as Message;
    expect(sent.type, MessageType.image);
    expect(sent.attachments.single.thumbnailUrl, 'thumb');
  },
);
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd apps/loans && CI=true fvm flutter test test/features/chat/chat_attachment_test.dart`
Expected: FAIL — event undefined.

- [ ] **Step 3: Add attachment events + handlers to `ChatBloc`**

- `chat_event.dart`:
  ```dart
  final class SendImageAttachment extends ChatEvent {
    const SendImageAttachment({required this.fileName, required this.bytes});
    final String fileName;
    final Uint8List bytes;
    @override
    List<Object?> get props => [fileName, bytes.length];
  }
  final class SendFileAttachment extends ChatEvent {
    const SendFileAttachment({required this.fileName, required this.bytes});
    final String fileName;
    final Uint8List bytes;
    @override
    List<Object?> get props => [fileName, bytes.length];
  }
  ```
  (add `import 'dart:typed_data';` to the bloc part scope via `chat_bloc.dart`.)
- `chat_bloc.dart` handlers — allocate a message id up front so the storage folder matches the doc (use `uuid` already in the app, or the repo's generated id). Simplest: send first with a temp, then upload under the returned id. To keep the folder = the message id, generate a client id via `uuid`:
  ```dart
  import 'package:uuid/uuid.dart';
  // ...
  Future<void> _onSendImage(SendImageAttachment e, Emitter<ChatState> emit) async {
    emit(state.copyWith(sending: true));
    try {
      final msgId = const Uuid().v4();
      final img = await _storage.upload(
        data: e.bytes,
        folder: 'chat/$_roomId/$msgId',
        fileName: e.fileName,
        includeOriginal: true,
      );
      final att = Attachment(
        name: e.fileName,
        url: img.original ?? img.thumbnail ?? '',
        thumbnailUrl: img.thumbnail,
        contentType: 'image/*',
        size: e.bytes.length,
      );
      await _messages.add(
        data: Message.create(
          roomId: _roomId, senderId: _myUserId,
          senderParticipantId: _mySenderParticipantId,
          type: MessageType.image, attachments: [att],
        )..id = msgId,
      );
      emit(state.copyWith(sending: false));
    } catch (err) {
      _log.severe('image send failed: $err');
      emit(state.copyWith(sending: false, message: 'Failed to send image'));
    }
  }

  Future<void> _onSendFile(SendFileAttachment e, Emitter<ChatState> emit) async {
    emit(state.copyWith(sending: true));
    try {
      final msgId = const Uuid().v4();
      final file = await _storage.uploadFile(
        data: e.bytes, folder: 'chat/$_roomId/$msgId', fileName: e.fileName,
      );
      final att = Attachment(
        name: e.fileName, url: file.url ?? '',
        contentType: 'application/octet-stream', size: e.bytes.length,
      );
      await _messages.add(
        data: Message.create(
          roomId: _roomId, senderId: _myUserId,
          senderParticipantId: _mySenderParticipantId,
          type: MessageType.file, attachments: [att],
        )..id = msgId,
      );
      emit(state.copyWith(sending: false));
    } catch (err) {
      _log.severe('file send failed: $err');
      emit(state.copyWith(sending: false, message: 'Failed to send file'));
    }
  }
  ```
  Wire `on<SendImageAttachment>(_onSendImage); on<SendFileAttachment>(_onSendFile);`.
  > Note: `MessageRepository.add` currently assigns its own doc id (Task 9/10, Plan 1). To keep the storage folder aligned with the doc id, either (a) have `add` respect a pre-set non-`NO_ID` id, or (b) upload to `chat/$roomId/$msgId` where `msgId` is the client uuid and set `..id = msgId` before `add` (shown above) — confirm the service uses the model's id when it is not `NO_ID`, else adjust `MessageFirestoreService.add` to honor a pre-set id.

- [ ] **Step 4: Attach button in the composer**

Add an attach `IconButton` left of the text field:
```dart
IconButton(
  icon: const Icon(Icons.attach_file),
  onPressed: () async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo), title: const Text('Photo'),
              onTap: () => Navigator.pop(context, 'photo')),
          ListTile(leading: const Icon(Icons.insert_drive_file), title: const Text('File'),
              onTap: () => Navigator.pop(context, 'file')),
        ]),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'photo') {
      final data = await AppWidgets.defaultMediaChooserDialog(context);
      if (data != null && context.mounted) {
        context.read<ChatBloc>().add(SendImageAttachment(
              fileName: data['name'] as String, bytes: data['bytes'] as Uint8List));
      }
    } else {
      final res = await FilePicker.platform.pickFiles(withData: true);
      final f = res?.files.single;
      if (f?.bytes != null && context.mounted) {
        context.read<ChatBloc>().add(SendFileAttachment(
              fileName: f!.name, bytes: f.bytes!));
      }
    }
  },
),
```
Imports: `package:file_picker/file_picker.dart`, `package:loooans/widgets/app_widgets.dart`, `dart:typed_data`.

- [ ] **Step 5: Render attachments in `MessageBubble`**

When `message.type != text`, render instead of the text:
```dart
if (!deleted && message.type == MessageType.image && message.attachments.isNotEmpty)
  ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Image.network(message.attachments.first.thumbnailUrl ??
        message.attachments.first.url, width: 180, fit: BoxFit.cover),
  )
else if (!deleted && message.type == MessageType.file && message.attachments.isNotEmpty)
  Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.insert_drive_file,
        color: isMine ? AppColors.white : AppColors.black),
    const SizedBox(width: 8),
    Flexible(child: Text(message.attachments.first.name,
        style: TextStyle(color: isMine ? AppColors.white : AppColors.black))),
  ])
else
  Text(/* the existing text branch */),
```
(Refactor the bubble body so text is the `else`.)

- [ ] **Step 6: Run test + analyze**

Run: `cd apps/loans && CI=true fvm flutter test test/features/chat/chat_attachment_test.dart && CI=true fvm flutter analyze lib/features/chat`
Expected: PASS + no issues.

- [ ] **Step 7: Commit**

```bash
git add apps/loans/lib apps/loans/test/features/chat
git commit -m "feat(chat): image + file attachments (pick, upload, render)"
```

---

### Task 5: Team-inbox handled/awaiting UI + staff mark-handled

**Files:**
- Modify: `apps/loans/lib/features/chat/bloc/chat_bloc.dart` (staff read → markHandled)
- Modify: `apps/loans/lib/features/chat/screen/conversations_screen.dart` (awaiting/handled indicator)
- Modify: `apps/loans/lib/features/chat/bloc/conversations_state.dart` (awaiting aggregate)
- Test: `apps/loans/test/features/chat/chat_team_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// bloc test: when I am staff (mySenderParticipantId == companyId), _onMessagesUpdated
// also calls chatRoomRepository.markHandled(roomId, companyId, userId, seq).
blocTest<ChatBloc, ChatState>(
  'staff reading advances team handled watermark',
  build: () => ChatBloc.withDependencies(
    roomId: 'r1', chatRoomRepository: rooms, messageRepository: messages,
    typingService: typing, storageRepository: storage,
    myUserId: 'staff1', mySenderParticipantId: 'c1'),
  act: (bloc) {
    bloc.add(const SubscribeChat());
    msgCtrl.add([Message.create(roomId:'r1', senderId:'u1', senderParticipantId:'u1',
        type: MessageType.text, text:'hi')..seq = 4]);
  },
  wait: const Duration(milliseconds: 20),
  verify: (_) {
    verify(() => rooms.markHandled(
        roomId: 'r1', companyId: 'c1', userId: 'staff1', seq: 4)).called(1);
  },
);
```
(Stub `when(() => rooms.markHandled(...)).thenAnswer((_) async {})`.)

- [ ] **Step 2: Run it to see it fail**

Run: `cd apps/loans && CI=true fvm flutter test test/features/chat/chat_team_test.dart`
Expected: FAIL — no `markHandled` call.

- [ ] **Step 3: Advance team handled in `ChatBloc._onMessagesUpdated`**

After the existing `markRead`, add:
```dart
final iAmStaff = _mySenderParticipantId != _myUserId; // company id != my uid
if (iAmStaff && latestSeq > 0) {
  await _rooms.markHandled(
    roomId: _roomId, companyId: _mySenderParticipantId,
    userId: _myUserId, seq: latestSeq,
  );
}
```

- [ ] **Step 4: Awaiting/handled indicator + aggregate**

- `conversations_state.dart`: add `final String? myCompanyId;` (ctor/copyWith/props) and:
  ```dart
  int get awaitingCount {
    final cid = myCompanyId;
    if (cid == null) return 0;
    return rooms.where((r) => isAwaitingResponse(r, cid)).length;
  }
  ```
  (import `chat_repository`; set `myCompanyId` from `ConversationsBloc` — add it to both constructors' `super(ConversationsState(myUserId:, myCompanyId:))`.)
- `conversations_screen.dart`: in `_ConversationRow`, for staff (when `myCompanyId != null`), show an "Awaiting" pill when `isAwaitingResponse(room, myCompanyId)`:
  ```dart
  if (myCompanyId != null && isAwaitingResponse(room, myCompanyId))
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.ubOrange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8)),
      child: const Text('Awaiting',
          style: TextStyle(fontSize: 10, color: AppColors.ubOrange, fontWeight: FontWeight.w600)),
    ),
  ```
  (Thread `myCompanyId` from state into `_ConversationRow`.) Optionally show `state.awaitingCount` in the AppBar title (`Messages (${state.awaitingCount} awaiting)`), staff only.

- [ ] **Step 5: Run test + analyze**

Run: `cd apps/loans && CI=true fvm flutter test test/features/chat/chat_team_test.dart && CI=true fvm flutter analyze lib/features/chat`
Expected: PASS + no issues.

- [ ] **Step 6: Commit**

```bash
git add apps/loans/lib apps/loans/test/features/chat
git commit -m "feat(chat): team-inbox handled watermark + awaiting indicator/aggregate"
```

---

### Task 6: FCM tap-routing + delivered ack

**Files:**
- Create: `apps/loans/lib/features/chat/chat_push.dart` (pure payload helpers)
- Modify: `apps/loans/lib/services/notification_service.dart` (tap routing + foreground delivered ack)
- Modify: `apps/loans/lib/bootstrap.dart` or `apps/loans/lib/main_*.dart` (background handler registration)
- Test: `apps/loans/test/features/chat/chat_push_test.dart`

- [ ] **Step 1: Write the failing test (pure helpers)**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/chat/chat_push.dart';

void main() {
  test('isChatPush + chatRoomId', () {
    final data = {'notification_type': 'chat', 'room_id': 'r1', 'seq': '5'};
    expect(isChatPush(data), isTrue);
    expect(chatRoomId(data), 'r1');
    expect(chatSeq(data), 5);
    expect(isChatPush({'notification_type': 'payment'}), isFalse);
    expect(chatSeq({'notification_type': 'chat', 'room_id': 'r1'}), 0);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd apps/loans && CI=true fvm flutter test test/features/chat/chat_push_test.dart`
Expected: FAIL — functions undefined.

- [ ] **Step 3: Create `chat_push.dart`**

```dart
bool isChatPush(Map<String, dynamic> data) => data['notification_type'] == 'chat';

String? chatRoomId(Map<String, dynamic> data) => data['room_id'] as String?;

int chatSeq(Map<String, dynamic> data) =>
    int.tryParse('${data['seq'] ?? ''}') ?? 0;
```

- [ ] **Step 4: Route taps + foreground delivered ack in `notification_service.dart`**

- In `onMessageOpenedApp` and `getInitialMessage`, route chat pushes:
  ```dart
  void _handleChatTap(RemoteMessage message) {
    final data = message.data;
    if (!isChatPush(data)) return;
    final roomId = chatRoomId(data);
    if (roomId == null) return;
    GoRouter.of(_context!).go(Paths.chatRoom.replaceFirst(':roomId', roomId));
  }
  ```
  Call it from `getInitialMessage().then((m) { if (m != null) _handleChatTap(m); })` and `onMessageOpenedApp.listen(_handleChatTap)`.
- In the foreground `onMessage` path (via `showFlutterNotification` in `bootstrap.dart`, or add a second `onMessage` listener here), ack delivery:
  ```dart
  FirebaseMessaging.onMessage.listen((message) async {
    if (!isChatPush(message.data)) return;
    final roomId = chatRoomId(message.data);
    final seq = chatSeq(message.data);
    if (roomId == null || seq == 0) return;
    await _context!.read<ChatRoomRepository>().markDelivered(
          roomId: roomId,
          userId: AuthenticationService.instance.user.id,
          seq: seq,
        );
  });
  ```
  (imports: `chat_push.dart`, `Paths`, `go_router`, `chat_repository`.)

- [ ] **Step 5: Background handler (delivered ack while app is closed)**

Add a top-level function (in `bootstrap.dart` or `main_*.dart`, must be top-level + `@pragma('vm:entry-point')`) and register it once at startup:
```dart
@pragma('vm:entry-point')
Future<void> chatBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (message.data['notification_type'] != 'chat') return;
  final roomId = message.data['room_id'] as String?;
  final seq = int.tryParse('${message.data['seq'] ?? ''}') ?? 0;
  if (roomId == null || seq == 0) return;
  // background isolate has no auth context; recover the uid from local storage
  // OR skip the delivered-ack while closed (delivered updates on next open).
}
```
> **Decision for v1:** the background isolate has no `AuthenticationService` / logged-in `uid`. Two honest options — pick one during implementation and note it:
> (a) **Register the handler but no-op the ack** (`FirebaseMessaging.onBackgroundMessage(chatBackgroundHandler)` present, but delivered only advances when the app next opens and the foreground listener/`ChatBloc` runs). Simplest; "delivered" is slightly delayed for closed-app messages.
> (b) **Persist the uid** (e.g. `shared_preferences`) at login and read it in the handler to call `markDelivered` via a fresh `ChatRoomRepository()`. True delivered-while-closed, more moving parts + a new dependency.
> Recommend **(a)** for v1; log a follow-up for (b). Register in `bootstrap.dart` startup: `FirebaseMessaging.onBackgroundMessage(chatBackgroundHandler);`.

- [ ] **Step 6: Run test + analyze + build**

Run: `cd apps/loans && CI=true fvm flutter test test/features/chat/chat_push_test.dart && CI=true fvm flutter analyze`
Expected: PASS + "No issues found!".

- [ ] **Step 7: Commit**

```bash
git add apps/loans/lib apps/loans/test/features/chat
git commit -m "feat(chat): FCM chat tap-routing + delivered ack (foreground; background no-op v1)"
```

---

### Task 7: App-bar chat icon + global unread badge (entry #2)

**Files:**
- Modify: `apps/loans/lib/widgets/app_widgets.dart` + `apps/loans/lib/widgets/layout_widgets.dart` (add `showMessagesButton`)
- Modify: `apps/loans/lib/features/index/screens/home_screen.dart` (pass `showMessagesButton: true`)

- [ ] **Step 1: Add the param to `defaultAppBar`**

In `app_widgets.dart` and the underlying `layout_widgets.dart` `defaultAppBar`, add `bool showMessagesButton = false`. When true, render (before the notification bell) a `BlocBuilder<ConversationsBloc, ConversationsState>` (the providers are ancestors of every shelled screen):
```dart
if (showMessagesButton)
  BlocBuilder<ConversationsBloc, ConversationsState>(
    builder: (context, state) {
      final n = state.totalUnread;
      final button = IconButton(
        tooltip: 'Messages',
        onPressed: () => GoRouter.of(context).go(Paths.chat),
        style: IconButton.styleFrom(
          backgroundColor: AppColors.white, foregroundColor: AppColors.black),
        icon: const Icon(Icons.chat_bubble_outline),
      );
      if (n == 0) return button;
      return Badge(label: Text('$n'), child: button);
    },
  ),
```
Imports in `layout_widgets.dart`: `flutter_bloc`, `conversations_bloc`.

- [ ] **Step 2: Turn it on**

In `home_screen.dart`, pass `showMessagesButton: true` to `AppWidgets.defaultAppBar(...)`.

- [ ] **Step 3: Analyze + build**

Run: `cd apps/loans && CI=true fvm flutter analyze`
Expected: "No issues found!".

- [ ] **Step 4: Commit**

```bash
git add apps/loans/lib/widgets apps/loans/lib/features/index/screens/home_screen.dart
git commit -m "feat(chat): app-bar chat icon with global unread badge"
```

---

### Task 8: Finalize — full app analyze + tests

- [ ] **Step 1: Analyze the whole app**

Run: `cd apps/loans && CI=true fvm flutter analyze`
Expected: "No issues found!".

- [ ] **Step 2: Run the full test suite**

Run: `cd apps/loans && CI=true fvm flutter test`
Expected: all PASS (chat suite + pre-existing tests). Fix any regressions.

- [ ] **Step 3: Commit**

```bash
git add apps/loans
git commit -m "chore(chat): rich features green analyze + tests" || echo "nothing to commit"
```

---

## Self-Review (completed by plan author)

**Spec coverage (rich slice):**
- Delivered/read ticks (sending→sent→delivered→read), sender label, "edited" → Task 1. ✅
- Typing indicators via RTDB `TypingService` (compose + display) → Task 2. ✅
- Edit/delete own messages (menu + dialog + tombstone) → Task 3. ✅
- Attachments: image (thumbnail) + file (chip), pick + upload to `chat/{roomId}/{msgId}` → Task 4. ✅
- Team inbox: staff read advances handled watermark; awaiting/handled indicator + aggregate → Task 5. ✅
- FCM chat tap → `/chat/:roomId`; foreground delivered ack; background handler (no-op v1, flagged) → Task 6. ✅
- App-bar chat icon + global unread badge (entry #2) → Task 7. ✅

**Deviations / decisions flagged:**
- **Background delivered-ack is a no-op in v1** (Task 6, option a) — the background isolate lacks the logged-in uid; delivered advances on next app open. Option (b) (persist uid) is a logged follow-up. This matches spec §12's open item "confirm background Firestore write works."
- **Attachment doc-id alignment** (Task 4 Step 3): messages set a client `uuid` id so the storage folder matches the doc; confirm `MessageFirestoreService.add` honors a pre-set id (else adjust it — small change to Plan 1's Task 10).
- RTDB/FCM/Storage wiring is build-verified only (no unit test), consistent with the app's untested service layer; all decision logic (status, counterpart selection, push parsing, handled advance) is unit-tested.

**Placeholder scan:** Task 3's test stub is intentionally sketched with an extracted `_chat_test_helpers.dart` (the mocks/controllers are identical to Task 2's) — the implementer creates that shared helper first; the concrete `verify(...)` assertions are specified inline.

**Type consistency:** new events (`TypingChanged`/`EditMessage`/`DeleteMessage`/`SendImageAttachment`/`SendFileAttachment`) and state fields (`typingUserIds`, `myCompanyId`, `awaitingCount`) extend the 3a `ChatState`/`ConversationsState` `copyWith` shape; `counterpartReadStates`/`messageStatus`/`isAwaitingResponse`/`markHandled`/`markDelivered`/`editMessage`/`deleteMessage`/`upload`/`uploadFile` are all defined in Plan 1 / 3a / the codebase and referenced consistently. `ChatBloc.withDependencies` now takes `typingService` + `storageRepository` — the 3a `chat_bloc_test.dart` setUp must be updated to pass them (called out in Task 2 Step 5).
