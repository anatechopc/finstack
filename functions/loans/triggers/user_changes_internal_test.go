package triggers

import (
	"testing"

	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
)

// TestFlattenFields_SearchTokensRoundTrip is the loop-termination proof for the
// user_changes trigger, and it has to live inside package triggers: the thing
// under test is flattenFields' "search_tokens" case, which is unexported and
// unreachable from the triggers_test suite under test/triggers/.
//
// The two passes model the two deliveries the trigger really sees. Pass 1 is
// the user's own edit: the document has no search_tokens field, so tokens are
// computed and written. That write re-delivers the event, which is pass 2: the
// document now carries the tokens the trigger just wrote, and the trigger must
// recognise them and stop.
//
// The link between the passes is entirely flattenFields' array parsing. If that
// case is deleted — it looks like dead weight next to the string cases —
// search_tokens never reaches SearchTokensForUser, pass 2 reports needsWrite
// again, and the trigger writes forever in production. Nothing else in the
// repository catches that; the pass-2 assertion below is the guard.
func TestFlattenFields_SearchTokensRoundTrip(t *testing.T) {
	fields := map[string]*firestoredata.Value{
		"id":            stringValue("user-1"),
		"first_name":    stringValue("Juan"),
		"middle_name":   stringValue("Santos"),
		"last_name":     stringValue("dela Cruz"),
		"mobile_number": stringValue("09175550142"),
		"email_address": stringValue("juan.cruz@gmail.com"),
	}

	// Pass 1 — the user's edit. No search_tokens on the document yet.
	tokens, needsWrite := SearchTokensForUser(flattenFields(fields))
	if !needsWrite {
		t.Fatal("pass 1: a document with no search_tokens must be written")
	}
	if len(tokens) == 0 {
		t.Fatal("pass 1: expected a non-empty token set")
	}

	// The trigger's own write, as it comes back through the CloudEvent: a
	// Firestore array of strings.
	fields["search_tokens"] = arrayValue(tokens)

	// Pass 2 — the re-delivery caused by that write. Must terminate.
	if _, needsWrite := SearchTokensForUser(flattenFields(fields)); needsWrite {
		t.Fatal("pass 2: tokens written on pass 1 were not read back — the trigger would recurse")
	}
}

// TestFlattenFields_SearchTokensStaleArray guards the other direction: array
// parsing that returned something *constant* would also make pass 2 above
// terminate, while breaking real edits. Tokens that no longer match the
// document's fields must still produce a write.
func TestFlattenFields_SearchTokensStaleArray(t *testing.T) {
	fields := map[string]*firestoredata.Value{
		"id":            stringValue("user-1"),
		"first_name":    stringValue("Juan"),
		"last_name":     stringValue("Santos"),
		"search_tokens": arrayValue([]string{"cr", "cru", "cruz", "ju", "jua", "juan"}),
	}

	if _, needsWrite := SearchTokensForUser(flattenFields(fields)); !needsWrite {
		t.Fatal("stale tokens must be rewritten")
	}
}

func stringValue(s string) *firestoredata.Value {
	return &firestoredata.Value{ValueType: &firestoredata.Value_StringValue{StringValue: s}}
}

func arrayValue(values []string) *firestoredata.Value {
	elements := make([]*firestoredata.Value, 0, len(values))
	for _, v := range values {
		elements = append(elements, stringValue(v))
	}
	return &firestoredata.Value{
		ValueType: &firestoredata.Value_ArrayValue{
			ArrayValue: &firestoredata.ArrayValue{Values: elements},
		},
	}
}
