package utils

import "math"

// RoundFloat Rounds the float to the nearest decimal places
func RoundFloat(val float64, precision uint) float64 {
	ratio := math.Pow(10, float64(precision))
	return math.Round(val*ratio) / ratio
}

// ToInt64 coerces a value read back from Firestore into an int64, returning ok
// false for any unexpected type. Firestore numbers arrive as int64 or (after a
// JSON round-trip) float64; callers store millisecond timestamps and counts as
// int64 per the codebase's date convention. A non-numeric value (e.g. a
// Firestore Timestamp object instead of int64 millis — the documented
// serialization footgun) yields (0, false) so callers can fail closed rather
// than silently coerce. This is the single canonical coercion; do not re-inline
// the type switch.
func ToInt64(v any) (int64, bool) {
	switch n := v.(type) {
	case int64:
		return n, true
	case int:
		return int64(n), true
	case float64:
		return int64(n), true
	default:
		return 0, false
	}
}
