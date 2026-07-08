# chat_repository Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `packages/core/chat_repository`, the Dart data layer for the chat/messaging feature — models, entities, Firestore services (rooms + messages subcollection), an RTDB typing service, and repositories — with pure-logic + service tests.

**Architecture:** Mirrors the existing `notification_repository` conventions (Very Good CLI layout, `@JsonSerializable` entity/model split, `BaseFirestoreService` collection-prefixing, `BaseRepository` wrappers). Two deviations, both justified in the spec: (1) `MessageFirestoreService` overrides `root` to a `chat_rooms/{roomId}/messages` subcollection; (2) `BaseFirestoreService` is made injectable so the Firestore services can be unit-tested with `fake_cloud_firestore`. All non-trivial logic (unread/handled math, message-status derivation, room dedup, `member_ids`) lives in pure functions under `lib/src/logic/`.

**Tech Stack:** Dart/Flutter, `json_annotation` + `json_serializable` (build_runner codegen), `cloud_firestore`, `firebase_database`, `fake_cloud_firestore` (tests), `mocktail`, `very_good_analysis`. Commands use `fvm` (never bare `flutter`).

**Spec:** `docs/superpowers/specs/2026-07-01-chat-messaging-design.md` (Rev 3). **Deferred backlog:** anatechopc/loooans#138.

**Conventions reference (from the codebase):**
- Dates: `int64` millis. On a `DateTime` field use `@JsonKey(name: '<snake>', toJson: handleDateTimeToJson, fromJson: handleDateTimeFromJson)` (non-null) or `fromJson: handleDateTimeNullableFromJson` (nullable). Helpers live in `loooans_helpers/data_helpers.dart`. `handleDateTimeToJson` returns `millisecondsSinceEpoch`; the `fromJson` helpers read either an int or a Firestore `Timestamp`.
- Entities: `@JsonSerializable()`, `implements BaseEntity`, re-declare `id`/`createdAt`/`updatedAt`/`deletedAt` with `@override` + `@JsonKey`, `snake_case` `@JsonKey(name:)` on every field, `props`, `bool? get stringify => true`, `fromJson` factory + `toJson()` via `_$...`, and a `toModel()` mapper.
- Models: `extends <Entity> implements BaseModel<Entity>`, `factory X.create(...)` sets `id = NO_ID` and `createdAt == updatedAt == DateTime.timestamp()`, `toEntity() => this`.
- Enums: plain Dart enums (trailing `;`); on entity fields use `@JsonKey(unknownEnumValue: <Enum>.<default>)` for values read from server data.
- Barrel exports models/enums/repositories only (NOT entities or services).
- Constants: `NO_ID = 'no-id'`, `defaultDataLimit = 10`, `timeoutDuration = Duration(seconds: 60)`.

**Per-task loop:** every task ends by running `cd packages/core/chat_repository && CI=true fvm flutter test` (or the named test) and committing. After any task that adds/changes a `part 'X.g.dart'` file, run build_runner (shown inline) before the test.

---

### Task 1: Package scaffold

**Files:**
- Create: `packages/core/chat_repository/pubspec.yaml`
- Create: `packages/core/chat_repository/analysis_options.yaml`
- Create: `packages/core/chat_repository/README.md`
- Create: `packages/core/chat_repository/.gitignore`
- Create: `packages/core/chat_repository/lib/chat_repository.dart` (barrel, exports added per task)
- Create: `packages/core/chat_repository/test/src/chat_repository_test.dart`

- [ ] **Step 1: Write `pubspec.yaml`**

```yaml
name: chat_repository
description: Chat/messaging data layer (rooms, messages, typing) for finstack.
version: 0.1.0+1
publish_to: none

environment:
  sdk: ">=3.0.0 <4.0.0"
  flutter: 3.10.0

dependencies:
  cloud_firestore: ^5.4.1
  firebase_core: ^3.4.1
  firebase_database: ^11.1.2
  flutter:
    sdk: flutter
  json_annotation: ^4.8.1
  loooans_helpers:
    path: "../loooans_helpers"

dev_dependencies:
  build_runner: ^2.4.4
  fake_cloud_firestore: ^3.0.3
  flutter_test:
    sdk: flutter
  json_serializable: ^6.7.0
  mocktail: ^1.0.3
  very_good_analysis: ^6.0.0
```

- [ ] **Step 2: Write `analysis_options.yaml`** (verbatim from the sibling packages)

```yaml
include: package:very_good_analysis/analysis_options.5.0.0.yaml
analyzer:
  exclude:
    - "**/*.g.dart"
    - "**/*.gr.dart"
    - "**/*.freezed.dart"
  errors:
    must_be_immutable: ignore
    public_member_api_docs: ignore
    eol_at_end_of_file: ignore
    lines_longer_than_80_chars: ignore
linter:
  rules:
    lines_longer_than_80_chars: false
```

- [ ] **Step 3: Write `README.md` and `.gitignore`**

`README.md`:
```markdown
# chat_repository

Data layer for chat/messaging: rooms, messages (subcollection), typing (RTDB).
See `docs/superpowers/specs/2026-07-01-chat-messaging-design.md`.
```

`.gitignore` (copy from `packages/core/notification_repository/.gitignore`):
```
.dart_tool/
.packages
build/
pubspec.lock
coverage/
```

- [ ] **Step 4: Write the barrel `lib/chat_repository.dart`** (exports filled in as tasks land; start minimal so pub get works)

```dart
/// Chat/messaging data layer.
library chat_repository;
// Exports are added by later tasks.
```

- [ ] **Step 5: Write the placeholder test `test/src/chat_repository_test.dart`**

```dart
// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chat_repository', () {
    test('package loads', () {
      expect(true, isTrue);
    });
  });
}
```

- [ ] **Step 6: Resolve dependencies**

Run: `cd packages/core/chat_repository && fvm flutter pub get`
Expected: `Got dependencies!` (no version-solve errors). If `fake_cloud_firestore: ^3.0.3` fails to resolve against the pinned `cloud_firestore: ^5.4.1`, run `fvm flutter pub add dev:fake_cloud_firestore` and record the version it picks.

- [ ] **Step 7: Run the placeholder test**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test`
Expected: PASS (1 test).

- [ ] **Step 8: Commit**

```bash
git add packages/core/chat_repository
git commit -m "chore(chat_repository): scaffold package"
```

---

### Task 2: Make `BaseFirestoreService` injectable + expose collection prefix

Backward-compatible refactor in the shared helper so chat's Firestore services can be unit-tested with a fake, and so the messages subcollection can reuse the env prefix. Existing subclasses (no constructor args) are unaffected.

**Files:**
- Modify: `packages/core/loooans_helpers/lib/src/data_helpers/database/base_firestore_service.dart`
- Modify: `packages/core/loooans_helpers/pubspec.yaml` (add `fake_cloud_firestore` dev dep)
- Test: `packages/core/loooans_helpers/test/base_firestore_service_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// ignore_for_file: prefer_const_constructors
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans_helpers/data_helpers.dart';

class _Entity implements BaseEntity {
  @override
  String id = '';
  @override
  late final DateTime createdAt;
  @override
  late DateTime updatedAt;
  @override
  DateTime? deletedAt;
  @override
  List<Object?> get props => [id];
  @override
  bool? get stringify => true;
}

class _Service extends BaseFirestoreService<_Entity> {
  _Service({super.firestore});
  @override
  String get collectionName => 'things';
  @override
  Future<_Entity> get({required String id, bool isCache = false}) async => _Entity();
  @override
  void loadNext({List<QueryStatement>? statements, int? limit = defaultDataLimit, int? page, bool reset = false}) {}
}

void main() {
  test('root uses the injected firestore and dev_ prefix by default', () async {
    final fake = FakeFirebaseFirestore();
    final service = _Service(firestore: fake);
    expect(service.collectionPrefix, 'dev_');
    await service.root.doc('a').set({'x': 1});
    final snap = await fake.collection('dev_things').doc('a').get();
    expect(snap.exists, isTrue);
    expect(snap.data()!['x'], 1);
  });
}
```

- [ ] **Step 2: Add `fake_cloud_firestore` to loooans_helpers dev deps and run the test to see it fail**

Add under `dev_dependencies:` in `packages/core/loooans_helpers/pubspec.yaml`:
```yaml
  fake_cloud_firestore: ^3.0.3
```
Run: `cd packages/core/loooans_helpers && fvm flutter pub get && CI=true fvm flutter test test/base_firestore_service_test.dart`
Expected: FAIL — `_Service({super.firestore})` won't compile (no such super param) / `collectionPrefix` undefined.

- [ ] **Step 3: Refactor `base_firestore_service.dart`**

Replace the field + `root` getter. Full new file:
```dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:loooans_helpers/loooans_helpers.dart';

