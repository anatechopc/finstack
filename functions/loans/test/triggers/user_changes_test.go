package triggers_test

import (
	"context"
	"errors"
	"testing"

	"com.loooans.app/test/fakes"
	"com.loooans.app/triggers"
)

// depsWithBoth wires both collaborator paths so a single core call can be
// asserted against the mobile-verification updater and the name-cascade updater.
func depsWithBoth(
	updater *fakes.UserUpdater,
	names *fakes.LoanViewNameUpdater,
) triggers.UserChangesDeps {
	return triggers.UserChangesDeps{
		UpdateUser:              updater.Update,
		UpdateUserLoanViewNames: names.Update,
	}
}

// withMatchingTokens seeds after["search_tokens"] with the value
// SearchTokensForUser would already compute from after's own fields. Most of
// the tests below exercise the mobile-verification or name-cascade path in
// isolation; without this, HandleUserChangedCore's own (correct) search_tokens
// backfill would pad updater.Updates with an extra call these tests don't
// expect. TestSearchTokensForUser_* in user_search_tokens_test.go covers the
// token-diffing behavior itself.
func withMatchingTokens(after map[string]any) map[string]any {
	tokens, _ := triggers.SearchTokensForUser(after)
	after["search_tokens"] = toAnySlice(tokens)
	return after
}

func TestHandleUserChangedCore_MobileChanged_ClearsVerification(t *testing.T) {
	updater := &fakes.UserUpdater{}
	names := &fakes.LoanViewNameUpdater{}
	deps := depsWithBoth(updater, names)

	before := map[string]any{
		"id":                 "user-1",
		"mobile_number":      "9171234567",
		"verificationStatus": int64(2),
	}
	after := withMatchingTokens(map[string]any{
		"id":                 "user-1",
		"mobile_number":      "9170000000",
		"verificationStatus": int64(2),
	})

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
	// Name fields unchanged (absent on both sides) — no cascade.
	if len(names.Updates) != 0 {
		t.Fatalf("mobile-only change must not cascade names, got %d", len(names.Updates))
	}
}

func TestHandleUserChangedCore_NameChanged_CascadesFullName(t *testing.T) {
	updater := &fakes.UserUpdater{}
	names := &fakes.LoanViewNameUpdater{}
	deps := depsWithBoth(updater, names)

	before := map[string]any{
		"id":            "user-1",
		"first_name":    "Juan",
		"last_name":     "Dela Cruz",
		"middle_name":   "Santos",
		"mobile_number": "9171234567",
	}
	after := withMatchingTokens(map[string]any{
		"id":            "user-1",
		"first_name":    "Juan Carlos",
		"last_name":     "Dela Cruz",
		"middle_name":   "Santos",
		"mobile_number": "9171234567",
	})

	if err := triggers.HandleUserChangedCore(context.Background(), "user-1", before, after, deps); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(names.Updates) != 1 {
		t.Fatalf("expected 1 name cascade, got %d", len(names.Updates))
	}
	got := names.Updates[0]
	if got.UserId != "user-1" {
		t.Errorf("userId: got %s, want user-1", got.UserId)
	}
	// Eastern order: "$lastName, $firstName $middleName".
	if want := "Dela Cruz, Juan Carlos Santos"; got.FullName != want {
		t.Errorf("full name: got %q, want %q", got.FullName, want)
	}
	// Mobile unchanged — no verification clear.
	if len(updater.Updates) != 0 {
		t.Fatalf("name-only change must not touch verification, got %d", len(updater.Updates))
	}
}

func TestHandleUserChangedCore_NameChanged_NoMiddleName_OmitsMiddle(t *testing.T) {
	updater := &fakes.UserUpdater{}
	names := &fakes.LoanViewNameUpdater{}
	deps := depsWithBoth(updater, names)

	// middle_name absent (null in Firestore arrives as "") — must render
	// "Last, First" with no trailing middle, matching the Dart getter.
	before := map[string]any{"id": "u", "first_name": "Ana", "last_name": "Reyes"}
	after := map[string]any{"id": "u", "first_name": "Anabelle", "last_name": "Reyes"}

	if err := triggers.HandleUserChangedCore(context.Background(), "u", before, after, deps); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(names.Updates) != 1 {
		t.Fatalf("expected 1 name cascade, got %d", len(names.Updates))
	}
	if want := "Reyes, Anabelle"; names.Updates[0].FullName != want {
		t.Errorf("full name: got %q, want %q", names.Updates[0].FullName, want)
	}
}

func TestHandleUserChangedCore_NameUnchanged_NoCascade(t *testing.T) {
	updater := &fakes.UserUpdater{}
	names := &fakes.LoanViewNameUpdater{}
	deps := depsWithBoth(updater, names)

	// Only the mobile number changes; name fields are identical on both sides.
	before := map[string]any{
		"id":            "user-1",
		"first_name":    "Juan",
		"last_name":     "Dela Cruz",
		"mobile_number": "9171234567",
	}
	after := withMatchingTokens(map[string]any{
		"id":            "user-1",
		"first_name":    "Juan",
		"last_name":     "Dela Cruz",
		"mobile_number": "9170000000",
	})

	if err := triggers.HandleUserChangedCore(context.Background(), "user-1", before, after, deps); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(names.Updates) != 0 {
		t.Fatalf("unchanged name must not cascade, got %d", len(names.Updates))
	}
	// Mobile changed and was previously set -> verification still cleared.
	if len(updater.Updates) != 1 {
		t.Fatalf("expected mobile logic to still run, got %d updates", len(updater.Updates))
	}
}

func TestHandleUserChangedCore_NameCascadeErrorPropagates(t *testing.T) {
	updater := &fakes.UserUpdater{}
	names := &fakes.LoanViewNameUpdater{Err: errors.New("firestore: query failed")}
	deps := depsWithBoth(updater, names)

	before := map[string]any{"id": "u", "first_name": "Ana", "last_name": "Reyes"}
	after := map[string]any{"id": "u", "first_name": "Anabelle", "last_name": "Reyes"}

	if err := triggers.HandleUserChangedCore(context.Background(), "u", before, after, deps); err == nil {
		t.Fatal("expected the name-cascade error to propagate")
	}
}

func TestHandleUserChangedCore_MobileUnchanged_NoOp(t *testing.T) {
	updater := &fakes.UserUpdater{}
	deps := triggers.UserChangesDeps{UpdateUser: updater.Update}
	before := map[string]any{"mobile_number": "9171234567"}
	after := withMatchingTokens(map[string]any{"mobile_number": "9171234567"})

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
	after := withMatchingTokens(map[string]any{"mobile_number": "9170000000"})
	if err := triggers.HandleUserChangedCore(context.Background(), "user-1", map[string]any{}, after, deps); err != nil {
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
