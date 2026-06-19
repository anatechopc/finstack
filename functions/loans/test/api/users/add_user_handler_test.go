package users_test

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"com.loooans.app/api/users"
	"com.loooans.app/test/fakes"
)

// addUserHarness assembles the smallest viable AddUserHandler for HTTP tests: a
// stub validator that returns the configured uid (or "" to simulate auth
// failure), a deps builder that returns the supplied deps + a no-op cleanup,
// and tracks the build error to simulate Firebase init failure. Mirrors the
// RequestOtp handlerHarness.
type addUserHarness struct {
	uid      string // returned by the validator; "" means "auth failed"
	buildErr error  // optional: simulates Firebase init failure
	deps     users.AddUserDeps
	handler  http.Handler
}

func newAddUserHarness(t *testing.T, uid string, deps users.AddUserDeps) *addUserHarness {
	t.Helper()
	h := &addUserHarness{uid: uid, deps: deps}

	validate := func(w http.ResponseWriter, r *http.Request) string {
		if h.uid == "" {
			// Mirror real ValidateRequestV2 behavior: the validator writes
			// 401 itself and the handler returns immediately.
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return ""
		}
		return h.uid
	}
	build := func(ctx context.Context) (users.AddUserDeps, func(), error) {
		if h.buildErr != nil {
			return users.AddUserDeps{}, nil, h.buildErr
		}
		return h.deps, func() {}, nil
	}

	h.handler = users.AddUserHandler(validate, build)
	return h
}

func doAddUserRequest(t *testing.T, h http.Handler, method, body string) *httptest.ResponseRecorder {
	t.Helper()
	var bodyReader io.Reader
	if body != "" {
		bodyReader = strings.NewReader(body)
	}
	req := httptest.NewRequest(method, "/addUser", bodyReader)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

// addUserDepsFor builds a working AddUserDeps wired to fresh fakes, with the
// caller being an admin of company "co-1" whose management type is mgmt. Tests
// that want a specific Core error override the returned auth fake before
// passing the deps to the harness.
func addUserDepsFor(mgmt string, auth *fakes.AuthAccountManager) users.AddUserDeps {
	writer := &fakes.UserAddressWriter{}
	inviter := &fakes.Inviter{}
	callers := &fakes.UserReader{Users: map[string]map[string]any{
		"admin-1": {"user_role": "admin", "company_id": "co-1"},
		"dup-uid": {"id": "dup-uid", "email_address": "jane@example.com"},
	}}
	companies := &fakes.CompanyManagementReader{Types: map[string]string{"co-1": mgmt}}
	return users.AddUserDeps{
		GetUser:                  callers.Read,
		GetCompanyManagementType: companies.Read,
		CreateAuthUser:           auth.Create,
		GetAuthUIDByEmail:        auth.UIDByEmail,
		DeleteAuthUser:           auth.Delete,
		WriteUserAndAddress:      writer.Write,
		SendInvite:               inviter.Send,
		GeneratePassword:         func() string { return "pw-fixed" },
	}
}

const addUserValidBody = `{"role":"teller","user":{"first_name":"Jane","last_name":"Doe","email_address":"jane@example.com"}}`

func TestAddUserHandler_OptionsPreflight_Returns204WithCORSHeaders(t *testing.T) {
	auth := &fakes.AuthAccountManager{NextUID: "uid-new"}
	h := newAddUserHarness(t, "admin-1", addUserDepsFor("app", auth))

	rec := doAddUserRequest(t, h.handler, http.MethodOptions, "")

	if rec.Code != http.StatusNoContent {
		t.Errorf("expected 204 on OPTIONS, got %d", rec.Code)
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "*" {
		t.Errorf("missing or wrong Access-Control-Allow-Origin: %q", got)
	}
	if got := rec.Header().Get("Access-Control-Allow-Methods"); !strings.Contains(got, "POST") {
		t.Errorf("expected Access-Control-Allow-Methods to include POST, got %q", got)
	}
	if got := rec.Header().Get("Access-Control-Allow-Headers"); !strings.Contains(got, "Authorization") {
		t.Errorf("expected Access-Control-Allow-Headers to include Authorization, got %q", got)
	}
}

func TestAddUserHandler_NonPostMethod_Returns400(t *testing.T) {
	auth := &fakes.AuthAccountManager{NextUID: "uid-new"}
	h := newAddUserHarness(t, "admin-1", addUserDepsFor("app", auth))

	rec := doAddUserRequest(t, h.handler, http.MethodGet, "")

	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for GET, got %d", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "Use POST method") {
		t.Errorf("expected body to mention 'Use POST method', got %q", rec.Body.String())
	}
}

func TestAddUserHandler_AuthFailure_HaltsProcessing(t *testing.T) {
	auth := &fakes.AuthAccountManager{NextUID: "uid-new"}
	h := newAddUserHarness(t, "", addUserDepsFor("app", auth))

	rec := doAddUserRequest(t, h.handler, http.MethodPost, addUserValidBody)

	if rec.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d (body=%s)", rec.Code, rec.Body.String())
	}
	if len(auth.Created) != 0 {
		t.Errorf("expected no auth creates when auth fails, got %d", len(auth.Created))
	}
}

