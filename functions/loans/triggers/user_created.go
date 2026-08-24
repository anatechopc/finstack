package triggers

import (
	"context"
	"errors"
	"fmt"

	"cloud.google.com/go/firestore"
	"com.loooans.app/utils"
	firebase "firebase.google.com/go/v4"
	"github.com/cloudevents/sdk-go/v2/event"
	"github.com/golang/protobuf/proto"
	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
)

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

// UserCreatedDeps are the collaborators the core needs, injected so the
// welcome-email decision is unit-testable without Firebase.
type UserCreatedDeps struct {
	// GetUserEmail returns the Firebase Auth email for uid.
	GetUserEmail func(ctx context.Context, uid string) (string, error)
	// SendWelcomeEmail sends the "new_user" welcome/verify email to the address.
	SendWelcomeEmail func(ctx context.Context, email string) error
}

// HandleUserCreatedCore sends the welcome email for a newly-created user,
// unless the user was provisioned by an admin (which sends its own invite).
func HandleUserCreatedCore(ctx context.Context, uid string, skipWelcome bool, deps UserCreatedDeps) error {
	if skipWelcome {
		return nil
	}
	if uid == "" {
		return errors.New("user_created: missing uid")
	}
	email, err := deps.GetUserEmail(ctx, uid)
	if err != nil {
		return fmt.Errorf("user_created: get email for %q: %w", uid, err)
	}
	if email == "" {
		// No address to send to — nothing actionable.
		return nil
	}
	return deps.SendWelcomeEmail(ctx, email)
}

// UserCreated is the CloudEvent adapter. It wires real Firebase Auth + the
// in-process SendEmailActions into the core. Triggered by document.v1.created
// on users/{uid}.
//
// The welcome email is sent in-process (Firebase Auth lookup + MS Graph send),
// not via a self-call to the sendEmail HTTP endpoint with a minted custom
// token. That self-call was the only caller relying on the ParseUnverified
// fallback in ValidateRequestV2 (issue #71); removing it lets that insecure
// fallback be deleted.
func UserCreated(ctx context.Context, event event.Event) error {
	log, logErr := utils.InitializeLogger("user_created")

	if logErr != nil {
		return logErr
	}

	var data firestoredata.DocumentEventData

	if err := proto.Unmarshal(event.Data(), &data); err != nil {
		return fmt.Errorf("proto.Unmarshal: %w", err)
	}

	log.Debug(fmt.Sprintf("Function triggered by change to: %v\n", event.Source()))
	log.Debug(fmt.Sprintf("Old value: %+v\n", data.GetOldValue()))
	log.Debug(fmt.Sprintf("New value: %+v\n", data.GetValue()))

	if data.GetValue() == nil {
		log.Error("No value for newly created doc")
		return errors.New("no value for newly created doc")
	}

	var uid string

	if vId, ok := data.GetValue().GetFields()["id"]; ok {
		uid = vId.GetStringValue()
	} else {
		return fmt.Errorf("no id for user: %s", data.GetValue().GetName())
	}

	app, errFirebaseAdmin := utils.InitializeFirebase(ctx)

	if errFirebaseAdmin != nil {
		return errFirebaseAdmin
	}

	authClient, errAuthClient := app.Auth(ctx)

	if errAuthClient != nil {
		return errAuthClient
	}

	// Write search_tokens for the new user unconditionally — including
	// admin-provisioned users that skip the welcome email below. Done here
	// rather than in HandleUserCreatedCore so that skip decision (which only
	// governs the welcome email) can't also make a user unfindable in
	// search. Best-effort: a failure degrades search but must not fail the
	// trigger, which also carries the (more important) welcome email and
	// would otherwise retry it too.
	if tokens, needsWrite := SearchTokensForUser(flattenFields(data.GetValue().GetFields())); needsWrite {
		if err := writeUserSearchTokens(ctx, app, uid, tokens); err != nil {
			log.Sugar().Warnf("user_created: write search tokens for %s: %v", uid, err)
		}
	}

	deps := UserCreatedDeps{
		GetUserEmail: func(ctx context.Context, uid string) (string, error) {
			u, gErr := authClient.GetUser(ctx, uid)
			if gErr != nil {
				return "", gErr
			}
			return u.Email, nil
		},
		SendWelcomeEmail: func(_ context.Context, email string) error {
			return utils.SendEmailActions("new_user", []string{email})
		},
	}

	return HandleUserCreatedCore(ctx, uid, ShouldSkipWelcomeEmail(data.GetValue().GetFields()), deps)
}

// writeUserSearchTokens merges the given search_tokens onto users/{uid}.
func writeUserSearchTokens(ctx context.Context, app *firebase.App, uid string, tokens []string) error {
	fs, fsErr := app.Firestore(ctx)
	if fsErr != nil {
		return fmt.Errorf("firestore client: %w", fsErr)
	}
	defer fs.Close()

	docRef := fs.Doc(utils.GetCollectionPrefix() + "users/" + uid)
	_, err := docRef.Set(ctx, map[string]any{"search_tokens": tokens}, firestore.MergeAll)
	return err
}
