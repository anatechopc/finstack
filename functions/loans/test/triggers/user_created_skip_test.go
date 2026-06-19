package triggers_test

import (
	"testing"

	"com.loooans.app/triggers"
	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
)

func TestShouldSkipWelcomeEmail(t *testing.T) {
	cases := []struct {
		name   string
		fields map[string]*firestoredata.Value
		want   bool
	}{
		{
			name:   "invited by admin → skip",
			fields: map[string]*firestoredata.Value{"invited_by_admin": {ValueType: &firestoredata.Value_BooleanValue{BooleanValue: true}}},
			want:   true,
		},
		{
			name:   "self-registered (no field) → send",
			fields: map[string]*firestoredata.Value{"id": {ValueType: &firestoredata.Value_StringValue{StringValue: "u1"}}},
			want:   false,
		},
		{
			name:   "field present but false → send",
			fields: map[string]*firestoredata.Value{"invited_by_admin": {ValueType: &firestoredata.Value_BooleanValue{BooleanValue: false}}},
			want:   false,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := triggers.ShouldSkipWelcomeEmail(tc.fields); got != tc.want {
				t.Fatalf("ShouldSkipWelcomeEmail = %v, want %v", got, tc.want)
			}
		})
	}
}
