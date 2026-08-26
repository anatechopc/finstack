package utils

import (
	"math"
	"time"
)

// RoundFloat Rounds the float to the nearest decimal places
func RoundFloat(val float64, precision uint) float64 {
	ratio := math.Pow(10, float64(precision))
	return math.Round(val*ratio) / ratio
}

// ToInt64 coerces a value read back from Firestore into an int64, returning ok
// false for any unexpected type. Firestore numbers arrive as int64 or (after a
// JSON round-trip) float64; callers store millisecond timestamps and counts as
// int64 per the codebase's date convention. This is the single canonical
// coercion; do not re-inline the type switch.
//
// time.Time is accepted and converted to epoch millis, because that is how the
// Firestore client hands back a field stored as a Timestamp rather than as int
// millis — the documented serialization footgun. It is converted, not rejected,
// so that the same document read two ways agrees: a CloudEvent payload reaches
// intMillisFromValue (triggers/message_written.go), which has always accepted
// TimestampValue, while a DocumentSnapshot.Data() read reaches here. Rejecting
// only here made the product_view projection produce two different views of one
// product depending on which writer ran, and the two never converged. Rejecting
// was not fail-safe either: most call sites discard ok, so a Timestamp became a
// silent 0 — a 1970 date — rather than an error.
func ToInt64(v any) (int64, bool) {
	switch n := v.(type) {
	case int64:
		return n, true
	case int:
		return int64(n), true
	case float64:
		return int64(n), true
	case time.Time:
		return n.UnixMilli(), true
	default:
		return 0, false
	}
}
