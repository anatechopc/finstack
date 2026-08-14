# OTP Phone Number Normalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make OTP SMS deliverable by normalizing `mobile_number` to E.164 at request time (country derived from the user's address), and make the SMS gateway report real send outcomes instead of unconditionally writing `sent`.

**Architecture:** Three independent PRs. PR A (Go backend): `requestOtp` normalizes the phone via `nyaruka/phonenumbers` using the country from the `{prefix}address` doc, rejecting un-normalizable requests with 400. PR B (Android gateway): `sentIntent` PendingIntents + result receiver write honest `sent`/`failed` status and skip expired entries. PR C (Flutter): typed `RequestOtpException` surfaces the server's 400 text in the two OTP blocs.

**Tech Stack:** Go 1.22 (multi-module: root `com.loooans.app` + `api` submodule), `github.com/nyaruka/phonenumbers`; Kotlin/Android (minSdk 31, JUnit4); Flutter/Dart (mocktail + bloc_test).

**Spec:** `docs/superpowers/specs/2026-07-24-otp-phone-normalization-design.md`

## Global Constraints

- Go tests on macOS: always `CGO_ENABLED=0 go test ./...` (dyld LC_UUID workaround).
- Flutter: always `fvm flutter`, never bare `flutter`.
- NEVER run bare `firebase deploy` from `apps/loans/`.
- Backend-first: PR A merges (and auto-deploys to dev on `develop`) before PR C matters in practice; PRs are independent otherwise.
- SSH to GitHub is broken in this environment. Push with:
  `git -c credential.helper='!gh auth git-credential' push https://github.com/anatechopc/finstack.git <branch>`
- Go functions auto-deploy on merge to `develop` (region asia-east1, project loooans-dev-stg). No manual deploy step.
- Commit messages end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

# PR A — Backend normalization (branch `feature/otp-phone-normalization`, current branch)

### Task 1: `NormalizePhoneE164` service helper

**Files:**
- Create: `functions/loans/api/service/phone_service.go`
- Test: `functions/loans/test/api/service/phone_service_test.go` (new directory)
- Modify: `functions/loans/api/go.mod` / `go.sum` (new dep), root `functions/loans/go.mod` / `go.sum` (tidy)

**Interfaces:**
- Produces: `service.NormalizePhoneE164(number, countryName string) (string, error)`; error sentinels `service.ErrCountryUnknown`, `service.ErrPhoneInvalid` (checked with `errors.Is`). Task 2 consumes all three.

- [ ] **Step 1: Write the failing test**

Create `functions/loans/test/api/service/phone_service_test.go`:

```go
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions/loans && CGO_ENABLED=0 go test ./test/api/service/...`
Expected: FAIL — `undefined: service.NormalizePhoneE164` (compile error).

- [ ] **Step 3: Add the dependency**

```bash
cd functions/loans/api
go get github.com/nyaruka/phonenumbers@latest
go mod tidy
cd ..
go mod tidy
```

- [ ] **Step 4: Write the implementation**

Create `functions/loans/api/service/phone_service.go`:

```go
package service

import (
	"errors"
	"fmt"
	"strings"

	"github.com/nyaruka/phonenumbers"
)

// Errors returned by NormalizePhoneE164. The users package maps these to
// its HTTP-facing sentinels — service cannot import users (import cycle).
var (
	ErrCountryUnknown = errors.New("unknown country")
	ErrPhoneInvalid   = errors.New("invalid phone number")
)

// countryToRegion maps the free-text address `country` value (trimmed,
// lower-cased) to an ISO 3166-1 alpha-2 region for libphonenumber. The
// registration form hardcodes "Philippines"; extend when new countries are
// onboarded.
var countryToRegion = map[string]string{
	"philippines": "PH",
}

// NormalizePhoneE164 parses a stored mobile number against the user's
// country and returns it in E.164 form ("9175551291" + "Philippines" →
// "+639175551291"). Numbers already carrying a "+" prefix parse
// independently of the region hint, so well-formed legacy values pass
// through even when countryName is empty or unknown.
func NormalizePhoneE164(number, countryName string) (string, error) {
	trimmed := strings.TrimSpace(number)
	region := ""
	if !strings.HasPrefix(trimmed, "+") {
		var ok bool
		region, ok = countryToRegion[strings.ToLower(strings.TrimSpace(countryName))]
		if !ok {
			return "", fmt.Errorf("%w: %q", ErrCountryUnknown, countryName)
		}
	}
	parsed, err := phonenumbers.Parse(trimmed, region)
	if err != nil {
		return "", fmt.Errorf("%w: %v", ErrPhoneInvalid, err)
	}
	if !phonenumbers.IsValidNumber(parsed) {
		return "", fmt.Errorf("%w: %q is not valid for region %q", ErrPhoneInvalid, trimmed, region)
	}
	return phonenumbers.Format(parsed, phonenumbers.E164), nil
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd functions/loans && CGO_ENABLED=0 go test ./test/api/service/...`
Expected: PASS (9 subtests).

- [ ] **Step 6: Build everything and commit**

```bash
cd functions/loans && go build -v ./...
git add api/service/phone_service.go api/go.mod api/go.sum go.mod go.sum test/api/service/
git commit -m "feat(request-otp): add country-aware E.164 phone normalization helper

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Core wiring — read address country, normalize before queueing

**Files:**
- Modify: `functions/loans/api/users/request_otp.go` (sentinels ~line 21-26, `RequestOtpDeps` ~line 56-81, `RequestOtpCore` mobile branch ~line 127-145)
- Modify: `functions/loans/test/fakes/fakes.go` (append `AddressReader`)
- Modify: `functions/loans/test/api/users/request_otp_test.go` (`buildDeps` + new cases)

**Interfaces:**
- Consumes: `service.NormalizePhoneE164`, `service.ErrCountryUnknown`, `service.ErrPhoneInvalid` (Task 1).
- Produces: users-package sentinels `ErrAddressMissing`, `ErrCountryUnknown`, `ErrPhoneInvalid`; `RequestOtpDeps.ReadUserAddress func(ctx context.Context, uid string) (string, error)` (returns `("", nil)` when no address doc); `fakes.AddressReader` with fields `Countries map[string]string`, `Err error`, `ReadCalls []string` and method `Read`. Task 3 consumes all of these.

- [ ] **Step 1: Add the `AddressReader` fake**

Append to `functions/loans/test/fakes/fakes.go`:

```go
// AddressReader fake — returns Countries[uid] as the country on the user's
// address doc. A uid absent from Countries yields ("", nil), the "no
// address doc" signal that RequestOtpCore maps to ErrAddressMissing.
type AddressReader struct {
	Countries map[string]string
	Err       error
	ReadCalls []string
}

