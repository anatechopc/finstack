package users_test

import (
	"context"
	"errors"
	"testing"

	"com.loooans.app/api/users"
	"com.loooans.app/test/fakes"
)

func baseUserPayload() map[string]any {
	return map[string]any{
		"first_name":    "Jane",
		"last_name":     "Doe",
		"email_address": "jane@example.com",
	}
}

// depsWith builds AddUserDeps wired to fresh fakes, with the caller being an
// admin of company "co-1" whose management type is provided.
func depsWith(mgmt string) (users.AddUserDeps, *fakes.AuthAccountManager, *fakes.UserAddressWriter, *fakes.Inviter) {
	auth := &fakes.AuthAccountManager{NextUID: "uid-new"}
	writer := &fakes.UserAddressWriter{}
	inviter := &fakes.Inviter{}
	callers := &fakes.UserReader{Users: map[string]map[string]any{
		"admin-1": {"user_role": "admin", "company_id": "co-1"},
	}}
	companies := &fakes.CompanyManagementReader{Types: map[string]string{"co-1": mgmt}}
	deps := users.AddUserDeps{
		GetUser:                  callers.Read,
		GetCompanyManagementType: companies.Read,
		CreateAuthUser:           auth.Create,
		DeleteAuthUser:           auth.Delete,
		WriteUserAndAddress:      writer.Write,
		SendInvite:               inviter.Send,
		GeneratePassword:         func() string { return "pw-fixed" },
	}
	return deps, auth, writer, inviter
}

func TestAddUserCore_StaffInAppCompany_Succeeds(t *testing.T) {
	deps, auth, writer, inviter := depsWith("app")

	res, err := users.HandleAddUserCore(context.Background(), "admin-1", "teller", baseUserPayload(), nil, deps)
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if res.UID != "uid-new" || !res.InviteSent {
		t.Fatalf("unexpected result: %+v", res)
	}
	if len(auth.Created) != 1 || auth.Created[0].Email != "jane@example.com" {
		t.Fatalf("auth create not called correctly: %+v", auth.Created)
	}
	if len(writer.Writes) != 1 {
		t.Fatalf("expected 1 write, got %d", len(writer.Writes))
	}
	w := writer.Writes[0]
	if w.UID != "uid-new" || w.User["id"] != "uid-new" || w.User["company_id"] != "co-1" ||
		w.User["user_role"] != "teller" || w.User["invited_by_admin"] != true {
		t.Fatalf("server-authoritative fields wrong: %+v", w.User)
	}
	if len(inviter.Invites) != 1 || inviter.Invites[0].Email != "jane@example.com" {
		t.Fatalf("invite not sent: %+v", inviter.Invites)
	}
}

func TestAddUserCore_BorrowerInSelfManaged_Succeeds(t *testing.T) {
	deps, _, writer, _ := depsWith("selfManaged")
	if _, err := users.HandleAddUserCore(context.Background(), "admin-1", "customer", baseUserPayload(), nil, deps); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if writer.Writes[0].User["user_role"] != "customer" {
		t.Fatalf("expected customer role written")
	}
}

func TestAddUserCore_BorrowerInAppCompany_Forbidden(t *testing.T) {
	deps, auth, writer, _ := depsWith("app")
	_, err := users.HandleAddUserCore(context.Background(), "admin-1", "customer", baseUserPayload(), nil, deps)
	if !errors.Is(err, users.ErrRoleNotAllowed) {
		t.Fatalf("expected ErrRoleNotAllowed, got %v", err)
	}
	if len(auth.Created) != 0 || len(writer.Writes) != 0 {
		t.Fatalf("must not create auth/write when forbidden")
	}
}

func TestAddUserCore_CallerNotAdmin_Forbidden(t *testing.T) {
	deps, _, _, _ := depsWith("app")
	callers := &fakes.UserReader{Users: map[string]map[string]any{
		"teller-1": {"user_role": "teller", "company_id": "co-1"},
	}}
	deps.GetUser = callers.Read
	_, err := users.HandleAddUserCore(context.Background(), "teller-1", "teller", baseUserPayload(), nil, deps)
	if !errors.Is(err, users.ErrCallerNotAdmin) {
		t.Fatalf("expected ErrCallerNotAdmin, got %v", err)
	}
}