/// Base class for all firestore access
abstract class BaseFirestoreService<T extends BaseEntity>
    extends BaseDatabaseService<T> {
  BaseFirestoreService({FirebaseFirestore? firestore})
      : fs = firestore ?? FirebaseFirestore.instance;

  /// A flag which switches to a stream when calling load().
  bool switchStream = false;

  StreamController<List<T>> controller = StreamController.broadcast();

  Stream<List<T>> get dataStream => controller.stream;

  /// the last document snapshot the query was getting (pagination).
  DocumentSnapshot? lastDocumentSnapshot;

  /// Firestore instance; overridable for tests via the constructor.
  final FirebaseFirestore fs;

  /// env-based collection prefix: `dev_`, `stg_`, or '' (production).
  String get collectionPrefix {
    if (const String.fromEnvironment('ENVIRONMENT') ==
        Environments.staging.name) {
      return 'stg_';
    } else if (const String.fromEnvironment('ENVIRONMENT') ==
        Environments.production.name) {
      return '';
    }
    return 'dev_';
  }

  CollectionReference get root => fs.collection('$collectionPrefix$collectionName');

  /// name of the collection or table
  String get collectionName;

  @override
  Future<T> get({required String id, bool isCache = false});

  void loadNext({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  });

  void resetStreamController() {
    controller = StreamController.broadcast();
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/core/loooans_helpers && CI=true fvm flutter test test/base_firestore_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify no existing subclass broke**

Run: `cd packages/core/notification_repository && fvm flutter pub get && CI=true fvm flutter analyze`
Expected: analyze passes (existing `NotificationFirestoreService()` still compiles — its implicit `super()` resolves to the all-optional constructor).

- [ ] **Step 6: Commit**

```bash
git add packages/core/loooans_helpers
git commit -m "refactor(helpers): make BaseFirestoreService firestore injectable + expose collectionPrefix"
```

---

### Task 3: Enums

**Files:**
- Create: `packages/core/chat_repository/lib/src/model/participant_type.dart`
- Create: `packages/core/chat_repository/lib/src/model/message_type.dart`
- Create: `packages/core/chat_repository/lib/src/model/message_status.dart`
- Modify: `packages/core/chat_repository/lib/chat_repository.dart`
- Test: `packages/core/chat_repository/test/src/enums_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// ignore_for_file: prefer_const_constructors
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enum names are stable (used as JSON values)', () {
    expect(ParticipantType.values.map((e) => e.name), ['user', 'company']);
    expect(MessageType.values.map((e) => e.name), ['text', 'image', 'file']);
    expect(MessageStatus.values.map((e) => e.name),
        ['sending', 'sent', 'delivered', 'read']);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test test/src/enums_test.dart`
Expected: FAIL — types not defined.

- [ ] **Step 3: Create the enums**

`participant_type.dart`:
```dart
/// Whether a room participant is an individual user or a company.
enum ParticipantType { user, company; }
```
`message_type.dart`:
```dart
/// Kind of message content.
enum MessageType { text, image, file; }
```
`message_status.dart`:
```dart
/// Delivery/read status of an outgoing message, derived in the UI.
enum MessageStatus { sending, sent, delivered, read; }
```

- [ ] **Step 4: Export them from the barrel**

Add to `lib/chat_repository.dart`:
```dart
export 'src/model/message_status.dart';
export 'src/model/message_type.dart';
export 'src/model/participant_type.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test test/src/enums_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/core/chat_repository
git commit -m "feat(chat_repository): add ParticipantType, MessageType, MessageStatus enums"
```

---

### Task 4: `Attachment` and `Participant` value objects

Plain `@JsonSerializable` value objects (no `BaseEntity` — they carry no id/dates).

**Files:**
- Create: `packages/core/chat_repository/lib/src/model/attachment.dart`
- Create: `packages/core/chat_repository/lib/src/model/participant.dart`
- Modify: `packages/core/chat_repository/lib/chat_repository.dart`
- Test: `packages/core/chat_repository/test/src/attachment_participant_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// ignore_for_file: prefer_const_constructors
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Attachment round-trips with snake_case keys', () {
    final a = Attachment(
      name: 'receipt.pdf',
      url: 'https://x/receipt.pdf',
      contentType: 'application/pdf',
      size: 1024,
      thumbnailUrl: null,
    );
    final json = a.toJson();
    expect(json['content_type'], 'application/pdf');
    expect(json['thumbnail_url'], isNull);
    final back = Attachment.fromJson(json);
    expect(back.name, 'receipt.pdf');
    expect(back.size, 1024);
  });

  test('Participant round-trips and defaults unknown type to user', () {
    final p = Participant(
      id: 'c1',
      type: ParticipantType.company,
      displayName: 'Acme',
      photoUrl: null,
    );
    final json = p.toJson();
    expect(json['type'], 'company');
    expect(json['display_name'], 'Acme');
    final back = Participant.fromJson(json);
    expect(back.type, ParticipantType.company);

    final unknown = Participant.fromJson({'id': 'x', 'type': 'alien'});
    expect(unknown.type, ParticipantType.user);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test test/src/attachment_participant_test.dart`
Expected: FAIL — types not defined.

- [ ] **Step 3: Create `attachment.dart`**

```dart
import 'package:json_annotation/json_annotation.dart';

part 'attachment.g.dart';

@JsonSerializable()
class Attachment {
  Attachment({
    required this.name,
    required this.url,
    required this.contentType,
    required this.size,
    this.thumbnailUrl,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) =>
      _$AttachmentFromJson(json);

  final String name;
  final String url;

  @JsonKey(name: 'thumbnail_url')
  final String? thumbnailUrl;

  @JsonKey(name: 'content_type')
  final String contentType;

  final int size;

  Map<String, dynamic> toJson() => _$AttachmentToJson(this);
}
```

- [ ] **Step 4: Create `participant.dart`**

```dart
import 'package:chat_repository/src/model/participant_type.dart';
import 'package:json_annotation/json_annotation.dart';

part 'participant.g.dart';

@JsonSerializable()
class Participant {
  Participant({
    required this.id,
    required this.type,
    this.displayName,
    this.photoUrl,
  });

  factory Participant.fromJson(Map<String, dynamic> json) =>
      _$ParticipantFromJson(json);

  final String id;

  @JsonKey(unknownEnumValue: ParticipantType.user)
  final ParticipantType type;

  @JsonKey(name: 'display_name')
  final String? displayName;

  @JsonKey(name: 'photo_url')
  final String? photoUrl;

  Map<String, dynamic> toJson() => _$ParticipantToJson(this);
}
```

- [ ] **Step 5: Export from the barrel**

Add to `lib/chat_repository.dart`:
```dart
export 'src/model/attachment.dart';
export 'src/model/participant.dart';
```

- [ ] **Step 6: Generate code**

Run: `cd packages/core/chat_repository && fvm flutter pub run build_runner build --delete-conflicting-outputs`
Expected: creates `attachment.g.dart`, `participant.g.dart`; "Succeeded".

- [ ] **Step 7: Run the test to verify it passes**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test test/src/attachment_participant_test.dart`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add packages/core/chat_repository
git commit -m "feat(chat_repository): add Attachment and Participant value objects"
```

---

### Task 5: `ReadState`, `TeamReadState`, `LastMessage` value objects

**Files:**
- Create: `packages/core/chat_repository/lib/src/model/read_state.dart`
- Create: `packages/core/chat_repository/lib/src/model/team_read_state.dart`
- Create: `packages/core/chat_repository/lib/src/model/last_message.dart`
- Modify: `packages/core/chat_repository/lib/chat_repository.dart`
- Test: `packages/core/chat_repository/test/src/value_objects_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// ignore_for_file: prefer_const_constructors
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ReadState round-trips; seqs default to 0; dates are int millis', () {
    final at = DateTime.utc(2026, 7, 1, 9);
    final r = ReadState(
      lastDeliveredSeq: 5,
      lastReadSeq: 3,
      lastDeliveredAt: at,
      lastReadAt: at,
    );
    final json = r.toJson();
    expect(json['last_delivered_seq'], 5);
    expect(json['last_read_seq'], 3);
    expect(json['last_read_at'], isA<num>());
    final back = ReadState.fromJson(json);
    expect(back.lastDeliveredSeq, 5);
    expect(back.lastReadAt!.millisecondsSinceEpoch, at.millisecondsSinceEpoch);

    final empty = ReadState.fromJson(<String, dynamic>{});
    expect(empty.lastDeliveredSeq, 0);
    expect(empty.lastReadSeq, 0);
    expect(empty.lastReadAt, isNull);
  });

  test('TeamReadState round-trips', () {
    final t = TeamReadState(
      lastHandledSeq: 4,
      handledBy: 'u1',
      lastHandledAt: DateTime.utc(2026, 7, 1, 9),
    );
    final json = t.toJson();
    expect(json['last_handled_seq'], 4);
    expect(json['handled_by'], 'u1');
    expect(TeamReadState.fromJson(json).lastHandledSeq, 4);
    expect(TeamReadState.fromJson(<String, dynamic>{}).lastHandledSeq, 0);
  });

  test('LastMessage round-trips', () {
    final m = LastMessage(
      text: 'hi',
      senderParticipantId: 'c1',
      type: MessageType.text,
      seq: 7,
      createdAt: DateTime.utc(2026, 7, 1, 9),
    );
    final json = m.toJson();
    expect(json['sender_participant_id'], 'c1');
    expect(json['type'], 'text');
    expect(json['seq'], 7);
    expect(json['created_at'], isA<num>());
    expect(LastMessage.fromJson(json).seq, 7);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test test/src/value_objects_test.dart`
Expected: FAIL — types not defined.

- [ ] **Step 3: Create `read_state.dart`**

```dart
import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'read_state.g.dart';

/// Per-user delivered/read watermarks stored in `chat_rooms.reads[userId]`.
@JsonSerializable()
class ReadState {
  ReadState({
    this.lastDeliveredSeq = 0,
    this.lastReadSeq = 0,
    this.lastDeliveredAt,
    this.lastReadAt,
  });

  factory ReadState.fromJson(Map<String, dynamic> json) =>
      _$ReadStateFromJson(json);

  @JsonKey(name: 'last_delivered_seq', defaultValue: 0)
  final int lastDeliveredSeq;

  @JsonKey(
    name: 'last_delivered_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  final DateTime? lastDeliveredAt;

  @JsonKey(name: 'last_read_seq', defaultValue: 0)
  final int lastReadSeq;

  @JsonKey(
    name: 'last_read_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  final DateTime? lastReadAt;

  Map<String, dynamic> toJson() => _$ReadStateToJson(this);
}
```

- [ ] **Step 4: Create `team_read_state.dart`**

```dart
import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'team_read_state.g.dart';

/// Company team handled watermark, `chat_rooms.team_reads[companyId]`.
@JsonSerializable()
class TeamReadState {
  TeamReadState({
    this.lastHandledSeq = 0,
    this.lastHandledAt,
    this.handledBy,
  });

  factory TeamReadState.fromJson(Map<String, dynamic> json) =>
      _$TeamReadStateFromJson(json);

  @JsonKey(name: 'last_handled_seq', defaultValue: 0)
  final int lastHandledSeq;

  @JsonKey(
    name: 'last_handled_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  final DateTime? lastHandledAt;

  @JsonKey(name: 'handled_by')
  final String? handledBy;

  Map<String, dynamic> toJson() => _$TeamReadStateToJson(this);
}
```

- [ ] **Step 5: Create `last_message.dart`**

```dart
import 'package:chat_repository/src/model/message_type.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'last_message.g.dart';

/// Denormalized preview of the latest message, `chat_rooms.last_message`.
@JsonSerializable()
class LastMessage {
  LastMessage({
    required this.senderParticipantId,
    required this.type,
    required this.seq,
    required this.createdAt,
    this.text,
  });

  factory LastMessage.fromJson(Map<String, dynamic> json) =>
      _$LastMessageFromJson(json);

  final String? text;

  @JsonKey(name: 'sender_participant_id')
  final String senderParticipantId;

  @JsonKey(unknownEnumValue: MessageType.text)
  final MessageType type;

  final int seq;

  @JsonKey(
    name: 'created_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  final DateTime createdAt;

  Map<String, dynamic> toJson() => _$LastMessageToJson(this);
}
```

- [ ] **Step 6: Export from the barrel**

Add to `lib/chat_repository.dart`:
```dart
export 'src/model/last_message.dart';
export 'src/model/read_state.dart';
export 'src/model/team_read_state.dart';
```

- [ ] **Step 7: Generate code**

Run: `cd packages/core/chat_repository && fvm flutter pub run build_runner build --delete-conflicting-outputs`
Expected: creates the three `.g.dart` files; "Succeeded".

- [ ] **Step 8: Run the test to verify it passes**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test test/src/value_objects_test.dart`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add packages/core/chat_repository
git commit -m "feat(chat_repository): add ReadState, TeamReadState, LastMessage value objects"
```

---

### Task 6: `Message` entity + model

**Files:**
- Create: `packages/core/chat_repository/lib/src/model/message_entity.dart`
- Create: `packages/core/chat_repository/lib/src/model/message.dart`
- Modify: `packages/core/chat_repository/lib/chat_repository.dart`
- Test: `packages/core/chat_repository/test/src/message_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// ignore_for_file: prefer_const_constructors
import 'package:chat_repository/chat_repository.dart';
import 'package:chat_repository/src/model/message_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans_helpers/data_helpers.dart';

void main() {
  test('Message.create sets NO_ID, null seq, equal timestamps, empty attachments', () {
    final m = Message.create(
      roomId: 'r1',
      senderId: 'u1',
      senderParticipantId: 'u1',
      type: MessageType.text,
      text: 'hello',
    );
    expect(m.id, NO_ID);
    expect(m.seq, isNull);
    expect(m.createdAt, m.updatedAt);
    expect(m.attachments, isEmpty);
  });

  test('Message round-trips with snake_case + int-millis dates + attachments', () {
    final m = Message.create(
      roomId: 'r1',
      senderId: 'u1',
      senderParticipantId: 'c1',
      type: MessageType.file,
      attachments: [
        Attachment(name: 'a.pdf', url: 'u', contentType: 'application/pdf', size: 9),
      ],
    );
    final json = m.toJson();
    expect(json['room_id'], 'r1');
    expect(json['sender_participant_id'], 'c1');
    expect(json['type'], 'file');
    expect(json['created_at'], isA<num>());
    expect((json['attachments'] as List).first['content_type'], 'application/pdf');

    final entity = MessageEntity.fromJson(json);
    expect(entity.roomId, 'r1');
    expect(entity.attachments.single.name, 'a.pdf');
    expect(entity.type, MessageType.file);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test test/src/message_test.dart`
Expected: FAIL — types not defined.

- [ ] **Step 3: Create `message_entity.dart`**

```dart
import 'package:chat_repository/src/model/attachment.dart';
import 'package:chat_repository/src/model/message.dart';
import 'package:chat_repository/src/model/message_type.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'message_entity.g.dart';

@JsonSerializable()
class MessageEntity implements BaseEntity {
  MessageEntity();

  factory MessageEntity.fromJson(Map<String, dynamic> json) =>
      _$MessageEntityFromJson(json);

  @override
  late String id;

  @JsonKey(name: 'room_id')
  late String roomId;

  /// Assigned by the Go trigger on create; null while pending.
  int? seq;

  @JsonKey(name: 'sender_id')
  late String senderId;

  @JsonKey(name: 'sender_participant_id')
  late String senderParticipantId;

  @JsonKey(unknownEnumValue: MessageType.text)
  late MessageType type;

  String? text;

  @JsonKey(toJson: MessageEntity._attachmentsToJson, defaultValue: <Attachment>[])
  late List<Attachment> attachments;

  @JsonKey(
    name: 'created_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  @override
  late DateTime createdAt;

  @JsonKey(
    name: 'updated_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  @override
  late DateTime updatedAt;

  @JsonKey(
    name: 'edited_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  DateTime? editedAt;

  @JsonKey(
    name: 'deleted_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  @override
  DateTime? deletedAt;

  @override
  List<Object?> get props => [
        id, roomId, seq, senderId, senderParticipantId, type, text,
        attachments, createdAt, updatedAt, editedAt, deletedAt,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() => _$MessageEntityToJson(this);

  Message toMessage() {
    return Message()
      ..id = id
      ..roomId = roomId
      ..seq = seq
      ..senderId = senderId
      ..senderParticipantId = senderParticipantId
      ..type = type
      ..text = text
      ..attachments = attachments
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..editedAt = editedAt
      ..deletedAt = deletedAt;
  }

  static List<Map<String, dynamic>> _attachmentsToJson(List<Attachment> items) =>
      items.map((a) => a.toJson()).toList();
}
```

- [ ] **Step 4: Create `message.dart`**

```dart
import 'package:chat_repository/src/model/attachment.dart';
import 'package:chat_repository/src/model/message_entity.dart';
import 'package:chat_repository/src/model/message_type.dart';
import 'package:loooans_helpers/data_helpers.dart';

class Message extends MessageEntity implements BaseModel<MessageEntity> {
  Message() : super();

  factory Message.create({
    required String roomId,
    required String senderId,
    required String senderParticipantId,
    required MessageType type,
    String? text,
    List<Attachment>? attachments,
  }) {
    final now = DateTime.timestamp();
    return Message()
      ..id = NO_ID
      ..roomId = roomId
      ..seq = null
      ..senderId = senderId
      ..senderParticipantId = senderParticipantId
      ..type = type
      ..text = text
      ..attachments = attachments ?? <Attachment>[]
      ..createdAt = now
      ..updatedAt = now;
  }

  @override
  MessageEntity toEntity() => this;
}
```

- [ ] **Step 5: Export the model from the barrel**

Add to `lib/chat_repository.dart`:
```dart
export 'src/model/message.dart';
```

- [ ] **Step 6: Generate code**

Run: `cd packages/core/chat_repository && fvm flutter pub run build_runner build --delete-conflicting-outputs`
Expected: creates `message_entity.g.dart`; "Succeeded".

- [ ] **Step 7: Run the test to verify it passes**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test test/src/message_test.dart`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add packages/core/chat_repository
git commit -m "feat(chat_repository): add Message entity + model"
```

---

### Task 7: `ChatRoom` entity + model

The room carries object-lists and object-maps; each gets a `static` toJson helper, and the maps get `static` fromJson helpers to defensively re-key.

**Files:**
- Create: `packages/core/chat_repository/lib/src/model/chat_room_entity.dart`
- Create: `packages/core/chat_repository/lib/src/model/chat_room.dart`
- Modify: `packages/core/chat_repository/lib/chat_repository.dart`
- Test: `packages/core/chat_repository/test/src/chat_room_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// ignore_for_file: prefer_const_constructors
import 'package:chat_repository/chat_repository.dart';
import 'package:chat_repository/src/model/chat_room_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans_helpers/data_helpers.dart';

void main() {
  final borrower = Participant(id: 'u1', type: ParticipantType.user, displayName: 'Bob');
  final company = Participant(id: 'c1', type: ParticipantType.company, displayName: 'Acme');

  test('ChatRoom.create derives member_ids, NO_ID, empty reads, lastSeq 0', () {
    final room = ChatRoom.create(
      participants: [borrower, company],
      createdBy: 'u1',
      contextType: 'product',
      contextId: 'p1',
    );
    expect(room.id, NO_ID);
    expect(room.memberIds, ['u1', 'c1']);
    expect(room.lastSeq, 0);
    expect(room.reads, isEmpty);
    expect(room.teamReads, isEmpty);
    expect(room.createdAt, room.updatedAt);
  });

  test('ChatRoom round-trips participants, reads map, team_reads map, last_message', () {
    final room = ChatRoom.create(
      participants: [borrower, company],
      createdBy: 'u1',
    )
      ..lastSeq = 3
      ..lastMessage = LastMessage(
        senderParticipantId: 'u1',
        type: MessageType.text,
        seq: 3,
        createdAt: DateTime.utc(2026, 7, 1, 9),
        text: 'hi',
      )
      ..reads = {'u1': ReadState(lastReadSeq: 3, lastDeliveredSeq: 3)}
      ..teamReads = {'c1': TeamReadState(lastHandledSeq: 1, handledBy: 'staff1')};

    final json = room.toJson();
    expect((json['participants'] as List).length, 2);
    expect(json['member_ids'], ['u1', 'c1']);
    expect(json['last_seq'], 3);
    expect((json['reads'] as Map)['u1']['last_read_seq'], 3);
    expect((json['team_reads'] as Map)['c1']['last_handled_seq'], 1);
    expect(json['last_message']['seq'], 3);

    final entity = ChatRoomEntity.fromJson(json);
    expect(entity.participants.map((p) => p.id), ['u1', 'c1']);
    expect(entity.reads['u1']!.lastReadSeq, 3);
    expect(entity.teamReads['c1']!.handledBy, 'staff1');
    expect(entity.lastMessage!.seq, 3);
  });

  test('reads/team_reads survive Firestore-style Map<Object?,Object?> input', () {
    final room = ChatRoom.create(participants: [borrower, company], createdBy: 'u1')
      ..reads = {'u1': ReadState(lastReadSeq: 2)};
    final json = Map<String, dynamic>.from(room.toJson());
    // Simulate a nested map arriving with loose key/value typing.
    json['reads'] = <Object?, Object?>{
      'u1': <Object?, Object?>{'last_read_seq': 2, 'last_delivered_seq': 0},
    };
    final entity = ChatRoomEntity.fromJson(json);
    expect(entity.reads['u1']!.lastReadSeq, 2);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test test/src/chat_room_test.dart`
Expected: FAIL — types not defined.

- [ ] **Step 3: Create `chat_room_entity.dart`**

```dart
import 'package:chat_repository/src/model/chat_room.dart';
import 'package:chat_repository/src/model/last_message.dart';
import 'package:chat_repository/src/model/participant.dart';
import 'package:chat_repository/src/model/read_state.dart';
import 'package:chat_repository/src/model/team_read_state.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'chat_room_entity.g.dart';

@JsonSerializable()
class ChatRoomEntity implements BaseEntity {
  ChatRoomEntity();

  factory ChatRoomEntity.fromJson(Map<String, dynamic> json) =>
      _$ChatRoomEntityFromJson(json);

  @override
  late String id;

  @JsonKey(toJson: ChatRoomEntity._participantsToJson, defaultValue: <Participant>[])
  late List<Participant> participants;

  @JsonKey(name: 'member_ids', defaultValue: <String>[])
  late List<String> memberIds;

  @JsonKey(name: 'context_type')
  String? contextType;

  @JsonKey(name: 'context_id')
  String? contextId;

  @JsonKey(name: 'last_seq', defaultValue: 0)
  late int lastSeq;

  @JsonKey(
    name: 'last_message',
    toJson: ChatRoomEntity._lastMessageToJson,
    fromJson: ChatRoomEntity._lastMessageFromJson,
  )
  LastMessage? lastMessage;

  @JsonKey(
    toJson: ChatRoomEntity._readsToJson,
    fromJson: ChatRoomEntity._readsFromJson,
    defaultValue: <String, ReadState>{},
  )
  late Map<String, ReadState> reads;

  @JsonKey(
    name: 'team_reads',
    toJson: ChatRoomEntity._teamReadsToJson,
    fromJson: ChatRoomEntity._teamReadsFromJson,
    defaultValue: <String, TeamReadState>{},
  )
  late Map<String, TeamReadState> teamReads;

  @JsonKey(name: 'created_by')
  late String createdBy;

  @JsonKey(
    name: 'created_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  @override
  late DateTime createdAt;

  @JsonKey(
    name: 'updated_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  @override
  late DateTime updatedAt;

  @JsonKey(
    name: 'deleted_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  @override
  DateTime? deletedAt;

  @override
  List<Object?> get props => [
        id, participants, memberIds, contextType, contextId, lastSeq,
        lastMessage, reads, teamReads, createdBy, createdAt, updatedAt, deletedAt,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() => _$ChatRoomEntityToJson(this);

  ChatRoom toChatRoom() {
    return ChatRoom()
      ..id = id
      ..participants = participants
      ..memberIds = memberIds
      ..contextType = contextType
      ..contextId = contextId
      ..lastSeq = lastSeq
      ..lastMessage = lastMessage
      ..reads = reads
      ..teamReads = teamReads
      ..createdBy = createdBy
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..deletedAt = deletedAt;
  }

  // --- (de)serialization helpers for object lists/maps ---

  static List<Map<String, dynamic>> _participantsToJson(List<Participant> items) =>
      items.map((p) => p.toJson()).toList();

  static Map<String, dynamic>? _lastMessageToJson(LastMessage? m) => m?.toJson();

  static LastMessage? _lastMessageFromJson(Object? json) {
    if (json == null) return null;
    return LastMessage.fromJson(_asStringMap(json));
  }

  static Map<String, Map<String, dynamic>> _readsToJson(Map<String, ReadState> m) =>
      m.map((k, v) => MapEntry(k, v.toJson()));

  static Map<String, ReadState> _readsFromJson(Object? json) {
    if (json == null) return <String, ReadState>{};
    return (json as Map).map(
      (k, v) => MapEntry(k as String, ReadState.fromJson(_asStringMap(v))),
    );
  }

  static Map<String, Map<String, dynamic>> _teamReadsToJson(
          Map<String, TeamReadState> m) =>
      m.map((k, v) => MapEntry(k, v.toJson()));

  static Map<String, TeamReadState> _teamReadsFromJson(Object? json) {
    if (json == null) return <String, TeamReadState>{};
    return (json as Map).map(
      (k, v) => MapEntry(k as String, TeamReadState.fromJson(_asStringMap(v))),
    );
  }

  /// Firestore/RTDB nested maps can arrive as `Map<Object?,Object?>`.
  static Map<String, dynamic> _asStringMap(Object? v) =>
      (v! as Map).map((k, val) => MapEntry(k as String, val));
}
```

- [ ] **Step 4: Create `chat_room.dart`**

```dart
import 'package:chat_repository/src/model/chat_room_entity.dart';
import 'package:chat_repository/src/model/last_message.dart';
import 'package:chat_repository/src/model/participant.dart';
import 'package:chat_repository/src/model/read_state.dart';
import 'package:chat_repository/src/model/team_read_state.dart';
import 'package:loooans_helpers/data_helpers.dart';

class ChatRoom extends ChatRoomEntity implements BaseModel<ChatRoomEntity> {
  ChatRoom() : super();

  factory ChatRoom.create({
    required List<Participant> participants,
    required String createdBy,
    String? contextType,
    String? contextId,
  }) {
    final now = DateTime.timestamp();
    return ChatRoom()
      ..id = NO_ID
      ..participants = participants
      ..memberIds = participants.map((p) => p.id).toList()
      ..contextType = contextType
      ..contextId = contextId
      ..lastSeq = 0
      ..lastMessage = null
      ..reads = <String, ReadState>{}
      ..teamReads = <String, TeamReadState>{}
      ..createdBy = createdBy
      ..createdAt = now
      ..updatedAt = now;
  }

  @override
  ChatRoomEntity toEntity() => this;
}
```

- [ ] **Step 5: Export the model from the barrel**

Add to `lib/chat_repository.dart`:
```dart
export 'src/model/chat_room.dart';
```

- [ ] **Step 6: Generate code**

Run: `cd packages/core/chat_repository && fvm flutter pub run build_runner build --delete-conflicting-outputs`
Expected: creates `chat_room_entity.g.dart`; "Succeeded".

- [ ] **Step 7: Run the test to verify it passes**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test test/src/chat_room_test.dart`
Expected: PASS (all 3 tests, including the loose-typing map test).

- [ ] **Step 8: Commit**

```bash
git add packages/core/chat_repository
git commit -m "feat(chat_repository): add ChatRoom entity + model"
```

---

### Task 8: Pure read-model logic

All the arithmetic/predicates the UI and services depend on, as pure functions — this is the primary tested logic.

**Files:**
- Create: `packages/core/chat_repository/lib/src/logic/chat_read_model.dart`
- Modify: `packages/core/chat_repository/lib/chat_repository.dart`
- Test: `packages/core/chat_repository/test/src/chat_read_model_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// ignore_for_file: prefer_const_constructors
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final borrower = Participant(id: 'u1', type: ParticipantType.user);
  final company = Participant(id: 'c1', type: ParticipantType.company);

  ChatRoom room() => ChatRoom.create(
        participants: [borrower, company],
        createdBy: 'u1',
        contextType: 'loan',
        contextId: 'l1',
      );

  test('unreadFor = lastSeq - lastReadSeq, clamped at 0', () {
    final r = room()
      ..lastSeq = 5
      ..reads = {'u1': ReadState(lastReadSeq: 2)};
    expect(unreadFor(r, 'u1'), 3);
    expect(unreadFor(r, 'unknown'), 5); // no read state => all unread
    r.reads = {'u1': ReadState(lastReadSeq: 9)};
    expect(unreadFor(r, 'u1'), 0); // clamp
  });

  test('team handled/awaiting from team_reads[companyId]', () {
    final r = room()..lastSeq = 4;
    expect(isAwaitingResponse(r, 'c1'), isTrue); // no watermark yet
    r.teamReads = {'c1': TeamReadState(lastHandledSeq: 4)};
    expect(isHandledByTeam(r, 'c1'), isTrue);
    expect(isAwaitingResponse(r, 'c1'), isFalse);
    r.teamReads = {'c1': TeamReadState(lastHandledSeq: 3)};
    expect(isAwaitingResponse(r, 'c1'), isTrue);
  });

  test('messageStatus derivation', () {
    final pending = Message.create(
        roomId: 'r', senderId: 'u1', senderParticipantId: 'u1', type: MessageType.text);
    expect(messageStatus(message: pending, counterpartReadStates: const []),
        MessageStatus.sending);

    final sent = Message.create(
        roomId: 'r', senderId: 'u1', senderParticipantId: 'u1', type: MessageType.text)
      ..seq = 4;
    expect(messageStatus(message: sent, counterpartReadStates: const []),
        MessageStatus.sent);
    expect(
      messageStatus(
          message: sent,
          counterpartReadStates: [ReadState(lastDeliveredSeq: 4, lastReadSeq: 0)]),
      MessageStatus.delivered,
    );
    expect(
      messageStatus(
          message: sent,
          counterpartReadStates: [ReadState(lastDeliveredSeq: 4, lastReadSeq: 4)]),
      MessageStatus.read,
    );
    // max across staff: one staffer read, another only delivered => read
    expect(
      messageStatus(message: sent, counterpartReadStates: [
        ReadState(lastDeliveredSeq: 4, lastReadSeq: 0),
        ReadState(lastDeliveredSeq: 4, lastReadSeq: 4),
      ]),
      MessageStatus.read,
    );
  });

  test('memberIdsOf', () {
    expect(memberIdsOf([borrower, company]), ['u1', 'c1']);
  });

  test('roomMatchesAnchor requires same members + same context', () {
    final r = room();
    expect(
      roomMatchesAnchor(r,
          memberIds: {'u1', 'c1'}, contextType: 'loan', contextId: 'l1'),
      isTrue,
    );
    // different context
    expect(
      roomMatchesAnchor(r,
          memberIds: {'u1', 'c1'}, contextType: 'product', contextId: 'p1'),
      isFalse,
    );
    // superset/subset of members
    expect(
      roomMatchesAnchor(r,
          memberIds: {'u1'}, contextType: 'loan', contextId: 'l1'),
      isFalse,
    );
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test test/src/chat_read_model_test.dart`
Expected: FAIL — functions not defined.

- [ ] **Step 3: Create `chat_read_model.dart`**

```dart
import 'package:chat_repository/src/model/chat_room_entity.dart';
import 'package:chat_repository/src/model/message_entity.dart';
import 'package:chat_repository/src/model/message_status.dart';
import 'package:chat_repository/src/model/participant.dart';
import 'package:chat_repository/src/model/read_state.dart';

/// Unread message count for [userId] in [room]: lastSeq minus that user's
/// read watermark (0 when they have no watermark yet), clamped at 0.
int unreadFor(ChatRoomEntity room, String userId) {
  final lastRead = room.reads[userId]?.lastReadSeq ?? 0;
  final diff = room.lastSeq - lastRead;
  return diff > 0 ? diff : 0;
}

/// Whether the team has handled the room (caught up to lastSeq).
bool isHandledByTeam(ChatRoomEntity room, String companyId) {
  final handled = room.teamReads[companyId]?.lastHandledSeq ?? 0;
  return handled >= room.lastSeq;
}

/// Inverse of [isHandledByTeam].
bool isAwaitingResponse(ChatRoomEntity room, String companyId) =>
    !isHandledByTeam(room, companyId);

/// Derive the outgoing-message status from the counterpart watermark(s).
/// For a company counterpart, pass every staff member's [ReadState]; the
/// highest watermark wins.
MessageStatus messageStatus({
  required MessageEntity message,
  required Iterable<ReadState> counterpartReadStates,
}) {
  final seq = message.seq;
  if (seq == null) return MessageStatus.sending;
  var delivered = false;
  var read = false;
  for (final rs in counterpartReadStates) {
    if (rs.lastReadSeq >= seq) read = true;
    if (rs.lastDeliveredSeq >= seq) delivered = true;
  }
  if (read) return MessageStatus.read;
  if (delivered) return MessageStatus.delivered;
  return MessageStatus.sent;
}

/// Denormalized `member_ids` for a participant set.
List<String> memberIdsOf(List<Participant> participants) =>
    participants.map((p) => p.id).toList();

/// Dedup predicate: does [room] have exactly [memberIds] and the same anchor?
bool roomMatchesAnchor(
  ChatRoomEntity room, {
  required Set<String> memberIds,
  String? contextType,
  String? contextId,
}) {
  final sameMembers = room.memberIds.toSet().length == memberIds.length &&
      room.memberIds.toSet().containsAll(memberIds);
  return sameMembers &&
      room.contextType == contextType &&
      room.contextId == contextId;
}
```

- [ ] **Step 4: Export from the barrel**

Add to `lib/chat_repository.dart`:
```dart
export 'src/logic/chat_read_model.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test test/src/chat_read_model_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/core/chat_repository
git commit -m "feat(chat_repository): add pure read-model logic (unread/handled/status/dedup)"
```

---

### Task 9: `ChatRoomFirestoreService`

**Files:**
- Create: `packages/core/chat_repository/lib/src/data/database/chat_room_firestore_service.dart`
- Test: `packages/core/chat_repository/test/src/chat_room_firestore_service_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// ignore_for_file: prefer_const_constructors
import 'package:chat_repository/chat_repository.dart';
import 'package:chat_repository/src/data/database/chat_room_firestore_service.dart';
import 'package:chat_repository/src/model/chat_room_entity.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore fs;
  late ChatRoomFirestoreService service;

  final borrower = Participant(id: 'u1', type: ParticipantType.user);
  final company = Participant(id: 'c1', type: ParticipantType.company);

  setUp(() {
    fs = FakeFirebaseFirestore();
    service = ChatRoomFirestoreService(firestore: fs);
  });

  ChatRoomEntity newRoom() => ChatRoom.create(
        participants: [borrower, company],
        createdBy: 'u1',
        contextType: 'loan',
        contextId: 'l1',
      ).toEntity();

  test('add assigns a doc id and persists under dev_chat_rooms', () async {
    final saved = await service.add(data: newRoom());
    expect(saved.id, isNotEmpty);
    expect(saved.id, isNot('no-id'));
    final doc = await fs.collection('dev_chat_rooms').doc(saved.id).get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['member_ids'], ['u1', 'c1']);
  });

  test('findAnchoredRoom returns an existing match, null otherwise', () async {
    final saved = await service.add(data: newRoom());
    final found = await service.findAnchoredRoom(
      currentId: 'u1',
      memberIds: {'u1', 'c1'},
      contextType: 'loan',
      contextId: 'l1',
    );
    expect(found, isNotNull);
    expect(found!.id, saved.id);

    final miss = await service.findAnchoredRoom(
      currentId: 'u1',
      memberIds: {'u1', 'c1'},
      contextType: 'product',
      contextId: 'p9',
    );
    expect(miss, isNull);
  });

  test('markRead advances only that user reads entry (merge, others intact)', () async {
    final saved = await service.add(
      data: newRoom()
        ..lastSeq = 5
        ..reads = {'c1': ReadState(lastReadSeq: 1)},
    );
    await service.markRead(roomId: saved.id, userId: 'u1', seq: 5);
    final doc = await fs.collection('dev_chat_rooms').doc(saved.id).get();
    final reads = doc.data()!['reads'] as Map;
    expect(reads['u1']['last_read_seq'], 5);
    expect(reads['u1']['last_delivered_seq'], 5);
    expect(reads['c1']['last_read_seq'], 1); // untouched
  });

  test('markHandled advances team_reads for the company', () async {
    final saved = await service.add(data: newRoom()..lastSeq = 4);
    await service.markHandled(
        roomId: saved.id, companyId: 'c1', userId: 'staff1', seq: 4);
    final doc = await fs.collection('dev_chat_rooms').doc(saved.id).get();
    final team = doc.data()!['team_reads'] as Map;
    expect(team['c1']['last_handled_seq'], 4);
    expect(team['c1']['handled_by'], 'staff1');
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test test/src/chat_room_firestore_service_test.dart`
Expected: FAIL — service not defined.

- [ ] **Step 3: Create `chat_room_firestore_service.dart`**

```dart
import 'dart:async';

import 'package:chat_repository/src/logic/chat_read_model.dart';
import 'package:chat_repository/src/model/chat_room_entity.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:loooans_helpers/data_helpers.dart';

final class ChatRoomFirestoreService extends BaseFirestoreService<ChatRoomEntity> {
  ChatRoomFirestoreService({super.firestore});

  @override
  String get collectionName => 'chat_rooms';

  @override
  Future<ChatRoomEntity> add({required ChatRoomEntity data}) async {
    final doc = root.doc();
    final updated = data..id = doc.id;
    await doc.set(updated.toJson());
    return updated;
  }

  @override
  Future<ChatRoomEntity> get({required String id, bool isCache = false}) async {
    final doc = await root
        .doc(id)
        .get(!isCache ? null : const GetOptions(source: Source.cache));
    return ChatRoomEntity.fromJson(doc.data()! as Map<String, dynamic>);
  }

  @override
  Future<ChatRoomEntity> update({required ChatRoomEntity data}) async {
    data.updatedAt = DateTime.timestamp();
    await root.doc(data.id).update(data.toJson());
    return data;
  }

  @override
  Future<ChatRoomEntity> delete({required ChatRoomEntity data}) async {
    final updated = data..deletedAt = DateTime.timestamp();
    await root.doc(data.id).update(updated.toJson());
    return updated;
  }

  @override
  Future<List<ChatRoomEntity>> load({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
    bool isCache = false,
  }) async {
    if (reset) lastDocumentSnapshot = null;
    var query = root
        .where('deleted_at', isNull: true)
        .orderBy('updated_at', descending: true);
    if (lastDocumentSnapshot != null) {
      query = query.startAfterDocument(lastDocumentSnapshot!);
    }
    if (limit != null && limit > 0) query = query.limit(limit);
    if (statements != null) {
      for (final s in statements) {
        query = query.where(
          s.field,
          isEqualTo: s.isEqualTo,
          arrayContains: s.arrayContains,
          arrayContainsAny: s.arrayContainsAny,
          whereIn: s.whereIn,
          isNull: s.isNull,
        );
      }
    }
    final data = await query
        .get(!isCache ? null : const GetOptions(source: Source.cache));
    if (data.docs.isNotEmpty) lastDocumentSnapshot = data.docs.last;
    return data.docs
        .map((d) => ChatRoomEntity.fromJson(d.data()! as Map<String, dynamic>))
        .toList();
  }

  @override
  void loadNext({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) {
    var query = root
        .where('deleted_at', isNull: true)
        .orderBy('updated_at', descending: true);
    if (statements != null) {
      for (final s in statements) {
        query = query.where(
          s.field,
          isEqualTo: s.isEqualTo,
          arrayContains: s.arrayContains,
          arrayContainsAny: s.arrayContainsAny,
          whereIn: s.whereIn,
          isNull: s.isNull,
        );
      }
    }
    if (limit != null && limit > 0) query = query.limit(limit);
    resetStreamController();
    unawaited(
      controller.addStream(
        query.snapshots().map(
              (snap) => snap.docs
                  .map((d) =>
                      ChatRoomEntity.fromJson(d.data()! as Map<String, dynamic>))
                  .toList(),
            ),
      ),
    );
  }

  /// Find an existing anchored room for [currentId] matching [memberIds]/context.
  Future<ChatRoomEntity?> findAnchoredRoom({
    required String currentId,
    required Set<String> memberIds,
    String? contextType,
    String? contextId,
  }) async {
    final snap = await root
        .where('member_ids', arrayContains: currentId)
        .where('deleted_at', isNull: true)
        .get();
    for (final doc in snap.docs) {
      final entity =
          ChatRoomEntity.fromJson(doc.data()! as Map<String, dynamic>);
      if (roomMatchesAnchor(
        entity,
        memberIds: memberIds,
        contextType: contextType,
        contextId: contextId,
      )) {
        return entity;
      }
    }
    return null;
  }

  /// Advance the caller's delivered watermark (caller passes the max seq seen).
  Future<void> markDelivered({
    required String roomId,
    required String userId,
    required int seq,
  }) async {
    final now = DateTime.timestamp().millisecondsSinceEpoch;
    await root.doc(roomId).set(<String, dynamic>{
      'reads': {
        userId: {'last_delivered_seq': seq, 'last_delivered_at': now},
      },
    }, SetOptions(merge: true));
  }

  /// Advance the caller's read (and delivered) watermark.
  Future<void> markRead({
    required String roomId,
    required String userId,
    required int seq,
  }) async {
    final now = DateTime.timestamp().millisecondsSinceEpoch;
    await root.doc(roomId).set(<String, dynamic>{
      'reads': {
        userId: {
          'last_read_seq': seq,
          'last_read_at': now,
          'last_delivered_seq': seq,
          'last_delivered_at': now,
        },
      },
    }, SetOptions(merge: true));
  }

  /// Advance the company team handled watermark.
  Future<void> markHandled({
    required String roomId,
    required String companyId,
    required String userId,
    required int seq,
  }) async {
    final now = DateTime.timestamp().millisecondsSinceEpoch;
    await root.doc(roomId).set(<String, dynamic>{
      'team_reads': {
        companyId: {
          'last_handled_seq': seq,
          'last_handled_at': now,
          'handled_by': userId,
        },
      },
    }, SetOptions(merge: true));
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test test/src/chat_room_firestore_service_test.dart`
Expected: PASS. (If `fake_cloud_firestore` rejects nested `SetOptions(merge:true)` map-merge, fall back to `update({'reads.$userId.last_read_seq': seq, ...})` dotted paths and re-run — note which worked.)

- [ ] **Step 5: Commit**

```bash
git add packages/core/chat_repository
git commit -m "feat(chat_repository): add ChatRoomFirestoreService (dedup + watermarks)"
```

---

### Task 10: `MessageFirestoreService` (subcollection)

**Files:**
- Create: `packages/core/chat_repository/lib/src/data/database/message_firestore_service.dart`
- Test: `packages/core/chat_repository/test/src/message_firestore_service_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// ignore_for_file: prefer_const_constructors
import 'package:chat_repository/chat_repository.dart';
import 'package:chat_repository/src/model/message_entity.dart';
import 'package:chat_repository/src/data/database/message_firestore_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore fs;
  late MessageFirestoreService service;

  setUp(() {
    fs = FakeFirebaseFirestore();
    service = MessageFirestoreService(roomId: 'r1', firestore: fs);
  });

  MessageEntity newMsg({String text = 'hi'}) => Message.create(
        roomId: 'r1',
        senderId: 'u1',
        senderParticipantId: 'u1',
        type: MessageType.text,
        text: text,
      ).toEntity();

  test('add writes under dev_chat_rooms/r1/messages with a doc id', () async {
    final saved = await service.add(data: newMsg());
    expect(saved.id, isNotEmpty);
    final doc = await fs
        .collection('dev_chat_rooms')
        .doc('r1')
        .collection('messages')
        .doc(saved.id)
        .get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['text'], 'hi');
  });

  test('editMessage sets text + edited_at', () async {
    final saved = await service.add(data: newMsg());
    await service.editMessage(messageId: saved.id, text: 'edited');
    final doc = await fs
        .collection('dev_chat_rooms').doc('r1')
        .collection('messages').doc(saved.id).get();
    expect(doc.data()!['text'], 'edited');
    expect(doc.data()!['edited_at'], isA<num>());
  });

  test('deleteMessage soft-deletes (deleted_at set)', () async {
    final saved = await service.add(data: newMsg());
    await service.deleteMessage(messageId: saved.id);
    final doc = await fs
        .collection('dev_chat_rooms').doc('r1')
        .collection('messages').doc(saved.id).get();
    expect(doc.data()!['deleted_at'], isA<num>());
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test test/src/message_firestore_service_test.dart`
Expected: FAIL — service not defined.

- [ ] **Step 3: Create `message_firestore_service.dart`**

```dart
import 'dart:async';

import 'package:chat_repository/src/model/message_entity.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:loooans_helpers/data_helpers.dart';

/// Operates on the `chat_rooms/{roomId}/messages` subcollection.
final class MessageFirestoreService extends BaseFirestoreService<MessageEntity> {
  MessageFirestoreService({required this.roomId, super.firestore});

  final String roomId;

  /// Used only to build the prefixed parent path in [root].
  @override
  String get collectionName => 'chat_rooms';

  @override
  CollectionReference get root => fs
      .collection('$collectionPrefix$collectionName')
      .doc(roomId)
      .collection('messages');

  @override
  Future<MessageEntity> add({required MessageEntity data}) async {
    final doc = root.doc();
    final updated = data..id = doc.id;
    await doc.set(updated.toJson());
    return updated;
  }

  @override
  Future<MessageEntity> get({required String id, bool isCache = false}) async {
    final doc = await root
        .doc(id)
        .get(!isCache ? null : const GetOptions(source: Source.cache));
    return MessageEntity.fromJson(doc.data()! as Map<String, dynamic>);
  }

  @override
  Future<MessageEntity> update({required MessageEntity data}) async {
    data.updatedAt = DateTime.timestamp();
    await root.doc(data.id).update(data.toJson());
    return data;
  }

  @override
  Future<MessageEntity> delete({required MessageEntity data}) async {
    final updated = data..deletedAt = DateTime.timestamp();
    await root.doc(data.id).update(updated.toJson());
    return updated;
  }

  Future<void> editMessage({
    required String messageId,
    required String text,
  }) async {
    final now = DateTime.timestamp().millisecondsSinceEpoch;
    await root.doc(messageId).update(<String, dynamic>{
      'text': text,
      'edited_at': now,
      'updated_at': now,
    });
  }

  Future<void> deleteMessage({required String messageId}) async {
    final now = DateTime.timestamp().millisecondsSinceEpoch;
    await root.doc(messageId).update(<String, dynamic>{
      'deleted_at': now,
      'updated_at': now,
    });
  }

  @override
  Future<List<MessageEntity>> load({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
    bool isCache = false,
  }) async {
    if (reset) lastDocumentSnapshot = null;
    var query = root.orderBy('created_at', descending: true);
    if (lastDocumentSnapshot != null) {
      query = query.startAfterDocument(lastDocumentSnapshot!);
    }
    if (limit != null && limit > 0) query = query.limit(limit);
    final data = await query
        .get(!isCache ? null : const GetOptions(source: Source.cache));
    if (data.docs.isNotEmpty) lastDocumentSnapshot = data.docs.last;
    return data.docs
        .map((d) => MessageEntity.fromJson(d.data()! as Map<String, dynamic>))
        .toList();
  }

  @override
  void loadNext({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) {
    var query = root.orderBy('created_at', descending: true);
    if (limit != null && limit > 0) query = query.limit(limit);
    resetStreamController();
    unawaited(
      controller.addStream(
        query.snapshots().map(
              (snap) => snap.docs
                  .map((d) =>
                      MessageEntity.fromJson(d.data()! as Map<String, dynamic>))
                  .toList(),
            ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test test/src/message_firestore_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/core/chat_repository
git commit -m "feat(chat_repository): add MessageFirestoreService (subcollection)"
```

---

### Task 11: `TypingService` (RTDB)

RTDB has no fake harness in the repo, so the testable unit here is the **throttle** decision, extracted as a pure function. The RTDB writes/streams are thin and verified in-app (Plan 3).

**Files:**
- Create: `packages/core/chat_repository/lib/src/data/database/typing_service.dart`
- Modify: `packages/core/chat_repository/lib/chat_repository.dart`
- Test: `packages/core/chat_repository/test/src/typing_throttle_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// ignore_for_file: prefer_const_constructors
import 'package:chat_repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shouldSendTyping throttles within the window', () {
    // first write always allowed
    expect(shouldSendTyping(lastSentMillis: null, nowMillis: 1000), isTrue);
    // within 2s window -> suppressed
    expect(shouldSendTyping(lastSentMillis: 1000, nowMillis: 2500), isFalse);
    // past 2s window -> allowed
    expect(shouldSendTyping(lastSentMillis: 1000, nowMillis: 3001), isTrue);
  });

  test('isActivelyTyping honors the staleness window', () {
    expect(isActivelyTyping(atMillis: 10000, nowMillis: 12000), isTrue);
    expect(isActivelyTyping(atMillis: 10000, nowMillis: 16000), isFalse);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test test/src/typing_throttle_test.dart`
Expected: FAIL — functions not defined.

- [ ] **Step 3: Create `typing_service.dart`**

```dart
import 'package:firebase_database/firebase_database.dart';
import 'package:loooans_helpers/loooans_helpers.dart';

/// Throttle window for outgoing typing pings.
const typingThrottle = Duration(seconds: 2);

/// Staleness window: an entry older than this is not "actively typing".
const typingStaleness = Duration(seconds: 5);

/// Pure: may we send another typing ping now?
bool shouldSendTyping({required int? lastSentMillis, required int nowMillis}) {
  if (lastSentMillis == null) return true;
  return nowMillis - lastSentMillis >= typingThrottle.inMilliseconds;
}

/// Pure: is a typing entry stamped [atMillis] still active at [nowMillis]?
bool isActivelyTyping({required int atMillis, required int nowMillis}) {
  return nowMillis - atMillis < typingStaleness.inMilliseconds;
}

/// RTDB-backed typing presence at `typing/{roomId}/{userId}`.
class TypingService {
  TypingService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;
  int? _lastSentMillis;

  String get _prefix {
    if (const String.fromEnvironment('ENVIRONMENT') ==
        Environments.staging.name) {
      return 'stg/';
    } else if (const String.fromEnvironment('ENVIRONMENT') ==
        Environments.production.name) {
      return '';
    }
    return 'dev/';
  }

  DatabaseReference _ref(String roomId, String userId) =>
      _db.ref('${_prefix}typing/$roomId/$userId');

  /// Write a typing ping (throttled) and clear it on disconnect.
  Future<void> setTyping({
    required String roomId,
    required String userId,
    required int nowMillis,
  }) async {
    if (!shouldSendTyping(lastSentMillis: _lastSentMillis, nowMillis: nowMillis)) {
      return;
    }
    _lastSentMillis = nowMillis;
    final ref = _ref(roomId, userId);
    await ref.onDisconnect().remove();
    await ref.set(<String, dynamic>{'at': nowMillis});
  }

  /// Explicitly clear this user's typing state.
  Future<void> clearTyping({required String roomId, required String userId}) {
    _lastSentMillis = null;
    return _ref(roomId, userId).remove();
  }

  /// Stream of userIds currently (freshly) typing in [roomId].
  Stream<List<String>> typingStream({
    required String roomId,
    required int Function() clock,
  }) {
    return _db.ref('${_prefix}typing/$roomId').onValue.map((event) {
      final value = event.snapshot.value;
      if (value == null) return <String>[];
      final map = (value as Map).map((k, v) => MapEntry(k as String, v));
      final now = clock();
      return map.entries
          .where((e) {
            final at = ((e.value as Map)['at'] as num?)?.toInt() ?? 0;
            return isActivelyTyping(atMillis: at, nowMillis: now);
          })
          .map((e) => e.key)
          .toList();
    });
  }
}
```

- [ ] **Step 4: Export from the barrel**

Add to `lib/chat_repository.dart`:
```dart
export 'src/data/database/typing_service.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test test/src/typing_throttle_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/core/chat_repository
git commit -m "feat(chat_repository): add TypingService (RTDB) + pure throttle logic"
```

---

### Task 12: Repositories (`ChatRoomRepository`, `MessageRepository`)

Thin `BaseRepository` wrappers mapping entities↔models, matching `notification_repository`.

**Files:**
- Create: `packages/core/chat_repository/lib/src/repository/chat_room_repository.dart`
- Create: `packages/core/chat_repository/lib/src/repository/message_repository.dart`
- Modify: `packages/core/chat_repository/lib/chat_repository.dart`
- Test: `packages/core/chat_repository/test/src/chat_room_repository_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// ignore_for_file: prefer_const_constructors
import 'package:chat_repository/chat_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ChatRoomRepository.findOrCreate reuses an existing anchored room', () async {
    final fs = FakeFirebaseFirestore();
    final repo = ChatRoomRepository(firestore: fs);
    final participants = [
      Participant(id: 'u1', type: ParticipantType.user),
      Participant(id: 'c1', type: ParticipantType.company),
    ];

    final created = await repo.findOrCreate(
      participants: participants,
      createdBy: 'u1',
      contextType: 'loan',
      contextId: 'l1',
    );
    expect(created.id, isNot('no-id'));

    final again = await repo.findOrCreate(
      participants: participants,
      createdBy: 'u1',
      contextType: 'loan',
      contextId: 'l1',
    );
    expect(again.id, created.id); // dedup — same room
  });

  test('MessageRepository.send persists a message model', () async {
    final fs = FakeFirebaseFirestore();
    final repo = MessageRepository(roomId: 'r1', firestore: fs);
    final sent = await repo.add(
      data: Message.create(
        roomId: 'r1',
        senderId: 'u1',
        senderParticipantId: 'u1',
        type: MessageType.text,
        text: 'yo',
      ),
    );
    expect(sent.id, isNot('no-id'));
    expect(sent.text, 'yo');
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test test/src/chat_room_repository_test.dart`
Expected: FAIL — repositories not defined.

- [ ] **Step 3: Create `chat_room_repository.dart`**

```dart
import 'package:chat_repository/src/data/database/chat_room_firestore_service.dart';
import 'package:chat_repository/src/logic/chat_read_model.dart';
import 'package:chat_repository/src/model/chat_room.dart';
import 'package:chat_repository/src/model/participant.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:loooans_helpers/data_helpers.dart';

class ChatRoomRepository implements BaseRepository<ChatRoom> {
  ChatRoomRepository({FirebaseFirestore? firestore})
      : _service = ChatRoomFirestoreService(firestore: firestore);

  final ChatRoomFirestoreService _service;

  @override
  Future<ChatRoom> add({required ChatRoom data}) =>
      _service.add(data: data.toEntity()).then((e) => e.toChatRoom());

  @override
  Future<ChatRoom> update({required ChatRoom data}) =>
      _service.update(data: data.toEntity()).then((e) => e.toChatRoom());

  @override
  Future<ChatRoom> delete({required ChatRoom data}) =>
      _service.delete(data: data.toEntity()).then((e) => e.toChatRoom());

  @override
  Future<ChatRoom> get({required String id}) => _service
      .get(id: id)
      .timeout(
        timeoutDuration,
        onTimeout: () => _service.get(id: id, isCache: true),
      )
      .then((e) => e.toChatRoom());

  @override
  Future<List<ChatRoom>> load({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) =>
      _service
          .load(statements: statements, limit: limit, page: page, reset: reset)
          .then((list) => list.map((e) => e.toChatRoom()).toList());

  @override
  Stream<List<ChatRoom>> get dataStream =>
      _service.dataStream.map((list) => list.map((e) => e.toChatRoom()).toList());

  @override
  void loadNext({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) =>
      _service.loadNext(
          statements: statements, limit: limit, page: page, reset: reset);

  /// Reuse the existing anchored room or create a new one (dedup).
  Future<ChatRoom> findOrCreate({
    required List<Participant> participants,
    required String createdBy,
    String? contextType,
    String? contextId,
  }) async {
    final memberIds = memberIdsOf(participants).toSet();
    final existing = await _service.findAnchoredRoom(
      currentId: createdBy,
      memberIds: memberIds,
      contextType: contextType,
      contextId: contextId,
    );
    if (existing != null) return existing.toChatRoom();
    final room = ChatRoom.create(
      participants: participants,
      createdBy: createdBy,
      contextType: contextType,
      contextId: contextId,
    );
    return add(data: room);
  }

  Future<void> markDelivered({
    required String roomId,
    required String userId,
    required int seq,
  }) =>
      _service.markDelivered(roomId: roomId, userId: userId, seq: seq);

  Future<void> markRead({
    required String roomId,
    required String userId,
    required int seq,
  }) =>
      _service.markRead(roomId: roomId, userId: userId, seq: seq);

  Future<void> markHandled({
    required String roomId,
    required String companyId,
    required String userId,
    required int seq,
  }) =>
      _service.markHandled(
          roomId: roomId, companyId: companyId, userId: userId, seq: seq);
}
```

- [ ] **Step 4: Create `message_repository.dart`**

```dart
import 'package:chat_repository/src/data/database/message_firestore_service.dart';
import 'package:chat_repository/src/model/message.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:loooans_helpers/data_helpers.dart';

class MessageRepository implements BaseRepository<Message> {
  MessageRepository({required String roomId, FirebaseFirestore? firestore})
      : _service = MessageFirestoreService(roomId: roomId, firestore: firestore);

  final MessageFirestoreService _service;

  @override
  Future<Message> add({required Message data}) =>
      _service.add(data: data.toEntity()).then((e) => e.toMessage());

  @override
  Future<Message> update({required Message data}) =>
      _service.update(data: data.toEntity()).then((e) => e.toMessage());

  @override
  Future<Message> delete({required Message data}) =>
      _service.delete(data: data.toEntity()).then((e) => e.toMessage());

  @override
  Future<Message> get({required String id}) =>
      _service.get(id: id).then((e) => e.toMessage());

  @override
  Future<List<Message>> load({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) =>
      _service
          .load(statements: statements, limit: limit, page: page, reset: reset)
          .then((list) => list.map((e) => e.toMessage()).toList());

  @override
  Stream<List<Message>> get dataStream =>
      _service.dataStream.map((list) => list.map((e) => e.toMessage()).toList());

  @override
  void loadNext({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) =>
      _service.loadNext(
          statements: statements, limit: limit, page: page, reset: reset);

  Future<void> editMessage({required String messageId, required String text}) =>
      _service.editMessage(messageId: messageId, text: text);

  Future<void> deleteMessage({required String messageId}) =>
      _service.deleteMessage(messageId: messageId);
}
```

- [ ] **Step 5: Export from the barrel**

Add to `lib/chat_repository.dart`:
```dart
export 'src/repository/chat_room_repository.dart';
export 'src/repository/message_repository.dart';
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test test/src/chat_room_repository_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add packages/core/chat_repository
git commit -m "feat(chat_repository): add ChatRoomRepository and MessageRepository"
```

---

### Task 13: Finalize — analyze, full test + build, commit

**Files:**
- Modify: `packages/core/chat_repository/lib/chat_repository.dart` (verify exports complete)

- [ ] **Step 1: Confirm the barrel exports everything public**

`lib/chat_repository.dart` should read:
```dart
/// Chat/messaging data layer.
library chat_repository;

export 'src/data/database/typing_service.dart';
export 'src/logic/chat_read_model.dart';
export 'src/model/attachment.dart';
export 'src/model/chat_room.dart';
export 'src/model/last_message.dart';
export 'src/model/message.dart';
export 'src/model/message_status.dart';
export 'src/model/message_type.dart';
export 'src/model/participant.dart';
export 'src/model/participant_type.dart';
export 'src/model/read_state.dart';
export 'src/model/team_read_state.dart';
export 'src/repository/chat_room_repository.dart';
export 'src/repository/message_repository.dart';
```
(Entities and Firestore services stay `src`-internal, matching `notification_repository`.)

- [ ] **Step 2: Regenerate all codegen from clean**

Run: `cd packages/core/chat_repository && fvm flutter pub run build_runner build --delete-conflicting-outputs`
Expected: "Succeeded", no conflicts.

- [ ] **Step 3: Analyze**

Run: `cd packages/core/chat_repository && CI=true fvm flutter analyze`
Expected: "No issues found!"

- [ ] **Step 4: Run the full package test suite**

Run: `cd packages/core/chat_repository && CI=true fvm flutter test`
Expected: All tests PASS (enums, attachment/participant, value objects, message, chat_room, read-model logic, room service, message service, typing throttle, repositories).

- [ ] **Step 5: Commit**

```bash
git add packages/core/chat_repository
git commit -m "chore(chat_repository): finalize barrel exports; green analyze + tests"
```

---

## Self-Review (completed by plan author)

**Spec coverage (§6 of the spec):**
- `ChatRoomRepository` (findOrCreate/markDelivered/markRead/markHandled) → Tasks 9, 12. ✅
- `MessageRepository` (subcollection root override, edit/delete) → Tasks 10, 12. ✅
- `TypingService` (RTDB) → Task 11. ✅
- Models `ChatRoom`/`Message`, `ReadState`/`TeamReadState`, `Participant`/`ParticipantType`, `MessageType`, `Attachment`, `MessageStatus`, `LastMessage` → Tasks 3–7. ✅
- Sequence-based read model math (unread, handled, receipts) → Task 8 (pure) + Task 9 (persistence). ✅
- Date int64-millis convention → all entity/value-object tasks (assert `isA<num>()`). ✅

**Deviations from spec noted:** Spec §10 said `fake_cloud_firestore`; this plan adds it (Task 1) plus the injectable-base refactor (Task 2), so the service layer is genuinely unit-tested — matching the "add real service tests" decision. `MessageStatus` lives in the package (not "UI only" as §6 loosely said) so its derivation is unit-tested (Task 8).

**Not in this plan (later plans):** the Go `message_written` trigger (Plan 2), the Flutter feature/UI + entry points + FCM (Plan 3), and Firestore/Storage/RTDB rules + indexes + deploy (Plan 4).

**Placeholder scan:** none — every code step contains full source.

**Type consistency:** method names used consistently across tasks — `findOrCreate` (repo) wraps `findAnchoredRoom` (service); `markDelivered/markRead/markHandled`, `editMessage/deleteMessage`, `toChatRoom()/toMessage()/toEntity()`, `collectionPrefix`, `roomMatchesAnchor`, `unreadFor`, `messageStatus`, `shouldSendTyping`, `isActivelyTyping` all defined once and reused as referenced.