func (r *AddressReader) Read(_ context.Context, uid string) (string, error) {
	r.ReadCalls = append(r.ReadCalls, uid)
	if r.Err != nil {
		return "", r.Err
	}
	return r.Countries[uid], nil
}
```

- [ ] **Step 2: Extend `buildDeps` and write the failing tests**

In `functions/loans/test/api/users/request_otp_test.go`, change `buildDeps` to accept the new fake (new parameter after `user`):

```go
func buildDeps(
	now time.Time,
	hash, otp string,
	user *fakes.UserReader,
	address *fakes.AddressReader,
	authEmail *fakes.AuthEmailReader,
	otpWriter *fakes.OtpWriter,
	emailSender *fakes.EmailSender,
) (users.RequestOtpDeps, *int) {
	gen, calls := stubOtp(hash, otp)
	return users.RequestOtpDeps{
		GenerateOtp:      gen,
		ReadUser:         user.Read,
		ReadUserAddress:  address.Read,
		GetAuthUserEmail: authEmail.Read,
		WriteOtp:         otpWriter.Write,
		SendEmail:        emailSender.Send,
		Now:              func() time.Time { return now },
	}, calls
}
```

Update **every existing** `buildDeps(...)` call in this file: insert `&fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}` as the new 5th argument (after the `UserReader` argument). For tests whose stub user has a `mobile_number`, also check the fixture value: any mobile-objective test using a number that is not a valid PH number must switch its fixture to `"9175551291"` (expected entry phone becomes `"+639175551291"`).

Then append the new cases:

```go
func TestRequestOtpCore_Mobile_NormalizesPhoneToE164(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	userReader := &fakes.UserReader{Users: map[string]map[string]any{
		"user-123": {"mobile_number": "9175551291"},
	}}
	address := &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}
	otpWriter := &fakes.OtpWriter{}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, address, &fakes.AuthEmailReader{}, otpWriter, &fakes.EmailSender{})

	_, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID: "user-123", Objective: "mobile_number", Subdomain: "dev.",
	}, deps)
	if err != nil {
		t.Fatalf("RequestOtpCore returned error: %v", err)
	}
	if len(otpWriter.Writes) != 1 {
		t.Fatalf("expected 1 OTP write, got %d", len(otpWriter.Writes))
	}
	if got := otpWriter.Writes[0].Entry["phone"]; got != "+639175551291" {
		t.Errorf("expected normalized phone +639175551291, got %v", got)
	}
	if len(address.ReadCalls) != 1 || address.ReadCalls[0] != "user-123" {
		t.Errorf("expected address read for user-123, got %v", address.ReadCalls)
	}
}

func TestRequestOtpCore_Mobile_LegacyE164PassesThroughWithoutAddress(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	userReader := &fakes.UserReader{Users: map[string]map[string]any{
		"user-123": {"mobile_number": "+639175551291"},
	}}
	address := &fakes.AddressReader{} // no address doc at all
	otpWriter := &fakes.OtpWriter{}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, address, &fakes.AuthEmailReader{}, otpWriter, &fakes.EmailSender{})

	_, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID: "user-123", Objective: "mobile_number", Subdomain: "dev.",
	}, deps)
	if err != nil {
		t.Fatalf("expected legacy +63 number to pass through, got error: %v", err)
	}
	if got := otpWriter.Writes[0].Entry["phone"]; got != "+639175551291" {
		t.Errorf("expected phone +639175551291, got %v", got)
	}
}

func TestRequestOtpCore_Mobile_MissingAddress_ReturnsErrAddressMissing(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	userReader := &fakes.UserReader{Users: map[string]map[string]any{
		"user-123": {"mobile_number": "9175551291"},
	}}
	otpWriter := &fakes.OtpWriter{}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, &fakes.AddressReader{}, &fakes.AuthEmailReader{}, otpWriter, &fakes.EmailSender{})

	_, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID: "user-123", Objective: "mobile_number", Subdomain: "dev.",
	}, deps)
	if !errors.Is(err, users.ErrAddressMissing) {
		t.Fatalf("expected ErrAddressMissing, got %v", err)
	}
	if len(otpWriter.Writes) != 0 {
		t.Errorf("no OTP entry may be written on failure, got %d writes", len(otpWriter.Writes))
	}
}

func TestRequestOtpCore_Mobile_UnknownCountry_ReturnsErrCountryUnknown(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	userReader := &fakes.UserReader{Users: map[string]map[string]any{
		"user-123": {"mobile_number": "9175551291"},
	}}
	address := &fakes.AddressReader{Countries: map[string]string{"user-123": "Narnia"}}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, address, &fakes.AuthEmailReader{}, &fakes.OtpWriter{}, &fakes.EmailSender{})

	_, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID: "user-123", Objective: "mobile_number", Subdomain: "dev.",
	}, deps)
	if !errors.Is(err, users.ErrCountryUnknown) {
		t.Fatalf("expected ErrCountryUnknown, got %v", err)
	}
}

func TestRequestOtpCore_Mobile_InvalidNumber_ReturnsErrPhoneInvalid(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	userReader := &fakes.UserReader{Users: map[string]map[string]any{
		"user-123": {"mobile_number": "1234567890"},
	}}
	address := &fakes.AddressReader{Countries: map[string]string{"user-123": "Philippines"}}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, address, &fakes.AuthEmailReader{}, &fakes.OtpWriter{}, &fakes.EmailSender{})

	_, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID: "user-123", Objective: "mobile_number", Subdomain: "dev.",
	}, deps)
	if !errors.Is(err, users.ErrPhoneInvalid) {
		t.Fatalf("expected ErrPhoneInvalid, got %v", err)
	}
}

