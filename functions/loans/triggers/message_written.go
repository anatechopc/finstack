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
