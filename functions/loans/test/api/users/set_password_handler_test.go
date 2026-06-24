package users_test

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"com.loooans.app/api/users"
	"com.loooans.app/test/fakes"
)

// spHarness assembles the smallest viable SetPasswordHandler for HTTP tests: a
// deps builder that returns deps backed by the shared fakes (a token consumer
// and a password setter), plus a build error to simulate Firebase init failure.
// The endpoint is unauthenticated, so there is no validator. Mirrors the
// SendPasswordSetupLink handlerHarness.
type spHarness struct {
	consumer *fakes.SetPasswordTokenConsumer // returns uid/email or an error
	setter   *fakes.PasswordSetter           // records set-password calls
	buildErr error                           // optional: simulates Firebase init failure
	handler  http.Handler
}

func newSpHarness(t *testing.T) *spHarness {
	t.Helper()
	h := &spHarness{
		consumer: &fakes.SetPasswordTokenConsumer{UID: "uid-1", Email: "jane@example.com"},
		setter:   &fakes.PasswordSetter{},
	}

	build := func(ctx context.Context) (users.SetPasswordDeps, func(), error) {
		if h.buildErr != nil {
			return users.SetPasswordDeps{}, nil, h.buildErr
		}
		deps := users.SetPasswordDeps{
			ConsumeToken: h.consumer.Consume,
			SetPassword:  h.setter.Set,
		}
		return deps, func() {}, nil
	}

	h.handler = users.SetPasswordHandler(build)
	return h
}

func doSpRequest(t *testing.T, h http.Handler, method, body string) *httptest.ResponseRecorder {
	t.Helper()
	var bodyReader io.Reader
	if body != "" {
		bodyReader = strings.NewReader(body)
	}
	req := httptest.NewRequest(method, "/setPassword", bodyReader)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestSetPasswordHandler_OptionsPreflight_Returns204(t *testing.T) {
	h := newSpHarness(t)

	rec := doSpRequest(t, h.handler, http.MethodOptions, "")

	if rec.Code != http.StatusNoContent {
		t.Errorf("expected 204 on OPTIONS, got %d", rec.Code)
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "*" {
		t.Errorf("missing or wrong Access-Control-Allow-Origin: %q", got)
	}
	if got := rec.Header().Get("Access-Control-Allow-Methods"); got != "POST" {
		t.Errorf("missing or wrong Access-Control-Allow-Methods: %q", got)
	}
}

func TestSetPasswordHandler_NonPostMethod_Returns400(t *testing.T) {
	h := newSpHarness(t)

	rec := doSpRequest(t, h.handler, http.MethodGet, "")

	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for GET, got %d", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "Use POST method") {
		t.Errorf("expected body to mention 'Use POST method', got %q", rec.Body.String())
	}
}

func TestSetPasswordHandler_MalformedJsonBody_Returns400(t *testing.T) {
	h := newSpHarness(t)

	rec := doSpRequest(t, h.handler, http.MethodPost, `{not json`)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for malformed JSON, got %d (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestSetPasswordHandler_BuildError_Returns500GenericBody(t *testing.T) {
	// The deps builder fails (e.g. Firebase init). The client must get a 500
	// with a GENERIC body — the raw internal error must NOT leak to the
	// unauthenticated caller. Pins Fix 4.
	h := newSpHarness(t)
	h.buildErr = errors.New("dial firestore: super-secret internal wiring detail")

	rec := doSpRequest(t, h.handler, http.MethodPost, `{"token":"tok","newPassword":"new-secret"}`)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500 on build error, got %d (body=%s)", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "Internal error") {
		t.Errorf("expected generic 'Internal error' body, got %q", rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "super-secret internal wiring detail") {
		t.Errorf("raw build error leaked to client: %q", rec.Body.String())
	}
}

func TestSetPasswordHandler_HappyPath_Returns200WithEmail(t *testing.T) {
	h := newSpHarness(t)

	rec := doSpRequest(t, h.handler, http.MethodPost, `{"token":"tok","newPassword":"new-secret"}`)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d (body=%s)", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"data":{"email":"jane@example.com"}`) {
		t.Errorf(`expected body {"data":{"email":"jane@example.com"}}, got %q`, rec.Body.String())
	}
	// The token (hashed) must have been consumed and the password set.
	if len(h.consumer.Calls) != 1 {
		t.Errorf("expected one consume call, got %v", h.consumer.Calls)
	}
	if len(h.setter.Sets) != 1 || h.setter.Sets[0].UID != "uid-1" || h.setter.Sets[0].NewPassword != "new-secret" {
		t.Errorf("expected SetPassword(uid-1, new-secret), got %+v", h.setter.Sets)
	}
}

func TestSetPasswordHandler_WeakPassword_Returns400(t *testing.T) {
	h := newSpHarness(t)

	rec := doSpRequest(t, h.handler, http.MethodPost, `{"token":"tok","newPassword":"short"}`)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for a too-short password, got %d (body=%s)", rec.Code, rec.Body.String())
	}
	// A weak password must not burn the one-time token.
	if len(h.consumer.Calls) != 0 || len(h.setter.Sets) != 0 {
		t.Errorf("weak password must not consume token / set password: consume=%v set=%v", h.consumer.Calls, h.setter.Sets)
	}
}

func TestSetPasswordHandler_InvalidToken_Returns400NoInternals(t *testing.T) {
	// The consumer rejects the token (expired/used/absent). The client gets a
	// 400 with the opaque sentinel reason — and crucially the raw token value
	// must never be echoed back.
	h := newSpHarness(t)
	h.consumer = &fakes.SetPasswordTokenConsumer{Err: users.ErrInvalidSetPasswordToken}

	rec := doSpRequest(t, h.handler, http.MethodPost, `{"token":"super-secret-token","newPassword":"new-secret"}`)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for an invalid token, got %d (body=%s)", rec.Code, rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "super-secret-token") {
		t.Errorf("raw token leaked to client: %q", rec.Body.String())
	}
	if len(h.setter.Sets) != 0 {
		t.Errorf("must not set a password when the token is invalid, got %v", h.setter.Sets)
	}
}