func TestRequestOtpCore_Mobile_AddressReadError_Propagates(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	userReader := &fakes.UserReader{Users: map[string]map[string]any{
		"user-123": {"mobile_number": "9175551291"},
	}}
	boom := errors.New("firestore unavailable")
	address := &fakes.AddressReader{Err: boom}
	deps, _ := buildDeps(now, "h-1", "111111", userReader, address, &fakes.AuthEmailReader{}, &fakes.OtpWriter{}, &fakes.EmailSender{})

	_, err := users.RequestOtpCore(context.Background(), users.RequestOtpParams{
		UserID: "user-123", Objective: "mobile_number", Subdomain: "dev.",
	}, deps)
	if !errors.Is(err, boom) {
		t.Fatalf("expected transport error to propagate, got %v", err)
	}
}
```

Also extend the existing email-objective test (`TestRequestOtpCore_EmailObjective_ReadsRecipientFromAuth`): after the `userReader.ReadCalls` assertion, assert the address fake was never consulted (declare its `AddressReader` in a variable to do so):

```go
	if len(addressReader.ReadCalls) != 0 {
		t.Errorf("expected ReadUserAddress to be skipped on email path, got %d calls", len(addressReader.ReadCalls))
	}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd functions/loans && CGO_ENABLED=0 go test ./test/api/users/...`
Expected: FAIL — `unknown field ReadUserAddress`, `undefined: users.ErrAddressMissing` (compile errors).

- [ ] **Step 4: Implement the Core changes**

In `functions/loans/api/users/request_otp.go`:

(a) Add `"strings"` to the imports.

(b) Extend the sentinel block:

```go
var (
	ErrInvalidObjective     = errors.New("invalid objective")
	ErrUserNotFound         = errors.New("user not found")
	ErrMobileNumberMissing  = errors.New("user has no mobile_number")
	ErrAuthUserMissingEmail = errors.New("auth user has no email")
	// Phone-normalization failures (spec 2026-07-24): the OTP request is
	// rejected rather than queueing an undeliverable SMS.
	ErrAddressMissing = errors.New("user has no address record")
	ErrCountryUnknown = errors.New("country not recognized")
	ErrPhoneInvalid   = errors.New("mobile_number not valid for country")
)
```

(c) Add to `RequestOtpDeps` (after `ReadUser`):

```go
	// ReadUserAddress returns the `country` value on the user's address
	// doc ({prefix}address where data_id == uid, data_type == 'user'),
	// or ("", nil) when the user has no (non-deleted) address doc.
	ReadUserAddress func(ctx context.Context, uid string) (string, error)
```

(d) In `RequestOtpCore`, inside the `if p.Objective == objectiveMobileNumber` block, replace

```go
		entry["phone"] = phone
```

with

```go
		country, err := deps.ReadUserAddress(ctx, targetUserID)
		if err != nil {
			return RequestOtpResult{}, err
		}
		normalized, err := service.NormalizePhoneE164(phone, country)
		if err != nil {
			switch {
			case errors.Is(err, service.ErrCountryUnknown):
				if strings.TrimSpace(country) == "" {
					return RequestOtpResult{}, fmt.Errorf("%w: user %s", ErrAddressMissing, targetUserID)
				}
				return RequestOtpResult{}, fmt.Errorf("%w: %q", ErrCountryUnknown, country)
			case errors.Is(err, service.ErrPhoneInvalid):
				return RequestOtpResult{}, fmt.Errorf("%w: %v", ErrPhoneInvalid, err)
			default:
				return RequestOtpResult{}, err
			}
		}
		entry["phone"] = normalized
```

(`service` is already imported as `"com.loooans.app/api/service"`.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd functions/loans && CGO_ENABLED=0 go test ./test/api/users/...`
Expected: PASS, including all pre-existing tests. If a pre-existing mobile-objective test fails on the phone assertion, fix its fixture per Step 2's note (valid PH number in, E.164 out).

- [ ] **Step 6: Commit**

```bash
cd functions/loans
git add api/users/request_otp.go test/fakes/fakes.go test/api/users/request_otp_test.go
git commit -m "feat(request-otp): normalize mobile_number to E.164 from address country

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: HTTP adapter mapping + real Firestore address read

**Files:**
- Modify: `functions/loans/api/users/request_otp.go` (adapter error switch ~line 261-274; `buildRealRequestOtpDeps` ~line 291-349)
- Modify: `functions/loans/test/api/users/request_otp_handler_test.go`

**Interfaces:**
- Consumes: sentinels and `ReadUserAddress` dep from Task 2.
- Produces: HTTP 400 bodies (must match verbatim — PR C's tests reuse the first string):
  - `Cannot determine the country for the user's mobile number. Please complete the user's address record.`
  - `The mobile number on record is not a valid phone number for the user's country.`

- [ ] **Step 1: Write the failing handler tests**

Append to `functions/loans/test/api/users/request_otp_handler_test.go`. First check `minimumValidDeps`: add `ReadUserAddress: func(context.Context, string) (string, error) { return "Philippines", nil }` to the deps it returns, and make sure its stub user's `mobile_number` fixture is `"9175551291"` (or another valid PH number).

```go
func TestRequestOtpHandler_AddressMissing_Returns400(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	deps := minimumValidDeps(now)
	deps.ReadUserAddress = func(context.Context, string) (string, error) { return "", nil }
	h := newHarness(t, "user-123", deps)

	rec := doRequest(t, h.handler, http.MethodPost, `{"purpose":"mobile_number"}`)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "complete the user's address record") {
		t.Errorf("unexpected body: %s", rec.Body.String())
	}
}

func TestRequestOtpHandler_UnknownCountry_Returns400(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	deps := minimumValidDeps(now)
	deps.ReadUserAddress = func(context.Context, string) (string, error) { return "Narnia", nil }
	h := newHarness(t, "user-123", deps)

	rec := doRequest(t, h.handler, http.MethodPost, `{"purpose":"mobile_number"}`)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "Cannot determine the country") {
		t.Errorf("unexpected body: %s", rec.Body.String())
	}
}

func TestRequestOtpHandler_InvalidPhone_Returns400(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	deps := minimumValidDeps(now)
	deps.ReadUser = func(context.Context, string) (map[string]any, error) {
		return map[string]any{"mobile_number": "1234567890"}, nil
	}
	h := newHarness(t, "user-123", deps)

	rec := doRequest(t, h.handler, http.MethodPost, `{"purpose":"mobile_number"}`)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "not a valid phone number") {
		t.Errorf("unexpected body: %s", rec.Body.String())
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd functions/loans && CGO_ENABLED=0 go test ./test/api/users/ -run TestRequestOtpHandler`
Expected: the three new tests FAIL with 500 (unmapped error falls to the default branch).

