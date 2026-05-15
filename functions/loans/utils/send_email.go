package utils

import (
	"bytes"
	"com.loooans.app/types"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
)

func SendEmail(subject string, emailBody string, recipients []string) (bool, error) {
	log, errLog := InitializeLogger("send_email")

	if errLog != nil {
		return false, errLog
	}

	// Credentials are injected at deploy time via Cloud Functions env vars
	// (MS_GRAPH_TENANT_ID, MS_GRAPH_CLIENT_ID) and Google Secret Manager
	// (MS_GRAPH_CLIENT_SECRET). Fail fast if any are missing so the caller
	// surfaces a meaningful error instead of a downstream
	// "JWT not well formed" from Microsoft Graph.
	tenantId := os.Getenv("MS_GRAPH_TENANT_ID")
	clientId := os.Getenv("MS_GRAPH_CLIENT_ID")
	clientSecret := os.Getenv("MS_GRAPH_CLIENT_SECRET")
	if tenantId == "" || clientId == "" || clientSecret == "" {
		return false, fmt.Errorf("send_email: missing required env vars (MS_GRAPH_TENANT_ID=%v, MS_GRAPH_CLIENT_ID=%v, MS_GRAPH_CLIENT_SECRET=%v)", tenantId != "", clientId != "", clientSecret != "")
	}

	log.Info("Requesting token from microsoft")

	scope := "https://graph.microsoft.com/.default"
	tokenUrl := fmt.Sprintf("https://login.microsoftonline.com/%s/oauth2/v2.0/token", tenantId)

	// url.Values.Encode() already URL-encodes values; do not pre-escape.
	tokenUrlParams := url.Values{}
	tokenUrlParams.Set("client_id", clientId)
	tokenUrlParams.Set("client_secret", clientSecret)
	tokenUrlParams.Set("scope", scope)
	tokenUrlParams.Set("grant_type", "client_credentials")
	tokenReq, err := http.NewRequest(http.MethodPost, tokenUrl, strings.NewReader(tokenUrlParams.Encode()))

	if err != nil {
		return false, err
	}

	tokenReq.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	tokenReq.Header.Set("Host", "login.microsoftonline.com")

	client := &http.Client{}

	res, errResponse := client.Do(tokenReq)

	if errResponse != nil {
		return false, errResponse
	}

	defer res.Body.Close()
	resBody, _ := io.ReadAll(res.Body)

	// If Microsoft rejects our credentials (e.g. expired client secret), the
	// response is non-2xx with an error body. Surface it directly so the
	// caller sees the actual reason (e.g. "invalid_client") instead of a
	// generic failure when the JSON happens to parse.
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		log.Error(fmt.Sprintf("microsoft token request failed: status=%d body=%s", res.StatusCode, string(resBody)))
		return false, fmt.Errorf("microsoft token request failed: status=%d body=%s", res.StatusCode, string(resBody))
	}

	var responseJsonBody map[string]any

	errResponseJsonBody := json.Unmarshal(resBody, &responseJsonBody)

	if errResponseJsonBody != nil {
		return false, errResponseJsonBody
	}

	log.Info("Response token success")
	log.Debug(fmt.Sprintf("response Token: %v", responseJsonBody))
	// access_token, bearer, expires_in, ext_expires_in
	accessToken, hasAccessToken := responseJsonBody["access_token"].(string)
	tokenType, _ := responseJsonBody["token_type"].(string)
	if !hasAccessToken || accessToken == "" {
		log.Error(fmt.Sprintf("microsoft token response missing access_token: body=%s", string(resBody)))
		return false, fmt.Errorf("microsoft token response missing access_token: body=%s", string(resBody))
	}
	sendMailUrl := "https://graph.microsoft.com/v1.0/users/no-reply@loooans.com/sendMail"

	var toRecipients []types.EmailAddressContainer

	for _, recipient := range recipients {
		toRecipients = append(toRecipients, types.EmailAddressContainer{
			Email: types.EmailAddress{
				Address: recipient,
			},
		})
	}

	log.Debug(fmt.Sprintf("toRecipients: %v", toRecipients))

	mailContainer := types.MailContainer{
		Message: types.Mail{
			Subject: subject,
			Body: types.MailBody{
				ContentType: "html",
				Content:     emailBody,
			},
			ToRecipients: toRecipients,
		},
	}
	somebyte, _ := json.Marshal(mailContainer)

	log.Debug("something: " + string(somebyte))
	sendMailReq, errSendMail := http.NewRequest(http.MethodPost, sendMailUrl, bytes.NewReader(somebyte))

	if errSendMail != nil {
		return false, errSendMail
	}

	sendMailReq.Header.Set("Authorization", fmt.Sprintf("%s %s", tokenType, accessToken))
	sendMailReq.Header.Set("Content-Type", "application/json")

	sendMailClient := &http.Client{}

	sendMailResponse, errSendMailReq := sendMailClient.Do(sendMailReq)
	if errSendMailReq != nil {
		return false, errSendMailReq
	}
	defer sendMailResponse.Body.Close()

	log.Debug(fmt.Sprintf("Status code: %d", sendMailResponse.StatusCode))

	sendMailBody, _ := io.ReadAll(sendMailResponse.Body)

	if sendMailResponse.StatusCode <= http.StatusAccepted {
		log.Info("Email sent!")
		return true, nil
	}

	log.Error(fmt.Sprintf("microsoft sendMail failed: status=%d body=%s", sendMailResponse.StatusCode, string(sendMailBody)))
	return false, fmt.Errorf("microsoft sendMail failed: status=%d body=%s", sendMailResponse.StatusCode, string(sendMailBody))
}
