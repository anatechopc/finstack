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
	"go.uber.org/zap"
)

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
	return HandleMessageWrittenCore(ctx, me, buildMessageWrittenDeps(app, fs, prefix, log))
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
		case "sender_id", "sender_participant_id", "type", "text":
			out[k] = v.GetStringValue()
		case "seq", "created_at":
			iv, _ := intMillisFromValue(v)
			out[k] = iv
		case "edited_at", "deleted_at":
			if iv, ok := intMillisFromValue(v); ok && iv != 0 {
				out[k] = iv
			} else {
				out[k] = nil
			}
		}
	}
	return out
}

// intMillisFromValue reads an int64 epoch-millis field, tolerating a Firestore
// Timestamp encoding (the documented Go→Firestore `time.Time` footgun) by
// converting it to millis. Returns ok=false for any other or absent type, so
// callers keep the codebase's "epoch millis" invariant even if a rogue producer
// ever writes a Timestamp instead of an int.
func intMillisFromValue(v *firestoredata.Value) (int64, bool) {
	switch v.GetValueType().(type) {
	case *firestoredata.Value_IntegerValue:
		return v.GetIntegerValue(), true
	case *firestoredata.Value_TimestampValue:
		return v.GetTimestampValue().AsTime().UnixMilli(), true
	default:
		return 0, false
	}
}

func buildMessageWrittenDeps(app *firebase.App, fs *firestore.Client, prefix string, log *zap.Logger) MessageWrittenDeps {
	return MessageWrittenDeps{
		GetRoom: func(ctx context.Context, roomId string) (int64, []types.ChatParticipant, error) {
			snap, err := fs.Doc(prefix + "chat_rooms/" + roomId).Get(ctx)
			if err != nil {
				return 0, nil, err
			}
			lastSeq, _ := utils.ToInt64(snap.Data()["last_seq"])
			return lastSeq, parseParticipants(snap.Data()["participants"]), nil
		},
		AllocateAndCommit: func(
			ctx context.Context, roomId, messageId string,
			build func(seq int64, participants []types.ChatParticipant) map[string]any,
		) (int64, []types.ChatParticipant, bool, error) {
			roomRef := fs.Doc(prefix + "chat_rooms/" + roomId)
			msgRef := fs.Collection(prefix + "chat_rooms/" + roomId + "/messages").Doc(messageId)
			var (
				seq          int64
				participants []types.ChatParticipant
				isNew        bool
			)
			err := fs.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
				// Idempotency: a message that already carries a seq was processed by
				// a prior invocation (Eventarc is at-least-once) — no-op, so we
				// neither re-allocate a seq nor re-send the push.
				msgSnap, err := tx.Get(msgRef)
				if err != nil {
					return err
				}
				if existing, ok := utils.ToInt64(msgSnap.Data()["seq"]); ok && existing > 0 {
					seq, isNew = existing, false
					return nil
				}
				roomSnap, err := tx.Get(roomRef)
				if err != nil {
					return err
				}
				last, _ := utils.ToInt64(roomSnap.Data()["last_seq"])
				participants = parseParticipants(roomSnap.Data()["participants"])
				seq, isNew = last+1, true

				// last_seq and the derived last_message/team_reads are written in the
				// SAME transaction: transactions serialize on roomRef, so the message
				// with the higher seq always writes last — the preview and the team
				// handled-watermark can never regress under concurrent sends.
				meta := build(seq, participants)
				meta["last_seq"] = seq
				if err := tx.Set(roomRef, meta, firestore.MergeAll); err != nil {
					return err
				}
				// Stamping seq re-fires messageWritten as an update; handleMessageUpdate
				// no-ops it (neither edited_at nor deleted_at changed). This is the one
				// intentional extra (no-op) invocation per created message.
				return tx.Set(msgRef, map[string]any{"seq": seq}, firestore.MergeAll)
			})
			if err != nil {
				return 0, nil, false, err
			}
			return seq, participants, isNew, nil
		},
		UpdateRoomMeta: func(ctx context.Context, roomId string, meta map[string]any) error {
			_, err := fs.Doc(prefix+"chat_rooms/"+roomId).Set(ctx, meta, firestore.MergeAll)
			return err
		},
		CompanyUserIds: func(ctx context.Context, companyId string, roles []string) ([]string, error) {
			return getCompanyUserIdsByRole(ctx, fs, prefix, companyId, roles)
		},
		SendPush: func(ctx context.Context, recipientUserIds []string, title, body string, data map[string]string) error {
			return sendChatPush(ctx, app, fs, prefix, log, recipientUserIds, title, body, data)
		},
		Now:     time.Now,
		LogWarn: func(format string, args ...any) { log.Sugar().Warnf(format, args...) },
	}
}

// parseParticipants decodes the denormalized `participants` array on a chat room
// doc into typed participants (nil when absent/malformed).
func parseParticipants(raw any) []types.ChatParticipant {
	items, ok := raw.([]any)
	if !ok {
		return nil
	}
	parts := make([]types.ChatParticipant, 0, len(items))
	for _, item := range items {
		if m, ok := item.(map[string]any); ok {
			id, _ := m["id"].(string)
			t, _ := m["type"].(string)
			parts = append(parts, types.ChatParticipant{Id: id, Type: t})
		}
	}
	return parts
}

func sendChatPush(
	ctx context.Context, app *firebase.App, fs *firestore.Client, prefix string, log *zap.Logger,
	recipientUserIds []string, title, body string, data map[string]string,
) error {
	tokens := deviceTokensForUsers(ctx, fs, prefix, log, recipientUserIds)
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

// deviceTokensForUsers collects the FCM tokens registered under each user's
// devices subcollection. A per-user read failure is logged and skipped (rather
// than silently dropped with a bare `continue`) so one recipient's transient
// error never aborts the whole fan-out — or vanishes without a trace.
func deviceTokensForUsers(
	ctx context.Context, fs *firestore.Client, prefix string, log *zap.Logger, userIds []string,
) []string {
	var tokens []string
	for _, uid := range userIds {
		docs, err := fs.Collection(prefix + "users/" + uid + "/devices").Documents(ctx).GetAll()
		if err != nil {
			if log != nil {
				log.Sugar().Warnf("message_written: skipping recipient %q — devices read failed: %v", uid, err)
			}
			continue
		}
		for _, d := range docs {
			if t, ok := d.Data()["token"].(string); ok && t != "" {
				tokens = append(tokens, t)
			}
		}
	}
	return tokens
}
