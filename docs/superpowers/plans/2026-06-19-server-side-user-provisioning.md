# Server-Side User Provisioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace client-side, session-replacing user creation with a server-owned, atomic path: an admin adds a staff member or borrower → the Go backend mints the Firebase Auth account (uid), writes `users/{uid}` + address atomically, and emails a "set your password" invite; everyone added can log in.

**Architecture:** Two new Go HTTP Cloud Functions (`addUser`, `sendPasswordSetupLink`) follow the adapter+core pattern. The server owns the auth mint + Firestore write (authorized, atomic via compensating delete); the Flutter client owns serialization (assembles entity JSON, uploads photos) so the Go side never re-models the `User` schema — it strongly-types only logic-critical fields and writes the rest through as a map. Delivered as three sequenced PRs: A (backend) → B (hosting rewrites) → C (frontend).

**Tech Stack:** Go 1.22 (Cloud Functions gen2, Firebase Admin SDK, Firestore), Flutter/Dart (flutter_bloc, mocktail), Firebase Hosting rewrites.

**Spec:** `docs/superpowers/specs/2026-06-19-server-side-user-provisioning-design.md`

**Verified facts (do not re-derive):**
- User entity JSON keys: `id`, `first_name`, `last_name`, `email_address`, `user_role`, `company_id`, dates as int64 millis.
- `UserRole` serialized strings: `appAdmin`, `customer`, `admin`, `loanOfficer`, `teller`, `reviewModerator`.
- `CompanyManagementType` serialized strings: `app`, `selfManaged`; stored under `management_type` in the company doc.
- Address entity keys: `data_id`, `data_type` (top-level `address` collection, auto-id).
- Flutter `_parseDateTime` accepts any `num` (`constants.dart:39`), so Go `float64` millis round-trip correctly.
- Auth helper: `utils.ValidateRequestV2(w, r) string` returns the verified caller uid (writes the HTTP error itself on failure, returns `""`).
- Collection prefix: `utils.GetCollectionPrefix()` → `dev_`/`stg_`/`""`.
- Firebase init: `utils.InitializeFirebase(ctx)` → `app`; `app.Auth(ctx)`, `app.Firestore(ctx)`.
- Firestore write convention (`triggers/notification_helpers.go:50-62`): `Collection(prefix+name).Add(ctx, doc)` or `.Doc(id).Set(...)`, then stamp `id`.
- An existing `userCreated` trigger (`triggers/user_created.go`) sends a generic "Verify your account" email on **every** `users/{uid}` creation. Admin-created users would get that **plus** our invite, so we suppress it for admin-created docs (Task A8).
- Each `functions/loans` subdir is its own Go module; run `go mod tidy` in the subdir after adding deps. Tests run with `CGO_ENABLED=0 go test ./...` (macOS dyld gotcha).

---

# PHASE A — Backend (Go Cloud Functions)

> **Branch:** create `feat/user-provisioning-backend` off `develop`. All Phase A work lands here → PR A → deploy to dev (creates the `adduser-development` + `sendpasswordsetuplink-development` Cloud Run services).

## Task A1: Random password helper

**Files:**
- Create: `functions/loans/utils/generate_password.go`
- Test: `functions/loans/test/utils/generate_password_test.go`

- [ ] **Step 1: Write the failing test**

Create `functions/loans/test/utils/generate_password_test.go`:
```go
package utils_test

import (
	"testing"

	"com.loooans.app/utils"
)

func TestGenerateRandomPassword_LengthAndVariation(t *testing.T) {
	a := utils.GenerateRandomPassword()
	b := utils.GenerateRandomPassword()

	if len(a) != 24 {
		t.Fatalf("expected length 24, got %d (%q)", len(a), a)
	}
	if a == b {
		t.Fatalf("expected two random passwords to differ, both were %q", a)
	}
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `cd functions/loans && CGO_ENABLED=0 go test ./test/utils/...`
Expected: FAIL — `undefined: utils.GenerateRandomPassword`.

- [ ] **Step 3: Implement the helper**

Create `functions/loans/utils/generate_password.go`:
```go
package utils

import (
	"crypto/rand"
	"math/big"
)

const passwordChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#%^*?!"

// GenerateRandomPassword returns a cryptographically-random 24-character
// password. It is only ever used as the throwaway initial password for an
// admin-provisioned account; the user immediately replaces it via the
// password-reset invite link, so it is never shown to anyone.
func GenerateRandomPassword() string {
	const length = 24
	max := big.NewInt(int64(len(passwordChars)))
	b := make([]byte, length)
	for i := range b {
		n, err := rand.Int(rand.Reader, max)
		if err != nil {
			// crypto/rand failure is effectively impossible; index 0 keeps the
			// function total. The account is reset via the invite link anyway.
			b[i] = passwordChars[0]
			continue
		}
		b[i] = passwordChars[n.Int64()]
	}
	return string(b)
}
```

- [ ] **Step 4: Run the test and make sure it passes**

Run: `cd functions/loans && CGO_ENABLED=0 go test ./test/utils/...`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add functions/loans/utils/generate_password.go functions/loans/test/utils/generate_password_test.go
git commit -m "feat(functions): add GenerateRandomPassword helper"
```

## Task A2: AddUser core + fakes

**Files:**
- Create: `functions/loans/api/users/add_user_core.go`
- Modify: `functions/loans/test/fakes/fakes.go` (append new fakes)
- Test: `functions/loans/test/users/add_user_core_test.go`

- [ ] **Step 1: Add the fakes**

