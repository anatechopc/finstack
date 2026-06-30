package utils_test

import (
	"testing"
	"time"

	"com.loooans.app/utils"
)

func TestToInt64(t *testing.T) {
	cases := []struct {
		name   string
		in     any
		want   int64
		wantOk bool
	}{
		{"int64", int64(1700000000000), 1700000000000, true},
		{"int", int(42), 42, true},
		{"float64 (JSON round-trip)", float64(1700000000000), 1700000000000, true},
		{"float64 fractional truncates", float64(12.9), 12, true},
		{"string", "1700000000000", 0, false},
		{"nil", nil, 0, false},
		{"bool", true, 0, false},
		// A Firestore Timestamp deserializes as time.Time, NOT int64 millis — the
		// documented serialization footgun. It must fail closed (ok=false) so a
		// caller rejects rather than silently mis-reads it as 0.
		{"time.Time (Firestore Timestamp footgun)", time.UnixMilli(1700000000000), 0, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, ok := utils.ToInt64(c.in)
			if got != c.want || ok != c.wantOk {
				t.Fatalf("ToInt64(%v) = (%d, %v), want (%d, %v)", c.in, got, ok, c.want, c.wantOk)
			}
		})
	}
}
