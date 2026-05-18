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
	"time"

	"com.loooans.app/api/users"
	"com.loooans.app/test/fakes"
)

// handlerHarness assembles the smallest viable RequestOtpHandler for HTTP
// tests: a stub validator that always returns the configured uid (or "" to
// simulate auth failure), a deps builder that returns the supplied fakes,
// and a constant subdomain. Tests use the returned handler with httptest to
// drive single requests and assert response status, headers, and body.
type handlerHarness struct {
	uid         string // returned by the validator; "" means "auth failed"
	validateErr string // when uid is empty, this body has already been written to w
	buildErr    error  // optional: simulates Firebase init failure
	deps        users.RequestOtpDeps
	subdomain   string
	handler     http.Handler
}

func newHarness(t *testing.T, uid string, deps users.RequestOtpDeps) *handlerHarness {
	t.Helper()
	h := &handlerHarness{uid: uid, deps: deps, subdomain: "dev."}

	validate := func(w http.ResponseWriter, r *http.Request) string {
		if h.uid == "" {
			// Mirror real ValidateRequestV2 behavior: the validator writes
			// 401 itself and the handler returns immediately.
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return ""
		}
		return h.uid
	}
	build := func(ctx context.Context) (users.RequestOtpDeps, func(), error) {
		if h.buildErr != nil {
			return users.RequestOtpDeps{}, nil, h.buildErr
		}
		return h.deps, func() {}, nil
	}
	getSubdomain := func() string { return h.subdomain }

	h.handler = users.RequestOtpHandler(validate, build, getSubdomain)
	return h
}