func TestAddUserCore_InvalidRole_Rejected(t *testing.T) {
	deps, _, _, _ := depsWith("app")
	_, err := users.HandleAddUserCore(context.Background(), "admin-1", "appAdmin", baseUserPayload(), nil, deps)
	if !errors.Is(err, users.ErrInvalidRole) {
		t.Fatalf("expected ErrInvalidRole for appAdmin, got %v", err)
	}
}

func TestAddUserCore_MissingEmail_Rejected(t *testing.T) {
	deps, _, _, _ := depsWith("app")
	payload := map[string]any{"first_name": "Jane", "last_name": "Doe"}
	_, err := users.HandleAddUserCore(context.Background(), "admin-1", "teller", payload, nil, deps)
	if !errors.Is(err, users.ErrMissingEmail) {
		t.Fatalf("expected ErrMissingEmail, got %v", err)
	}
}

func TestAddUserCore_DuplicateEmail_Conflict(t *testing.T) {
	deps, auth, _, _ := depsWith("app")
	auth.CreateErr = users.ErrEmailExists
	_, err := users.HandleAddUserCore(context.Background(), "admin-1", "teller", baseUserPayload(), nil, deps)
	if !errors.Is(err, users.ErrEmailExists) {
		t.Fatalf("expected ErrEmailExists, got %v", err)
	}
}

func TestAddUserCore_WriteFails_RollsBackAuth(t *testing.T) {
	deps, auth, writer, _ := depsWith("app")
	writer.Err = errors.New("firestore down")
	_, err := users.HandleAddUserCore(context.Background(), "admin-1", "teller", baseUserPayload(), nil, deps)
	if err == nil {
		t.Fatalf("expected error when write fails")
	}
	if len(auth.Deleted) != 1 || auth.Deleted[0] != "uid-new" {
		t.Fatalf("expected compensating delete of uid-new, got %+v", auth.Deleted)
	}
}

func TestAddUserCore_InviteFails_StillSucceeds(t *testing.T) {
	deps, _, _, inviter := depsWith("app")
	inviter.Err = errors.New("graph 500")
	res, err := users.HandleAddUserCore(context.Background(), "admin-1", "teller", baseUserPayload(), nil, deps)
	if err != nil {
		t.Fatalf("invite failure must not fail the request: %v", err)
	}
	if res.InviteSent {
		t.Fatalf("expected InviteSent=false when invite errors")
	}
}

func TestAddUserCore_StampsAddressDataId(t *testing.T) {
	deps, _, writer, _ := depsWith("selfManaged")
	addr := map[string]any{"line1": "1 Main St"}
	if _, err := users.HandleAddUserCore(context.Background(), "admin-1", "customer", baseUserPayload(), addr, deps); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if writer.Writes[0].Address["data_id"] != "uid-new" {
		t.Fatalf("expected address data_id stamped to uid-new, got %+v", writer.Writes[0].Address)
	}
}

func TestAddUserCore_StampsEmploymentUserId(t *testing.T) {
	deps, _, writer, _ := depsWith("app")
	payload := baseUserPayload()
	payload["employment_details"] = map[string]any{"user_id": "no-id"}
	if _, err := users.HandleAddUserCore(context.Background(), "admin-1", "teller", payload, nil, deps); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	emp, _ := writer.Writes[0].User["employment_details"].(map[string]any)
	if emp == nil || emp["user_id"] != "uid-new" {
		t.Fatalf("expected employment_details.user_id stamped to uid-new, got %+v", emp)
	}
}

