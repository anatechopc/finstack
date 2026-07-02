package triggers

import (
	"context"
	"fmt"
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
