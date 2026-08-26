package triggers

import (
	"sort"

	"cloud.google.com/go/firestore"
)

// MergeFields returns the Set option that replaces exactly the TOP-LEVEL keys
// of fields and leaves every other field of the document untouched.
//
// It exists because firestore.MergeAll is not that. MergeAll walks the payload
// down to its LEAVES — see fpvsFromData in the client's docref.go — and emits
// one merge path per leaf, so writing
//
//	company_profile_photo_url: {"url": "b"}
//
// produces the single path `company_profile_photo_url.url`. A document already
// holding {"url": "a", "thumbnail": "t"} therefore keeps "thumbnail" forever:
// the projection compares whole maps, sees a difference, rewrites — and the
// rewrite cannot remove the stale subkey either. The view never converges, so
// every backfill pass rewrites the same documents indefinitely, which is
// exactly the "second pass writes nothing" invariant the job is built around.
//
// Naming the top-level path makes Firestore replace the whole map. The paths
// are derived from the payload's own keys so the two cannot drift, and the
// single-element FieldPath form takes each key literally rather than splitting
// it on dots.
//
// Callers must not pass an empty map: firestore.Merge with no paths produces a
// write with an empty mask, and a caller with nothing to write should not
// write at all.
func MergeFields(fields map[string]any) firestore.SetOption {
	keys := make([]string, 0, len(fields))
	for key := range fields {
		keys = append(keys, key)
	}
	// Sorted so the update mask a given payload produces is deterministic.
	sort.Strings(keys)

	paths := make([]firestore.FieldPath, 0, len(keys))
	for _, key := range keys {
		paths = append(paths, firestore.FieldPath{key})
	}
	return firestore.Merge(paths...)
}
