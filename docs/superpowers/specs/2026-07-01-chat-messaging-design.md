# Chat / Messaging — Design Spec

- **Issue:** [anatechopc/loooans#61](https://github.com/anatechopc/loooans/issues/61)
- **Deferred backlog:** [anatechopc/loooans#138](https://github.com/anatechopc/loooans/issues/138)
- **Date:** 2026-07-01 (Rev 3 — added team-inbox auto-handled coordination; anti-spam & manual-claim deferred to #138)
- **Status:** Design approved, ready for implementation plan
- **Scope:** finstack monorepo — new Flutter feature, new shared package, new Go trigger, Firestore + Storage + RTDB rules

---

## 1. Summary

A general-purpose, real-time messaging feature for the loans app. Borrowers and lenders (and, later, other participant combinations) exchange text and file/image messages inside **rooms**, anchored to a domain entity (a product or a loan) in v1. The Flutter app writes messages directly to Firestore; a Go Cloud Function reacts to each new message to maintain room metadata, read sequencing, and push notifications. Messages support **delivered/read receipts**, **per-staff unread**, a **team-inbox layer** (auto-handled), **edit/delete**, and **typing indicators** (via Realtime Database).

The issue's original sketch (`messages/<room_id>` doc + a `threads` subcollection) is adopted with two refinements: the top-level collection is named `chat_rooms`, and the (flat) message subcollection is named `messages`.

---

## 2. Decisions (locked)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Participants | General-purpose. A participant is a **user OR a company**; rooms hold N participants. |
| 2 | Room anchoring | Room doc carries optional `context_type`/`context_id`. **v1 creates anchored rooms only** (product/loan); freeform DMs deferred. |
| 3 | Write path | **Client writes the message; a Go trigger does side effects.** No HTTP send endpoint. |
| 4 | Threading | **Flat messages** (chronological). Subcollection named `messages`. |
| 5 | Content | **Text + any files** (images and arbitrary files). |
| 6 | Read model | **Sequence-based.** Room `last_seq` + per-**user** `reads` watermarks. Powers per-staff unread, receipts, and the team layer from one structure. |
| 7 | Receipts | **Delivered + Read (double ticks).** Recipients' clients ack delivery on arrival (foreground listener + FCM background handler) and read on open. |
| 8 | Unread | **Per-staff** (keyed by real userId) — each staff member's own unread badge. Company team layer in #14. |
| 9 | Edit/Delete | Own messages. Edit → `text` + `edited_at` ("edited"). Delete → soft tombstone `deleted_at` ("This message was deleted"). No time window in v1. |
| 10 | Typing indicators | **Realtime Database** (`typing/{roomId}/{userId}`) with `onDisconnect` cleanup. Not Firestore. |
| 11 | Lender identity | **Company as participant** — any of its staff can read/respond. `sender_id` (audit) + `sender_participant_id` (company for display). |
| 12 | Collection layout | **Option A — subcollection**: `chat_rooms/{roomId}` + `chat_rooms/{roomId}/messages/{msgId}`. |
| 13 | Push | Direct **FCM data-push** from the trigger (payload carries `roomId` + `seq`). No persistent notification-list entries. |
| 14 | Team inbox | **Auto-handled.** A company handled watermark (`team_reads`) that any staffer advances by **reading or replying** → clears the room from the team queue and feeds a shared **awaiting-response** aggregate. No manual claim/assignment (→ #138). |

### Explicit non-goals (future) — tracked in [#138]
- **Manual claim/assignment for team inbox** — explicit assign-to-me, "my conversations" vs "unclaimed" filters, reassignment. v1 ships **auto-handled** only.
- **Marketplace anti-spam / abuse prevention on room creation** — rate limits, App Check. Deferred; anchored + dedup already blocks obvious duplicate-room spam.
- Reply threading, message reactions, message search, edit history, edit/delete time limits.
- Freeform DM discovery / people-picker.

---

## 3. Architecture

```
┌──────────────────────────────┐          ┌───────────────────────────────┐
│  Flutter (apps/loans)         │  write   │  Go (functions/loans)         │
│  features/chat/               │ ───────▶ │  triggers/message_written.go  │
│    ConversationsBloc (inbox)  │  message │   (adapter)                    │
│    ChatBloc (one room)        │          │   + core pkg (testable logic) │
│                               │  realtime│    create: assign seq,         │
│  packages/core/chat_repository│ ◀─────── │      last_message, last_seq,   │
│    ChatRoomRepository         │  snapshot│      team_reads (on co. reply),│
│    MessageRepository          │          │      FCM data-push             │
│    TypingService (RTDB)       │          │    update: refresh last_message│
└───────────┬──────────────────┘          └───────────────────────────────┘
            │  typing (RTDB)                          │
            ▼                                         ▼
   RTDB: typing/{roomId}/{userId}      Firestore: chat_rooms/{id} (+ /messages/{id})
                                       Storage:  chat/{roomId}/{msgId}/{fileName}
```

**New units of work**

1. `packages/core/chat_repository` (Flutter/Dart) — shared, reusable. Includes `TypingService` (RTDB).
2. `apps/loans/lib/features/chat/` (Flutter) — feature UI + BLoCs + routing wiring.
3. `functions/loans/triggers/message_written.go` (Go, adapter) + a core package with the business logic and fakes.
4. Firestore security rules for `chat_rooms` (+ subcollection).
5. Cloud Storage security rules for `chat/…`.
6. RTDB rules for `typing/…` (dev-stg + prod rule files).

---

## 4. Data model

### 4.1 `chat_rooms/{roomId}` (top-level, env-prefixed `dev_`/`stg_`/none)

| field | type | written by | notes |
|-------|------|-----------|-------|
| `id` | string | client | doc id |
| `participants` | list&lt;map&gt; | client (on create) | `{ id, type: "user"｜"company", display_name, photo_url }` — denormalized |
| `member_ids` | list&lt;string&gt; | client (on create) | every participant's `id`; powers the inbox `array-contains-any` query |
| `context_type` | string? | client | `"product"` ｜ `"loan"` ｜ `"company"` ｜ null |
| `context_id` | string? | client | anchored entity id |
| `last_seq` | int | **trigger** | monotonic message counter; basis for unread, receipts, team handled |
| `last_message` | map? | **trigger** | `{ text (preview), sender_participant_id, type, seq, created_at }` |
| `reads` | map&lt;userId, map&gt; | **client** (own entry) | `{ last_delivered_seq, last_delivered_at, last_read_seq, last_read_at }` per real user — personal per-staff state |
| `team_reads` | map&lt;companyId, map&gt; | **client** (staff, on read) + **trigger** (on company reply) | `{ last_handled_seq, last_handled_at, handled_by }` — team handled watermark per company participant |
| `created_by` | string | client | uid of creator |
| `created_at` | int64 millis | client | |
| `updated_at` | int64 millis | client + trigger | bumped on each new message |
| `deleted_at` | int64 millis? | — | soft-delete of the room (future) |

### 4.2 `chat_rooms/{roomId}/messages/{msgId}`

| field | type | written by | notes |
|-------|------|-----------|-------|
| `id` | string | client | doc id |
| `room_id` | string | client | denormalized parent id |
| `seq` | int? | **trigger** | assigned on create (transaction). Null briefly = "pending/sending" |
| `sender_id` | string | client | **actual user** who sent (audit — even when staff reply) |
| `sender_participant_id` | string | client | participant entry this counts as: user's own id, or **company id** when staff reply |
| `type` | string | client | `"text"` ｜ `"image"` ｜ `"file"` |
| `text` | string? | client | text body / optional caption |
| `attachments` | list&lt;map&gt; | client | `{ name, url, thumbnail_url?, content_type, size }` |
| `created_at` | int64 millis | client | display ordering key |
| `updated_at` | int64 millis | client | |
| `edited_at` | int64 millis? | client | set on edit → UI shows "edited" |
| `deleted_at` | int64 millis? | client | set on delete → tombstone |

**Date convention:** all timestamps are int64 millis since epoch. Dart entities follow existing `createdAt`/`updatedAt` serialization; the Go trigger must use `.UnixMilli()` (never raw `time.Time`).

### 4.3 `sender_id` vs `sender_participant_id`
When company staff reply, the borrower sees the message as coming from *the company*, while we record which staff member typed it. `sender_id` = staff user (audit + "own message" alignment); `sender_participant_id` = company id (display grouping + the entry the trigger excludes from unread).

### 4.4 Read model (sequence-based)
- `seq` is a per-room monotonic integer assigned by the trigger on message create.
- **Personal** — `reads[userId]` holds `last_delivered_seq` and `last_read_seq` (+ timestamps). For a message with seq `S`:
  - **delivered to user U** ⇔ `reads[U].last_delivered_seq ≥ S`
  - **read by user U** ⇔ `reads[U].last_read_seq ≥ S`
  - **unread for user U** = `max(0, last_seq − reads[U].last_read_seq)`. Sending sets the sender's `last_read_seq = last_seq` so own messages never count.
- **Company aggregation for receipts** (borrower's view of a company counterpart): delivered/read = the **max** personal watermark across that company's staff users.
- **Team handled** — `team_reads[companyId].last_handled_seq` (+ `handled_at`, `handled_by`). Advanced to `max(current, S)` whenever **any** staffer reads up to `S`, or the company **replies** (trigger sets it to the reply's seq). A room is **handled** when `last_handled_seq ≥ last_seq`, else **awaiting response**. This is independent of individual staff unread.

---

## 5. Flows

### 5.1 Create-or-open room (anchored, dedup)
Triggered by a "Message …" button (§8). The repository: build participant set + `context_type`/`context_id`; query `chat_rooms` where `member_ids array-contains <currentId>` and match participant set + context; open if found, else create then open. Makes "Message lender" idempotent.

### 5.2 Send a message
1. If attachments: upload each to Storage `chat/{roomId}/{msgId}/{fileName}` via `storage_repository` (`upload()` for images → thumbnail; `uploadFile()` otherwise); collect `{ url, thumbnail_url?, content_type, size }`.
2. Client writes the message doc (no `seq` yet → shows "sending").
3. `message_written` trigger fires on **create**: in a transaction reads room `last_seq`, sets message `seq = last_seq+1`, writes room `last_seq`, `last_message`, `updated_at`; **if `sender_participant_id` is a company**, advances `team_reads[companyId]` to that seq (`handled_by = sender_id`); then resolves recipients → device tokens → FCM data-push (payload `{ roomId, seq }`).

### 5.3 Delivered ack
When a recipient's client observes a new message:
- **Foreground / room open:** the room's live message listener sees seq `S`; client raises `reads[myUserId].last_delivered_seq` to `max(current, S)`.
- **Backgrounded / closed:** the FCM background handler (extended in `notification_service.dart`) reads `seq` from the push payload and raises `last_delivered_seq`.
Writes are coalesced to the max seq seen (not one write per message).

### 5.4 Read ack (+ team handled)
When a user has the room open and the messages are visible, the client raises `reads[myUserId].last_read_seq` (and `last_delivered_seq`) to the latest visible seq. If the reader is company staff, the client also advances `team_reads[theirCompanyId].last_handled_seq` to the same seq (`handled_by = userId`). This clears personal unread, drives the sender's "Read" tick, and marks the room handled for the team.

### 5.5 Edit / delete (own messages)
- **Edit:** client updates `text`, sets `edited_at`. UI shows "edited".
- **Delete:** client sets `deleted_at` (soft). UI renders a tombstone; attachments may be removed from Storage.
- The `message_written` trigger's **update** branch: if the changed message is the room's latest (`seq == last_seq`), refresh `last_message` (deleted → "message deleted"). No seq/unread/team change, no push.

### 5.6 Recipient resolution (trigger → FCM)
For each participant `≠ sender_participant_id`:
- **user participant:** device tokens from `users/{id}/devices`.
- **company participant:** query `users` where `company_id == <companyId>` (staff), collect each staff user's device tokens.
No persistent notification-list document (chat would spam it); unread is the durable signal.

### 5.7 Typing indicators (RTDB)
- On composing, client writes `typing/{roomId}/{userId} = { at: <ts> }` (throttled, ≤ once/2s) and sets `onDisconnect().remove()`.
- Clients listen to `typing/{roomId}`; an entry is "actively typing" if `now − at < ~5s`.
- No Firestore or trigger involvement.

### 5.8 Inbox + unread + team queue
- Inbox = `chat_rooms` where `member_ids array-contains-any [myUserId, myCompanyId?]`, ordered `updated_at desc`, `deleted_at == null`. Requires a composite index.
- **Personal unread badge** = Σ over inbox of `max(0, last_seq − reads[myUserId].last_read_seq)` (from the room docs already in the stream — no extra reads).
- **Team "awaiting response" aggregate** (staff of company C) = count of inbox rooms where `last_seq > team_reads[C].last_handled_seq`. Surfaced as a company backlog indicator / inbox filter; per-room state shows **handled (by X)** vs **awaiting response**.

---

## 6. `packages/core/chat_repository`

Follows the established repository pattern (`BaseRepository<T>` + `BaseFirestoreService<T>`, entity/model split, `*.g.dart`, `dataStream`).

**Public API**
- `ChatRoomRepository` — top-level `chat_rooms` (`BaseFirestoreService`, collection name `chat_rooms`, env prefix via `root`). Methods: `findAnchoredRoom(...)`, `createRoom(...)`, `markDelivered(roomId, userId, seq)`, `markRead(roomId, userId, seq)`, `markHandled(roomId, companyId, userId, seq)`.
- `MessageRepository` — the one **deviation**: its Firestore service operates on a **subcollection** scoped by `roomId`. `BaseFirestoreService.root` only builds top-level references, so the message service overrides `root` → `chatRoomsRoot.doc(roomId).collection('messages')` (env prefix applies to the `chat_rooms` segment only; subcollections are not prefixed). Provides a paginated real-time `dataStream` ordered by `created_at`, plus `editMessage(...)` and `deleteMessage(...)`.
- `TypingService` — RTDB-backed (extends the existing `BaseRealtimeDatabaseService`). `setTyping(roomId, userId)` (throttled, with `onDisconnect` cleanup) and `typingStream(roomId)`.

**Models**
- `ChatRoom`/`ChatRoomEntity`, `Message`/`MessageEntity`.
- `ReadState { lastDeliveredSeq, lastDeliveredAt, lastReadSeq, lastReadAt }`, `TeamReadState { lastHandledSeq, lastHandledAt, handledBy }`.
- `Participant { id, ParticipantType type, displayName, photoUrl }`, `ParticipantType { user, company }`.
- `MessageType { text, image, file }`, `Attachment { name, url, thumbnailUrl?, contentType, size }`.
- `MessageStatus { sending, sent, delivered, read }` (derived in the UI from `seq` + counterpart watermark).

---

## 7. `functions/loans` — `message_written`

- **Adapter+core split** (repo convention + tests-required rule): `triggers/message_written.go` is the thin CloudEvent entry point; logic lives in a core package taking interfaces for Firestore + FCM, with fakes in `functions/loans/test/fakes/`.
- Trigger scope: **written** (create + update) on `{prefix}chat_rooms/{roomId}/messages/{messageId}`. `roomId` from the path wildcard; branch on create vs update via presence of `oldValue`.
- **Create branch:** transaction to assign `seq` and bump room `last_seq`; write `last_message`, `updated_at`; if `sender_participant_id` is a company, advance `team_reads[companyId]` to the new seq (`handled_by = sender_id`); resolve recipients (user + company→staff) → tokens; send FCM data-push (`{ roomId, seq }`).
- **Update branch:** if the message is the room's latest, refresh `last_message` (deleted → "message deleted"). No seq/unread/team/push.
- Reuses `utils.GetCollectionPrefix()`, `utils.InitializeFirebase`, `.UnixMilli()`, and the FCM multicast pattern from `notification_created.go` / `notification_helpers.go`.

---

## 8. UI / UX

Primary nav: left **side-menu drawer** (`MenuDrawerWidget` from `Constants.allMenu`) + top **app bar** (`AppWidgets.defaultAppBar`). Detail screens: `loan_offer_detail.dart`, `loan_details.dart`, `loan_client_detail.dart` / `borrower_detail_screen.dart`.

### 8.1 Entry points (v1)
1. **Side-menu "Messages"** item (`show: true` for all roles) + unread badge → `/chat`.
2. **App-bar chat-bubble icon** with global unread badge.
3. **Borrower on `loan_offer_detail`** → "Message lender" → room anchored `product` + company.
4. **Borrower on `loan_details`** → "Message lender" → room anchored `loan` + company.
5. **Staff on `loan_client_detail` / `borrower_detail_screen`** → "Message borrower" → room with that customer (optionally anchored to the loan).

### 8.2 Screens
- **`ConversationsScreen` (inbox, `/chat`)** — rooms sorted by recency. Row: counterpart name/avatar, last-message preview + relative time, **personal unread badge**. For staff: a **handled / awaiting-response** indicator per room and a company **"awaiting" aggregate** (header count or a filter toggle "Awaiting / All"). States: empty, loading, error. Green background → **black text** for empty/message states (repo contrast rule).
- **`ChatScreen` (`/chat/:roomId`)** — app bar: counterpart + optional context chip ("Re: <product>") + (staff) a "handled by X" hint. Message list: own messages right-aligned with **status ticks** (sending → sent → delivered → read), others left-aligned with sender label for company/staff. A **typing indicator** row (RTDB). **Composer**: text field, attach button (file/image picker), send. Attachments: **image → inline thumbnail** (tap to view full); **file → file chip** (name + size + type icon). **Long-press own message → edit / delete**; edited → "edited"; deleted → tombstone.

### 8.3 Cross-cutting UI
- Badges: side-menu item, app-bar icon, inbox rows (personal); staff also see the team awaiting-response indicator/aggregate.
- FCM tap → `/chat/:roomId`; FCM background handler also writes the **delivered** watermark from payload `seq`.
- Routing: add `Paths.chat = '/chat'` and `Paths.chatRoom = '/chat/:roomId'`; register in `router.dart`; provide repositories in `repository_providers.dart` and BLoCs in `bloc_providers.dart`.

_(No high-fidelity mockups for v1 — chat UI follows established conventions and the app's existing look.)_

---

## 9. Security rules

**Firestore** (`chat_rooms` + `messages` subcollection):
- **Read** room/messages: requester is a participant — `request.auth.uid ∈ member_ids`, OR a company in `member_ids` the requester is staff of (their user doc's `company_id` matches).
- **Create message**: requester is a participant; `sender_id == request.auth.uid`; `sender_participant_id` is one they may act as (own uid or their `company_id`); may not set `seq`/room fields (trigger-only).
- **Edit/delete message**: only `sender_id == request.auth.uid`; may change only `text`/`edited_at` (edit) or `deleted_at` (delete) — enforced via `diff().affectedKeys()`.
- **Update room**: a participant may change only (a) their own `reads[uid]` sub-entry, and (b) if staff, `team_reads[theirCompanyId]` — both monotonically non-decreasing. `last_seq`/`last_message`/`updated_at` are trigger-only.
- **Create room**: authenticated; creator in `participants`; `created_by == request.auth.uid`.

**Cloud Storage** (`chat/{roomId}/…`): gate on room participation via `firestore.get()`.
> ⚠️ **Plan item:** Storage rules must reference the **env-prefixed** collection (`dev_chat_rooms` vs `chat_rooms`). Resolve by encoding env in the storage path (`chat/{env}/{roomId}/…`) or per-project rule variable.

**RTDB** (`typing/{roomId}/{userId}`): read/write limited to authenticated room participants; `$userId == auth.uid` for writes. Add to `database.rules.json` (dev-stg) and `database.rules.prod.json` (prod, deployed manually).

All rules are **console-managed / manually deployed** per repo convention and must be in place before prod.

---

## 10. Testing

- **Dart:**
  - `chat_repository` unit tests with `fake_cloud_firestore` (create/dedup room, subcollection message stream, edit/delete, unread math, delivered/read watermarks, **team-handled watermark**). `TypingService` tested against a fake/mock RTDB.
  - `bloc_test` for `ConversationsBloc` (inbox stream, per-staff unread totals, **team awaiting-response aggregate**) and `ChatBloc` (send text, send attachment w/ upload, receive, delivered/read transitions, mark-handled, edit, delete, typing, error paths).
  - Widget tests for `ConversationsScreen` and `ChatScreen` (empty/loading/error, bubble alignment, status ticks, typing row, attachment rendering, edit/delete menu, tombstone, handled/awaiting indicator).
- **Go:** core-logic unit tests with Firestore + FCM fakes in `functions/loans/test/fakes/` — create branch (seq assignment + monotonicity, `last_message`, **team_reads advance on company reply**, company→staff fan-out, push payload incl. `seq`) and update branch (latest edited/deleted refresh, non-latest no-op). Run `CGO_ENABLED=0 go test ./...` locally (macOS dyld gotcha).

---

## 11. Build sequence (high level; detailed in the plan)

1. `packages/core/chat_repository` — models (incl. `ReadState`, `TeamReadState`, `MessageStatus`), entities, services (rooms, messages-subcollection, `TypingService` RTDB), repositories, unit tests.
2. Firestore composite index (inbox query) + Firestore/Storage/RTDB rules drafts.
3. Go `message_written` core + adapter + fakes + tests (create + update branches, team_reads).
4. Flutter feature: BLoCs → screens → widgets (bubbles, status ticks, typing row, composer, attachment rendering, edit/delete menu, handled/awaiting indicator) → routing/DI wiring → FCM tap + background delivered-ack.
5. Entry-point buttons on the four detail screens + side-menu item + app-bar icon.
6. Rules deploy checklist (Firestore + Storage env-prefix resolution + RTDB dev-stg/prod).

---

## 12. Open items to resolve during planning
- Storage-rules env-prefix approach (§9).
- Exact composite index definition for the inbox query.
- Whether `MessageRepository` subclasses `BaseFirestoreService` (override `root`) or introduces a small `BaseSubcollectionFirestoreService`.
- Attachment size/type limits and the file-picker package already used in the app.
- FCM background handler wiring for the delivered watermark (confirm background Firestore write works on both platforms).
- Throttle/coalesce policy for delivered/read/handled watermark writes and typing writes.
- Company-aggregated receipt + team-awaiting display cost when a room has many staff (max-watermark scan).