- [ ] **Step 3: Implement adapter mapping + real deps**

(a) In the `RequestOtpHandler` error switch, before the `default:` case:

```go
			case errors.Is(err, ErrAddressMissing), errors.Is(err, ErrCountryUnknown):
				http.Error(w, "Cannot determine the country for the user's mobile number. Please complete the user's address record.", http.StatusBadRequest)
			case errors.Is(err, ErrPhoneInvalid):
				http.Error(w, "The mobile number on record is not a valid phone number for the user's country.", http.StatusBadRequest)
```

(b) In `buildRealRequestOtpDeps`, add after the `ReadUser` field (mirrors the Flutter `getByDataType` query; `data_type` values come from the Dart `DataType` enum — `user` / `provider`):

```go
			ReadUserAddress: func(ctx context.Context, uid string) (string, error) {
				iter := firestoreClient.Collection(collectionPrefix+"address").
					Where("data_id", "==", uid).
					Where("data_type", "==", "user").
					Limit(1).
					Documents(ctx)
				defer iter.Stop()
				snap, err := iter.Next()
				if errors.Is(err, iterator.Done) {
					return "", nil
				}
				if err != nil {
					return "", err
				}
				data := snap.Data()
				if data["deleted_at"] != nil {
					return "", nil
				}
				country, _ := data["country"].(string)
				return country, nil
			},
```

Add `"google.golang.org/api/iterator"` to the imports of `request_otp.go`.

- [ ] **Step 4: Run the full backend suite**

Run: `cd functions/loans && go build -v ./... && CGO_ENABLED=0 go test ./...`
Expected: build OK, all tests PASS (known pre-existing failures per `finstack-testing-and-validation` excepted — none are in `api/`).

- [ ] **Step 5: Commit, push, open PR A**

