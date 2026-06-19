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
)

// spslHarness assembles the smallest viable SendPasswordSetupLinkHandler for
// HTTP tests: a deps builder that returns deps whose SendInvite returns the
// configured inviteErr (and records the email), plus a build error to simulate
// Firebase init failure. The endpoint is unauthenticated, so there is no
// validator. Mirrors the RequestOtp handlerHarness.
type spslHarness struct {
	inviteErr   error  // returned by SendInvite (core swallows it → still 200)
	buildErr    error  // optional: simulates Firebase init failure
	invitedWith string // captures the last email passed to SendInvite
	handler     http.Handler
}

func newSpslHarness(t *testing.T) *spslHarness {
	t.Helper()
	h := &spslHarness{}

	build := func(ctx context.Context) (users.SendPasswordSetupLinkDeps, func(), error) {
		if h.buildErr != nil {
			return users.SendPasswordSetupLinkDeps{}, nil, h.buildErr
		}
		deps := users.SendPasswordSetupLinkDeps{
			SendInvite: func(ctx context.Context, email string) error {
				h.invitedWith = email
				return h.inviteErr
			},
		}
		return deps, func() {}, nil
	}

	h.handler = users.SendPasswordSetupLinkHandler(build)
	return h
}

func doSpslRequest(t *testing.T, h http.Handler, method, body string) *httptest.ResponseRecorder {
	t.Helper()
	var bodyReader io.Reader
	if body != "" {
		bodyReader = strings.NewReader(body)
	}
	req := httptest.NewRequest(method, "/sendPasswordSetupLink", bodyReader)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestSendPasswordSetupLinkHandler_OptionsPreflight_Returns204(t *testing.T) {
	h := newSpslHarness(t)

	rec := doSpslRequest(t, h.handler, http.MethodOptions, "")

	if rec.Code != http.StatusNoContent {
		t.Errorf("expected 204 on OPTIONS, got %d", rec.Code)
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "*" {
		t.Errorf("missing or wrong Access-Control-Allow-Origin: %q", got)
	}
}

func TestSendPasswordSetupLinkHandler_NonPostMethod_Returns400(t *testing.T) {
	h := newSpslHarness(t)

	rec := doSpslRequest(t, h.handler, http.MethodGet, "")

	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for GET, got %d", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "Use POST method") {
		t.Errorf("expected body to mention 'Use POST method', got %q", rec.Body.String())
	}
}

func TestSendPasswordSetupLinkHandler_MalformedJsonBody_Returns400(t *testing.T) {
	h := newSpslHarness(t)

	rec := doSpslRequest(t, h.handler, http.MethodPost, `{not json`)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for malformed JSON, got %d (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestSendPasswordSetupLinkHandler_ValidEmail_Returns200(t *testing.T) {
	h := newSpslHarness(t)

	rec := doSpslRequest(t, h.handler, http.MethodPost, `{"email":"jane@example.com"}`)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d (body=%s)", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"message":"ok"`) {
		t.Errorf("expected body to be {\"message\":\"ok\"}, got %q", rec.Body.String())
	}
	if h.invitedWith != "jane@example.com" {
		t.Errorf("expected SendInvite called with jane@example.com, got %q", h.invitedWith)
	}
}

func TestSendPasswordSetupLinkHandler_UnknownEmail_StillReturns200(t *testing.T) {
	// Configure the inviter to error (simulating "no such user"); the core
	// swallows it so the endpoint never reveals whether an account exists.
	h := newSpslHarness(t)
	h.inviteErr = errors.New("no such user")

	rec := doSpslRequest(t, h.handler, http.MethodPost, `{"email":"ghost@example.com"}`)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 even for unknown email, got %d (body=%s)", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"message":"ok"`) {
		t.Errorf("expected body to be {\"message\":\"ok\"}, got %q", rec.Body.String())
	}
}
