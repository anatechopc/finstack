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
	"google.golang.org/api/iterator"
)

const verificationBitMobileNumber = 2

// UserChangesDeps holds the collaborator functions used by the core.
type UserChangesDeps struct {
	// UpdateUser clears mobile-verification fields on the user document.
	UpdateUser func(ctx context.Context, uid string, fields map[string]any) error
	// UpdateUserLoanViewNames refreshes the denormalized user_full_name on every
	// user_loan_views document owned by the given user. Called only when the
	// user's name fields actually change.
	UpdateUserLoanViewNames func(ctx context.Context, userId, newFullName string) error
}

// HandleUserChangedCore inspects before/after snapshots and:
//   - clears mobile verification fields when the mobile_number changes, and
//   - cascades a profile-name change to the denormalized user_full_name on the
//     user's user_loan_views documents.
//
// The two paths are independent: a name-only edit refreshes the loan views and
// leaves verification alone; a mobile-only edit clears verification and leaves
// the loan views alone; an edit touching both runs both.
func HandleUserChangedCore(ctx context.Context, uid string, before, after map[string]any, deps UserChangesDeps) error {
	if before == nil || after == nil {
		return nil
	}

	// Name cascade: keep the denormalized borrower name in user_loan_views in
	// sync with the live user. Computed independently of the mobile path so a
	// rename always refreshes the views even if the mobile number is unchanged.
	beforeName := userFullNameFrom(before)
	afterName := userFullNameFrom(after)
	if beforeName != afterName && deps.UpdateUserLoanViewNames != nil {
		if err := deps.UpdateUserLoanViewNames(ctx, uid, afterName); err != nil {
			return fmt.Errorf("cascade user_full_name for %s: %w", uid, err)
		}
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

// userFullNameFrom composes the borrower's display name from a flattened user
// snapshot, replicating the Flutter User.completeNameEasternOrder getter:
//
//	'$lastName, $firstName${middleName != null ? ' $middleName' : ''}'
//
// The middle name is appended only when present. The Dart getter guards on
// `middleName != null`; a null/absent Firestore middle_name arrives here as the
// empty string, which renders no middle name in the app, so we append only for
// a non-empty value to match what the list actually shows.
func userFullNameFrom(snap map[string]any) string {
	firstName, _ := snap["first_name"].(string)
	lastName, _ := snap["last_name"].(string)
	middleName, _ := snap["middle_name"].(string)

	name := lastName + ", " + firstName
	if middleName != "" {
		name += " " + middleName
	}
	return name
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
		UpdateUserLoanViewNames: func(ctx context.Context, userId, newFullName string) error {
			// Refresh the denormalized borrower name on every loan view owned by
			// this user. Equality-only query (served by the automatic single-field
			// user_id index, so no composite index is required). Each matching
			// doc gets a single-field MergeAll set; a borrower has at most a
			// handful of loans, so the write fan-out is small.
			iter := fs.Collection(collectionPrefix + "user_loan_views").
				Where("user_id", "==", userId).
				Documents(ctx)
			defer iter.Stop()

			for {
				doc, err := iter.Next()
				if err == iterator.Done {
					break
				}
				if err != nil {
					return fmt.Errorf("query user_loan_views for %s: %w", userId, err)
				}
				if _, err := doc.Ref.Set(ctx, map[string]any{
					"user_full_name": newFullName,
				}, firestore.MergeAll); err != nil {
					return fmt.Errorf("update user_loan_view %s: %w", doc.Ref.ID, err)
				}
			}
			return nil
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
		case "mobile_number", "first_name", "last_name", "middle_name":
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
