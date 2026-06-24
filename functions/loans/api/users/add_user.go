package users

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"

	"com.loooans.app/utils"
	"firebase.google.com/go/v4/auth"
	"go.uber.org/zap"
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

// AddUserValidator authenticates the inbound HTTP request and returns the
// caller's uid, or "" when validation failed (in which case the implementation
// has already written the response).
type AddUserValidator func(w http.ResponseWriter, r *http.Request) string

// AddUserDepsBuilder constructs AddUserDeps for a single request, returning a
// cleanup func that the caller defer-runs (typically closing the Firestore
// client). Returning a non-nil error causes the handler to emit a 500.
type AddUserDepsBuilder func(ctx context.Context) (AddUserDeps, func(), error)

// AddUserHandler returns a stateless http.HandlerFunc that wires the given
// validator and deps builder. Extracted so tests can stub auth + Firebase
// wiring with httptest without spinning up real infrastructure.
func AddUserHandler(validate AddUserValidator, build AddUserDepsBuilder) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
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

		callerUid := validate(w, r)
		if callerUid == "" {
			return // validate already wrote the error.
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
		deps, cleanup, errBuild := build(ctx)
		if errBuild != nil {
			log.Error("error building deps", zap.String("error", errBuild.Error()))
			http.Error(w, errBuild.Error(), http.StatusInternalServerError)
			return
		}
		if cleanup != nil {
			defer cleanup()
		}

		res, err := HandleAddUserCore(ctx, callerUid, req.Role, req.User, req.Address, deps)
		if err != nil {
			log.Error("add_user core error: "+err.Error(), zap.String("callerUid", callerUid))
			writeAddUserError(w, err)
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
}

// buildRealAddUserDeps wires the real Firebase clients (Auth, Firestore) for a
// single request. The returned cleanup closes the Firestore client.
func buildRealAddUserDeps(ctx context.Context) (AddUserDeps, func(), error) {
	app, err := utils.InitializeFirebase(ctx)
	if err != nil {
		return AddUserDeps{}, nil, fmt.Errorf("firebase admin initialization error: %w", err)
	}
	authClient, err := app.Auth(ctx)
	if err != nil {
		return AddUserDeps{}, nil, fmt.Errorf("firebase auth client error: %w", err)
	}
	fs, err := app.Firestore(ctx)
	if err != nil {
		return AddUserDeps{}, nil, fmt.Errorf("firestore client error: %w", err)
	}

	prefix := utils.GetCollectionPrefix()
	log, _ := utils.InitializeLogger("add_user")
	cleanup := func() { _ = fs.Close() }

	return AddUserDeps{
		GetUser: func(ctx context.Context, uid string) (map[string]any, error) {
			doc, dErr := fs.Collection(prefix + "users").Doc(uid).Get(ctx)
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
			doc, dErr := fs.Collection(prefix + "companies").Doc(companyId).Get(ctx)
			if dErr != nil {
				return "", dErr
			}
			mt, _ := doc.Data()["management_type"].(string)
			return mt, nil
		},
		CreateAuthUser: func(ctx context.Context, email, password, displayName string) (string, error) {
			params := (&auth.UserToCreate{}).Email(email).Password(password)
			if displayName != "" {
				params = params.DisplayName(displayName)
			}
			rec, cErr := authClient.CreateUser(ctx, params)
			if cErr != nil {
				if auth.IsEmailAlreadyExists(cErr) {
					return "", ErrEmailExists
				}
				return "", cErr
			}
			return rec.UID, nil
		},
		GetAuthUIDByEmail: func(ctx context.Context, email string) (string, error) {
			rec, gErr := authClient.GetUserByEmail(ctx, email)
			if gErr != nil {
				return "", gErr
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
		SendInvite: func(ctx context.Context, email, displayName, role string) error {
			if err := sendPasswordSetupEmail(ctx, authClient, fs, prefix, utils.GetSubdomain(), email, displayName, role); err != nil {
				log.Error("addUser: invite email failed", zap.String("email", email), zap.String("error", err.Error()))
				return err
			}
			return nil
		},
		GeneratePassword: utils.GenerateRandomPassword,
	}, cleanup, nil
}

// AddUser provisions a new user on behalf of an authenticated company admin:
// mints a Firebase Auth account, atomically writes users/{uid} + address, and
// emails a set-password invite. See HandleAddUserCore for the business logic.
func AddUser(w http.ResponseWriter, r *http.Request) {
	AddUserHandler(utils.ValidateRequestV2, buildRealAddUserDeps)(w, r)
}

// writeAddUserError maps core sentinels onto HTTP status codes.
func writeAddUserError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrInvalidRole), errors.Is(err, ErrMissingEmail):
		http.Error(w, err.Error(), http.StatusBadRequest)
	case errors.Is(err, ErrCallerNotFound), errors.Is(err, ErrCallerNotAdmin), errors.Is(err, ErrCallerNoCompany), errors.Is(err, ErrRoleNotAllowed):
		http.Error(w, err.Error(), http.StatusForbidden)
	case errors.Is(err, ErrEmailExists):
		http.Error(w, err.Error(), http.StatusConflict)
	default:
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}