func doRequest(t *testing.T, h http.Handler, method, body string) *httptest.ResponseRecorder {
	t.Helper()
	var bodyReader io.Reader
	if body != "" {
		bodyReader = strings.NewReader(body)
	}
	req := httptest.NewRequest(method, "/requestOtp", bodyReader)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

// minimumValidDeps wires a working deps set with stub closures so tests
// that focus on the HTTP layer don't have to repeat the plumbing. Tests
// that want to exercise specific Core errors override the relevant
// closures inline.
func minimumValidDeps(now time.Time) users.RequestOtpDeps {
	return users.RequestOtpDeps{
		GenerateOtp:      func() (string, string, error) { return "h-1", "111111", nil },
		ReadUser:         (&fakes.UserReader{}).Read,
		GetAuthUserEmail: (&fakes.AuthEmailReader{Emails: map[string]string{"user-123": "u@x.com"}}).Read,
		WriteOtp:         (&fakes.OtpWriter{}).Write,
		SendEmail:        (&fakes.EmailSender{}).Send,
		Now:              func() time.Time { return now },
	}
}

func TestRequestOtpHandler_OptionsPreflight_Returns204WithCORSHeaders(t *testing.T) {
	h := newHarness(t, "user-123", minimumValidDeps(time.Now()))

	rec := doRequest(t, h.handler, http.MethodOptions, "")

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

func TestRequestOtpHandler_NonPostMethod_Returns400(t *testing.T) {
	h := newHarness(t, "user-123", minimumValidDeps(time.Now()))

	for _, method := range []string{http.MethodGet, http.MethodPut, http.MethodDelete, http.MethodPatch} {
		t.Run(method, func(t *testing.T) {
			rec := doRequest(t, h.handler, method, "")
			if rec.Code != http.StatusBadRequest {
				t.Errorf("expected 400 for %s, got %d", method, rec.Code)
			}
			if !strings.Contains(rec.Body.String(), "Use POST method") {
				t.Errorf("expected body to mention 'Use POST method', got %q", rec.Body.String())
			}
		})
	}
}

func TestRequestOtpHandler_AuthFailure_HaltsProcessing(t *testing.T) {
	// uid="" → validator stubs 401 and we expect no further processing.
	otpWriter := &fakes.OtpWriter{}
	deps := minimumValidDeps(time.Now())
	deps.WriteOtp = otpWriter.Write
	h := newHarness(t, "", deps)

	rec := doRequest(t, h.handler, http.MethodPost, `{"purpose":"email"}`)

	if rec.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d (body=%s)", rec.Code, rec.Body.String())
	}
	if len(otpWriter.Writes) != 0 {
		t.Errorf("expected no RTDB writes when auth fails, got %d", len(otpWriter.Writes))
	}
}

func TestRequestOtpHandler_MalformedJsonBody_Returns500(t *testing.T) {
	h := newHarness(t, "user-123", minimumValidDeps(time.Now()))

	rec := doRequest(t, h.handler, http.MethodPost, `{not json`)

	if rec.Code != http.StatusInternalServerError {
		t.Errorf("expected 500 for malformed JSON, got %d (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestRequestOtpHandler_MissingPurpose_Returns400(t *testing.T) {
	h := newHarness(t, "user-123", minimumValidDeps(time.Now()))

	rec := doRequest(t, h.handler, http.MethodPost, `{}`)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for missing purpose, got %d", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "Missing field") {
		t.Errorf("expected body to mention missing field, got %q", rec.Body.String())
	}
}

func TestRequestOtpHandler_EmptyPurpose_Returns400(t *testing.T) {
	h := newHarness(t, "user-123", minimumValidDeps(time.Now()))

	rec := doRequest(t, h.handler, http.MethodPost, `{"purpose":""}`)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for empty purpose, got %d", rec.Code)
	}
}

func TestRequestOtpHandler_BuildDepsError_Returns500(t *testing.T) {
	h := newHarness(t, "user-123", minimumValidDeps(time.Now()))
	h.buildErr = errors.New("firebase admin init failure")

	rec := doRequest(t, h.handler, http.MethodPost, `{"purpose":"email"}`)

	if rec.Code != http.StatusInternalServerError {
		t.Errorf("expected 500 when deps build fails, got %d", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "firebase admin init failure") {
		t.Errorf("expected body to surface build error, got %q", rec.Body.String())
	}
}

func TestRequestOtpHandler_InvalidObjective_Returns400(t *testing.T) {
	h := newHarness(t, "user-123", minimumValidDeps(time.Now()))

	rec := doRequest(t, h.handler, http.MethodPost, `{"purpose":"weird"}`)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for unknown objective, got %d (body=%s)", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "not valid") {
		t.Errorf("expected body to mention objective validity, got %q", rec.Body.String())
	}
}

func TestRequestOtpHandler_AuthMissingEmail_Returns400(t *testing.T) {
	deps := minimumValidDeps(time.Now())
	deps.GetAuthUserEmail = (&fakes.AuthEmailReader{Emails: map[string]string{"user-123": ""}}).Read
	h := newHarness(t, "user-123", deps)

	rec := doRequest(t, h.handler, http.MethodPost, `{"purpose":"email"}`)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 when auth user has no email, got %d", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "no email on record") {
		t.Errorf("expected body to surface missing-email reason, got %q", rec.Body.String())
	}
}

func TestRequestOtpHandler_MobileUserNotFound_Returns400(t *testing.T) {
	deps := minimumValidDeps(time.Now())
	deps.ReadUser = (&fakes.UserReader{}).Read // empty Users → (nil, nil)
	h := newHarness(t, "user-123", deps)

	rec := doRequest(t, h.handler, http.MethodPost, `{"purpose":"mobile_number"}`)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 when user not found, got %d", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "User not found") {
		t.Errorf("expected body to mention 'User not found', got %q", rec.Body.String())
	}
}

func TestRequestOtpHandler_MobileMissingNumber_Returns400(t *testing.T) {
	deps := minimumValidDeps(time.Now())
	deps.ReadUser = (&fakes.UserReader{Users: map[string]map[string]any{
		"user-123": {}, // no mobile_number
	}}).Read
	h := newHarness(t, "user-123", deps)

	rec := doRequest(t, h.handler, http.MethodPost, `{"purpose":"mobile_number"}`)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for missing mobile_number, got %d", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "no mobile number") {
		t.Errorf("expected body to mention missing mobile number, got %q", rec.Body.String())
	}
}

