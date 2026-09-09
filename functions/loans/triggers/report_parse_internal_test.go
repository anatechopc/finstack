package triggers

import (
	"testing"

	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
)

// stringValue / integerValue / doubleValue come from the sibling internal tests.

func loanDoc(fields map[string]*firestoredata.Value) *firestoredata.Document {
	return &firestoredata.Document{Name: "projects/p/databases/(default)/documents/dev_loans/L1", Fields: fields}
}

func TestParseLoanChange_CreateWithIntegerAmounts(t *testing.T) {
	data := &firestoredata.DocumentEventData{Value: loanDoc(map[string]*firestoredata.Value{
		"company_id": stringValue("C1"), "id": stringValue("L1"), "status": stringValue("approved"),
		"amount": integerValue(10000), "additional_charges": integerValue(500),
	})}

	ev, err := parseLoanChange("e1", data)
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if ev.IsDelete || ev.OldStatus != "" || ev.Status != "approved" || ev.CompanyId != "C1" || ev.LoanId != "L1" {
		t.Errorf("event: %+v", ev)
	}
	if ev.Amount != 10000 || ev.AdditionalCharges != 500 || ev.Deductions != 0 || ev.UpfrontCollection != 0 {
		t.Errorf("amounts (missing optionals must be 0): %+v", ev)
	}
}

func TestParseLoanChange_UpdateCarriesOldStatusAndDoubles(t *testing.T) {
	data := &firestoredata.DocumentEventData{
		Value: loanDoc(map[string]*firestoredata.Value{
			"company_id": stringValue("C1"), "id": stringValue("L1"), "status": stringValue("completed"),
			"amount": doubleValue(10000.5), "deductions": doubleValue(200.25),
			"additional_charge_upfront_collection": integerValue(100),
		}),
		OldValue: loanDoc(map[string]*firestoredata.Value{"status": stringValue("approved")}),
	}

	ev, err := parseLoanChange("e2", data)
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if ev.OldStatus != "approved" || ev.Amount != 10000.5 || ev.Deductions != 200.25 || ev.UpfrontCollection != 100 {
		t.Errorf("event: %+v", ev)
	}
}

func TestParseLoanChange_DeleteAndMissingFields(t *testing.T) {
	ev, err := parseLoanChange("e3", &firestoredata.DocumentEventData{OldValue: loanDoc(nil)})
	if err != nil || !ev.IsDelete {
		t.Errorf("delete: %+v err %v", ev, err)
	}

	for _, missing := range []string{"company_id", "status", "id", "amount"} {
		fields := map[string]*firestoredata.Value{
			"company_id": stringValue("C1"), "id": stringValue("L1"), "status": stringValue("approved"), "amount": integerValue(1),
		}
		delete(fields, missing)
		if _, err := parseLoanChange("e4", &firestoredata.DocumentEventData{Value: loanDoc(fields)}); err == nil {
			t.Errorf("missing %s must be rejected", missing)
		}
	}
}

func TestNumberOf_HandlesFirestoreNumberTypes(t *testing.T) {
	cases := map[string]struct {
		in   any
		want float64
	}{
		"float64": {2500.5, 2500.5},
		"int64":   {int64(2500), 2500},
		"int":     {2500, 2500},
		"nil":     {nil, 0},
		"string":  {"2500", 0},
	}
	for name, c := range cases {
		if got := numberOf(c.in); got != c.want {
			t.Errorf("%s: got %v, want %v", name, got, c.want)
		}
	}
}
