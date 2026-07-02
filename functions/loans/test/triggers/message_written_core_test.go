package triggers_test

import (
	"context"
	"errors"
	"sort"
	"testing"

	"com.loooans.app/test/fakes"
	"com.loooans.app/triggers"
	"com.loooans.app/types"
)

func chatDeps(
	committer *fakes.ChatCommitter, company *fakes.CompanyUsersReader, push *fakes.ChatPusher,
) triggers.MessageWrittenDeps {
	return triggers.MessageWrittenDeps{
		AllocateAndCommit: committer.AllocateAndCommit,
		CompanyUserIds:    company.CompanyUserIds,
		SendPush:          push.SendPush,
		Now:               triggers.FixedClock(1_700_000_000_000),
	}
}

func borrowerCompanyCommitter() *fakes.ChatCommitter {
	return &fakes.ChatCommitter{Rooms: map[string]fakes.ChatRoomInfo{
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
	committer := borrowerCompanyCommitter()
	company := &fakes.CompanyUsersReader{Users: map[string][]string{"c1": {"admin1", "teller1"}}}
	push := &fakes.ChatPusher{}

	ev := triggers.MessageEvent{
		RoomId: "r1", MessageId: "m1",
		New: map[string]any{
			"sender_id": "u1", "sender_participant_id": "u1",
			"type": "text", "text": "hello", "created_at": int64(111),
		},
	}
	if err := triggers.HandleMessageWrittenCore(context.Background(), ev, chatDeps(committer, company, push)); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}

	if len(committer.Commits) != 1 || committer.Commits[0].MessageId != "m1" || !committer.Commits[0].IsNew {
		t.Fatalf("AllocateAndCommit commits: %+v", committer.Commits)
	}
	lm := committer.Commits[0].Meta["last_message"].(map[string]any)
	if lm["seq"].(int64) != 1 || lm["text"].(string) != "hello" {
		t.Errorf("last_message: %+v", lm)
	}
	if committer.Commits[0].Meta["last_seq"].(int64) != 1 {
		t.Errorf("room last_seq must advance to 1, meta=%+v", committer.Commits[0].Meta)
	}
	if _, hasTeam := committer.Commits[0].Meta["team_reads"]; hasTeam {
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
	committer := borrowerCompanyCommitter()
	company := &fakes.CompanyUsersReader{Users: map[string][]string{"c1": {"admin1"}}}
	push := &fakes.ChatPusher{}

	ev := triggers.MessageEvent{
		RoomId: "r1", MessageId: "m2",
		New: map[string]any{
			"sender_id": "admin1", "sender_participant_id": "c1",
			"type": "text", "text": "hi back", "created_at": int64(222),
		},
	}
	if err := triggers.HandleMessageWrittenCore(context.Background(), ev, chatDeps(committer, company, push)); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(push.Pushes) != 1 || !equalStrs(push.Pushes[0].Recipients, []string{"u1"}) {
		t.Fatalf("expected push to [u1], got %+v", push.Pushes)
	}
	if len(company.Calls) != 0 {
		t.Errorf("company staff should not be expanded for its own outgoing message")
	}
	// A company message advances the team handled watermark (handled_by = sender).
	tr, ok := committer.Commits[0].Meta["team_reads"].(map[string]any)
	if !ok {
		t.Fatalf("expected team_reads on a company message, meta=%+v", committer.Commits[0].Meta)
	}
	c1 := tr["c1"].(map[string]any)
	if c1["last_handled_seq"].(int64) != 1 || c1["handled_by"].(string) != "admin1" {
		t.Errorf("team_reads[c1]: %+v", c1)
	}
}

func TestCreate_Redelivered_NoDuplicatePush(t *testing.T) {
	committer := borrowerCompanyCommitter()
	company := &fakes.CompanyUsersReader{Users: map[string][]string{"c1": {"admin1", "teller1"}}}
	push := &fakes.ChatPusher{}
	deps := chatDeps(committer, company, push)

	ev := triggers.MessageEvent{
		RoomId: "r1", MessageId: "m1",
		New: map[string]any{
			"sender_id": "u1", "sender_participant_id": "u1",
			"type": "text", "text": "hello", "created_at": int64(111),
		},
	}
	// Eventarc is at-least-once: the same create event is delivered twice.
	for i := 0; i < 2; i++ {
		if err := triggers.HandleMessageWrittenCore(context.Background(), ev, deps); err != nil {
			t.Fatalf("delivery %d: %v", i, err)
		}
	}
	if len(committer.Commits) != 2 {
		t.Fatalf("expected 2 commit attempts, got %d", len(committer.Commits))
	}
	if committer.Commits[0].Seq != 1 || committer.Commits[1].Seq != 1 {
		t.Errorf("redelivery must reuse seq 1, got %d then %d",
			committer.Commits[0].Seq, committer.Commits[1].Seq)
	}
	if committer.Commits[1].IsNew {
		t.Errorf("second delivery must be idempotent (isNew=false)")
	}
	if len(push.Pushes) != 1 {
		t.Errorf("redelivered create must not push twice, got %d pushes", len(push.Pushes))
	}
}

func TestCreate_PushError_IsBestEffort(t *testing.T) {
	committer := borrowerCompanyCommitter()
	company := &fakes.CompanyUsersReader{Users: map[string][]string{"c1": {"admin1"}}}
	push := &fakes.ChatPusher{Err: errors.New("fcm boom")}

	ev := triggers.MessageEvent{
		RoomId: "r1", MessageId: "m1",
		New: map[string]any{
			"sender_id": "u1", "sender_participant_id": "u1",
			"type": "text", "text": "hello", "created_at": int64(111),
		},
	}
	// A push failure must NOT propagate: the message is already committed and a
	// retry would only no-op the push (idempotency guard), so it must be swallowed.
	if err := triggers.HandleMessageWrittenCore(context.Background(), ev, chatDeps(committer, company, push)); err != nil {
		t.Fatalf("push failure must be swallowed, got err: %v", err)
	}
	if len(committer.Commits) != 1 || !committer.Commits[0].IsNew {
		t.Errorf("message must still be committed, commits=%+v", committer.Commits)
	}
	if len(push.Pushes) != 1 {
		t.Errorf("push should have been attempted once, got %d", len(push.Pushes))
	}
}

func TestCreate_RecipientLookupError_IsBestEffort(t *testing.T) {
	committer := borrowerCompanyCommitter()
	company := &fakes.CompanyUsersReader{Err: errors.New("query boom")}
	push := &fakes.ChatPusher{}

	ev := triggers.MessageEvent{
		RoomId: "r1", MessageId: "m1",
		New: map[string]any{
			"sender_id": "u1", "sender_participant_id": "u1",
			"type": "text", "text": "hello", "created_at": int64(111),
		},
	}
	// A recipient-lookup failure after the commit must also be best-effort.
	if err := triggers.HandleMessageWrittenCore(context.Background(), ev, chatDeps(committer, company, push)); err != nil {
		t.Fatalf("recipient-lookup failure must be swallowed, got err: %v", err)
	}
	if len(committer.Commits) != 1 {
		t.Errorf("message must still be committed, commits=%+v", committer.Commits)
	}
	if len(push.Pushes) != 0 {
		t.Errorf("no push expected when recipient lookup failed, got %d", len(push.Pushes))
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