Append to `functions/loans/test/fakes/fakes.go` (keeps the existing decoupled style — these record calls and return configurable errors; tests set `CreateErr` to the caller package's sentinel when needed):
```go
// AuthCreate records one auth-account creation request.
type AuthCreate struct {
	Email       string
	Password    string
	DisplayName string
}

// AuthAccountManager fake — records created/deleted auth accounts. Create
// returns NextUID (default "new-uid") unless CreateErr is set; tests set
// CreateErr to the core's email-exists sentinel to exercise the 409 path.
// Delete records the uid and returns DeleteErr.
type AuthAccountManager struct {
	Created   []AuthCreate
	Deleted   []string
	NextUID   string
	CreateErr error
	DeleteErr error
}

func (m *AuthAccountManager) Create(_ context.Context, email, password, displayName string) (string, error) {
	m.Created = append(m.Created, AuthCreate{Email: email, Password: password, DisplayName: displayName})
	if m.CreateErr != nil {
		return "", m.CreateErr
	}
	uid := m.NextUID
	if uid == "" {
		uid = "new-uid"
	}
	return uid, nil
}

func (m *AuthAccountManager) Delete(_ context.Context, uid string) error {
	m.Deleted = append(m.Deleted, uid)
	return m.DeleteErr
}

// UserAddressWrite records one atomic user+address write.
type UserAddressWrite struct {
	UID     string
	User    map[string]any
	Address map[string]any
}

// UserAddressWriter fake — records every write. Err is returned to exercise the
// compensating-delete path.
type UserAddressWriter struct {
	Writes []UserAddressWrite
	Err    error
}

func (w *UserAddressWriter) Write(_ context.Context, uid string, user, address map[string]any) error {
	w.Writes = append(w.Writes, UserAddressWrite{UID: uid, User: user, Address: address})
	return w.Err
}

// CompanyManagementReader fake — maps companyId -> management_type
// ("app"/"selfManaged"). Unknown company resolves to "". Records read calls.
type CompanyManagementReader struct {
	Types     map[string]string
	Err       error
	ReadCalls []string
}

func (r *CompanyManagementReader) Read(_ context.Context, companyId string) (string, error) {
	r.ReadCalls = append(r.ReadCalls, companyId)
	if r.Err != nil {
		return "", r.Err
	}
	return r.Types[companyId], nil
}

// InviteCall records one invite send.
type InviteCall struct {
	Email       string
	DisplayName string
}

// Inviter fake — records every invite. Err is returned to exercise the
// best-effort path (invite failure must not fail the request).
type Inviter struct {
	Invites []InviteCall
	Err     error
}

func (i *Inviter) Send(_ context.Context, email, displayName string) error {
	i.Invites = append(i.Invites, InviteCall{Email: email, DisplayName: displayName})
	return i.Err
}
```

- [ ] **Step 2: Write the failing core tests**

Create `functions/loans/test/users/add_user_core_test.go`:
```go
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd functions/loans && CGO_ENABLED=0 go test ./test/users/...`
Expected: FAIL — `undefined: users.HandleAddUserCore` (and the sentinels).

- [ ] **Step 4: Implement the core**

Create `functions/loans/api/users/add_user_core.go`:
```go
package users

import (
	"context"
	"errors"
	"fmt"
	"strings"
)

// Sentinel errors returned by HandleAddUserCore. The HTTP adapter maps these to
// status codes; any other (transport) error maps to 500.
var (
	ErrInvalidRole    = errors.New("invalid or unsupported role")
	ErrMissingEmail   = errors.New("user payload missing email_address")
	ErrCallerNotFound = errors.New("caller user record not found")
	ErrCallerNotAdmin = errors.New("caller is not authorized to add users")
	ErrRoleNotAllowed = errors.New("role not allowed for this company")
	ErrEmailExists    = errors.New("a user with this email already exists")
)

// staffRoles are the company-management roles an admin may assign to a new team
// member (mirrors UserRole.companyManagedRoles in the Flutter app).
var staffRoles = map[string]bool{
	"admin":           true,
	"loanOfficer":     true,
	"teller":          true,
	"reviewModerator": true,
}

// AddUserDeps are the collaborators the core needs, so the business logic is
// unit-testable without Firebase. The real implementations are wired in the
// HTTP adapter (add_user.go).
type AddUserDeps struct {
	GetUser                  func(ctx context.Context, uid string) (map[string]any, error)
	GetCompanyManagementType func(ctx context.Context, companyId string) (string, error)
	// CreateAuthUser returns the new uid, or ErrEmailExists if the email is
	// already registered. The adapter maps the Admin SDK's
	// auth.IsEmailAlreadyExists onto ErrEmailExists.
	CreateAuthUser      func(ctx context.Context, email, password, displayName string) (string, error)
	DeleteAuthUser      func(ctx context.Context, uid string) error
	WriteUserAndAddress func(ctx context.Context, uid string, user, address map[string]any) error
	SendInvite          func(ctx context.Context, email, displayName string) error
	GeneratePassword    func() string
}

// AddUserResult is returned to the adapter to render the HTTP response.
type AddUserResult struct {
	UID        string
	InviteSent bool
}

// HandleAddUserCore authorizes an admin-initiated user creation, mints the
// Firebase Auth account, atomically writes users/{uid} + address, and sends a
// best-effort set-password invite. company_id and user_role are made
// server-authoritative (the client cannot add to another company or escalate).
func HandleAddUserCore(
	ctx context.Context,
	callerUid string,
	role string,
	user map[string]any,
	address map[string]any,
	deps AddUserDeps,
) (AddUserResult, error) {
	if role != "customer" && !staffRoles[role] {
		return AddUserResult{}, ErrInvalidRole
	}

	email, _ := user["email_address"].(string)
	email = strings.TrimSpace(email)
	if email == "" {
		return AddUserResult{}, ErrMissingEmail
	}

	caller, err := deps.GetUser(ctx, callerUid)
	if err != nil {
		return AddUserResult{}, fmt.Errorf("read caller %q: %w", callerUid, err)
	}
	if caller == nil {
		return AddUserResult{}, ErrCallerNotFound
	}
	callerRole, _ := caller["user_role"].(string)
	if callerRole != "admin" && callerRole != "appAdmin" {
		return AddUserResult{}, ErrCallerNotAdmin
	}
	companyId, _ := caller["company_id"].(string)

	mgmtType, err := deps.GetCompanyManagementType(ctx, companyId)
	if err != nil {
		return AddUserResult{}, fmt.Errorf("read company %q: %w", companyId, err)
	}
	if role == "customer" && mgmtType != "selfManaged" {
		return AddUserResult{}, ErrRoleNotAllowed
	}

	displayName := composeDisplayName(user)
	uid, err := deps.CreateAuthUser(ctx, email, deps.GeneratePassword(), displayName)
	if err != nil {
		if errors.Is(err, ErrEmailExists) {
			return AddUserResult{}, ErrEmailExists
		}
		return AddUserResult{}, fmt.Errorf("create auth user: %w", err)
	}

	// Server-authoritative fields. invited_by_admin lets the userCreated trigger
	// skip its generic welcome email so admin-provisioned users receive only the
	// set-password invite.
	user["id"] = uid
	user["company_id"] = companyId
	user["user_role"] = role
	user["invited_by_admin"] = true
	// Fix the embedded employment backref to the real uid (the client built it
	// before a uid existed).
	if emp, ok := user["employment_details"].(map[string]any); ok {
		emp["user_id"] = uid
	}
	if address != nil {
		address["data_id"] = uid
	}

	if err := deps.WriteUserAndAddress(ctx, uid, user, address); err != nil {
		if delErr := deps.DeleteAuthUser(ctx, uid); delErr != nil {
			return AddUserResult{}, fmt.Errorf("write failed (%v) and auth rollback failed: %w", err, delErr)
		}
		return AddUserResult{}, fmt.Errorf("write user+address: %w", err)
	}

	inviteSent := true
	if err := deps.SendInvite(ctx, email, displayName); err != nil {
		inviteSent = false
	}

	return AddUserResult{UID: uid, InviteSent: inviteSent}, nil
}

func composeDisplayName(user map[string]any) string {
	first, _ := user["first_name"].(string)
	last, _ := user["last_name"].(string)
	return strings.TrimSpace(strings.TrimSpace(first) + " " + strings.TrimSpace(last))
}
```

- [ ] **Step 5: Run the tests and make sure they pass**

Run: `cd functions/loans && CGO_ENABLED=0 go test ./test/users/... ./test/fakes/...`
Expected: PASS (all `TestAddUserCore_*`).

- [ ] **Step 6: Commit**

```bash
git add functions/loans/api/users/add_user_core.go functions/loans/test/fakes/fakes.go functions/loans/test/users/add_user_core_test.go
git commit -m "feat(functions): add HandleAddUserCore (authz + atomic create + invite)"
```

## Task A3: SendPasswordSetupLink core

**Files:**
- Create: `functions/loans/api/users/send_password_setup_link_core.go`
- Test: `functions/loans/test/users/send_password_setup_link_core_test.go`

- [ ] **Step 1: Write the failing test**

Create `functions/loans/test/users/send_password_setup_link_core_test.go`:
```go
package users_test

import (
	"context"
	"errors"
	"testing"

	"com.loooans.app/api/users"
	"com.loooans.app/test/fakes"
)

func TestSendPasswordSetupLinkCore_KnownEmail_Sends(t *testing.T) {
	inviter := &fakes.Inviter{}
	deps := users.SendPasswordSetupLinkDeps{SendInvite: func(ctx context.Context, email string) error {
		return inviter.Send(ctx, email, "")
	}}
	if err := users.HandleSendPasswordSetupLinkCore(context.Background(), "jane@example.com", deps); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(inviter.Invites) != 1 || inviter.Invites[0].Email != "jane@example.com" {
		t.Fatalf("expected invite to jane@example.com, got %+v", inviter.Invites)
	}
}

func TestSendPasswordSetupLinkCore_EmptyEmail_NoOp(t *testing.T) {
	inviter := &fakes.Inviter{}
	deps := users.SendPasswordSetupLinkDeps{SendInvite: func(ctx context.Context, email string) error {
		return inviter.Send(ctx, email, "")
	}}
	if err := users.HandleSendPasswordSetupLinkCore(context.Background(), "  ", deps); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(inviter.Invites) != 0 {
		t.Fatalf("expected no invite for empty email, got %+v", inviter.Invites)
	}
}

func TestSendPasswordSetupLinkCore_UnknownEmail_NeverLeaks(t *testing.T) {
	deps := users.SendPasswordSetupLinkDeps{SendInvite: func(ctx context.Context, email string) error {
		return errors.New("there is no user record corresponding to the provided identifier")
	}}
	// Must swallow the error so the caller cannot distinguish existing vs
	// non-existing accounts.
	if err := users.HandleSendPasswordSetupLinkCore(context.Background(), "ghost@example.com", deps); err != nil {
		t.Fatalf("expected nil error (no account-existence leak), got %v", err)
	}
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd functions/loans && CGO_ENABLED=0 go test ./test/users/...`
Expected: FAIL — `undefined: users.HandleSendPasswordSetupLinkCore`.

- [ ] **Step 3: Implement the core**

Create `functions/loans/api/users/send_password_setup_link_core.go`:
```go
package users

import (
	"context"
	"strings"
)

// SendPasswordSetupLinkDeps wires the invite sender for the core.
type SendPasswordSetupLinkDeps struct {
	// SendInvite generates + emails a password-reset link. An error (e.g. no
	// such user) is intentionally swallowed by the core so the endpoint never
	// leaks whether an account exists.
	SendInvite func(ctx context.Context, email string) error
}

// HandleSendPasswordSetupLinkCore best-effort sends a set-password / reset link
// to the given email. It ALWAYS returns nil: an empty email is a no-op, and a
// send error (including "no such user") is swallowed so the endpoint is safe to
// expose unauthenticated without enabling account enumeration.
func HandleSendPasswordSetupLinkCore(ctx context.Context, email string, deps SendPasswordSetupLinkDeps) error {
	email = strings.TrimSpace(email)
	if email == "" {
		return nil
	}
	_ = deps.SendInvite(ctx, email)
	return nil
}
```

- [ ] **Step 4: Run the test and make sure it passes**

Run: `cd functions/loans && CGO_ENABLED=0 go test ./test/users/...`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add functions/loans/api/users/send_password_setup_link_core.go functions/loans/test/users/send_password_setup_link_core_test.go
git commit -m "feat(functions): add HandleSendPasswordSetupLinkCore (leak-safe)"
```

## Task A4: Shared invite email helper

**Files:**
- Create: `functions/loans/api/users/invite_email.go`

This helper performs real I/O (Admin SDK link generation + MS Graph email), so it is covered indirectly by the core tests (via the `SendInvite` fake) and exercised end-to-end on dev. No standalone unit test.

- [ ] **Step 1: Implement the helper**

Create `functions/loans/api/users/invite_email.go`:
```go
package users

import (
	"context"
	"fmt"

	"com.loooans.app/utils"
	"firebase.google.com/go/v4/auth"
)

// sendPasswordSetupEmail generates a Firebase password-reset link for email and
// sends a branded "set your password" message via Microsoft Graph. Used both
// for the first invite (AddUser) and for resend / forgot-password
// (SendPasswordSetupLink). displayName may be empty (forgot-password path).
//
// PasswordResetLink errors when no account exists for the email; callers in the
// forgot-password path swallow that error to avoid leaking account existence.
func sendPasswordSetupEmail(ctx context.Context, authClient *auth.Client, email, displayName string) error {
	link, err := authClient.PasswordResetLink(ctx, email)
	if err != nil {
		return fmt.Errorf("generate password reset link: %w", err)
	}

	greeting := "Hi!"
	if displayName != "" {
		greeting = fmt.Sprintf("Hi %s!", displayName)
	}

	subject := "Set your Loooans password"
	body := fmt.Sprintf(
		`<p>%s</p>`+
			`<p>An account has been created for you on Loooans. `+
			`Tap the button below to set your password and sign in.</p>`+
			`<p><a href="%s">Set your password</a></p>`+
			`<p>On your first sign-in you'll be asked to verify your email and mobile number.</p>`+
			`<p>If you weren't expecting this, you can ignore this email.</p>`+
			`<p>From: The Loooans team</p>`,
		greeting, link,
	)

	if _, err := utils.SendEmail(subject, body, []string{email}); err != nil {
		return fmt.Errorf("send invite email: %w", err)
	}
	return nil
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd functions/loans && CGO_ENABLED=0 go build ./...`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add functions/loans/api/users/invite_email.go
git commit -m "feat(functions): add shared password-setup invite email helper"
```

## Task A5: AddUser HTTP adapter (rewrite the stub)

**Files:**
- Modify: `functions/loans/api/users/add_user.go` (full rewrite)

- [ ] **Step 1: Replace the file contents**

Overwrite `functions/loans/api/users/add_user.go` with:
```go
package users

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"

	"com.loooans.app/utils"
	"firebase.google.com/go/v4/auth"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// addUserRequest is the wire shape: a requested role plus the client-serialized
// user (and optional address) entity JSON. The user/address maps are written
// through to Firestore largely as-is; only logic-critical fields are typed.
type addUserRequest struct {
	Role    string         `json:"role"`
	User    map[string]any `json:"user"`
	Address map[string]any `json:"address"`
}

// AddUser provisions a new user on behalf of an authenticated company admin:
// mints a Firebase Auth account, atomically writes users/{uid} + address, and
// emails a set-password invite. See HandleAddUserCore for the business logic.
func AddUser(w http.ResponseWriter, r *http.Request) {
	log, errLog := utils.InitializeLogger("add_user")
	if errLog != nil {
		http.Error(w, errLog.Error(), http.StatusInternalServerError)
		return
	}

	if r.Method == http.MethodOptions {
		w.Header().Set("Access-Control-Allow-Credentials", "true")
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "POST")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		w.Header().Set("Access-Control-Max-Age", "3600")
		w.WriteHeader(http.StatusNoContent)
		return
	}
	w.Header().Set("Access-Control-Allow-Credentials", "true")
	w.Header().Set("Access-Control-Allow-Origin", "*")

	callerUid := utils.ValidateRequestV2(w, r)
	if callerUid == "" {
		return // ValidateRequestV2 already wrote the error.
	}
	if r.Method != http.MethodPost {
		http.Error(w, "Use POST method", http.StatusBadRequest)
		return
	}

	body, errBody := io.ReadAll(r.Body)
	defer r.Body.Close()
	if errBody != nil {
		http.Error(w, errBody.Error(), http.StatusBadRequest)
		return
	}
	var req addUserRequest
	if err := json.Unmarshal(body, &req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	ctx := context.Background()
	app, err := utils.InitializeFirebase(ctx)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	authClient, err := app.Auth(ctx)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	fs, err := app.Firestore(ctx)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer fs.Close()

	prefix := utils.GetCollectionPrefix()

	deps := AddUserDeps{
		GetUser: func(ctx context.Context, uid string) (map[string]any, error) {
			doc, dErr := fs.Collection(prefix+"users").Doc(uid).Get(ctx)
			if status.Code(dErr) == codes.NotFound {
				return nil, nil
			}
			if dErr != nil {
				return nil, dErr
			}
			return doc.Data(), nil
		},
		GetCompanyManagementType: func(ctx context.Context, companyId string) (string, error) {
			if companyId == "" {
				return "", nil
			}
			doc, dErr := fs.Collection(prefix+"companies").Doc(companyId).Get(ctx)
			if dErr != nil {
				return "", dErr
			}
			mt, _ := doc.Data()["management_type"].(string)
			return mt, nil
		},
		CreateAuthUser: func(ctx context.Context, email, password, displayName string) (string, error) {
			params := (&auth.UserToCreate{}).Email(email).Password(password).DisplayName(displayName)
			rec, cErr := authClient.CreateUser(ctx, params)
			if cErr != nil {
				if auth.IsEmailAlreadyExists(cErr) {
					return "", ErrEmailExists
				}
				return "", cErr
			}
			return rec.UID, nil
		},
		DeleteAuthUser: func(ctx context.Context, uid string) error {
			return authClient.DeleteUser(ctx, uid)
		},
		WriteUserAndAddress: func(ctx context.Context, uid string, user, address map[string]any) error {
			batch := fs.Batch()
			batch.Set(fs.Collection(prefix+"users").Doc(uid), user)
			if address != nil {
				addrRef := fs.Collection(prefix + "address").NewDoc()
				address["id"] = addrRef.ID
				batch.Set(addrRef, address)
			}
			_, cErr := batch.Commit(ctx)
			return cErr
		},
		SendInvite: func(ctx context.Context, email, displayName string) error {
			return sendPasswordSetupEmail(ctx, authClient, email, displayName)
		},
		GeneratePassword: utils.GenerateRandomPassword,
	}

	res, err := HandleAddUserCore(ctx, callerUid, req.Role, req.User, req.Address, deps)
	if err != nil {
		writeAddUserError(w, log, err)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"message": "Successfully added user",
		"data": map[string]any{
			"uid":        res.UID,
			"inviteSent": res.InviteSent,
		},
	})
}

// writeAddUserError maps core sentinels onto HTTP status codes.
func writeAddUserError(w http.ResponseWriter, log interface{ Error(string, ...interface{}) }, err error) {
	switch {
	case errors.Is(err, ErrInvalidRole), errors.Is(err, ErrMissingEmail):
		http.Error(w, err.Error(), http.StatusBadRequest)
	case errors.Is(err, ErrCallerNotFound), errors.Is(err, ErrCallerNotAdmin), errors.Is(err, ErrRoleNotAllowed):
		http.Error(w, err.Error(), http.StatusForbidden)
	case errors.Is(err, ErrEmailExists):
		http.Error(w, err.Error(), http.StatusConflict)
	default:
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}
```

> Note: `utils.InitializeLogger` returns a `*zap.Logger`; if its `Error` signature differs from the `interface{ Error(string, ...interface{}) }` shown, drop the `log` parameter from `writeAddUserError` and call `http.Error` directly (the logger is optional here). Verify against `utils/logger.go` during implementation and adjust the parameter type to match, or remove it.

- [ ] **Step 2: Tidy + build**

Run:
```bash
cd functions/loans/api && go mod tidy
cd .. && CGO_ENABLED=0 go build ./...
```
Expected: builds clean (pulls in `google.golang.org/grpc/codes`+`status` if not already present).

- [ ] **Step 3: Run all backend tests**

Run: `cd functions/loans && CGO_ENABLED=0 go test ./...`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add functions/loans/api/users/add_user.go functions/loans/api/go.mod functions/loans/api/go.sum
git commit -m "feat(functions): wire AddUser HTTP adapter to core (Admin SDK + atomic write)"
```

## Task A6: SendPasswordSetupLink HTTP adapter

**Files:**
- Create: `functions/loans/api/users/send_password_setup_link.go`

- [ ] **Step 1: Implement the adapter**

Create `functions/loans/api/users/send_password_setup_link.go`:
```go
package users

import (
	"context"
	"encoding/json"
	"io"
	"net/http"

	"com.loooans.app/utils"
)

type sendPasswordSetupLinkRequest struct {
	Email string `json:"email"`
}

// SendPasswordSetupLink emails a set-password / reset link for the given email.
// It backs both the admin "Resend invite" action and the login "Forgot
// password" link, so it is intentionally UNAUTHENTICATED and always responds
// 200 — it never reveals whether an account exists.
//
// TODO(rate-limit): this endpoint is unauthenticated; add per-email/IP rate
// limiting before production to prevent email-bombing.
func SendPasswordSetupLink(w http.ResponseWriter, r *http.Request) {
	log, errLog := utils.InitializeLogger("send_password_setup_link")
	if errLog != nil {
		http.Error(w, errLog.Error(), http.StatusInternalServerError)
		return
	}

	if r.Method == http.MethodOptions {
		w.Header().Set("Access-Control-Allow-Credentials", "true")
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "POST")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		w.Header().Set("Access-Control-Max-Age", "3600")
		w.WriteHeader(http.StatusNoContent)
		return
	}
	w.Header().Set("Access-Control-Allow-Credentials", "true")
	w.Header().Set("Access-Control-Allow-Origin", "*")

	if r.Method != http.MethodPost {
		http.Error(w, "Use POST method", http.StatusBadRequest)
		return
	}

	body, errBody := io.ReadAll(r.Body)
	defer r.Body.Close()
	if errBody != nil {
		http.Error(w, errBody.Error(), http.StatusBadRequest)
		return
	}
	var req sendPasswordSetupLinkRequest
	if err := json.Unmarshal(body, &req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	ctx := context.Background()
	app, err := utils.InitializeFirebase(ctx)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	authClient, err := app.Auth(ctx)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	deps := SendPasswordSetupLinkDeps{
		SendInvite: func(ctx context.Context, email string) error {
			return sendPasswordSetupEmail(ctx, authClient, email, "")
		},
	}
	if err := HandleSendPasswordSetupLinkCore(ctx, req.Email, deps); err != nil {
		// Core never returns an error today; log defensively and still 200.
		log.Error("send_password_setup_link core error: " + err.Error())
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"message": "ok"})
}
```

> Note: adjust the `log.Error(...)` call to the project's zap logger API if needed (e.g. `log.Error("...", zap.String(...))`).

- [ ] **Step 2: Build**

Run: `cd functions/loans && CGO_ENABLED=0 go build ./...`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add functions/loans/api/users/send_password_setup_link.go
git commit -m "feat(functions): add SendPasswordSetupLink HTTP adapter (unauthenticated, leak-safe)"
```

## Task A7: Suppress the duplicate welcome email for admin-created users

**Files:**
- Modify: `functions/loans/triggers/user_created.go`
- Create: `functions/loans/test/triggers/user_created_skip_test.go`

The `userCreated` trigger emails every new user a generic "Verify your account" message. Admin-provisioned users already get the set-password invite, so suppress the generic one when the doc carries `invited_by_admin == true`.

- [ ] **Step 1: Write the failing test (pure helper)**

Create `functions/loans/test/triggers/user_created_skip_test.go`:
```go
package triggers_test

import (
	"testing"

	"com.loooans.app/triggers"
	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
)

func TestShouldSkipWelcomeEmail(t *testing.T) {
	cases := []struct {
		name   string
		fields map[string]*firestoredata.Value
		want   bool
	}{
		{
			name:   "invited by admin → skip",
			fields: map[string]*firestoredata.Value{"invited_by_admin": {ValueType: &firestoredata.Value_BooleanValue{BooleanValue: true}}},
			want:   true,
		},
		{
			name:   "self-registered (no field) → send",
			fields: map[string]*firestoredata.Value{"id": {ValueType: &firestoredata.Value_StringValue{StringValue: "u1"}}},
			want:   false,
		},
		{
			name:   "field present but false → send",
			fields: map[string]*firestoredata.Value{"invited_by_admin": {ValueType: &firestoredata.Value_BooleanValue{BooleanValue: false}}},
			want:   false,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := triggers.ShouldSkipWelcomeEmail(tc.fields); got != tc.want {
				t.Fatalf("ShouldSkipWelcomeEmail = %v, want %v", got, tc.want)
			}
		})
	}
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd functions/loans && CGO_ENABLED=0 go test ./test/triggers/...`
Expected: FAIL — `undefined: triggers.ShouldSkipWelcomeEmail`.

- [ ] **Step 3: Implement the helper + use it**

In `functions/loans/triggers/user_created.go`, add the exported helper (top of file, after imports):
```go
// ShouldSkipWelcomeEmail reports whether the newly-created user doc was
// provisioned by an admin (invited_by_admin == true). Such users already
// receive the set-password invite from the addUser endpoint, so the generic
// "Verify your account" email is suppressed to avoid a confusing duplicate.
func ShouldSkipWelcomeEmail(fields map[string]*firestoredata.Value) bool {
	if v, ok := fields["invited_by_admin"]; ok {
		return v.GetBooleanValue()
	}
	return false
}
```

Then, in `UserCreated`, right after `uid` is resolved (after the `if vId, ok := ...` block, before `app, errFirebaseAdmin := ...`), add:
```go
	if ShouldSkipWelcomeEmail(data.GetValue().GetFields()) {
		log.Debug("user_created: invited_by_admin set, skipping generic welcome email")
		return nil
	}
```

- [ ] **Step 4: Run the test + build**

Run: `cd functions/loans && CGO_ENABLED=0 go test ./test/triggers/... && CGO_ENABLED=0 go build ./...`
Expected: PASS + clean build.

- [ ] **Step 5: Commit**

```bash
git add functions/loans/triggers/user_created.go functions/loans/test/triggers/user_created_skip_test.go
git commit -m "feat(functions): skip generic welcome email for admin-invited users"
```

## Task A8: Register both functions

**Files:**
- Modify: `functions/loans/loooans_cloud_functions.go:23`

- [ ] **Step 1: Edit the registration block**

In `functions/loans/loooans_cloud_functions.go`, replace the commented line:
```go
	//functions.HTTP("addUser", users.AddUser)
```
with:
```go
	functions.HTTP("addUser", users.AddUser)
	functions.HTTP("sendPasswordSetupLink", users.SendPasswordSetupLink)
```

- [ ] **Step 2: Build**

Run: `cd functions/loans && CGO_ENABLED=0 go build ./...`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add functions/loans/loooans_cloud_functions.go
git commit -m "feat(functions): register addUser + sendPasswordSetupLink HTTP functions"
```

## Task A9: Deploy script

**Files:**
- Modify: `.github/scripts/deploy_functions.sh`

- [ ] **Step 1: Add the two HTTP deploys**

In `.github/scripts/deploy_functions.sh`, after the `sendEmail` deploy block (the `pids[$!]="sendEmail"` line), add:
```bash
echo "Deploying addUser"
gcloud functions deploy addUser_$environment --set-env-vars "$MS_GRAPH_ENV_VARS" --set-secrets "$MS_GRAPH_SECRETS" --runtime go122 --trigger-http --project $project --region asia-east1 --allow-unauthenticated --gen2 --service-account="$serviceAccount" --entry-point addUser &
pids[$!]="addUser"

echo "Deploying sendPasswordSetupLink"
gcloud functions deploy sendPasswordSetupLink_$environment --set-env-vars "$MS_GRAPH_ENV_VARS" --set-secrets "$MS_GRAPH_SECRETS" --runtime go122 --trigger-http --project $project --region asia-east1 --allow-unauthenticated --gen2 --service-account="$serviceAccount" --entry-point sendPasswordSetupLink &
pids[$!]="sendPasswordSetupLink"
```

- [ ] **Step 2: Bump the function counts**

In the same file, update the two summary strings (currently "All 12 functions ..." after the reviewUpdated addition — verify the current number and add 2):
- `echo "All 14 functions deploying in parallel. Waiting for completion..."`
- `echo "Deployment done. All 14 functions deployed successfully."`

(Confirm the current count first with `grep -n "functions deploying" .github/scripts/deploy_functions.sh` and add 2 to whatever it shows.)

- [ ] **Step 3: Lint the script**

Run: `bash -n .github/scripts/deploy_functions.sh`
Expected: no syntax errors.

- [ ] **Step 4: Commit**

```bash
git add .github/scripts/deploy_functions.sh
git commit -m "ci(functions): deploy addUser + sendPasswordSetupLink"
```

## Task A10: Update backend memory + open PR A

**Files:**
- Modify: `functions/loans/MEMORY.md`

- [ ] **Step 1: Append a memory entry**

Add a section to `functions/loans/MEMORY.md` summarizing: the two new HTTP endpoints (adapter+core), the authz matrix, the atomic compensating-delete write, the invite via PasswordResetLink + MS Graph, the `invited_by_admin` suppression of the userCreated welcome email, and that the endpoints need the MS Graph secret accessor IAM (already on dev; prod pending).

- [ ] **Step 2: Full backend test + build**

Run: `cd functions/loans && CGO_ENABLED=0 go test ./... && CGO_ENABLED=0 go build ./...`
Expected: all PASS, clean build.

- [ ] **Step 3: Commit, push, open PR A**

```bash
git add functions/loans/MEMORY.md
git commit -m "docs(functions): record server-side user provisioning endpoints"
git push -u origin feat/user-provisioning-backend
gh pr create --repo anatechopc/finstack --base develop \
  --title "feat(functions): server-side user provisioning (addUser + sendPasswordSetupLink)" \
  --body "Phase A of server-side user provisioning. See docs/superpowers/specs/2026-06-19-server-side-user-provisioning-design.md. Deploy this first; Phase B (hosting rewrites) depends on the Cloud Run services this creates."
```

- [ ] **Step 4: After merge — verify the dev deploy created the services**

Wait for the `develop` deploy workflow, then confirm the services exist (needed by Phase B):
```bash
gcloud run services list --project loooans-dev-stg --region asia-east1 | grep -E "adduser-development|sendpasswordsetuplink-development"
```
Expected: both services listed.

---

# PHASE B — Hosting rewrites (firebase.json)

> **Branch:** create `feat/user-provisioning-hosting` off `develop` **after Phase A is merged and deployed**. Gen2 Cloud Run services must exist before hosting can reference them (known gotcha). Lands → PR B → deploy hosting routes the public `/api/users/...` paths to the Phase A services.

## Task B1: Add the two rewrites to all three hosting targets

**Files:**
- Modify: `apps/loans/firebase.json`

- [ ] **Step 1: Add the rewrites**

In `apps/loans/firebase.json`, in EACH of the three `hosting` targets (`develop`, `staging`, `production`), insert these two rewrite entries **immediately above** the existing `{ "source": "**", "destination": "/index.html" }` catch-all. Substitute `<env>` with the target's service suffix: `development` for the `develop` target, `staging` for `staging`, `production` for `production`:
```jsonc
{
  "source": "/api/users/add",
  "run": {
    "serviceId": "adduser-<env>",
    "region": "asia-east1"
  }
},
{
  "source": "/api/users/password/setup-link",
  "run": {
    "serviceId": "sendpasswordsetuplink-<env>",
    "region": "asia-east1"
  }
},
```
So the `develop` target gets `adduser-development` + `sendpasswordsetuplink-development`, `staging` gets `...-staging`, `production` gets `...-production`.

- [ ] **Step 2: Validate the JSON**

Run: `cd apps/loans && python3 -c "import json; json.load(open('firebase.json')); print('valid')"`
Expected: `valid`.

- [ ] **Step 3: Commit + open PR B**

```bash
git add apps/loans/firebase.json
git commit -m "feat(hosting): route /api/users/add + /password/setup-link to Cloud Run"
git push -u origin feat/user-provisioning-hosting
gh pr create --repo anatechopc/finstack --base develop \
  --title "feat(hosting): rewrites for addUser + sendPasswordSetupLink" \
  --body "Phase B of server-side user provisioning. Merge + deploy AFTER Phase A (the Cloud Run services must exist). Phase C (frontend) depends on these routes being live."
```

- [ ] **Step 4: After merge — verify routing is live**

```bash
curl -i -X POST https://development.loooans.com/api/users/password/setup-link \
  -H 'Content-Type: application/json' -d '{"email":"nobody@example.com"}'
```
Expected: HTTP 200 with `{"message":"ok"}` (not the SPA's `index.html`), confirming the rewrite hits the function.

---

# PHASE C — Frontend (Flutter)

> **Branch:** create `feat/user-provisioning-frontend` off `develop` **after Phases A+B are deployed** (so the client can be tested end-to-end against the live backend). Lands → PR C (supersedes PR #69 — close #69 referencing this).

## Task C1: Network service — createUser + sendPasswordSetupLink

**Files:**
- Modify: `packages/core/user_repository/lib/src/data/network/user_network_service.dart`

- [ ] **Step 1: Replace `createUserAccess` with `createUser` + add `sendPasswordSetupLink`**

In `user_network_service.dart`, delete the `createUserAccess` method and add:
```dart
  /// Creates a user server-side (Firebase Auth account + Firestore doc) via the
  /// addUser Cloud Function. [user] and [address] are the client-serialized
  /// entity JSON maps. Returns the server-minted uid and whether the invite
  /// email was sent.
  Future<({String uid, bool inviteSent})> createUser({
    required String role,
    required Map<String, dynamic> user,
    Map<String, dynamic>? address,
    required String idToken,
  }) async {
    final response = await http.post(
      Uri.parse('$LOOOANS_BASE_API_URL/users/add'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'role': role,
        'user': user,
        if (address != null) 'address': address,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final payload = data['data'] as Map<String, dynamic>;
      return (
        uid: payload['uid'] as String,
        inviteSent: payload['inviteSent'] as bool? ?? false,
      );
    }

    throw HttpException(
      'Create user failed: ${response.statusCode} ${response.body}',
    );
  }

  /// Requests a set-password / reset link email for [email]. Backs both the
  /// admin "Resend invite" action and the login "Forgot password" link. The
  /// endpoint always succeeds and never reveals whether the account exists.
  Future<void> sendPasswordSetupLink({required String email}) async {
    final response = await http.post(
      Uri.parse('$LOOOANS_BASE_API_URL/users/password/setup-link'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );

    if (response.statusCode > HttpStatus.noContent) {
      throw HttpException(
        'Send password setup link failed: ${response.statusCode} ${response.body}',
      );
    }
  }
```

- [ ] **Step 2: Analyze**

Run: `cd packages/core/user_repository && fvm flutter analyze lib/src/data/network/user_network_service.dart`
Expected: no issues (a "method removed" reference error here means a caller still uses `createUserAccess` — fixed in Task C2).

- [ ] **Step 3: Commit**

```bash
git add packages/core/user_repository/lib/src/data/network/user_network_service.dart
git commit -m "feat(user_repository): network createUser + sendPasswordSetupLink"
```

## Task C2: Repository — createUser + sendPasswordSetupLink

**Files:**
- Modify: `packages/core/user_repository/lib/src/repository/user_repository.dart`

- [ ] **Step 1: Replace `createUserAccess` wrapper**

In `user_repository.dart`, delete the `createUserAccess` method (lines 91–103) and add:
```dart
  /// Provisions a user server-side. Returns the server-minted uid and whether
  /// the invite email was sent. See [UserNetworkService.createUser].
  Future<({String uid, bool inviteSent})> createUser({
    required String role,
    required Map<String, dynamic> user,
    Map<String, dynamic>? address,
    required String idToken,
  }) {
    return _networkService.createUser(
      role: role,
      user: user,
      address: address,
      idToken: idToken,
    );
  }

  /// Requests a set-password / reset link email for [email].
  Future<void> sendPasswordSetupLink({required String email}) {
    return _networkService.sendPasswordSetupLink(email: email);
  }
```

- [ ] **Step 2: Analyze the package**

Run: `cd packages/core/user_repository && fvm flutter analyze`
Expected: no issues.

- [ ] **Step 3: Commit**

```bash
git add packages/core/user_repository/lib/src/repository/user_repository.dart
git commit -m "feat(user_repository): repository createUser + sendPasswordSetupLink"
```

## Task C3: `User.createInvited` factory

**Files:**
- Modify: `packages/core/user_repository/lib/src/model/user.dart`
- Test: `packages/core/user_repository/test/user_create_invited_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/core/user_repository/test/user_create_invited_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:user_repository/user_repository.dart';

void main() {
  EmploymentDetails blankEmployment() => EmploymentDetails.createBlank();

  test('createInvited builds a uid-less user with the given role', () {
    final user = User.createInvited(
      role: UserRole.teller,
      firstName: 'Jane',
      lastName: 'Doe',
      mobileNumber: '+639170000000',
      emailAddress: 'jane@example.com',
      birthDate: DateTime(1990, 1, 1),
      sex: Sex.female,
      employmentDetails: blankEmployment(),
      companyId: 'co-1',
    );

    expect(user.id, NO_ID);
    expect(user.userRole, UserRole.teller);
    expect(user.emailAddress, 'jane@example.com');
    expect(user.companyId, 'co-1');
  });

  test('createInvited throws when email is empty', () {
    expect(
      () => User.createInvited(
        role: UserRole.customer,
        firstName: 'Jane',
        lastName: 'Doe',
        mobileNumber: '+639170000000',
        emailAddress: '   ',
        birthDate: DateTime(1990, 1, 1),
        sex: Sex.female,
        employmentDetails: blankEmployment(),
        companyId: 'co-1',
      ),
      throwsException,
    );
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/core/user_repository && fvm flutter test test/user_create_invited_test.dart`
Expected: FAIL — `The method 'createInvited' isn't defined`.

- [ ] **Step 3: Add the factory**

In `packages/core/user_repository/lib/src/model/user.dart`, after `createManagedCustomer` (line ~140), add:
```dart
  /// Creates a user for the admin "Add team member / Add borrower" flow. The
  /// account is provisioned server-side, so [id] is left as [NO_ID] (the
  /// backend stamps the real Firebase Auth uid). Email is required because the
  /// user is invited by email and must pass the email-verification gate.
  factory User.createInvited({
    required UserRole role,
    required String firstName,
    required String lastName,
    required String mobileNumber,
    required String emailAddress,
    required DateTime birthDate,
    required Sex sex,
    required EmploymentDetails employmentDetails,
    String? companyId,
    ImageUrl? profilePhotoUrl,
    ImageUrl? photoWithValidIdUrl,
    String? middleName,
    String? businessName,
    String? facebookProfileUrl,
  }) {
    if (emailAddress.trim().isEmpty) {
      throw Exception('Email address is required for invited users');
    }

    final now = DateTime.timestamp();

    return User()
      ..id = NO_ID
      ..updatedAt = now
      ..createdAt = now
      ..lastName = lastName
      ..firstName = firstName
      ..middleName = middleName
      ..birthDate = birthDate
      ..mobileNumber = mobileNumber
      ..emailAddress = emailAddress
      ..userRole = role
      ..profilePhotoUrl = profilePhotoUrl
      ..photoWithValidIdUrl = photoWithValidIdUrl
      ..facebookProfileUrl = facebookProfileUrl
      ..karma = 0
      ..aiVerifyRef = null
      ..verificationStatus = UserVerificationStatus.unverified.value
      ..mobileVerifiedAt = null
      ..companyId = companyId
      ..sex = sex
      ..employmentDetails = employmentDetails
      ..businessName = businessName;
  }
```

- [ ] **Step 4: Run the test and make sure it passes**

Run: `cd packages/core/user_repository && fvm flutter test test/user_create_invited_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/core/user_repository/lib/src/model/user.dart packages/core/user_repository/test/user_create_invited_test.dart
git commit -m "feat(user_repository): add User.createInvited factory"
```

## Task C4: RegistrationBloc — server-backed invited-user handler + test seam

**Files:**
- Modify: `apps/loans/lib/features/registration/bloc/registration_bloc.dart`
- Modify: `apps/loans/lib/features/registration/bloc/registration_event.dart`
- Test: `apps/loans/test/features/registration/registration_bloc_invited_test.dart`

- [ ] **Step 1: Add the new event**

In `registration_event.dart`: remove `SubmitManagedUserRegistrationEvent` and the `adminCreating` field from `SubmitUserRegistrationEvent` (self-registration only now), and add:
```dart
class SubmitUserRegistrationEvent extends RegistrationEvent {
  SubmitUserRegistrationEvent({required this.fields});
  final Map<String, dynamic> fields;
}

class SubmitInvitedUserEvent extends RegistrationEvent {
  SubmitInvitedUserEvent({required this.fields, required this.role});
  final Map<String, dynamic> fields;

  /// The role assigned to the invited user: a staff role for "Add team member"
  /// or [UserRole.customer] for "Add borrower". Server re-validates it.
  final UserRole role;
}
```

- [ ] **Step 2: Add a test seam constructor + the handler**

In `registration_bloc.dart`:

(a) Add a `withDependencies` constructor next to the existing one (the existing `RegistrationBloc(BuildContext context)` stays). It accepts all five repos so no stand-ins are needed; the test passes mocks for all of them (the invited handler only exercises `_userRepository`, `_storageRepository`, and `authService`):
```dart
  RegistrationBloc.withDependencies({
    required AuthenticationRepository authenticationRepository,
    required UserRepository userRepository,
    required StorageRepository storageRepository,
    required CompanyRepository companyRepository,
    required AddressRepository addressRepository,
    AuthenticationService? authService,
  })  : authService = authService ?? AuthenticationService.instance,
        _authenticationRepository = authenticationRepository,
        _userRepository = userRepository,
        _storageRepository = storageRepository,
        _companyRepository = companyRepository,
        _addressRepository = addressRepository,
        super(RegisterInitial()) {
    on(_handleSubmitUserRegistrationEvent);
    on(_handleSubmitProviderRegistrationEvent);
    on(_handleSubmitInvitedUser);
  }
```

(b) Register the handler in the **default** constructor too — replace `on(_handleSubmitManagedUserRegistrationEvent);` with `on(_handleSubmitInvitedUser);`.

(c) Replace `registerManagedUser` with:
```dart
  void registerInvitedUser(Map<String, dynamic> data, {required UserRole role}) {
    add(SubmitInvitedUserEvent(fields: data, role: role));
  }
```

(d) Delete `_handleSubmitManagedUserRegistrationEvent` and add:
```dart
  Future<void> _handleSubmitInvitedUser(
    SubmitInvitedUserEvent event,
    Emitter<RegistrationState> emit,
  ) async {
    try {
      emit(RegistrationLoadingState(isLoading: true));
      final data = event.fields;

      // Photos are optional for admin-added users. There is no uid yet, so
      // upload under a temporary folder; the URLs are embedded in the entity.
      final folder = 'users/invites/${StringHelper.generateId(length: 16)}';
      final tempProfile = data['profile_picture'] as Map<String, dynamic>?;
      final tempSelfie = data['selfie_valid_id'] as Map<String, dynamic>?;

      ImageUrl? profilePhotoUrl;
      if (tempProfile != null) {
        profilePhotoUrl = await _storageRepository.upload(
          data: tempProfile['bytes'] as Uint8List,
          folder: folder,
          fileName:
              'profile_pic_${DateTime.timestamp().toIso8601String()}_${tempProfile['name'] as String}',
          includeOriginal: true,
        );
      }

      ImageUrl? photoWithValidIdUrl;
      if (tempSelfie != null) {
        photoWithValidIdUrl = await _storageRepository.upload(
          data: tempSelfie['bytes'] as Uint8List,
          folder: folder,
          fileName:
              'selfie_valid_id_${DateTime.timestamp().toIso8601String()}_${tempSelfie['name'] as String}',
          includeOriginal: true,
        );
      }

      final tempUser = User.createInvited(
        role: event.role,
        firstName: data['first_name'] as String,
        lastName: data['last_name'] as String,
        middleName: data['middle_name'] as String?,
        mobileNumber: data['mobile_number'] as String,
        emailAddress: data['email_address'] as String,
        birthDate: data['birth_date'] as DateTime,
        sex: data['sex'] as Sex,
        companyId: authService.company.id,
        profilePhotoUrl: profilePhotoUrl,
        photoWithValidIdUrl: photoWithValidIdUrl,
        businessName: data['business_name'] as String?,
        facebookProfileUrl: data['facebook_profile'] as String?,
        employmentDetails: EmploymentDetails.createBlank()
          ..id = StringHelper.generateId(length: 12)
          ..employmentStatus = data['employment_status'] as EmploymentStatus
          ..employerName = data['employer_name'] as String?
          ..salaryDays = (data['salary_days'] as String?)?.toIntList() ?? [],
      );

      final tempAddress = AddressBuilder.buildFromFields(
        data,
        dataId: NO_ID,
        dataType: DataType.user,
      );

      final result = await _userRepository.createUser(
        role: event.role.name,
        user: tempUser.toEntity().toJson(),
        address: tempAddress.toEntity().toJson(),
        idToken: authService.idToken,
      );

      emit(RegistrationLoadingState());
      emit(RegistrationSuccessState(
        message: result.inviteSent
            ? 'User created — an invite email was sent.'
            : 'User created, but the invite email failed. Use "Resend invite".',
      ));
    } catch (err) {
      log.severe('SubmitInvitedUserEvent: $err', err);
      emit(RegistrationLoadingState());
      emit(RegistrationErrorState(message: 'Cannot add user: $err'));
    }
  }
```

(e) In `_handleSubmitUserRegistrationEvent`, remove the `event.adminCreating` branch so it always uses `createUserCredential` (self-registration only):
```dart
      final uid = await _authenticationRepository.createUserCredential(
        email: email,
        password: password,
      );
```

> Note: `event.role.name` returns the Dart enum identifier (`teller`, `admin`, `loanOfficer`, `reviewModerator`, `customer`), which exactly matches `_$UserRoleEnumMap` — the string the Go core expects.

- [ ] **Step 3: Write the failing handler test**

Create `apps/loans/test/features/registration/registration_bloc_invited_test.dart`:
```dart
import 'package:address_repository/address_repository.dart';
import 'package:authentication_repository/authentication_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:company_repository/company_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/registration/bloc/registration_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:storage_repository/storage_repository.dart';
import 'package:user_repository/user_repository.dart';

class _MockUserRepo extends Mock implements UserRepository {}
class _MockStorage extends Mock implements StorageRepository {}
class _MockAddressRepo extends Mock implements AddressRepository {}
class _MockAuthRepo extends Mock implements AuthenticationRepository {}
class _MockCompanyRepo extends Mock implements CompanyRepository {}
class _MockAuthService extends Mock implements AuthenticationService {}
class _MockCompany extends Mock implements Company {}

void main() {
  late _MockUserRepo users;
  late _MockStorage storage;
  late _MockAddressRepo addresses;
  late _MockAuthRepo authRepo;
  late _MockCompanyRepo companyRepo;
  late _MockAuthService auth;

  setUp(() {
    users = _MockUserRepo();
    storage = _MockStorage();
    addresses = _MockAddressRepo();
    authRepo = _MockAuthRepo();
    companyRepo = _MockCompanyRepo();
    auth = _MockAuthService();
    final company = _MockCompany();
    when(() => company.id).thenReturn('co-1');
    when(() => auth.company).thenReturn(company);
    when(() => auth.idToken).thenReturn('id-token');
    when(
      () => users.createUser(
        role: any(named: 'role'),
        user: any(named: 'user'),
        address: any(named: 'address'),
        idToken: any(named: 'idToken'),
      ),
    ).thenAnswer((_) async => (uid: 'uid-new', inviteSent: true));
  });

  RegistrationBloc build() => RegistrationBloc.withDependencies(
        authenticationRepository: authRepo,
        userRepository: users,
        storageRepository: storage,
        companyRepository: companyRepo,
        addressRepository: addresses,
        authService: auth,
      );

  Map<String, dynamic> fields() => {
        'first_name': 'Jane',
        'last_name': 'Doe',
        'mobile_number': '+639170000000',
        'email_address': 'jane@example.com',
        'birth_date': DateTime(1990, 1, 1),
        'sex': Sex.female,
        'employment_status': EmploymentStatus.employed,
        'line1': '1 Main St',
        'barangay': 'B',
        'city': 'C',
        'province': 'P',
        'country': 'PH',
        'zip_code': '1000',
      };

  blocTest<RegistrationBloc, RegistrationState>(
    'invited user → calls createUser with the role name and emits success',
    build: build,
    act: (b) => b.registerInvitedUser(fields(), role: UserRole.teller),
    expect: () => [
      isA<RegistrationLoadingState>(),
      isA<RegistrationLoadingState>(),
      isA<RegistrationSuccessState>(),
    ],
    verify: (_) {
      final captured = verify(
        () => users.createUser(
          role: captureAny(named: 'role'),
          user: any(named: 'user'),
          address: any(named: 'address'),
          idToken: 'id-token',
        ),
      ).captured;
      expect(captured.single, 'teller');
    },
  );
}
```
> Adjust imports/field names (`AddressBuilder` required fields) to whatever `AddressBuilder.buildFromFields` actually needs — check `address_repository` for the exact keys (`line1`, `barangay`, `city`, `province`, `country`, `zip_code`). If `Company` isn't exported where shown, import from `company_repository`.

- [ ] **Step 4: Run the test**

Run: `cd apps/loans && fvm flutter test test/features/registration/registration_bloc_invited_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
cd apps/loans && fvm flutter analyze lib/features/registration
git add apps/loans/lib/features/registration apps/loans/test/features/registration/registration_bloc_invited_test.dart
git commit -m "feat(registration): server-backed invited-user handler + test seam"
```

## Task C5: Remove `createUserCredentialIsolated`

**Files:**
- Modify: `packages/core/authentication_repository/lib/src/authentication_repository.dart`

- [ ] **Step 1: Delete the method**

Remove `createUserCredentialIsolated` (lines ~208–246) and the now-unused `firebase_core` import if nothing else uses it. Keep `createUserCredential` (self-registration still uses it).

- [ ] **Step 2: Analyze the package**

Run: `cd packages/core/authentication_repository && fvm flutter analyze`
Expected: no issues (no remaining references to `createUserCredentialIsolated`).

- [ ] **Step 3: Commit**

```bash
git add packages/core/authentication_repository/lib/src/authentication_repository.dart
git commit -m "refactor(auth): remove createUserCredentialIsolated (superseded by server path)"
```

## Task C6: Add-user form — modes, role picker, email required

**Files:**
- Modify: `apps/loans/lib/features/registration/widgets/register_screen_form_users_widget.dart`

- [ ] **Step 1: Add the mode param + role dropdown, rewire submit**

In `RegisterScreenFormUsersWidget`:

(a) Replace the `isUserCompanyManaged` field with `isTeamMemberMode` (keep `isAdminCreating`):
```dart
    this.isAdminCreating = false,
    this.isTeamMemberMode = false,
```
```dart
  /// True for "Add team member" (shows the staff role picker). False for
  /// "Add borrower" (role fixed to customer) and for self-registration.
  final bool isTeamMemberMode;
```

(b) Rewrite the submit `onPressed`:
```dart
                  onPressed: () {
                    if (_formKey.currentState?.saveAndValidate() ?? false) {
                      final values = _formKey.currentState!.value;
                      if (!isAdminCreating) {
                        context.read<RegistrationBloc>().registerUser(values);
                      } else if (isTeamMemberMode) {
                        context.read<RegistrationBloc>().registerInvitedUser(
                              values,
                              role: values['user_role'] as UserRole,
                            );
                      } else {
                        context.read<RegistrationBloc>().registerInvitedUser(
                              values,
                              role: UserRole.customer,
                            );
                      }
                    }
                  },
```

(c) Email field — always required + valid (replace the `if (!isUserCompanyManaged)` conditional validator):
```dart
        AppWidgets.defaultFormBuilderTextField(
          name: 'email_address',
          label: 'Email address',
          borderColor: defaultInputColor,
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(errorText: 'Email is required'),
            FormBuilderValidators.email(
              errorText: 'Please enter a valid email address',
            ),
          ]),
        ),
```

(d) Password + facebook + selfie blocks — gate on `!isAdminCreating` instead of `!isUserCompanyManaged` (admin-added users set no password and KYC is optional). Profile picture validator: `!isAdminCreating ? FormBuilderValidators.required() : null`.

(e) Add the role dropdown at the top of the field column, shown only in team-member mode:
```dart
        if (isTeamMemberMode)
          FormBuilderDropdown<UserRole>(
            name: 'user_role',
            decoration: const InputDecoration(labelText: 'Role'),
            validator: FormBuilderValidators.required(),
            items: UserRole.companyManagedRoles
                .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
                .toList(),
          ),
```
> Match the surrounding field styling (the file uses `AppWidgets.defaultFormBuilder*` helpers and a `.mapIndexed` gap inserter); place the dropdown so the gap spacing stays consistent. If a `defaultFormBuilderDropdown` helper exists in `AppWidgets`, prefer it.

- [ ] **Step 2: Analyze**

Run: `cd apps/loans && fvm flutter analyze lib/features/registration/widgets/register_screen_form_users_widget.dart`
Expected: no issues.

- [ ] **Step 3: Commit**

```bash
git add apps/loans/lib/features/registration/widgets/register_screen_form_users_widget.dart
git commit -m "feat(registration): add-user form modes + role picker + required email"
```

## Task C7: Two entries — "Add team member" vs "Add borrower"

**Files:**
- Modify: `apps/loans/lib/widgets/app_widgets.dart` (`showAddUserWidget`)
- Modify: `apps/loans/lib/widgets/dialog_widgets.dart` (`showAddUserWidget`)
- Modify: `apps/loans/lib/features/users/screens/add_user_widget.dart`
- Modify: `apps/loans/lib/features/users/screens/users_screen.dart`
- Modify: `apps/loans/lib/features/users/screens/borrowers_screen.dart`

- [ ] **Step 1: Thread an `isTeamMember` flag through the entry chain**

Add a `bool isTeamMember = false` parameter to `AppWidgets.showAddUserWidget` and `DialogWidgets.showAddUserWidget`, pass it into `AddUserWidget(isTeamMember: ...)`, and add the field to `AddUserWidget`. In `add_user_widget.dart:249-257`, pass it to the form and drop `isUserCompanyManaged`:
```dart
      return RegisterScreenFormUsersWidget(
        disableWidthConstraints: true,
        defaultInputColor: AppColors.black,
        isAdminCreating: true,
        isTeamMemberMode: widget.isTeamMember,
      );
```

- [ ] **Step 2: Make the "Add User" entry a team-member entry**

In `users_screen.dart` (the button at ~179), rename label to `'Add team member'` and pass `isTeamMember: true`:
```dart
              AppWidgets.defaultOutlinedButton(
                foregroundColor: AppColors.white,
                child: const Text('Add team member'),
                onPressed: () {
                  AppWidgets.showAddUserWidget(
                    context,
                    forCompanyUser: true,
                    withExtendedUserDetailInputs: true,
                    isTeamMember: true,
                  );
                },
              ),
```

- [ ] **Step 3: Gate "Add Borrower" to self-managed companies**

In `borrowers_screen.dart` (the button at ~190) wrap/extend the existing role guard with `AuthenticationService.instance.allowAddClients` so the borrower entry only shows for self-managed companies, and keep `isTeamMember` defaulting false:
```dart
            if (AuthenticationService.instance.allowAddClients &&
                ![
                  UserRole.customer,
                  UserRole.reviewModerator,
                ].contains(AuthenticationService.instance.user.userRole)) ...[
              AppWidgets.defaultOutlinedButton(
                foregroundColor: AppColors.white,
                child: const Text('Add Borrower'),
                onPressed: () {
                  AppWidgets.showAddUserWidget(
                    context,
                    withExtendedUserDetailInputs: true,
                  );
                },
              ),
```
> Apply the same `allowAddClients` gate to the other "Add borrower" entry points: `loan_clients_screen.dart` and `layout_widgets.dart`. Leave loan-application uses of `showAddUserWidget` (the wizard, `withLoanApplication: true`) unchanged — those create the borrower for a loan and remain borrower-mode.

- [ ] **Step 4: Analyze**

Run: `cd apps/loans && fvm flutter analyze lib/features/users lib/widgets/app_widgets.dart lib/widgets/dialog_widgets.dart`
Expected: no issues.

- [ ] **Step 5: Commit**

```bash
git add apps/loans/lib/widgets/app_widgets.dart apps/loans/lib/widgets/dialog_widgets.dart apps/loans/lib/features/users/screens/add_user_widget.dart apps/loans/lib/features/users/screens/users_screen.dart apps/loans/lib/features/users/screens/borrowers_screen.dart apps/loans/lib/features/loans/widget/loan_clients_screen.dart apps/loans/lib/widgets/layout_widgets.dart
git commit -m "feat(users): split Add team member / Add borrower entries"
```

## Task C8: Remove dead user-creation paths

**Files:**
- Modify: `apps/loans/lib/features/users/bloc/user_bloc.dart`
- Modify: `packages/core/user_repository/lib/src/model/user.dart`
- Modify: `apps/loans/lib/app/routing/route_utils.dart`

- [ ] **Step 1: Remove `UserBloc.addUser` + `_handleAddUserEvent`**

In `user_bloc.dart`: delete `addUser` (lines ~175–177), `_handleAddUserEvent` (lines ~217–286), the `on(_handleAddUserEvent);` registration, and the now-unused `AddUserEvent` class (in `user_event.dart`). Confirm no remaining references: `grep -rn "addUser\|AddUserEvent" apps/loans/lib` should show none in `user_bloc`/its callers.

- [ ] **Step 2: Remove `User.createManagedCustomer`**

In `user.dart`: delete the `createManagedCustomer` factory (lines ~109–140). Confirm no references remain: `grep -rn "createManagedCustomer" apps packages` → none.

- [ ] **Step 3: Remove the dead `AddUserScreen` route**

In `route_utils.dart:66`, remove the commented `AddUserScreen()..isCustomer = true` route line. If the `AddUserScreen` widget file has no other references (`grep -rn "AddUserScreen" apps/loans/lib`), delete it too.

- [ ] **Step 4: Analyze the whole app**

Run: `cd apps/loans && fvm flutter analyze`
Expected: no issues (no dangling references to removed symbols).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: remove dead user-creation paths (UserBloc.addUser, createManagedCustomer, AddUserScreen)"
```

## Task C9: Admin "Resend invite"

**Files:**
- Modify: `apps/loans/lib/features/users/bloc/user_bloc.dart` (+ events/state)
- Modify: the users/borrowers list row UI (per-row overflow menu)
- Test: `apps/loans/test/features/users/user_bloc_resend_invite_test.dart`

- [ ] **Step 1: Write the failing bloc test**

Create `apps/loans/test/features/users/user_bloc_resend_invite_test.dart` using the project's `.withDependencies` + mocktail pattern (mirror `payment_submission_bloc_test.dart`). It should `verify(() => userRepository.sendPasswordSetupLink(email: 'jane@example.com'))` is called when `resendInvite('jane@example.com')` is dispatched, and assert a success state is emitted.
> If `UserBloc` has only a `BuildContext` constructor, add a `UserBloc.withDependencies({required UserRepository userRepository, ...})` seam (same pattern as Task C4) as part of this task so the handler is testable.

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/loans && fvm flutter test test/features/users/user_bloc_resend_invite_test.dart`
Expected: FAIL — `resendInvite` undefined.

- [ ] **Step 3: Implement `resendInvite`**

Add to `user_bloc.dart`:
```dart
  void resendInvite(String email) => add(ResendInviteEvent(email: email));

  Future<void> _handleResendInviteEvent(
    ResendInviteEvent event,
    Emitter<UserState> emit,
  ) async {
    try {
      emit(const UserState.loading(isLoading: true));
      await userRepository.sendPasswordSetupLink(email: event.email);
      emit(const UserState.loading());
      emit(const UserState.success('Invite re-sent.'));
    } catch (err) {
      log.severe('ResendInvite error: $err', err);
      emit(const UserState.loading());
      emit(const UserState.error('Could not resend the invite.'));
    }
  }
```
Add `ResendInviteEvent({required this.email}); final String email;` to `user_event.dart` and `on(_handleResendInviteEvent);` to the constructor(s).

- [ ] **Step 4: Add the per-row action**

In the users/borrowers list row UI, add an overflow-menu item "Resend invite" that calls `context.read<UserBloc>().resendInvite(user.emailAddress)` (only meaningful when the user has an email). Show a snackbar on the resulting success/error state.

- [ ] **Step 5: Run test + analyze + commit**

```bash
cd apps/loans && fvm flutter test test/features/users/user_bloc_resend_invite_test.dart && fvm flutter analyze lib/features/users
git add apps/loans/lib/features/users apps/loans/test/features/users/user_bloc_resend_invite_test.dart
git commit -m "feat(users): admin Resend invite action"
```

## Task C10: Login "Forgot password"

**Files:**
- Modify: `apps/loans/lib/features/authentication/bloc/authentication_bloc.dart` (+ event)
- Modify: `apps/loans/lib/features/authentication/screen/login_screen.dart`
- Test: `apps/loans/test/features/authentication/authentication_bloc_forgot_password_test.dart`

- [ ] **Step 1: Write the failing bloc test**

Create the test verifying `forgotPassword('jane@example.com')` calls `userRepository.sendPasswordSetupLink(email: 'jane@example.com')` and emits a success state. Use the `AuthenticationBloc` test construction pattern (mock `UserRepository`); add a `withDependencies` seam if the bloc has only a `BuildContext` constructor.

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/loans && fvm flutter test test/features/authentication/authentication_bloc_forgot_password_test.dart`
Expected: FAIL — `forgotPassword` undefined.

- [ ] **Step 3: Implement the event + handler**

Add `ForgotPasswordEvent({required this.email}); final String email;` to `authentication_event.dart`, register `on(_handleForgotPasswordEvent);`, and:
```dart
  void forgotPassword(String email) => add(ForgotPasswordEvent(email: email));

  Future<void> _handleForgotPasswordEvent(
    ForgotPasswordEvent event,
    Emitter<AuthenticationState> emit,
  ) async {
    try {
      emit(const AuthenticationState.loading(isLoading: true));
      await _userRepository.sendPasswordSetupLink(email: event.email);
      emit(const AuthenticationState.loading());
      emit(const AuthenticationState.success(
        message: 'If an account exists for that email, we sent a reset link.',
      ));
    } catch (err) {
      log.severe('ForgotPassword error: $err', err);
      emit(const AuthenticationState.loading());
      // Neutral message — never reveal whether the account exists.
      emit(const AuthenticationState.success(
        message: 'If an account exists for that email, we sent a reset link.',
      ));
    }
  }
```

- [ ] **Step 4: Wire the login-screen link**

In `login_screen.dart` (the "Forgot password" `RichText` at ~211), replace the `onTap` body with a small dialog prompting for an email, then `context.read<AuthenticationBloc>().forgotPassword(email)` and a confirmation snackbar:
```dart
                    ..onTap = () async {
                      final email = await showForgotPasswordEmailDialog(context);
                      if (email != null && email.trim().isNotEmpty && context.mounted) {
                        context.read<AuthenticationBloc>().forgotPassword(email.trim());
                      }
                    },
```
Add a small `showForgotPasswordEmailDialog(BuildContext) → Future<String?>` helper (a single `TextField` in an `AlertDialog`) near the login screen.

- [ ] **Step 5: Run test + analyze + commit**

```bash
cd apps/loans && fvm flutter test test/features/authentication/authentication_bloc_forgot_password_test.dart && fvm flutter analyze lib/features/authentication
git add apps/loans/lib/features/authentication apps/loans/test/features/authentication/authentication_bloc_forgot_password_test.dart
git commit -m "feat(auth): login Forgot password (set/reset link)"
```

## Task C11: Full app test, memory, open PR C

**Files:**
- Modify: `apps/loans/MEMORY.md`

- [ ] **Step 1: Full analyze + test**

Run:
```bash
cd apps/loans && fvm flutter analyze
fvm flutter test --test-randomize-ordering-seed random
cd ../../packages/core/user_repository && fvm flutter test
cd ../authentication_repository && fvm flutter analyze
```
Expected: analyzer clean; all tests pass.

- [ ] **Step 2: Update app memory**

Append to `apps/loans/MEMORY.md`: the move to server-side provisioning, the two add entries (team member / borrower), the `createInvited` factory, the removed dead paths + `createUserCredentialIsolated`, resend invite, and forgot password.

- [ ] **Step 3: Commit, push, open PR C, close #69**

```bash
git add apps/loans/MEMORY.md
git commit -m "docs(app): record server-side user provisioning frontend"
git push -u origin feat/user-provisioning-frontend
gh pr create --repo anatechopc/finstack --base develop \
  --title "feat(app): server-side user provisioning (invite flow, two entries, resend, forgot password)" \
  --body "Phase C of server-side user provisioning. Supersedes #69. Test after Phases A+B are deployed. Spec: docs/superpowers/specs/2026-06-19-server-side-user-provisioning-design.md"
gh pr close 69 --repo anatechopc/finstack --comment "Superseded by the server-side provisioning series (Phases A/B/C). createUserCredentialIsolated is removed in favor of the server-minted Auth account."
```

- [ ] **Step 4: Manual end-to-end verification (dev)**

As a company admin on dev: Add team member (each staff role) and Add borrower (self-managed) → confirm the new user appears, receives the set-password email, can set a password and log in, and lands on the email+mobile verify gate. Verify "Resend invite" re-sends and "Forgot password" works. Confirm an app-managed company sees no "Add Borrower" entry. Confirm an admin-created user's dates render correctly (no Timestamp/serialization errors).

---

## Self-review notes (for the executor)

- **A↔C contract:** the client POSTs `{role, user, address}` to `/api/users/add` with `role` = `UserRole.name` (e.g. `teller`); the server returns `{data:{uid, inviteSent}}`. Keep these in lockstep.
- **Date convention:** Go reads the client's int64-millis through `map[string]any` (becomes `float64`) and writes it back; Flutter's `_parseDateTime` accepts any `num`, so this round-trips. Verified.
- **No new Firestore rules:** the server writes via Admin SDK (bypasses rules). Don't add client rules for creation.
- **userCreated overlap:** handled by `invited_by_admin` (Task A7). If you skip A7, admin-created users get a duplicate "Verify your account" email.