func TestAddUserHandler_HappyPath_Returns200WithJSONBody(t *testing.T) {
	auth := &fakes.AuthAccountManager{NextUID: "uid-new"}
	h := newAddUserHarness(t, "admin-1", addUserDepsFor("app", auth))

	rec := doAddUserRequest(t, h.handler, http.MethodPost, addUserValidBody)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 on happy path, got %d (body=%s)", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("response body not valid JSON: %v\n%s", err, rec.Body.String())
	}
	data, _ := body["data"].(map[string]any)
	if data == nil {
		t.Fatalf("expected data object in response, got %v", body)
	}
	if got, _ := data["uid"].(string); got != "uid-new" {
		t.Errorf("expected data.uid=uid-new, got %v", data["uid"])
	}
	if got, ok := data["inviteSent"].(bool); !ok || !got {
		t.Errorf("expected data.inviteSent=true, got %v", data["inviteSent"])
	}
}

func TestAddUserHandler_RoleNotAllowed_Returns403(t *testing.T) {
	// customer role in an app-managed company → ErrRoleNotAllowed → 403.
	auth := &fakes.AuthAccountManager{NextUID: "uid-new"}
	h := newAddUserHarness(t, "admin-1", addUserDepsFor("app", auth))

	body := `{"role":"customer","user":{"email_address":"jane@example.com"}}`
	rec := doAddUserRequest(t, h.handler, http.MethodPost, body)

	if rec.Code != http.StatusForbidden {
		t.Errorf("expected 403 for disallowed role, got %d (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestAddUserHandler_EmailExists_Returns409(t *testing.T) {
	// Genuine duplicate: CreateAuthUser reports ErrEmailExists and the existing
	// uid already has a user doc → 409.
	auth := &fakes.AuthAccountManager{
		NextUID:    "uid-new",
		CreateErr:  users.ErrEmailExists,
		EmailToUID: map[string]string{"jane@example.com": "dup-uid"},
	}
	h := newAddUserHarness(t, "admin-1", addUserDepsFor("app", auth))

	rec := doAddUserRequest(t, h.handler, http.MethodPost, addUserValidBody)

	if rec.Code != http.StatusConflict {
		t.Errorf("expected 409 for duplicate email, got %d (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestAddUserHandler_InvalidRole_Returns400(t *testing.T) {
	auth := &fakes.AuthAccountManager{NextUID: "uid-new"}
	h := newAddUserHarness(t, "admin-1", addUserDepsFor("app", auth))

	body := `{"role":"","user":{"email_address":"jane@example.com"}}`
	rec := doAddUserRequest(t, h.handler, http.MethodPost, body)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for empty role, got %d (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestAddUserHandler_MissingEmail_Returns400(t *testing.T) {
	auth := &fakes.AuthAccountManager{NextUID: "uid-new"}
	h := newAddUserHarness(t, "admin-1", addUserDepsFor("app", auth))

	body := `{"role":"teller","user":{"first_name":"Jane"}}`
	rec := doAddUserRequest(t, h.handler, http.MethodPost, body)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for missing email, got %d (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestAddUserHandler_BuildDepsError_Returns500(t *testing.T) {
	auth := &fakes.AuthAccountManager{NextUID: "uid-new"}
	h := newAddUserHarness(t, "admin-1", addUserDepsFor("app", auth))
	h.buildErr = errors.New("firebase admin init failure")

	rec := doAddUserRequest(t, h.handler, http.MethodPost, addUserValidBody)

	if rec.Code != http.StatusInternalServerError {
		t.Errorf("expected 500 when deps build fails, got %d", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "firebase admin init failure") {
		t.Errorf("expected body to surface build error, got %q", rec.Body.String())
	}
}
