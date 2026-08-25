package triggers

import (
	"testing"
	"time"

	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
	"google.golang.org/protobuf/types/known/structpb"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// TestFlattenProductFields_PreservesNumericTypes has to live inside package
// triggers: flattenProductFields is unexported and unreachable from the
// triggers_test suite under test/triggers/.
//
// The obvious way to write that flattener — and the way the task brief wrote
// it — coerces every IntegerValue to float64. That looks harmless and is not:
// max_period would then be written to Firestore as a double, and the Dart
// entity casts it directly (`json['max_period'] as int?`), so the offers list
// throws a TypeError on a product whose max_period came through this path.
// The builders can only get the type right if the flattener keeps it.
func TestFlattenProductFields_PreservesNumericTypes(t *testing.T) {
	product := flattenProductFields(map[string]*firestoredata.Value{
		"id":                  stringValue("prod-1"),
		"provider_id":         stringValue("company-1"),
		"loan_type":           stringValue("Salary Loan"),
		"term":                stringValue("1m"),
		"interest_rate":       integerValue(8),
		"max_loanable_amount": doubleValue(50000),
		"max_period":          integerValue(6),
		"allow_add_ons":       boolValue(false),
	})

	if _, ok := product["interest_rate"].(int64); !ok {
		t.Errorf("interest_rate flattened to %T, want the stored int64 kept as-is", product["interest_rate"])
	}
	if _, ok := product["max_period"].(int64); !ok {
		t.Errorf("max_period flattened to %T, want int64", product["max_period"])
	}
	if _, ok := product["max_loanable_amount"].(float64); !ok {
		t.Errorf("max_loanable_amount flattened to %T, want float64", product["max_loanable_amount"])
	}

	// A product that disallows add-ons must not be defaulted back to true by
	// the flattener dropping the field.
	if product["allow_add_ons"] != false {
		t.Errorf("allow_add_ons = %v, want false preserved", product["allow_add_ons"])
	}

	view := BuildProductViewCreate("view-1", product, nil, 1755000000000)
	if _, ok := view["interest_rate"].(float64); !ok {
		t.Errorf("view interest_rate is %T, want float64 (Dart: late double)", view["interest_rate"])
	}
	if view["max_period"] != int64(6) {
		t.Errorf("view max_period = %v (%T), want int64(6)", view["max_period"], view["max_period"])
	}
	if view["allow_add_ons"] != false {
		t.Errorf("view allow_add_ons = %v, want false", view["allow_add_ons"])
	}
}

// deleted_at reaches this trigger in three shapes, and all three have to land
// as something Firestore's `where('deleted_at', isNull: true)` filter reads
// correctly: absent and null both mean "live" (explicit null on the view), and
// a Timestamp — what a Go-written date looks like — must become int64 millis
// rather than being dropped, which would publish a deleted product as a live
// offer.
func TestFlattenProductFields_DeletedAtShapes(t *testing.T) {
	deletedAt := time.Date(2026, 8, 20, 1, 2, 3, 0, time.UTC)

	cases := []struct {
		name  string
		field *firestoredata.Value
		want  any
	}{
		{name: "absent", field: nil, want: nil},
		{name: "explicit null", field: nullValue(), want: nil},
		{name: "epoch millis", field: integerValue(1700000000000), want: int64(1700000000000)},
		{name: "firestore timestamp", field: timestampValue(deletedAt), want: deletedAt.UnixMilli()},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			fields := map[string]*firestoredata.Value{"id": stringValue("prod-1")}
			if tc.field != nil {
				fields["deleted_at"] = tc.field
			}

			view := BuildProductViewCreate("view-1", flattenProductFields(fields), nil, 1755000000000)

			if _, ok := view["deleted_at"]; !ok {
				t.Fatal("deleted_at key absent from the create payload — the document would never match isNull: true")
			}
			if view["deleted_at"] != tc.want {
				t.Errorf("deleted_at = %v (%T), want %v", view["deleted_at"], view["deleted_at"], tc.want)
			}
		})
	}
}

// created_at reaches this trigger in the same shapes as deleted_at: int millis
// from Dart's handleDateTimeToJson, and a Firestore Timestamp from anything Go
// wrote. Dropping it in the flattener is SILENT — the create path simply falls
// back to projection time — which is precisely why it is pinned here rather
// than left to the builder test.
func TestFlattenProductFields_CreatedAtShapes(t *testing.T) {
	const nowMillis = int64(1755000000000)
	createdAt := time.Date(2025, 3, 4, 5, 6, 7, 0, time.UTC)

	cases := []struct {
		name  string
		field *firestoredata.Value
		want  any
	}{
		{name: "absent falls back to now", field: nil, want: nowMillis},
		{name: "epoch millis", field: integerValue(1600000000000), want: int64(1600000000000)},
		{name: "firestore timestamp", field: timestampValue(createdAt), want: createdAt.UnixMilli()},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			fields := map[string]*firestoredata.Value{"id": stringValue("prod-1")}
			if tc.field != nil {
				fields["created_at"] = tc.field
			}

			view := BuildProductViewCreate("prod-1", flattenProductFields(fields), nil, nowMillis)

			if view["created_at"] != tc.want {
				t.Errorf("created_at = %v (%T), want %v", view["created_at"], view["created_at"], tc.want)
			}
		})
	}
}

func integerValue(n int64) *firestoredata.Value {
	return &firestoredata.Value{ValueType: &firestoredata.Value_IntegerValue{IntegerValue: n}}
}

func doubleValue(n float64) *firestoredata.Value {
	return &firestoredata.Value{ValueType: &firestoredata.Value_DoubleValue{DoubleValue: n}}
}

func boolValue(b bool) *firestoredata.Value {
	return &firestoredata.Value{ValueType: &firestoredata.Value_BooleanValue{BooleanValue: b}}
}

func nullValue() *firestoredata.Value {
	return &firestoredata.Value{ValueType: &firestoredata.Value_NullValue{NullValue: structpb.NullValue_NULL_VALUE}}
}

func timestampValue(t time.Time) *firestoredata.Value {
	return &firestoredata.Value{ValueType: &firestoredata.Value_TimestampValue{TimestampValue: timestamppb.New(t)}}
}
