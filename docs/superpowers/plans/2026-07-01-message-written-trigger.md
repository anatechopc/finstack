# message_written Trigger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Go Cloud Function `messageWritten`, a Firestore `document.v1.written` trigger on `chat_rooms/{roomId}/messages/{messageId}` that assigns a monotonic `seq`, maintains `last_message`/`team_reads`, and sends FCM push to the other participants.

**Architecture:** Adapter+core split (repo convention). `triggers/message_written_core.go` holds `HandleMessageWrittenCore` with all logic behind an injected `MessageWrittenDeps` struct of func fields; `triggers/message_written.go` is the CloudEvent adapter that parses the event and wires real Firestore/FCM. Tests live in the root module under `test/triggers/` (`package triggers_test`) using dependency-free fakes in `test/fakes/`.

**Tech Stack:** Go 1.22, firebase-admin `firebase.google.com/go/v4` (Firestore + messaging), cloudevents, `google-cloudevents-go/cloud/firestoredata`, protobuf. Tests: stdlib `testing` + `com.loooans.app/test/fakes`.

**Spec:** `docs/superpowers/specs/2026-07-01-chat-messaging-design.md` (Rev 3), §5.2/§5.5/§7.

### Conventions & decisions baked in
- **Adapter+core**: logic in `*_core.go`, `HandleXxxCore(ctx, …, XxxDeps)`, deps = struct of `func` fields; adapter builds real deps. Mirrors `PaymentCreated`/`ReviewCreated`.
- **Direct FCM, no notification doc** (spec #13): the core calls `deps.SendPush(...)`; the adapter fetches device tokens (`users/{id}/devices`) and calls `SendEachForMulticast`, mirroring `notification_created.go`. This *deviates* from the repo's usual `createNotification` pattern on purpose — chat would spam the notifications list. Payload carries `room_id`/`message_id`/`seq` for the client to open the room + ack delivery.
- **Dates = int64 millis** via `.UnixMilli()`; read back via `utils.ToInt64`.
- **seq allocation is transactional** (`fs.RunTransaction`, `tx.Get`→`tx.Set(..., firestore.MergeAll)`), mirroring `verify_otp.go`/`user_changes.go`.
- **Fakes stay dependency-free** (only stdlib + `com.loooans.app/types`); shared value type `types.ChatParticipant` lives in the `types` module so both `triggers` and `test/fakes` can use it.
- **Test placement**: `test/triggers/` (root module) so `go test ./...` from `functions/loans` runs them; the `triggers/` submodule itself has no test files.
- **Exported test surface**: helpers verified by the external `triggers_test` package must be exported (`ParseMessagePath`, `HandleMessageWrittenCore`).
- **Re-trigger safety**: the adapter stamps `seq` onto the message (a write) which re-fires the trigger as an *update*; the update branch no-ops unless `edited_at`/`deleted_at` changed, so no loop.
- **Module typo**: `triggers/go.mod` declares `module com.looans.app/triggers` (two o's) but is imported as `com.loooans.app/triggers` via `replace`. Leave it; new code is just `package triggers`.
- **Build caveat**: `go build ./...` from `functions/loans` skips submodules; verify trigger code with `cd functions/loans/triggers && CGO_ENABLED=0 go build ./...`. Run tests with `CGO_ENABLED=0` (macOS dyld gotcha).

---

### Task 1: `ParseMessagePath` helper

**Files:**
- Create: `functions/loans/triggers/message_written.go` (starts with just this helper; adapter added in Task 6)
- Test: `functions/loans/test/triggers/message_path_test.go`

- [ ] **Step 1: Write the failing test**

```go
package triggers_test

import (
	"testing"

	"com.loooans.app/triggers"
)

func TestParseMessagePath(t *testing.T) {
	cases := []struct {
		name              string
		in                string
		room, msg         string
		ok                bool
	}{
		{
			name: "dev prefix",
			in:   "projects/p/databases/(default)/documents/dev_chat_rooms/r1/messages/m1",
			room: "r1", msg: "m1", ok: true,
		},
		{
			name: "no prefix (prod)",
			in:   "projects/p/databases/(default)/documents/chat_rooms/r2/messages/m2",
			room: "r2", msg: "m2", ok: true,
		},
		{
			name: "wrong subcollection",
			in:   "projects/p/databases/(default)/documents/dev_chat_rooms/r1/reads/x",
			ok:   false,
		},
		{
			name: "not a message path",
			in:   "projects/p/databases/(default)/documents/dev_users/u1",
			ok:   false,
		},
	}
	for _, c := range cases {
		room, msg, ok := triggers.ParseMessagePath(c.in)
		if ok != c.ok || room != c.room || msg != c.msg {
			t.Errorf("%s: got (%q,%q,%v) want (%q,%q,%v)",
				c.name, room, msg, ok, c.room, c.msg, c.ok)
		}
	}
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd functions/loans && CGO_ENABLED=0 go test ./test/triggers/ -run TestParseMessagePath -v`
Expected: FAIL — `triggers.ParseMessagePath` undefined (won't compile).

- [ ] **Step 3: Create `message_written.go` with the helper**

```go
package triggers

import "strings"

// ParseMessagePath extracts roomId and messageId from a Firestore document
// resource name of the form
// projects/{p}/databases/{db}/documents/{prefix}chat_rooms/{roomId}/messages/{messageId}.
// It is prefix-agnostic (dev_/stg_/none).
func ParseMessagePath(name string) (roomId, messageId string, ok bool) {
	const marker = "/documents/"
	idx := strings.Index(name, marker)
	if idx < 0 {
		return "", "", false
	}
	segs := strings.Split(name[idx+len(marker):], "/")
	if len(segs) != 4 {
		return "", "", false
	}
	if !strings.HasSuffix(segs[0], "chat_rooms") || segs[2] != "messages" {
		return "", "", false
	}
	return segs[1], segs[3], true
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd functions/loans && CGO_ENABLED=0 go test ./test/triggers/ -run TestParseMessagePath -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add functions/loans/triggers/message_written.go functions/loans/test/triggers/message_path_test.go
git commit -m "feat(functions): add ParseMessagePath for chat message trigger"
```

---

### Task 2: `types.ChatParticipant` + fakes

**Files:**
- Create: `functions/loans/types/chat.go`
- Modify: `functions/loans/test/fakes/go.mod` (add `types` dep)
- Modify: `functions/loans/test/fakes/fakes.go` (append chat fakes)

- [ ] **Step 1: Create `types/chat.go`**

```go
package types

// ChatParticipant is a room participant reference shared by the trigger core
// and its test fakes. Type is "user" or "company".
type ChatParticipant struct {
	Id   string
	Type string
}
```

- [ ] **Step 2: Wire `types` into the fakes module**

In `functions/loans/test/fakes/go.mod`, add (module has no deps today):
```go
require com.loooans.app/types v0.0.0-00010101000000-000000000000

replace com.loooans.app/types => ../../types
```
Run: `cd functions/loans/test/fakes && go mod tidy`
Expected: resolves `com.loooans.app/types` via the replace; no errors.

- [ ] **Step 3: Append chat fakes to `test/fakes/fakes.go`**

Add the `types` import to the existing import block, then append:
```go
// ---- chat / message_written fakes ----

// ChatRoomInfo is the canned room state for RoomReader.
type ChatRoomInfo struct {
	LastSeq      int64
	Participants []types.ChatParticipant
}

// RoomReader fakes MessageWrittenDeps.GetRoom.
type RoomReader struct {
	Rooms map[string]ChatRoomInfo
	Err   error
	Calls []string
}

func (r *RoomReader) GetRoom(_ context.Context, roomId string) (int64, []types.ChatParticipant, error) {
	r.Calls = append(r.Calls, roomId)
	if r.Err != nil {
		return 0, nil, r.Err
	}
	info := r.Rooms[roomId]
	return info.LastSeq, info.Participants, nil
}

// SeqAllocator fakes MessageWrittenDeps.AllocateSeq (returns an incrementing seq).
type SeqAllocator struct {
	Start int64
	Err   error
	Calls []string
}

func (s *SeqAllocator) AllocateSeq(_ context.Context, roomId, messageId string) (int64, error) {
	s.Calls = append(s.Calls, roomId+":"+messageId)
	if s.Err != nil {
		return 0, s.Err
	}
	s.Start++
	return s.Start, nil
}

// RoomMetaUpdate records one UpdateRoomMeta call.
type RoomMetaUpdate struct {
	RoomId string
	Meta   map[string]any
}

// RoomMetaWriter fakes MessageWrittenDeps.UpdateRoomMeta.
type RoomMetaWriter struct {
	Updates []RoomMetaUpdate
	Err     error
}

func (w *RoomMetaWriter) UpdateRoomMeta(_ context.Context, roomId string, meta map[string]any) error {
	w.Updates = append(w.Updates, RoomMetaUpdate{RoomId: roomId, Meta: meta})
	return w.Err
}

// ChatPush records one SendPush call.
type ChatPush struct {
	Recipients []string
	Title      string
	Body       string
	Data       map[string]string
}

// ChatPusher fakes MessageWrittenDeps.SendPush.
type ChatPusher struct {
	Pushes []ChatPush
	Err    error
}

func (p *ChatPusher) SendPush(_ context.Context, recipients []string, title, body string, data map[string]string) error {
	p.Pushes = append(p.Pushes, ChatPush{Recipients: recipients, Title: title, Body: body, Data: data})
	return p.Err
}
```
(`CompanyUsersReader` already exists and is reused for `CompanyUserIds`.)

- [ ] **Step 4: Verify the fakes + types modules compile**

Run: `cd functions/loans/types && CGO_ENABLED=0 go build ./... && cd ../test/fakes && CGO_ENABLED=0 go build ./...`
Expected: both build clean.

- [ ] **Step 5: Commit**

```bash
git add functions/loans/types/chat.go functions/loans/test/fakes/
git commit -m "feat(functions): add ChatParticipant type + message_written test fakes"
```

---

### Task 3: Core — create branch (seq, last_message, recipient push)

**Files:**
- Create: `functions/loans/triggers/message_written_core.go`
- Modify: `functions/loans/triggers/go.mod` (promote `types` to a direct dep)
- Test: `functions/loans/test/triggers/message_written_core_test.go`

- [ ] **Step 1: Write the failing test**

```go
package triggers_test

import (
	"context"
	"sort"
	"testing"

	"com.loooans.app/test/fakes"
	"com.loooans.app/triggers"
	"com.loooans.app/types"
)

func fixedNow() func() interface{ } { return nil } // placeholder, replaced below

func chatDeps(
	rooms *fakes.RoomReader, seq *fakes.SeqAllocator, meta *fakes.RoomMetaWriter,
	company *fakes.CompanyUsersReader, push *fakes.ChatPusher,
) triggers.MessageWrittenDeps {
	return triggers.MessageWrittenDeps{
		GetRoom:        rooms.GetRoom,
		AllocateSeq:    seq.AllocateSeq,
		UpdateRoomMeta: meta.UpdateRoomMeta,
		CompanyUserIds: company.CompanyUserIds,
		SendPush:       push.SendPush,
		Now:            triggers.FixedClock(1_700_000_000_000),
	}
}

func borrowerCompanyRoom() *fakes.RoomReader {
	return &fakes.RoomReader{Rooms: map[string]fakes.ChatRoomInfo{
		"r1": {
			LastSeq: 0,
			Participants: []types.ChatParticipant{
				{Id: "u1", Type: "user"},
				{Id: "c1", Type: "company"},
			},
		},
	}}
}

func TestCreate_BorrowerSends_PushesCompanyStaff_AndWritesLastMessage(t *testing.T) {
	rooms := borrowerCompanyRoom()
	seq := &fakes.SeqAllocator{}
	meta := &fakes.RoomMetaWriter{}
	company := &fakes.CompanyUsersReader{Users: map[string][]string{"c1": {"admin1", "teller1"}}}
	push := &fakes.ChatPusher{}

	ev := triggers.MessageEvent{
		RoomId: "r1", MessageId: "m1",
		New: map[string]any{
			"sender_id": "u1", "sender_participant_id": "u1",
			"type": "text", "text": "hello", "created_at": int64(111),
		},
	}
	if err := triggers.HandleMessageWrittenCore(context.Background(), ev, chatDeps(rooms, seq, meta, company, push)); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}

	// seq allocated once
	if len(seq.Calls) != 1 || seq.Calls[0] != "r1:m1" {
		t.Fatalf("AllocateSeq calls: %v", seq.Calls)
	}
	// last_message written with seq 1
	if len(meta.Updates) != 1 {
		t.Fatalf("expected 1 meta update, got %d", len(meta.Updates))
	}
	lm := meta.Updates[0].Meta["last_message"].(map[string]any)
	if lm["seq"].(int64) != 1 || lm["text"].(string) != "hello" {
		t.Errorf("last_message: %+v", lm)
	}
	if _, hasTeam := meta.Updates[0].Meta["team_reads"]; hasTeam {
		t.Errorf("borrower message must not advance team_reads")
	}
	// pushed to company staff, not the sender
	if len(push.Pushes) != 1 {
		t.Fatalf("expected 1 push, got %d", len(push.Pushes))
	}
	got := append([]string{}, push.Pushes[0].Recipients...)
	sort.Strings(got)
	if want := []string{"admin1", "teller1"}; !equalStrs(got, want) {
		t.Errorf("recipients: got %v want %v", got, want)
	}
	if push.Pushes[0].Data["room_id"] != "r1" || push.Pushes[0].Data["seq"] != "1" ||
		push.Pushes[0].Data["notification_type"] != "chat" {
		t.Errorf("push data: %+v", push.Pushes[0].Data)
	}
}

func TestCreate_CompanySends_PushesBorrower_SkipsCompanyStaff(t *testing.T) {
	rooms := borrowerCompanyRoom()
	seq := &fakes.SeqAllocator{}
	meta := &fakes.RoomMetaWriter{}
	company := &fakes.CompanyUsersReader{Users: map[string][]string{"c1": {"admin1"}}}
	push := &fakes.ChatPusher{}

	ev := triggers.MessageEvent{
		RoomId: "r1", MessageId: "m2",
		New: map[string]any{
			"sender_id": "admin1", "sender_participant_id": "c1",
			"type": "text", "text": "hi back", "created_at": int64(222),
		},
	}
	if err := triggers.HandleMessageWrittenCore(context.Background(), ev, chatDeps(rooms, seq, meta, company, push)); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(push.Pushes) != 1 || !equalStrs(push.Pushes[0].Recipients, []string{"u1"}) {
		t.Fatalf("expected push to [u1], got %+v", push.Pushes)
	}
	// company reply should NOT re-query its own staff for recipients
	if len(company.Calls) != 0 {
		t.Errorf("company staff should not be expanded for its own outgoing message")
	}
}

func equalStrs(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
```

(Delete the stray `fixedNow` placeholder — it's not used; the real clock helper is `triggers.FixedClock`, defined in Step 3.)

- [ ] **Step 2: Run it to see it fail**

Run: `cd functions/loans && CGO_ENABLED=0 go test ./test/triggers/ -run TestCreate -v`
Expected: FAIL — `triggers.MessageEvent`, `MessageWrittenDeps`, `HandleMessageWrittenCore`, `FixedClock` undefined.

- [ ] **Step 3: Create `message_written_core.go`**

```go
package triggers

import (
	"context"
	"strconv"
	"time"

	"com.loooans.app/types"
	"com.loooans.app/utils"
)

// chatStaffRoles are the roles notified when a company participant is a recipient.
var chatStaffRoles = []string{"admin", "loanOfficer", "teller", "reviewModerator"}

// MessageEvent is the parsed, storage-agnostic view of a message write.
type MessageEvent struct {
	RoomId    string
	MessageId string
	IsDelete  bool           // Firestore hard-delete (GetValue == nil)
	New       map[string]any // nil on hard-delete
	Old       map[string]any // nil on create
}

// MessageWrittenDeps injects every side effect so the core is unit-testable.
type MessageWrittenDeps struct {
	GetRoom        func(ctx context.Context, roomId string) (lastSeq int64, participants []types.ChatParticipant, err error)
	AllocateSeq    func(ctx context.Context, roomId, messageId string) (int64, error)
	UpdateRoomMeta func(ctx context.Context, roomId string, meta map[string]any) error
	CompanyUserIds func(ctx context.Context, companyId string, roles []string) ([]string, error)
	SendPush       func(ctx context.Context, recipientUserIds []string, title, body string, data map[string]string) error
	Now            func() time.Time
}

// FixedClock returns a Now func pinned to the given epoch millis (for tests).
func FixedClock(epochMillis int64) func() time.Time {
	return func() time.Time { return time.UnixMilli(epochMillis).UTC() }
}

// HandleMessageWrittenCore is the trigger's business logic.
func HandleMessageWrittenCore(ctx context.Context, ev MessageEvent, deps MessageWrittenDeps) error {
	if ev.IsDelete {
		return nil // hard delete: nothing to maintain (we soft-delete via update)
	}
	if ev.Old == nil {
		return handleMessageCreate(ctx, ev, deps)
	}
	return handleMessageUpdate(ctx, ev, deps)
}

func handleMessageCreate(ctx context.Context, ev MessageEvent, deps MessageWrittenDeps) error {
	_, participants, err := deps.GetRoom(ctx, ev.RoomId)
	if err != nil {
		return err
	}
	senderPid, _ := ev.New["sender_participant_id"].(string)
	senderId, _ := ev.New["sender_id"].(string)
	msgType, _ := ev.New["type"].(string)
	text, _ := ev.New["text"].(string)
	createdAt, _ := utils.ToInt64(ev.New["created_at"])

	seq, err := deps.AllocateSeq(ctx, ev.RoomId, ev.MessageId)
	if err != nil {
		return err
	}
	now := deps.Now().UTC().UnixMilli()

	meta := map[string]any{
		"updated_at": now,
		"last_message": map[string]any{
			"text":                  messagePreview(msgType, text),
			"sender_participant_id": senderPid,
			"type":                  msgType,
			"seq":                   seq,
			"created_at":            createdAt,
		},
	}
	if isCompanyParticipant(participants, senderPid) {
		meta["team_reads"] = map[string]any{
			senderPid: map[string]any{
				"last_handled_seq": seq,
				"last_handled_at":  now,
				"handled_by":       senderId,
			},
		}
	}
	if err := deps.UpdateRoomMeta(ctx, ev.RoomId, meta); err != nil {
		return err
	}

	recipients, err := recipientUserIds(ctx, participants, senderPid, deps)
	if err != nil {
		return err
	}
	if len(recipients) == 0 {
		return nil
	}
	data := map[string]string{
		"notification_type": "chat",
		"room_id":           ev.RoomId,
		"message_id":        ev.MessageId,
		"seq":               strconv.FormatInt(seq, 10),
	}
	return deps.SendPush(ctx, recipients, "New message", messagePreview(msgType, text), data)
}

func messagePreview(msgType, text string) string {
	switch msgType {
	case "image":
		return "📷 Photo"
	case "file":
		return "📎 File"
	default:
		r := []rune(text)
		if len(r) > 140 {
			return string(r[:140])
		}
		return text
	}
}

func isCompanyParticipant(participants []types.ChatParticipant, id string) bool {
	for _, p := range participants {
		if p.Id == id {
			return p.Type == "company"
		}
	}
	return false
}

func recipientUserIds(
	ctx context.Context, participants []types.ChatParticipant,
	senderPid string, deps MessageWrittenDeps,
) ([]string, error) {
	seen := map[string]bool{}
	var out []string
	add := func(uid string) {
		if uid != "" && !seen[uid] {
			seen[uid] = true
			out = append(out, uid)
		}
	}
	for _, p := range participants {
		if p.Id == senderPid {
			continue
		}
		if p.Type == "company" {
			staff, err := deps.CompanyUserIds(ctx, p.Id, chatStaffRoles)
			if err != nil {
				return nil, err
			}
			for _, uid := range staff {
				add(uid)
			}
		} else {
			add(p.Id)
		}
	}
	return out, nil
}
```

- [ ] **Step 4: Promote `types` to a direct dep of the triggers module**

In `functions/loans/triggers/go.mod`, move `com.loooans.app/types` from the indirect `require` block into the direct `require`, then:
Run: `cd functions/loans/triggers && go mod tidy && CGO_ENABLED=0 go build ./...`
Expected: builds clean (the `handleMessageUpdate` referenced below is added in Task 4 — until then this file references it, so implement Task 4's function stub now OR keep going: add a temporary `func handleMessageUpdate(ctx context.Context, ev MessageEvent, deps MessageWrittenDeps) error { return nil }` at the bottom of this file, to be fleshed out in Task 4).

> Add this temporary stub now so the package compiles:
> ```go
> func handleMessageUpdate(ctx context.Context, ev MessageEvent, deps MessageWrittenDeps) error {
> 	return nil // implemented in Task 4
> }
> ```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd functions/loans && CGO_ENABLED=0 go test ./test/triggers/ -run TestCreate -v`
Expected: PASS (both create tests).

- [ ] **Step 6: Commit**

```bash
git add functions/loans/triggers/ functions/loans/test/triggers/message_written_core_test.go
git commit -m "feat(functions): message_written core create branch (seq, last_message, push)"
```

---

### Task 4: Core — update branch (edit/delete refresh; seq-stamp no-op)

**Files:**
- Modify: `functions/loans/triggers/message_written_core.go` (replace the `handleMessageUpdate` stub)
- Test: `functions/loans/test/triggers/message_written_update_test.go`

- [ ] **Step 1: Write the failing test**

```go
package triggers_test

import (
	"context"
	"testing"

	"com.loooans.app/test/fakes"
	"com.loooans.app/triggers"
	"com.loooans.app/types"
)

func updateRoom(lastSeq int64) *fakes.RoomReader {
	return &fakes.RoomReader{Rooms: map[string]fakes.ChatRoomInfo{
		"r1": {LastSeq: lastSeq, Participants: []types.ChatParticipant{
			{Id: "u1", Type: "user"}, {Id: "c1", Type: "company"},
		}},
	}}
}

func TestUpdate_SeqStamp_NoOp(t *testing.T) {
	rooms := updateRoom(1)
	meta := &fakes.RoomMetaWriter{}
	push := &fakes.ChatPusher{}
	deps := triggers.MessageWrittenDeps{
		GetRoom: rooms.GetRoom, UpdateRoomMeta: meta.UpdateRoomMeta,
		SendPush: push.SendPush, Now: triggers.FixedClock(1),
	}
	// trigger's own seq stamp: old had no seq, new has seq; no edit/delete change
	ev := triggers.MessageEvent{
		RoomId: "r1", MessageId: "m1",
		Old: map[string]any{"text": "hi", "seq": nil, "edited_at": nil, "deleted_at": nil},
		New: map[string]any{"text": "hi", "seq": int64(1), "edited_at": nil, "deleted_at": nil},
	}
	if err := triggers.HandleMessageWrittenCore(context.Background(), ev, deps); err != nil {
		t.Fatalf("err: %v", err)
	}
	if len(meta.Updates) != 0 || len(push.Pushes) != 0 {
		t.Errorf("seq-stamp must be a no-op; meta=%d push=%d", len(meta.Updates), len(push.Pushes))
	}
}

func TestUpdate_DeleteLatest_RefreshesLastMessageTombstone(t *testing.T) {
	rooms := updateRoom(3)
	meta := &fakes.RoomMetaWriter{}
	push := &fakes.ChatPusher{}
	deps := triggers.MessageWrittenDeps{
		GetRoom: rooms.GetRoom, UpdateRoomMeta: meta.UpdateRoomMeta,
		SendPush: push.SendPush, Now: triggers.FixedClock(999),
	}
	ev := triggers.MessageEvent{
		RoomId: "r1", MessageId: "m3",
		Old: map[string]any{"seq": int64(3), "type": "text", "text": "oops",
			"sender_participant_id": "u1", "created_at": int64(5), "deleted_at": nil},
		New: map[string]any{"seq": int64(3), "type": "text", "text": "oops",
			"sender_participant_id": "u1", "created_at": int64(5), "deleted_at": int64(999)},
	}
	if err := triggers.HandleMessageWrittenCore(context.Background(), ev, deps); err != nil {
		t.Fatalf("err: %v", err)
	}
	if len(meta.Updates) != 1 {
		t.Fatalf("expected last_message refresh, got %d", len(meta.Updates))
	}
	lm := meta.Updates[0].Meta["last_message"].(map[string]any)
	if lm["text"].(string) != "This message was deleted" {
		t.Errorf("expected tombstone preview, got %q", lm["text"])
	}
	if len(push.Pushes) != 0 {
		t.Errorf("edit/delete must not push")
	}
}

func TestUpdate_EditNonLatest_NoOp(t *testing.T) {
	rooms := updateRoom(5) // latest is 5
	meta := &fakes.RoomMetaWriter{}
	deps := triggers.MessageWrittenDeps{
		GetRoom: rooms.GetRoom, UpdateRoomMeta: meta.UpdateRoomMeta,
		Now: triggers.FixedClock(1),
	}
	ev := triggers.MessageEvent{
		RoomId: "r1", MessageId: "m2",
		Old: map[string]any{"seq": int64(2), "text": "a", "edited_at": nil},
		New: map[string]any{"seq": int64(2), "text": "b", "edited_at": int64(42)},
	}
	if err := triggers.HandleMessageWrittenCore(context.Background(), ev, deps); err != nil {
		t.Fatalf("err: %v", err)
	}
	if len(meta.Updates) != 0 {
		t.Errorf("editing a non-latest message must not touch last_message")
	}
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd functions/loans && CGO_ENABLED=0 go test ./test/triggers/ -run TestUpdate -v`
Expected: FAIL — the stub returns nil so `TestUpdate_DeleteLatest...` fails (no meta update).

- [ ] **Step 3: Replace the `handleMessageUpdate` stub**

```go
import "fmt" // add to the existing import block

func handleMessageUpdate(ctx context.Context, ev MessageEvent, deps MessageWrittenDeps) error {
	editedChanged := fmt.Sprint(ev.New["edited_at"]) != fmt.Sprint(ev.Old["edited_at"])
	deletedNow := ev.New["deleted_at"] != nil && ev.Old["deleted_at"] == nil
	if !editedChanged && !deletedNow {
		return nil // trigger's own seq stamp or an irrelevant field write
	}

	lastSeq, _, err := deps.GetRoom(ctx, ev.RoomId)
	if err != nil {
		return err
	}
	seq, _ := utils.ToInt64(ev.New["seq"])
	if seq != lastSeq {
		return nil // not the latest message; last_message preview is unaffected
	}

	msgType, _ := ev.New["type"].(string)
	text, _ := ev.New["text"].(string)
	senderPid, _ := ev.New["sender_participant_id"].(string)
	createdAt, _ := utils.ToInt64(ev.New["created_at"])

	preview := messagePreview(msgType, text)
	if deletedNow {
		preview = "This message was deleted"
	}
	meta := map[string]any{
		"updated_at": deps.Now().UTC().UnixMilli(),
		"last_message": map[string]any{
			"text":                  preview,
			"sender_participant_id": senderPid,
			"type":                  msgType,
			"seq":                   seq,
			"created_at":            createdAt,
		},
	}
	return deps.UpdateRoomMeta(ctx, ev.RoomId, meta)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd functions/loans && CGO_ENABLED=0 go test ./test/triggers/ -run TestUpdate -v`
Expected: PASS (all three update tests).

- [ ] **Step 5: Commit**

```bash
git add functions/loans/triggers/message_written_core.go functions/loans/test/triggers/message_written_update_test.go
git commit -m "feat(functions): message_written core update branch (edit/delete refresh)"
```

---

### Task 5: Adapter — event parsing + real deps

Wires the CloudEvent to the core. The Firestore-transaction/FCM glue here is thin and verified by build (no unit test, matching repo precedent for direct-Firebase code).

**Files:**
- Modify: `functions/loans/triggers/message_written.go` (append the adapter)

- [ ] **Step 1: Append the adapter to `message_written.go`**

Replace the file's `import "strings"` with the full block and append the adapter below `ParseMessagePath`:
```go
package triggers

import (
	"context"
	"fmt"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"com.loooans.app/types"
	"com.loooans.app/utils"
	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"github.com/cloudevents/sdk-go/v2/event"
	"github.com/golang/protobuf/proto"
	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
)

// MessageWritten is the CloudEvent entry point for
// chat_rooms/{roomId}/messages/{messageId} document.v1.written.
func MessageWritten(ctx context.Context, ev event.Event) error {
	log, logErr := utils.InitializeLogger("message_written")
	if logErr != nil {
		return logErr
	}

	var data firestoredata.DocumentEventData
	if err := proto.Unmarshal(ev.Data(), &data); err != nil {
		return fmt.Errorf("proto.Unmarshal: %w", err)
	}

	me, ok := extractMessageWrite(&data)
	if !ok {
		log.Sugar().Warnf("message_written: unparseable event %q; skipping", ev.Source())
		return nil
	}

	app, fbErr := utils.InitializeFirebase(ctx)
	if fbErr != nil {
		return fbErr
	}
	fs, fsErr := app.Firestore(ctx)
	if fsErr != nil {
		return fmt.Errorf("failed to instantiate firestore client: %w", fsErr)
	}
	defer fs.Close()

	prefix := utils.GetCollectionPrefix()
	return HandleMessageWrittenCore(ctx, me, buildMessageWrittenDeps(app, fs, prefix))
}

func extractMessageWrite(data *firestoredata.DocumentEventData) (MessageEvent, bool) {
	var name string
	isDelete := false
	switch {
	case data.GetValue() != nil:
		name = data.GetValue().GetName()
	case data.GetOldValue() != nil:
		name = data.GetOldValue().GetName()
		isDelete = true
	default:
		return MessageEvent{}, false
	}
	roomId, messageId, ok := ParseMessagePath(name)
	if !ok {
		return MessageEvent{}, false
	}
	me := MessageEvent{RoomId: roomId, MessageId: messageId, IsDelete: isDelete}
	if data.GetValue() != nil {
		me.New = flattenMessageFields(data.GetValue().GetFields())
	}
	if data.GetOldValue() != nil {
		me.Old = flattenMessageFields(data.GetOldValue().GetFields())
	}
	return me, true
}

func flattenMessageFields(fields map[string]*firestoredata.Value) map[string]any {
	out := map[string]any{}
	for k, v := range fields {
		switch k {
		case "sender_id", "sender_participant_id", "type", "text", "room_id":
			out[k] = v.GetStringValue()
		case "seq", "created_at":
			out[k] = v.GetIntegerValue()
		case "edited_at", "deleted_at":
			if iv := v.GetIntegerValue(); iv != 0 {
				out[k] = iv
			} else {
				out[k] = nil
			}
		}
	}
	return out
}

func buildMessageWrittenDeps(app *firebase.App, fs *firestore.Client, prefix string) MessageWrittenDeps {
	return MessageWrittenDeps{
		GetRoom: func(ctx context.Context, roomId string) (int64, []types.ChatParticipant, error) {
			snap, err := fs.Doc(prefix + "chat_rooms/" + roomId).Get(ctx)
			if err != nil {
				return 0, nil, err
			}
			lastSeq, _ := utils.ToInt64(snap.Data()["last_seq"])
			var parts []types.ChatParticipant
			if raw, ok := snap.Data()["participants"].([]any); ok {
				for _, item := range raw {
					if m, ok := item.(map[string]any); ok {
						id, _ := m["id"].(string)
						t, _ := m["type"].(string)
						parts = append(parts, types.ChatParticipant{Id: id, Type: t})
					}
				}
			}
			return lastSeq, parts, nil
		},
		AllocateSeq: func(ctx context.Context, roomId, messageId string) (int64, error) {
			roomRef := fs.Doc(prefix + "chat_rooms/" + roomId)
			msgRef := fs.Collection(prefix + "chat_rooms/" + roomId + "/messages").Doc(messageId)
			var next int64
			err := fs.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
				snap, err := tx.Get(roomRef)
				if err != nil {
					return err
				}
				last, _ := utils.ToInt64(snap.Data()["last_seq"])
				next = last + 1
				if err := tx.Set(roomRef, map[string]any{"last_seq": next}, firestore.MergeAll); err != nil {
					return err
				}
				return tx.Set(msgRef, map[string]any{"seq": next}, firestore.MergeAll)
			})
			if err != nil {
				return 0, err
			}
			return next, nil
		},
		UpdateRoomMeta: func(ctx context.Context, roomId string, meta map[string]any) error {
			_, err := fs.Doc(prefix + "chat_rooms/" + roomId).Set(ctx, meta, firestore.MergeAll)
			return err
		},
		CompanyUserIds: func(ctx context.Context, companyId string, roles []string) ([]string, error) {
			return getCompanyUserIdsByRole(ctx, fs, prefix, companyId, roles)
		},
		SendPush: func(ctx context.Context, recipientUserIds []string, title, body string, data map[string]string) error {
			return sendChatPush(ctx, app, fs, prefix, recipientUserIds, title, body, data)
		},
		Now: time.Now,
	}
}

func sendChatPush(
	ctx context.Context, app *firebase.App, fs *firestore.Client, prefix string,
	recipientUserIds []string, title, body string, data map[string]string,
) error {
	var tokens []string
	for _, uid := range recipientUserIds {
		docs, err := fs.Collection(prefix + "users/" + uid + "/devices").Documents(ctx).GetAll()
		if err != nil {
			continue
		}
		for _, d := range docs {
			if t, ok := d.Data()["token"].(string); ok && t != "" {
				tokens = append(tokens, t)
			}
		}
	}
	if len(tokens) == 0 {
		return nil
	}
	fcm, err := app.Messaging(ctx)
	if err != nil {
		return err
	}
	_, err = fcm.SendEachForMulticast(ctx, &messaging.MulticastMessage{
		Tokens:       tokens,
		Data:         data,
		Notification: &messaging.Notification{Title: title, Body: body},
		Android:      &messaging.AndroidConfig{Priority: "high"},
	})
	return err
}
```

> **Verify `getCompanyUserIdsByRole`'s signature** in `triggers/notification_helpers.go` matches `(ctx, *firestore.Client, prefix, companyId string, roles []string) ([]string, error)`. If it differs, adapt the `CompanyUserIds` closure call accordingly (do not change the helper).

- [ ] **Step 2: Tidy + build the triggers module**

Run: `cd functions/loans/triggers && go mod tidy && CGO_ENABLED=0 go build ./...`
Expected: builds clean (firebase-admin messaging + firestore already available in `triggers/go.mod`).

- [ ] **Step 3: Re-run the full trigger test suite (unchanged behavior)**

Run: `cd functions/loans && CGO_ENABLED=0 go test ./test/triggers/ -v`
Expected: PASS (path + create + update tests).

- [ ] **Step 4: Commit**

```bash
git add functions/loans/triggers/message_written.go functions/loans/triggers/go.mod functions/loans/triggers/go.sum
git commit -m "feat(functions): message_written CloudEvent adapter (parse + firestore/FCM deps)"
```

---

### Task 6: Register the function + deploy entry

**Files:**
- Modify: `functions/loans/loooans_cloud_functions.go`
- Modify: `.github/scripts/deploy_functions.sh`

- [ ] **Step 1: Register the CloudEvent handler**

In `functions/loans/loooans_cloud_functions.go`, add below the other `functions.CloudEvent(...)` lines (before `log.Info("added cloud functions")`):
```go
	functions.CloudEvent("messageWritten", triggers.MessageWritten)
```

- [ ] **Step 2: Add the deploy block**

In `.github/scripts/deploy_functions.sh`, after the `UserChanges` block (around line 150), add:
```bash
echo "Deploying MessageWritten trigger"
gcloud functions deploy messageWritten_$environment --gen2 --service-account="$serviceAccount" --runtime=go122 --region=asia-east1 --trigger-location=asia-east1 --source=. --entry-point=messageWritten --trigger-event-filters=type=google.cloud.firestore.document.v1.written --trigger-event-filters=database='(default)' --trigger-event-filters-path-pattern=document="${collectionPrefix}chat_rooms/{roomId}/messages/{messageId}" --set-env-vars=ENVIRONMENT=$environment --project=$project &
pids[$!]="messageWritten"
```
Then update both function-count strings: `"All 16 functions deploying in parallel..."` → `17` (line ~153) and `"All 16 functions deployed successfully."` → `17` (line ~166).

- [ ] **Step 3: Build the root module (registration compiles)**

Run: `cd functions/loans && CGO_ENABLED=0 go build ./...`
Expected: builds clean (root imports `triggers.MessageWritten`).

- [ ] **Step 4: Commit**

```bash
git add functions/loans/loooans_cloud_functions.go .github/scripts/deploy_functions.sh
git commit -m "feat(functions): register messageWritten trigger + deploy entry"
```

---

### Task 7: Finalize — full build + test

- [ ] **Step 1: Build every module**

Run:
```bash
cd functions/loans && CGO_ENABLED=0 go build ./... \
  && (cd types && CGO_ENABLED=0 go build ./...) \
  && (cd triggers && CGO_ENABLED=0 go build ./...) \
  && (cd test/fakes && CGO_ENABLED=0 go build ./...)
```
Expected: all build clean.

- [ ] **Step 2: Run all root-module tests**

Run: `cd functions/loans && CGO_ENABLED=0 go test ./... -v`
Expected: PASS, including `test/triggers` (path, create, update). Pre-existing tests unaffected.

- [ ] **Step 3: Commit (if any tidy changed go.sum)**

```bash
git add functions/loans
git commit -m "chore(functions): message_written trigger green build + tests" || echo "nothing to commit"
```

---

## Self-Review (completed by plan author)

**Spec coverage (§5.2/§5.5/§7):**
- Trigger on `chat_rooms/{roomId}/messages/{messageId}` `written` → Tasks 5–6. ✅
- Recover roomId/messageId from path → Task 1 (`ParseMessagePath`). ✅
- Create branch: assign `seq` (transaction), write `last_message`+`updated_at`, advance `team_reads` on company reply, resolve user+company→staff recipients, FCM data-push with `room_id`/`seq` → Tasks 3–5. ✅
- Update branch: refresh `last_message` only when the edited/deleted message is latest; ignore the trigger's own seq-stamp; no push → Task 4. ✅
- Company→staff fan-out via `getCompanyUserIdsByRole`; skip the sender participant → Task 3. ✅
- Dates via `.UnixMilli()`, read via `utils.ToInt64` → Tasks 3–5. ✅

**Deviations noted:** Direct FCM (spec #13) instead of the repo's `createNotification` pattern — the core's `SendPush` dep + adapter `sendChatPush`. The Firestore-transaction/FCM glue in the adapter is build-verified only (no unit test), consistent with `notification_created.go` having no test; all branching/recipient logic is unit-tested through the core.

**Not in this plan:** Firestore/Storage/RTDB security rules, composite index, and prod IAM/Eventarc grants (Plan 4); Flutter client that consumes the push + acks delivery (Plan 3).

**Placeholder scan:** none — every code step is complete. The one intentional temporary is the `handleMessageUpdate` stub in Task 3 Step 4, explicitly replaced in Task 4 Step 3.

**Type consistency:** `MessageEvent`, `MessageWrittenDeps`, `HandleMessageWrittenCore`, `FixedClock`, `ParseMessagePath`, `messagePreview`, `recipientUserIds`, `isCompanyParticipant`, `types.ChatParticipant`, and fakes (`RoomReader`/`SeqAllocator`/`RoomMetaWriter`/`ChatPusher`/`CompanyUsersReader`) are defined once and referenced consistently across tasks. Deps field names (`GetRoom`/`AllocateSeq`/`UpdateRoomMeta`/`CompanyUserIds`/`SendPush`/`Now`) match between the struct, the real builder, and the test wiring.
