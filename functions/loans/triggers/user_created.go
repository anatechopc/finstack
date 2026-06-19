package triggers

import (
	"bytes"
	"com.loooans.app/utils"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/cloudevents/sdk-go/v2/event"
	"github.com/golang/protobuf/proto"
	"github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
	"go.uber.org/zap"
	"net/http"
	"os"
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
		return errors.New(fmt.Sprintf("No email address for user: %s", data.GetValue().GetName()))
	}

	if ShouldSkipWelcomeEmail(data.GetValue().GetFields()) {
		log.Debug("user_created: invited_by_admin set, skipping generic welcome email")
		return nil
	}

	app, errFirebaseAdmin := utils.InitializeFirebase(ctx)

	if errFirebaseAdmin != nil {
		return errFirebaseAdmin
	}

	authClient, errAuthClient := app.Auth(ctx)

	if errAuthClient != nil {
		return errAuthClient
	}

	token, errToken := authClient.CustomToken(ctx, uid)

	if errToken != nil {
		return errToken
	}

	// send email http here
	env := os.Getenv("ENVIRONMENT")
	subdomain := ""

	switch env {
	case "development":
		subdomain = "dev."
		break
	case "staging":
		subdomain = "stg."
		break
	}
	body := map[string]any{
		"action": "new_user",
	}
	bodyBytes, _ := json.Marshal(body)
	req, errReq := http.NewRequest(http.MethodPost, fmt.Sprintf("https://%sloooans.com/api/utils/sendEmail", subdomain), bytes.NewReader(bodyBytes))

	if errReq != nil {
		log.Error("new request error")
		return errReq
	}

	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", token))
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{}
	res, errRes := client.Do(req)

	if errRes != nil {
		log.Error("client.Do error")
		return errRes
	}

	defer res.Body.Close()

	log.Debug(fmt.Sprintf("status_code: %d", res.StatusCode))
	var resData string
	errParse := json.NewDecoder(res.Body).Decode(&resData)

	if errParse != nil {
		log.Error("Response data parse error", zap.String("error", errParse.Error()))
		return errParse
	}

	log.Debug(fmt.Sprintf("response: %s", resData))

	return nil
}
