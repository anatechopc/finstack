package triggers_test

import (
	"context"
	"errors"
	"testing"

	"com.loooans.app/test/fakes"
	"com.loooans.app/triggers"
)

func TestHandleUserChangedCore_MobileChanged_ClearsVerification(t *testing.T) {
	updater := &fakes.UserUpdater{}
	deps := triggers.UserChangesDeps{UpdateUser: updater.Update}

	before := map[string]any{
		"id":                 "user-1",
		"mobile_number":      "9171234567",
		"verificationStatus": int64(2),
	}
	after := map[string]any{
		"id":                 "user-1",
		"mobile_number":      "9170000000",
		"verificationStatus": int64(2),
	}

	if err := triggers.HandleUserChangedCore(context.Background(), "user-1", before, after, deps); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(updater.Updates) != 1 {
		t.Fatalf("expected 1 update, got %d", len(updater.Updates))
	}
	upd := updater.Updates[0]
	if upd.UID != "user-1" {
		t.Errorf("uid: got %s, want user-1", upd.UID)
	}
	if got, ok := upd.Fields["verificationStatus_andNot"].(int); !ok || got != 2 {
		t.Errorf("expected verificationStatus_andNot=2, got %v", upd.Fields["verificationStatus_andNot"])
	}
	if v, ok := upd.Fields["mobile_verified_at"]; !ok {
		t.Errorf("expected mobile_verified_at key present")
	} else if v != nil {
		t.Errorf("expected mobile_verified_at=nil, got %v", v)
	}
}

func TestHandleUserChangedCore_MobileUnchanged_NoOp(t *testing.T) {
	updater := &fakes.UserUpdater{}
	deps := triggers.UserChangesDeps{UpdateUser: updater.Update}
	before := map[string]any{"mobile_number": "9171234567"}
	after := map[string]any{"mobile_number": "9171234567"}

	if err := triggers.HandleUserChangedCore(context.Background(), "user-1", before, after, deps); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(updater.Updates) != 0 {
		t.Fatalf("expected no update, got %d", len(updater.Updates))
	}
}

func TestHandleUserChangedCore_MissingValues_NoCrashNoUpdate(t *testing.T) {
	updater := &fakes.UserUpdater{}
	deps := triggers.UserChangesDeps{UpdateUser: updater.Update}

	if err := triggers.HandleUserChangedCore(context.Background(), "user-1", nil, nil, deps); err != nil {
		t.Fatalf("err on nil before/after: %v", err)
	}
	if len(updater.Updates) != 0 {
		t.Fatalf("expected no update, got %d", len(updater.Updates))
	}

	// missing mobile_number on either side -> also no-op
	if err := triggers.HandleUserChangedCore(context.Background(), "user-1", map[string]any{}, map[string]any{"mobile_number": "9170000000"}, deps); err != nil {
		t.Fatalf("err on missing-before: %v", err)
	}
	if len(updater.Updates) != 0 {
		t.Fatalf("expected no update on missing-before, got %d", len(updater.Updates))
	}
}

func TestHandleUserChangedCore_UpdaterErrorPropagates(t *testing.T) {
	updater := &fakes.UserUpdater{Err: errors.New("firestore: write failed")}
	deps := triggers.UserChangesDeps{UpdateUser: updater.Update}
	before := map[string]any{"mobile_number": "old"}
	after := map[string]any{"mobile_number": "new"}

	err := triggers.HandleUserChangedCore(context.Background(), "user-1", before, after, deps)
	if err == nil {
		t.Fatal("expected propagated error")
	}
}

func TestHandleUserChangedCore_MobileCleared_ClearsVerification(t *testing.T) {
	updater := &fakes.UserUpdater{}
	deps := triggers.UserChangesDeps{UpdateUser: updater.Update}

	before := map[string]any{
		"id":            "user-1",
		"mobile_number": "9171234567",
	}
	after := map[string]any{
		"id":            "user-1",
		"mobile_number": "",
	}

	if err := triggers.HandleUserChangedCore(context.Background(), "user-1", before, after, deps); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(updater.Updates) != 1 {
		t.Fatalf("expected 1 update when mobile is cleared, got %d", len(updater.Updates))
	}
	if got, ok := updater.Updates[0].Fields["verificationStatus_andNot"].(int); !ok || got != 2 {
		t.Errorf("expected verificationStatus_andNot=2, got %v", updater.Updates[0].Fields["verificationStatus_andNot"])
	}
}
