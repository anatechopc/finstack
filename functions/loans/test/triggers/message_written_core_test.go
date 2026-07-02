package triggers_test

import (
	"context"
	"sort"
	"testing"

	"com.loooans.app/test/fakes"
	"com.loooans.app/triggers"
	"com.loooans.app/types"
)

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

	if len(seq.Calls) != 1 || seq.Calls[0] != "r1:m1" {
		t.Fatalf("AllocateSeq calls: %v", seq.Calls)
	}
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
