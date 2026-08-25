package triggers

import (
	"context"
	"errors"
	"fmt"

	"cloud.google.com/go/firestore"
	"com.loooans.app/utils"
	"com.loooans.app/utils/search"
	"github.com/cloudevents/sdk-go/v2/event"
	"github.com/golang/protobuf/proto"
	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
	"google.golang.org/api/iterator"
)

const verificationBitMobileNumber = 2

// UserChangesDeps holds the collaborator functions used by the core.
type UserChangesDeps struct {
	// UpdateUser applies a partial write to the user document. Two callers use
	// it: the mobile path (clearing the verification bit and
	// mobile_verified_at) and the search path (writing search_tokens). The
	// adapter recognises each key independently, so a caller may pass either
	// set on its own.
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
	// beforeMobile != afterMobile AND beforeMobile != "" — clear verification.
	// Includes the case where afterMobile == "" (user cleared their number).
	// beforeMobile == "" is skipped: no prior mobile to invalidate, first
	// time setting a number.
	if beforeMobile != afterMobile && beforeMobile != "" {
		fields := map[string]any{
			"verificationStatus_andNot": verificationBitMobileNumber,
			"mobile_verified_at":        nil,
		}
		if err := deps.UpdateUser(ctx, uid, fields); err != nil {
			return err
		}
	}

	// Keep search_tokens in sync with the fields it's derived from. Runs
	// independently of the two paths above so a name-only or mobile-only
	// edit still refreshes findability. SearchTokensForUser reports
	// needsWrite=false once the document's own search_tokens field already
	// matches, which is what stops this from re-firing on its own write.
	if tokens, needsWrite := SearchTokensForUser(after); needsWrite {
		if err := deps.UpdateUser(ctx, uid, map[string]any{
			"search_tokens": tokens,
		}); err != nil {
			// Propagate like the paths above so the platform retries the
			// delivery — a token write failure otherwise degrades search
			// findability silently.
			return err
		}
	}

	return nil
}

// SearchTokensForUser computes the search_tokens array for a user document and
// reports whether it differs from what the document already carries.
//
// The bool return is load-bearing: this trigger fires on document writes, so
// writing tokens unconditionally would fire it again on its own write. When
// the tokens already match, the caller must skip the write.
func SearchTokensForUser(after map[string]any) ([]string, bool) {
	if after == nil {
		return nil, false
	}

	str := func(key string) string {
		value, _ := after[key].(string)
		return value
	}

	tokens := search.UserTokens(
		str("first_name"),
		str("middle_name"),
		str("last_name"),
		str("mobile_number"),
		str("email_address"),
	)

	existing := stringSliceFrom(after["search_tokens"])
	if equalStringSlices(existing, tokens) {
		return nil, false
	}
	return tokens, true
}

// stringSliceFrom reads a []any of strings (the shape a Firestore array field
// takes once flattened into a map[string]any) back into a []string. Anything
// else — absent key, wrong type, non-string elements — yields nil.
func stringSliceFrom(raw any) []string {
	values, ok := raw.([]any)
	if !ok {
		return nil
	}
	out := make([]string, 0, len(values))
	for _, value := range values {
		if s, ok := value.(string); ok {
			out = append(out, s)
		}
	}
	return out
}

// equalStringSlices compares two token slices for exact (order-sensitive)
// equality. search.UserTokens always returns a sorted slice and the stored
// search_tokens field is whatever a prior call wrote, so order-sensitivity is
// safe and cheaper than a set comparison.
func equalStringSlices(a, b []string) bool {
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
				if v, ok := fields["search_tokens"].([]string); ok {
					update["search_tokens"] = v
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
			iter := fs.Collection(collectionPrefix+"user_loan_views").
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
		case "mobile_number", "first_name", "last_name", "middle_name", "email_address":
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
		case "search_tokens":
			// Carried through as []any (string elements) — the same shape
			// SearchTokensForUser's stringSliceFrom expects, and the shape a
			// prior write to this same field produced. Parsing this is what
			// lets SearchTokensForUser see the document's current tokens and
			// recognise a no-op, which is what stops this trigger recursing
			// on its own search_tokens write.
			//
			// Pinned by TestFlattenFields_SearchTokensRoundTrip in
			// user_changes_internal_test.go — deleting this case makes that
			// test's pass-2 assertion fail. NOTE: that test lives in the
			// triggers *module*, which `go test ./...` from functions/loans
			// does not reach; run it with `cd functions/loans/triggers &&
			// go test ./...`.
			if arr := v.GetArrayValue(); arr != nil {
				tokens := make([]any, 0, len(arr.GetValues()))
				for _, tv := range arr.GetValues() {
					tokens = append(tokens, tv.GetStringValue())
				}
				out[k] = tokens
			}
		}
	}
	return out
}
