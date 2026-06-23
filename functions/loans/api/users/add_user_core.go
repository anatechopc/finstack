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
	ErrInvalidRole     = errors.New("invalid or unsupported role")
	ErrMissingEmail    = errors.New("user payload missing email_address")
	ErrCallerNotFound  = errors.New("caller user record not found")
	ErrCallerNotAdmin  = errors.New("caller is not authorized to add users")
	ErrCallerNoCompany = errors.New("caller has no company")
	ErrRoleNotAllowed  = errors.New("role not allowed for this company")
	ErrEmailExists     = errors.New("a user with this email already exists")
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
	CreateAuthUser func(ctx context.Context, email, password, displayName string) (string, error)
	// GetAuthUIDByEmail returns the Firebase Auth uid for an existing email.
	// Used to recover from an orphaned Auth account (created by a previous run
	// that died before the Firestore write).
	GetAuthUIDByEmail   func(ctx context.Context, email string) (string, error)
	DeleteAuthUser      func(ctx context.Context, uid string) error
	WriteUserAndAddress func(ctx context.Context, uid string, user, address map[string]any) error
	// SendInvite emails the set-password invite. role selects the audience copy
	// (borrower vs staff); see sendPasswordSetupEmail.
	SendInvite       func(ctx context.Context, email, displayName, role string) error
	GeneratePassword func() string
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
//
// NOTE: it MUTATES the supplied user and address maps in place (stamps id,
// company_id, user_role, invited_by_admin, employment_details.user_id, and
// data_id), so callers must pass maps they own (e.g. a freshly parsed request
// body).
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
	if companyId == "" {
		return AddUserResult{}, ErrCallerNoCompany
	}

	if role == "customer" {
		mgmtType, err := deps.GetCompanyManagementType(ctx, companyId)
		if err != nil {
			return AddUserResult{}, fmt.Errorf("read company %q: %w", companyId, err)
		}
		if mgmtType != "selfManaged" {
			return AddUserResult{}, ErrRoleNotAllowed
		}
	}

	displayName := composeDisplayName(user)
	uid, err := deps.CreateAuthUser(ctx, email, deps.GeneratePassword(), displayName)
	if err != nil {
		if !errors.Is(err, ErrEmailExists) {
			return AddUserResult{}, fmt.Errorf("create auth user: %w", err)
		}
		// Email already registered. Distinguish a genuine duplicate (a user doc
		// exists) from an orphaned Auth account (no doc) left by a prior run that
		// died before the Firestore write. Adopt the orphan; reject the duplicate.
		existingUID, lErr := deps.GetAuthUIDByEmail(ctx, email)
		if lErr != nil {
			return AddUserResult{}, fmt.Errorf("lookup existing auth user: %w", lErr)
		}
		existingDoc, dErr := deps.GetUser(ctx, existingUID)
		if dErr != nil {
			return AddUserResult{}, fmt.Errorf("read existing user %q: %w", existingUID, dErr)
		}
		if existingDoc != nil {
			return AddUserResult{}, ErrEmailExists
		}
		uid = existingUID
	}

	// Server-authoritative fields. invited_by_admin lets the userCreated trigger
	// skip its generic welcome email so admin-provisioned users receive only the
	// set-password invite.
	user["id"] = uid
	user["company_id"] = companyId
	user["user_role"] = role
	user["invited_by_admin"] = true
	// Force unverified: the email+mobile verification gate must not be bypassable
	// via the client payload.
	user["verificationStatus"] = 0
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
	if err := deps.SendInvite(ctx, email, displayName, role); err != nil {
		inviteSent = false
	}

	return AddUserResult{UID: uid, InviteSent: inviteSent}, nil
}

func composeDisplayName(user map[string]any) string {
	first, _ := user["first_name"].(string)
	last, _ := user["last_name"].(string)
	return strings.TrimSpace(strings.TrimSpace(first) + " " + strings.TrimSpace(last))
}
