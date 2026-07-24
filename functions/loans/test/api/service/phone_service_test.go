package service_test

import (
	"errors"
	"testing"

	"com.loooans.app/api/service"
)

func TestNormalizePhoneE164(t *testing.T) {
	cases := []struct {
		name    string
		number  string
		country string
		want    string
		wantErr error // nil means success
	}{
		{"bare 10-digit PH", "9175551291", "Philippines", "+639175551291", nil},
		{"national 0-prefixed PH", "09175551291", "Philippines", "+639175551291", nil},
		{"whitespace and case tolerated", " 9175551291 ", "  philippines ", "+639175551291", nil},
		{"already E.164, empty country", "+639175551291", "", "+639175551291", nil},
		{"already E.164, unknown country", "+639175551291", "Narnia", "+639175551291", nil},
		{"unknown country", "9175551291", "Narnia", "", service.ErrCountryUnknown},
		{"empty country", "9175551291", "", "", service.ErrCountryUnknown},
		{"too short for PH", "12345", "Philippines", "", service.ErrPhoneInvalid},
		{"ten digits but not a PH number", "1234567890", "Philippines", "", service.ErrPhoneInvalid},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := service.NormalizePhoneE164(tc.number, tc.country)
			if tc.wantErr != nil {
				if !errors.Is(err, tc.wantErr) {
					t.Fatalf("want error %v, got %v", tc.wantErr, err)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tc.want {
				t.Errorf("want %q, got %q", tc.want, got)
			}
		})
	}
}
