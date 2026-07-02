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
	rooms := updateRoom(5)
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