```bash
cd functions/loans
git add api/users/request_otp.go test/api/users/request_otp_handler_test.go
git commit -m "feat(request-otp): 400 mapping for phone-normalization failures + Firestore address read

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git -c credential.helper='!gh auth git-credential' push https://github.com/anatechopc/finstack.git feature/otp-phone-normalization
gh pr create --base develop --head feature/otp-phone-normalization \
  --title "feat(request-otp): normalize OTP phone numbers to E.164 from address country" \
  --body "Implements docs/superpowers/specs/2026-07-24-otp-phone-normalization-design.md (backend part).

Root cause: forms store bare 10-digit national numbers; the gateway sent them verbatim to an unroutable destination and null sentIntent masked the failure as 'sent'.

- NormalizePhoneE164 (nyaruka/phonenumbers) keyed by the country on the user's address doc
- Rejects with 400 when country undeterminable or number invalid (spec decision)
- Legacy +63-stored numbers pass through unchanged

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

---

# PR B — Gateway honest delivery status (branch `feature/sms-gateway-delivery-status`)

- [ ] **Step 0: Create the branch**

```bash
git -c credential.helper='!gh auth git-credential' fetch https://github.com/anatechopc/finstack.git develop
git checkout -b feature/sms-gateway-delivery-status FETCH_HEAD
```

### Task 4: `OtpEntry` expiry awareness

**Files:**
- Modify: `apps/sms-gateway/app/src/main/java/com/loooans/smsgateway/OtpEntry.kt`
- Test: `apps/sms-gateway/app/src/test/java/com/loooans/smsgateway/OtpEntryTest.kt`

**Interfaces:**
- Produces: `OtpEntry.expireAt: Long?` (parsed from `expire_at`, int64 millis); `OtpEntry.isExpired(nowMillis: Long): Boolean`. Task 6 consumes both.

- [ ] **Step 1: Write the failing tests**

Append to `OtpEntryTest.kt`:

```kotlin
    // --- expiry tests ---

    @Test
    fun `fromMap parses expire_at as Long`() {
        val data = validOtpMap().toMutableMap().apply { put("expire_at", 1784877157691L) }
        val entry = OtpEntry.fromMap("abc123", data)
        assertEquals(1784877157691L, entry!!.expireAt)
    }

    @Test
    fun `fromMap tolerates missing expire_at`() {
        val entry = OtpEntry.fromMap("abc123", validOtpMap())
        assertNull(entry!!.expireAt)
    }

    @Test
    fun `isExpired is true past expire_at`() {
        val data = validOtpMap().toMutableMap().apply { put("expire_at", 1_000L) }
        val entry = OtpEntry.fromMap("abc123", data)!!
        assertTrue(entry.isExpired(nowMillis = 1_001L))
    }

    @Test
    fun `isExpired is false before expire_at`() {
        val data = validOtpMap().toMutableMap().apply { put("expire_at", 1_000L) }
        val entry = OtpEntry.fromMap("abc123", data)!!
        assertFalse(entry.isExpired(nowMillis = 999L))
    }

    @Test
    fun `isExpired is false when expire_at missing`() {
        val entry = OtpEntry.fromMap("abc123", validOtpMap())!!
        assertFalse(entry.isExpired(nowMillis = Long.MAX_VALUE))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/sms-gateway && ./gradlew testDebugUnitTest --tests '*OtpEntryTest*'`
Expected: FAIL — no `expireAt` property (compile error).

- [ ] **Step 3: Implement**

In `OtpEntry.kt`: add `val expireAt: Long?,` to the data class (after `smsStatus`); add to the class body:

```kotlin
    /**
     * True when the entry's expire_at (int64 millis, house convention) is in
     * the past. Entries with no expire_at never count as expired.
     */
    fun isExpired(nowMillis: Long): Boolean = expireAt != null && expireAt < nowMillis
```

In `fromMap`, parse it (RTDB numbers arrive as `Long`; `Number` guards `Int`/`Double` edge cases) and pass it through:

```kotlin
            val expireAt = (data["expire_at"] as? Number)?.toLong()
```

and `expireAt = expireAt,` in the constructor call.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/sms-gateway && ./gradlew testDebugUnitTest --tests '*OtpEntryTest*'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/sms-gateway/app/src/main/java/com/loooans/smsgateway/OtpEntry.kt apps/sms-gateway/app/src/test/java/com/loooans/smsgateway/OtpEntryTest.kt
git commit -m "feat(sms-gateway): parse expire_at and expose OtpEntry.isExpired

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: `SendResultTracker` — aggregate per-part send results

**Files:**
- Create: `apps/sms-gateway/app/src/main/java/com/loooans/smsgateway/SendResultTracker.kt`
- Test: `apps/sms-gateway/app/src/test/java/com/loooans/smsgateway/SendResultTrackerTest.kt`

**Interfaces:**
- Produces (Task 6 consumes): `SendResultTracker(totalParts: Int)`; `record(isOk: Boolean, errorName: String): Outcome?`; `timeout(): Outcome?`; sealed `Outcome` = `Sent` | `Failed(error: String)`; top-level `smsResultErrorName(code: Int): String`. Pure Kotlin — no Android framework imports (JVM-testable).

- [ ] **Step 1: Write the failing tests**

Create `SendResultTrackerTest.kt`:

```kotlin
package com.loooans.smsgateway

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SendResultTrackerTest {

    @Test
    fun `single part ok completes as Sent`() {
        val tracker = SendResultTracker(totalParts = 1)
        assertEquals(SendResultTracker.Outcome.Sent, tracker.record(isOk = true, errorName = ""))
    }

    @Test
    fun `single part failure completes as Failed with error name`() {
        val tracker = SendResultTracker(totalParts = 1)
        val outcome = tracker.record(isOk = false, errorName = "RESULT_ERROR_LIMIT_EXCEEDED (5)")
        assertEquals(SendResultTracker.Outcome.Failed("RESULT_ERROR_LIMIT_EXCEEDED (5)"), outcome)
    }

    @Test
    fun `multipart completes only after all parts ok`() {
        val tracker = SendResultTracker(totalParts = 3)
        assertNull(tracker.record(isOk = true, errorName = ""))
        assertNull(tracker.record(isOk = true, errorName = ""))
        assertEquals(SendResultTracker.Outcome.Sent, tracker.record(isOk = true, errorName = ""))
    }

    @Test
    fun `multipart fails immediately on first failed part`() {
        val tracker = SendResultTracker(totalParts = 3)
        assertNull(tracker.record(isOk = true, errorName = ""))
        val outcome = tracker.record(isOk = false, errorName = "RESULT_ERROR_NO_SERVICE (4)")
        assertEquals(SendResultTracker.Outcome.Failed("RESULT_ERROR_NO_SERVICE (4)"), outcome)
    }

    @Test
    fun `record after completion returns null`() {
        val tracker = SendResultTracker(totalParts = 1)
        tracker.record(isOk = false, errorName = "RESULT_ERROR_GENERIC_FAILURE (1)")
        assertNull(tracker.record(isOk = true, errorName = ""))
    }

    @Test
    fun `timeout before completion fails with timeout error`() {
        val tracker = SendResultTracker(totalParts = 2)
        tracker.record(isOk = true, errorName = "")
        assertEquals(
            SendResultTracker.Outcome.Failed("timeout waiting for send result"),
            tracker.timeout(),
        )
    }

    @Test
    fun `timeout after completion returns null`() {
        val tracker = SendResultTracker(totalParts = 1)
        tracker.record(isOk = true, errorName = "")
        assertNull(tracker.timeout())
    }

    @Test
    fun `known result codes map to names`() {
        assertEquals("RESULT_ERROR_GENERIC_FAILURE (1)", smsResultErrorName(1))
        assertEquals("RESULT_ERROR_RADIO_OFF (2)", smsResultErrorName(2))
        assertEquals("RESULT_ERROR_NULL_PDU (3)", smsResultErrorName(3))
        assertEquals("RESULT_ERROR_NO_SERVICE (4)", smsResultErrorName(4))
        assertEquals("RESULT_ERROR_LIMIT_EXCEEDED (5)", smsResultErrorName(5))
        assertEquals("RESULT_ERROR (99)", smsResultErrorName(99))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/sms-gateway && ./gradlew testDebugUnitTest --tests '*SendResultTrackerTest*'`
Expected: FAIL — unresolved reference `SendResultTracker` (compile error).

- [ ] **Step 3: Implement**

Create `SendResultTracker.kt`:

```kotlin
package com.loooans.smsgateway

/**
 * Aggregates per-part SMS sentIntent results into one terminal outcome.
 * Completes exactly once: Sent when all parts report OK, Failed on the
 * first error or on timeout. Pure Kotlin so it stays JVM-unit-testable —
 * callers translate Android result codes via [smsResultErrorName].
 */
class SendResultTracker(private val totalParts: Int) {

    sealed interface Outcome {
        data object Sent : Outcome
        data class Failed(val error: String) : Outcome
    }

    private var okCount = 0
    private var completed = false

    /** Records one part's result; returns the terminal outcome exactly once. */
    @Synchronized
    fun record(isOk: Boolean, errorName: String): Outcome? {
        if (completed) return null
        if (!isOk) {
            completed = true
            return Outcome.Failed(errorName)
        }
        okCount++
        if (okCount == totalParts) {
            completed = true
            return Outcome.Sent
        }
        return null
    }

    /** Marks the send failed if no terminal outcome arrived in time. */
    @Synchronized
    fun timeout(): Outcome? {
        if (completed) return null
        completed = true
        return Outcome.Failed("timeout waiting for send result")
    }
}

/**
 * Maps SmsManager sentIntent result codes to readable names. Values mirror
 * android.telephony.SmsManager.RESULT_ERROR_* — duplicated as plain ints so
 * this file needs no Android framework import.
 */
fun smsResultErrorName(code: Int): String = when (code) {
    1 -> "RESULT_ERROR_GENERIC_FAILURE (1)"
    2 -> "RESULT_ERROR_RADIO_OFF (2)"
    3 -> "RESULT_ERROR_NULL_PDU (3)"
    4 -> "RESULT_ERROR_NO_SERVICE (4)"
    5 -> "RESULT_ERROR_LIMIT_EXCEEDED (5)"
    else -> "RESULT_ERROR ($code)"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/sms-gateway && ./gradlew testDebugUnitTest --tests '*SendResultTrackerTest*'`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/sms-gateway/app/src/main/java/com/loooans/smsgateway/SendResultTracker.kt apps/sms-gateway/app/src/test/java/com/loooans/smsgateway/SendResultTrackerTest.kt
git commit -m "feat(sms-gateway): add SendResultTracker for per-part send outcomes

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Wire `sentIntent` results + expiry skip into the service

**Files:**
- Modify: `apps/sms-gateway/app/src/main/java/com/loooans/smsgateway/SmsGatewayService.kt`

**Interfaces:**
- Consumes: `OtpEntry.isExpired` (Task 4); `SendResultTracker`, `smsResultErrorName` (Task 5).
- Behavior contract (spec): `sms_status` becomes `sent` only on RESULT_OK for **all** parts; otherwise `failed` + concrete error; expired entries are skipped untouched; 60s watchdog prevents stuck `pending`.

This is Android-framework wiring — no JVM unit test; verification is compile + the manual device pass in Step 4.

- [ ] **Step 1: Implement the service changes**

In `SmsGatewayService.kt`:

(a) New imports: `android.app.Activity`, `android.app.PendingIntent`, `android.content.BroadcastReceiver`, `android.content.Context`, `android.content.IntentFilter`, `android.net.Uri`, `androidx.core.content.ContextCompat`, `java.util.concurrent.ConcurrentHashMap`.

(b) Companion additions:

```kotlin
        private const val ACTION_SMS_SENT = "com.loooans.smsgateway.SMS_SENT"
        private const val EXTRA_HASH = "hash"
        private const val SEND_RESULT_TIMEOUT_MS = 60_000L
```

(c) New field + receiver:

```kotlin
    private val trackers = ConcurrentHashMap<String, SendResultTracker>()

    private val smsSentReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val hash = intent.getStringExtra(EXTRA_HASH) ?: return
            val tracker = trackers[hash] ?: return
            val isOk = resultCode == Activity.RESULT_OK
            when (val outcome = tracker.record(isOk, smsResultErrorName(resultCode))) {
                is SendResultTracker.Outcome.Sent -> {
                    trackers.remove(hash)
                    markSent(hash)
                }
                is SendResultTracker.Outcome.Failed -> {
                    trackers.remove(hash)
                    markFailed(hash, outcome.error)
                }
                null -> Unit // waiting for remaining parts, or already completed
            }
        }
    }
```

(d) Register in `onCreate` (after `startForeground`), unregister in `onDestroy`:

```kotlin
        ContextCompat.registerReceiver(
            this,
            smsSentReceiver,
            IntentFilter(ACTION_SMS_SENT),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
```

```kotlin
        unregisterReceiver(smsSentReceiver)
```

(e) `handleOtpEntry` passes the whole entry: `serviceScope.launch { sendSms(entry) }`.

(f) Replace `sendSms` with:

```kotlin
    private fun sendSms(entry: OtpEntry) {
        val hash = entry.hash
        if (entry.isExpired(System.currentTimeMillis())) {
            Log.i(TAG, "Skipping expired OTP entry $hash")
            return
        }
        try {
            val smsManager = getSystemService(SmsManager::class.java)
            val parts = smsManager.divideMessage(entry.message)
            val tracker = SendResultTracker(parts.size)
            trackers[hash] = tracker

            // One PendingIntent per part. The data Uri makes each intent
            // unique (extras alone don't distinguish PendingIntents).
            val sentIntents = ArrayList<PendingIntent>(parts.size)
            for (i in 0 until parts.size) {
                val intent = Intent(ACTION_SMS_SENT)
                    .setPackage(packageName)
                    .setData(Uri.parse("loooans-sms://$hash/$i"))
                    .putExtra(EXTRA_HASH, hash)
                sentIntents.add(
                    PendingIntent.getBroadcast(
                        this, 0, intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    ),
                )
            }

            if (parts.size > 1) {
                smsManager.sendMultipartTextMessage(entry.phone, null, parts, sentIntents, null)
            } else {
                smsManager.sendTextMessage(entry.phone, null, entry.message, sentIntents[0], null)
            }
            Log.i(TAG, "SMS handed to radio for $hash (${parts.size} part(s)), awaiting result")

            serviceScope.launch {
                delay(SEND_RESULT_TIMEOUT_MS)
                tracker.timeout()?.let { outcome ->
                    trackers.remove(hash)
                    markFailed(hash, (outcome as SendResultTracker.Outcome.Failed).error)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send SMS for $hash", e)
            trackers.remove(hash)
            markFailed(hash, e.message ?: e.javaClass.simpleName)
        }
    }

    private fun markSent(hash: String) {
        val updates = mapOf<String, Any?>(
            "sms_status" to "sent",
            "sent_at" to ServerValue.TIMESTAMP,
            "error" to null,
        )
        FirebaseConfig.database.reference
            .child("otp").child(hash)
            .updateChildren(updates)
            .addOnFailureListener { e -> Log.e(TAG, "Failed to update sms_status", e) }

        smsCount++
        updateNotification("Online - Sent $smsCount SMS(s)")
        broadcastStatus("online")
        Log.i(TAG, "SMS confirmed sent for hash $hash")
    }

    private fun markFailed(hash: String, error: String) {
        val updates = mapOf<String, Any?>(
            "sms_status" to "failed",
            "error" to error,
        )
        FirebaseConfig.database.reference
            .child("otp").child(hash)
            .updateChildren(updates)
            .addOnFailureListener { e -> Log.e(TAG, "Failed to update sms_status", e) }
        Log.w(TAG, "SMS failed for hash $hash: $error")
    }
```

Note: `lastSmsSentTo` — set `lastSmsSentTo = entry.phone` right after the send call in `sendSms` (it feeds the status broadcast only). `sendSms` is no longer `suspend` (nothing suspends in it); if the compiler flags the `serviceScope.launch` wrapper in `handleOtpEntry`, keep the wrapper — RTDB callbacks should stay off the main thread.

- [ ] **Step 2: Compile + run all gateway unit tests**

Run: `cd apps/sms-gateway && ./gradlew assembleDebug testDebugUnitTest`
Expected: BUILD SUCCESSFUL, all tests pass. (If `androidx.core` is unresolved, add `implementation("androidx.core:core-ktx:1.15.0")` to `app/build.gradle.kts` dependencies.)

- [ ] **Step 3: Commit, push, open PR B**

```bash
git add apps/sms-gateway/app/src/main/java/com/loooans/smsgateway/SmsGatewayService.kt apps/sms-gateway/app/build.gradle.kts
git commit -m "feat(sms-gateway): honest delivery status via sentIntent + skip expired entries

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git -c credential.helper='!gh auth git-credential' push https://github.com/anatechopc/finstack.git feature/sms-gateway-delivery-status
gh pr create --base develop --head feature/sms-gateway-delivery-status \
  --title "feat(sms-gateway): report real SMS send outcomes" \
  --body "Implements the gateway part of docs/superpowers/specs/2026-07-24-otp-phone-normalization-design.md.

- sentIntent PendingIntents per part; sent only when every part reports RESULT_OK
- failed + concrete result code (LIMIT_EXCEEDED, NO_SERVICE, ...) otherwise; 60s watchdog prevents stuck pending
- Expired entries are skipped (kills the replay-expired-OTPs-after-offline burst)

Manual device install required after merge (CI builds/tests only).

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 4: Manual device verification (after merge, on the gateway phone)**

1. `./gradlew assembleDebug`, `adb install -r app/build/outputs/apk/debug/app-debug.apk`, open the app, start the service.
2. Request a mobile OTP from the dev app to a real number → RTDB entry flips `pending` → `sent` only after the radio confirms; SMS arrives.
3. Temporarily enable airplane mode, request another OTP → entry becomes `failed` with `error: "RESULT_ERROR_RADIO_OFF (2)"` (or `NO_SERVICE`).
4. `adb logcat -s SmsGatewayService` shows "awaiting result" then "confirmed sent"/"failed".

---

# PR C — Flutter error surfacing (branch `feature/otp-error-surfacing`)

- [ ] **Step 0: Create the branch**

```bash
git -c credential.helper='!gh auth git-credential' fetch https://github.com/anatechopc/finstack.git develop
git checkout -b feature/otp-error-surfacing FETCH_HEAD
```

### Task 7: `RequestOtpException` in `user_repository`

**Files:**
- Modify: `packages/core/user_repository/lib/src/data/network/user_network_service.dart` (new exception class next to `SetPasswordException`; the two `throw HttpException` sites in `requestOtp` / `requestOtpForUser`)
- Modify: `packages/core/user_repository/lib/user_repository.dart` (export)
- Test: `packages/core/user_repository/test/request_otp_exception_test.dart`

**Interfaces:**
- Produces (Task 8 consumes): `RequestOtpException(statusCode, body)` with `String get userMessage` — the trimmed server body for non-empty 4xx, else `'Cannot request OTP'`. Exported from `package:user_repository/user_repository.dart`.

- [ ] **Step 1: Write the failing test**

Create `packages/core/user_repository/test/request_otp_exception_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:user_repository/user_repository.dart';

void main() {
  group('RequestOtpException.userMessage', () {
    test('returns the server body verbatim (trimmed) for a 400', () {
      final e = RequestOtpException(
        400,
        "Cannot determine the country for the user's mobile number. "
        "Please complete the user's address record.\n",
      );
      expect(
        e.userMessage,
        "Cannot determine the country for the user's mobile number. "
        "Please complete the user's address record.",
      );
    });

    test('falls back to a generic message for a 500', () {
      expect(
        RequestOtpException(500, 'internal error details').userMessage,
        'Cannot request OTP',
      );
    });

    test('falls back to a generic message for an empty 4xx body', () {
      expect(RequestOtpException(400, '   ').userMessage, 'Cannot request OTP');
    });

    test('toString carries status and body for logs', () {
      expect(
        RequestOtpException(400, 'nope').toString(),
        'RequestOtpException(400): nope',
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/core/user_repository && fvm flutter test test/request_otp_exception_test.dart`
Expected: FAIL — `RequestOtpException` isn't defined.

- [ ] **Step 3: Implement**

(a) In `user_network_service.dart`, directly below `SetPasswordException`:

```dart
/// Thrown by [UserNetworkService.requestOtp] and [requestOtpForUser] for a
/// non-2xx response, carrying the HTTP [statusCode] and raw [body] so blocs
/// can show the server's 4xx reason verbatim (e.g. the phone-normalization
/// rejections) instead of a generic failure.
class RequestOtpException implements Exception {
  RequestOtpException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  /// 4xx bodies are short actionable sentences written for end users;
  /// anything else collapses to a generic message.
  String get userMessage {
    final trimmed = body.trim();
    if (statusCode >= 400 && statusCode < 500 && trimmed.isNotEmpty) {
      return trimmed;
    }
    return 'Cannot request OTP';
  }

  @override
  String toString() => 'RequestOtpException($statusCode): $body';
}
```

(b) In `requestOtp`, replace the `throw HttpException('Request OTP error: ...')` with:

```dart
      throw RequestOtpException(response.statusCode, response.body);
```

and identically in `requestOtpForUser` (replace its `throw HttpException(...)`).

(c) In `lib/user_repository.dart`, extend the existing show-export:

```dart
export 'src/data/network/user_network_service.dart'
    show RequestOtpException, SetPasswordException;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/core/user_repository && fvm flutter test`
Expected: new test PASSES; pre-existing package tests unchanged.

- [ ] **Step 5: Commit**

```bash
git add packages/core/user_repository/lib/src/data/network/user_network_service.dart packages/core/user_repository/lib/user_repository.dart packages/core/user_repository/test/request_otp_exception_test.dart
git commit -m "feat(user-repository): typed RequestOtpException carrying the server 4xx message

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Surface the message in both OTP blocs

**Files:**
- Modify: `apps/loans/lib/features/authentication/bloc/authentication_bloc.dart` (`_handleRequestOtpEvent` catch, ~line 228-232)
- Modify: `apps/loans/lib/features/loans/bloc/payment_bloc.dart` (`_handleRequestPaymentOtpEvent` catch, ~line 306-310)
- Test: `apps/loans/test/features/authentication/authentication_bloc_request_otp_test.dart`

**Interfaces:**
- Consumes: `RequestOtpException.userMessage` (Task 7). Display needs no changes: `MobileVerificationScreen` already SnackBars `state.message`, and the payment dialog renders `PaymentState.error`'s message.

- [ ] **Step 1: Write the failing bloc test**

Create `apps/loans/test/features/authentication/authentication_bloc_request_otp_test.dart` (harness copied from `authentication_bloc_forgot_password_test.dart`):

```dart
import 'package:authentication_repository/authentication_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/authentication/bloc/authentication_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:user_repository/user_repository.dart';

class _MockAuthRepo extends Mock implements AuthenticationRepository {}

class _MockUserRepo extends Mock implements UserRepository {}

class _MockAuthService extends Mock implements AuthenticationService {}

void main() {
  late _MockAuthRepo authRepo;
  late _MockUserRepo users;
  late _MockAuthService auth;

  setUp(() {
    authRepo = _MockAuthRepo();
    users = _MockUserRepo();
    auth = _MockAuthService();
    when(() => auth.idToken).thenReturn('id-token');
  });

  AuthenticationBloc build() => AuthenticationBloc.withDependencies(
        authenticationRepository: authRepo,
        userRepository: users,
        authService: auth,
      );

  blocTest<AuthenticationBloc, AuthenticationState>(
    'requestOtp → surfaces the server 400 reason verbatim',
    setUp: () {
      when(
        () => users.requestOtp(
          idToken: any(named: 'idToken'),
          purpose: any(named: 'purpose'),
        ),
      ).thenThrow(
        RequestOtpException(
          400,
          "Cannot determine the country for the user's mobile number. "
          "Please complete the user's address record.",
        ),
      );
    },
    build: build,
    act: (b) => b.requestOtp(purpose: 'mobile_number'),
    expect: () => [
      isA<AuthenticationState>()
          .having((s) => s.isLoading, 'isLoading', true),
      isA<AuthenticationState>()
          .having((s) => s.isLoading, 'isLoading', false),
      isA<AuthenticationState>()
          .having((s) => s.status, 'status', AuthenticationStateStatus.error)
          .having(
            (s) => s.message,
            'message',
            "Cannot determine the country for the user's mobile number. "
            "Please complete the user's address record.",
          ),
    ],
  );

  blocTest<AuthenticationBloc, AuthenticationState>(
    'requestOtp → keeps the generic message for unexpected errors',
    setUp: () {
      when(
        () => users.requestOtp(
          idToken: any(named: 'idToken'),
          purpose: any(named: 'purpose'),
        ),
      ).thenThrow(Exception('socket closed'));
    },
    build: build,
    act: (b) => b.requestOtp(purpose: 'mobile_number'),
    expect: () => [
      isA<AuthenticationState>()
          .having((s) => s.isLoading, 'isLoading', true),
      isA<AuthenticationState>()
          .having((s) => s.isLoading, 'isLoading', false),
      isA<AuthenticationState>()
          .having((s) => s.status, 'status', AuthenticationStateStatus.error)
          .having((s) => s.message, 'message', 'Cannot request OTP'),
    ],
  );
}
```

Adaptation notes for the implementer: (1) if the bloc exposes no `requestOtp(purpose:)` method, use whatever the verify screen calls (per `authentication_bloc.dart:90-91`) — likely `b.add(RequestOtpEvent(purpose: 'mobile_number'))`; (2) match the exact loading-state emission pattern from the forgot-password test if the expect list above misfires (the bloc emits `loading(true)` … `loading(false)` around the error, same as forgot-password).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/loans && fvm flutter test test/features/authentication/authentication_bloc_request_otp_test.dart`
Expected: first case FAILS — message is the generic `'Cannot request OTP'` (bloc swallows the exception).

- [ ] **Step 3: Implement both bloc changes**

(a) `authentication_bloc.dart`, `_handleRequestOtpEvent` — replace the single `catch (err)` block with:

```dart
    } on RequestOtpException catch (err) {
      log.severe('Request OTP rejected: $err', err);
      emit(const AuthenticationState.loading());
      emit(AuthenticationState.error(message: err.userMessage));
    } catch (err) {
      log.severe('Something went wrong: $err', err);
      emit(const AuthenticationState.loading());
      emit(const AuthenticationState.error(message: 'Cannot request OTP'));
    }
```

(`user_repository` is already imported by this file.)

(b) `payment_bloc.dart`, `_handleRequestPaymentOtpEvent` — replace its `catch (err)` block with:

```dart
    } on RequestOtpException catch (err) {
      _log.severe('Request payment OTP rejected: $err', err);
      emit(const PaymentState.loading());
      emit(PaymentState.error(err.userMessage));
    } catch (err) {
      _log.severe('Request payment OTP error: $err', err);
      emit(const PaymentState.loading());
      emit(const PaymentState.error('Failed to send OTP'));
    }
```

- [ ] **Step 4: Run tests and analyzer**

Run: `cd apps/loans && fvm flutter test test/features/authentication/ && fvm flutter analyze`
Expected: both new cases PASS, analyzer clean (no new warnings).

- [ ] **Step 5: Commit, push, open PR C**

```bash
git add apps/loans/lib/features/authentication/bloc/authentication_bloc.dart apps/loans/lib/features/loans/bloc/payment_bloc.dart apps/loans/test/features/authentication/authentication_bloc_request_otp_test.dart
git commit -m "feat(otp): surface server-side OTP rejection reasons in auth and payment blocs

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git -c credential.helper='!gh auth git-credential' push https://github.com/anatechopc/finstack.git feature/otp-error-surfacing
gh pr create --base develop --head feature/otp-error-surfacing \
  --title "feat(otp): surface requestOtp 400 reasons to the user" \
  --body "Flutter part of docs/superpowers/specs/2026-07-24-otp-phone-normalization-design.md. Typed RequestOtpException in user_repository; auth + payment blocs show the server's 4xx text (address-missing / unknown-country / invalid-number rejections from the backend PR) instead of a generic failure.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

---

## Post-merge checklist (manual, outside the PRs)

- [ ] PR A merged → functions auto-deploy to dev; re-test the failing user from 2026-07-24 (`9175…91`): request OTP → RTDB entry shows `phone: "+639175…91"` → SMS arrives.
- [ ] PR B merged → build + `adb install` on the gateway phone (SM-S908E), run the Task 6 Step 4 device pass.
- [ ] Update `MEMORY.md` (root) + `functions/loans/MEMORY.md` per house rule.
- [ ] File follow-up issue: country dropdown for address forms (free-text `country` can 400 OTP requests under the strict policy).
- [ ] Optional ops cleanup: delete the two dead `/gateway_status` entries (Pixel 10, PJE110).