func TestAddUserCore_CallerNoCompany_Rejected(t *testing.T) {
	auth := &fakes.AuthAccountManager{NextUID: "uid-new"}
	writer := &fakes.UserAddressWriter{}
	companies := &fakes.CompanyManagementReader{Types: map[string]string{}}
	callers := &fakes.UserReader{Users: map[string]map[string]any{
		"admin-1": {"user_role": "admin"}, // no company_id
	}}
	deps := users.AddUserDeps{
		GetUser:                  callers.Read,
		GetCompanyManagementType: companies.Read,
		CreateAuthUser:           auth.Create,
		DeleteAuthUser:           auth.Delete,
		WriteUserAndAddress:      writer.Write,
		SendInvite:               (&fakes.Inviter{}).Send,
		GeneratePassword:         func() string { return "pw-fixed" },
	}

	_, err := users.HandleAddUserCore(context.Background(), "admin-1", "admin", baseUserPayload(), nil, deps)
	if !errors.Is(err, users.ErrCallerNoCompany) {
		t.Fatalf("expected ErrCallerNoCompany, got %v", err)
	}
	if len(auth.Created) != 0 {
		t.Fatalf("must not create auth account when caller has no company")
	}
	if len(writer.Writes) != 0 {
		t.Fatalf("must not write when caller has no company")
	}
}

func TestAddUserCore_StaffRole_SkipsCompanyRead(t *testing.T) {
	auth := &fakes.AuthAccountManager{NextUID: "uid-new"}
	writer := &fakes.UserAddressWriter{}
	inviter := &fakes.Inviter{}
	callers := &fakes.UserReader{Users: map[string]map[string]any{
		"admin-1": {"user_role": "admin", "company_id": "co-1"},
	}}
	companies := &fakes.CompanyManagementReader{Types: map[string]string{"co-1": "app"}}
	deps := users.AddUserDeps{
		GetUser:                  callers.Read,
		GetCompanyManagementType: companies.Read,
		CreateAuthUser:           auth.Create,
		DeleteAuthUser:           auth.Delete,
		WriteUserAndAddress:      writer.Write,
		SendInvite:               inviter.Send,
		GeneratePassword:         func() string { return "pw-fixed" },
	}

	_, err := users.HandleAddUserCore(context.Background(), "admin-1", "teller", baseUserPayload(), nil, deps)
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(companies.ReadCalls) != 0 {
		t.Fatalf("expected company NOT to be read for staff role, got %d read(s): %v", len(companies.ReadCalls), companies.ReadCalls)
	}
}

func TestAddUserCore_StampsVerificationStatus(t *testing.T) {
	deps, _, writer, _ := depsWith("app")

	_, err := users.HandleAddUserCore(context.Background(), "admin-1", "teller", baseUserPayload(), nil, deps)
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(writer.Writes) == 0 {
		t.Fatalf("expected at least one write")
	}
	got := writer.Writes[0].User["verificationStatus"]
	if got != 0 {
		t.Fatalf("expected verificationStatus==0, got %v", got)
	}
}

func TestAddUserCore_WriteAndRollbackBothFail_ReturnsError(t *testing.T) {
	auth := &fakes.AuthAccountManager{
		NextUID:   "uid-new",
		DeleteErr: errors.New("auth delete failed"),
	}
	writer := &fakes.UserAddressWriter{Err: errors.New("firestore down")}
	callers := &fakes.UserReader{Users: map[string]map[string]any{
		"admin-1": {"user_role": "admin", "company_id": "co-1"},
	}}
	companies := &fakes.CompanyManagementReader{Types: map[string]string{"co-1": "app"}}
	deps := users.AddUserDeps{
		GetUser:                  callers.Read,
		GetCompanyManagementType: companies.Read,
		CreateAuthUser:           auth.Create,
		DeleteAuthUser:           auth.Delete,
		WriteUserAndAddress:      writer.Write,
		SendInvite:               (&fakes.Inviter{}).Send,
		GeneratePassword:         func() string { return "pw-fixed" },
	}

	_, err := users.HandleAddUserCore(context.Background(), "admin-1", "teller", baseUserPayload(), nil, deps)
	if err == nil {
		t.Fatalf("expected error when both write and rollback fail")
	}
	if len(auth.Deleted) == 0 || auth.Deleted[0] != "uid-new" {
		t.Fatalf("expected delete attempted for uid-new, got %v", auth.Deleted)
	}
}
