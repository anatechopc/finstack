package triggers

import (
	"context"
	"errors"
	"fmt"

	"cloud.google.com/go/firestore"
	"com.loooans.app/utils"
	"github.com/cloudevents/sdk-go/v2/event"
	"github.com/golang/protobuf/proto"
	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
)

const verificationBitMobileNumber = 2

// UserChangesDeps holds the collaborator functions used by the core.
type UserChangesDeps struct {
	UpdateUser func(ctx context.Context, uid string, fields map[string]any) error
}

// HandleUserChangedCore inspects before/after snapshots and clears mobile
// verification fields when the mobile_number changes.
func HandleUserChangedCore(ctx context.Context, uid string, before, after map[string]any, deps UserChangesDeps) error {
	if before == nil || after == nil {
		return nil
	}
	beforeMobile, _ := before["mobile_number"].(string)
	afterMobile, _ := after["mobile_number"].(string)
	if beforeMobile == afterMobile {
		return nil
	}
	if beforeMobile == "" {
		// No prior mobile to invalidate — first time setting a number.
		return nil
	}
	// beforeMobile != afterMobile AND beforeMobile != "" — clear verification.
	// Includes the case where afterMobile == "" (user cleared their number).
	fields := map[string]any{
		"verificationStatus_andNot": verificationBitMobileNumber,
		"mobile_verified_at":        nil,
	}
	return deps.UpdateUser(ctx, uid, fields)
}

// UserChanges is the CloudEvent adapter. Wires real Firestore into the core.
func UserChanges(ctx context.Context, ev event.Event) error {
	log, logErr := utils.InitializeLogger("user_changes")
	if logErr != nil {
		return logErr
	}

	var data firestoredata.DocumentEventData
	if err := proto.Unmarshal(ev.Data(), &data); err != nil {
		return fmt.Errorf("proto.Unmarshal: %w", err)
	}

	app, fbErr := utils.InitializeFirebase(ctx)
	if fbErr != nil {
		return fbErr
	}
	fs, fsErr := app.Firestore(ctx)
	if fsErr != nil {
		return fsErr
	}
	defer fs.Close()

	collectionPrefix := utils.GetCollectionPrefix()

	uid, before, after, err := extractUserChange(&data)
	if err != nil {
		log.Sugar().Warnf("user_changes: skipping event: %v", err)
		return nil
	}

	deps := UserChangesDeps{
		UpdateUser: func(ctx context.Context, uid string, fields map[string]any) error {
			docRef := fs.Doc(collectionPrefix + "users/" + uid)
			return fs.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
				update := map[string]any{}
				if v, ok := fields["verificationStatus_andNot"].(int); ok {
					snap, sErr := tx.Get(docRef)
					if sErr != nil {
						return sErr
					}
					current, _ := snap.Data()["verificationStatus"].(int64)
					update["verificationStatus"] = current &^ int64(v)
				}
				if _, ok := fields["mobile_verified_at"]; ok {
					update["mobile_verified_at"] = nil
				}
				return tx.Set(docRef, update, firestore.MergeAll)
			})
		},
	}

	return HandleUserChangedCore(ctx, uid, before, after, deps)
}

// extractUserChange pulls uid + before/after maps from the proto event.
func extractUserChange(data *firestoredata.DocumentEventData) (string, map[string]any, map[string]any, error) {
	if data.GetValue() == nil || data.GetOldValue() == nil {
		return "", nil, nil, errors.New("missing value or old value")
	}
	var uid string
	if uidVal, ok := data.GetValue().GetFields()["id"]; ok {
		uid = uidVal.GetStringValue()
	}
	if uid == "" {
		return "", nil, nil, errors.New("missing user id")
	}
	before := flattenFields(data.GetOldValue().GetFields())
	after := flattenFields(data.GetValue().GetFields())
	return uid, before, after, nil
}

// flattenFields converts firestoredata.Value map into a Go map[string]any
// covering only the fields this trigger cares about.
func flattenFields(fields map[string]*firestoredata.Value) map[string]any {
	out := map[string]any{}
	for k, v := range fields {
		switch k {
		case "mobile_number":
			out[k] = v.GetStringValue()
		case "verificationStatus":
			out[k] = v.GetIntegerValue()
		case "mobile_verified_at":
			ts := v.GetTimestampValue()
			if ts != nil {
				out[k] = ts.AsTime()
			}
		case "id":
			out[k] = v.GetStringValue()
		}
	}
	return out
}