func TestRequestOtpHandler_UnknownCoreError_Returns500(t *testing.T) {
	// Simulate an unmapped Core error (e.g., RTDB transport failure).
	deps := minimumValidDeps(time.Now())
	deps.WriteOtp = (&fakes.OtpWriter{Err: errors.New("rtdb: backend unavailable")}).Write
	h := newHarness(t, "user-123", deps)

	rec := doRequest(t, h.handler, http.MethodPost, `{"purpose":"email"}`)

	if rec.Code != http.StatusInternalServerError {
		t.Errorf("expected 500 for unmapped errors, got %d (body=%s)", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "rtdb: backend unavailable") {
		t.Errorf("expected body to surface underlying error message, got %q", rec.Body.String())
	}
}

func TestRequestOtpHandler_EmailHappyPath_Returns200WithJSONBody(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	otpWriter := &fakes.OtpWriter{}
	emailSender := &fakes.EmailSender{}
	deps := minimumValidDeps(now)
	deps.WriteOtp = otpWriter.Write
	deps.SendEmail = emailSender.Send
	h := newHarness(t, "user-123", deps)

	rec := doRequest(t, h.handler, http.MethodPost, `{"purpose":"email"}`)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 on happy path, got %d (body=%s)", rec.Code, rec.Body.String())
	}

	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("response body not valid JSON: %v\n%s", err, rec.Body.String())
	}
	if got, _ := body["token"].(string); got != "h-1" {
		t.Errorf("expected token=h-1, got %v", body["token"])
	}
	if got, _ := body["redirect_url"].(string); !strings.Contains(got, "h-1") {
		t.Errorf("expected redirect_url to contain hash, got %v", body["redirect_url"])
	}
	if got, _ := body["redirect_url"].(string); !strings.HasPrefix(got, "dev.") {
		t.Errorf("expected redirect_url to use injected subdomain, got %v", body["redirect_url"])
	}
	wantExpire := float64(now.Add(5 * time.Minute).UnixMilli())
	if got, _ := body["expire_at"].(float64); got != wantExpire {
		t.Errorf("expected expire_at=%v (millis), got %v", wantExpire, body["expire_at"])
	}

	if len(emailSender.Sends) != 1 {
		t.Errorf("expected exactly 1 email send, got %d", len(emailSender.Sends))
	}
}

func TestRequestOtpHandler_PassesTargetUserIDAndReasonFromBody(t *testing.T) {
	now := time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC)
	otpWriter := &fakes.OtpWriter{}
	userReader := &fakes.UserReader{Users: map[string]map[string]any{
		"user-456": {"mobile_number": "+639171234567"},
	}}
	deps := minimumValidDeps(now)
	deps.ReadUser = userReader.Read
	deps.WriteOtp = otpWriter.Write
	h := newHarness(t, "user-123", deps)

	body := `{"purpose":"mobile_number","target_user_id":"user-456","reason":"payment"}`
	rec := doRequest(t, h.handler, http.MethodPost, body)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d (body=%s)", rec.Code, rec.Body.String())
	}
	if len(otpWriter.Writes) != 1 {
		t.Fatalf("expected 1 write, got %d", len(otpWriter.Writes))
	}
	entry := otpWriter.Writes[0].Entry
	if got, _ := entry["userId"].(string); got != "user-456" {
		t.Errorf("expected entry.userId=user-456 (from body), got %v", entry["userId"])
	}
	if got, _ := entry["requested_by"].(string); got != "user-123" {
		t.Errorf("expected entry.requested_by=user-123 (caller from validator), got %v", entry["requested_by"])
	}
	if got, _ := entry["reason"].(string); got != "payment" {
		t.Errorf("expected entry.reason=payment (from body), got %v", entry["reason"])
	}
}
