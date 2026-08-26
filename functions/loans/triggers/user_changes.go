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
	// UpdateUser applies a partial write to the user document. The core calls
	// it at most once per event, with whichever of the two key sets apply:
	// the mobile path (clearing the verification bit and mobile_verified_at)
	// and the search path (writing search_tokens). The adapter recognises each
	// key independently, so either set may arrive on its own or both together.
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

	// The mobile-verification keys and the search_tokens key are accumulated
	// into ONE payload and written once. They used to be two UpdateUser calls,
	// which meant an edit touching both wrote the same document twice and
	// re-fired userChanges twice — and left the document, between the two
	// writes, with verification cleared but tokens still describing the old
	// number. The adapter recognises each key independently, so either set may
	// still arrive on its own.
	fields := map[string]any{}

	beforeMobile, _ := before["mobile_number"].(string)
	afterMobile, _ := after["mobile_number"].(string)
	// beforeMobile != afterMobile AND beforeMobile != "" — clear verification.
	// Includes the case where afterMobile == "" (user cleared their number).
	// beforeMobile == "" is skipped: no prior mobile to invalidate, first
	// time setting a number.
	if beforeMobile != afterMobile && beforeMobile != "" {
		fields["verificationStatus_andNot"] = verificationBitMobileNumber
		fields["mobile_verified_at"] = nil
	}

	// Keep search_tokens in sync with the fields it's derived from. Decided
	// independently of the mobile path above so a name-only or mobile-only
	// edit still refreshes findability. SearchTokensForUser reports
	// needsWrite=false once the document's own search_tokens field already
	// matches, which is what stops this from re-firing on its own write.
	if tokens, needsWrite := SearchTokensForUser(after); needsWrite {
		fields["search_tokens"] = tokens
	}

	if len(fields) > 0 {
		if err := deps.UpdateUser(ctx, uid, fields); err != nil {
			// Named, and propagated so the platform retries the delivery. A
			// bare error here produced a retry log storm naming no document,
			// in which one unwritable user is indistinguishable from a
			// collection-wide failure; a token write that fails silently
			// degrades search findability.
			return fmt.Errorf("update user %s: %w", uid, err)
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

	existing := StringSliceFrom(after["search_tokens"])
	if EqualStringSlices(existing, tokens) {
		return nil, false
	}
	return tokens, true
}

// StringSliceFrom reads a []any of strings (the shape a Firestore array field
// takes once flattened into a map[string]any) back into a []string. Anything
// else — absent key, wrong type, non-string elements — yields nil.
//
// Exported because the backfill compares stored tokens against computed ones
// too. Two copies of that rule is the one shape guaranteed to let the trigger
// and the backfill disagree about whether a document is already migrated, at
// which point each rewrites the other's work forever and both writes succeed.
func StringSliceFrom(raw any) []string {
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

// EqualStringSlices compares two token slices for exact (order-sensitive)
// equality. search.UserTokens always returns a sorted slice and the stored
// search_tokens field is whatever a prior call wrote, so order-sensitivity is
// safe and cheaper than a set comparison.
//
// Exported alongside StringSliceFrom, and for the same reason.
func EqualStringSlices(a, b []string) bool {
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
				if len(update) == 0 {
					// No recognised key: writing an empty merge would still
					// bump the document and re-fire this trigger for nothing.
					return nil
				}
				// MergeFields, not MergeAll — see its doc comment. Every value
				// written here is a scalar or an array today, for which the
				// two agree, but the rule holds for the document either way
				// and a nested field added later must not silently regress.
				return tx.Set(docRef, update, MergeFields(update))
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
			// SearchTokensForUser's StringSliceFrom expects, and the shape a
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
