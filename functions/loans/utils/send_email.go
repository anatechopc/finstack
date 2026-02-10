package utils

import (
	"bytes"
	"com.loooans.app/types"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
)

func SendEmail(subject string, emailBody string, recipients []string) (bool, error) {
	log, errLog := InitializeLogger("send_email")

	if errLog != nil {
		return false, errLog
	}

	log.Info("Requesting token from microsoft")

	// for microsoft to send email
	tenantId := "9df89475-8709-4ec5-82f0-4cb73ebdc92b"
	clientId := "d5b456ce-6c94-47e9-a904-f071382fb4f6"
	clientSecret := "d3t8Q~LRHJTrXlhOFVkB.tJ.MZnVYMRY33WaFbLe"
	scope := "https://graph.microsoft.com/.default"
	tokenUrl := fmt.Sprintf("https://login.microsoftonline.com/%s/oauth2/v2.0/token", tenantId)

	tokenUrlParams := url.Values{}
	tokenUrlParams.Set("client_id", clientId)
	tokenUrlParams.Set("client_secret", url.QueryEscape(clientSecret))
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

	var responseJsonBody map[string]any

	errResponseJsonBody := json.Unmarshal(resBody, &responseJsonBody)

	if errResponseJsonBody != nil {
		return false, errResponseJsonBody
	}

	log.Info("Response token success")
	log.Debug(fmt.Sprintf("response Token: %v", responseJsonBody))
	// access_token, bearer, expires_in, ext_expires_in
	accessToken := responseJsonBody["access_token"]
	tokenType := responseJsonBody["token_type"]
	sendMailUrl := "https://graph.microsoft.com/v1.0/users/no-reply@loooans.com/sendMail"
	log.Debug("accessToken: " + fmt.Sprintf("%s", accessToken))

	//something := fmt.Sprintf(`{"message":{"subject":"Credentials","toRecipients":[{"emailAddress":{"address":"%s"}}],"body":{"contentType":"html","content":"%s"}}}`, parsedBody.Email, createHtmlBody(parsedBody.DisplayName, parsedBody.Email, parsedBody.Password))

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
	//log.Debug("something: " + something)
	sendMailReq, errSendMail := http.NewRequest(http.MethodPost, sendMailUrl, bytes.NewReader(somebyte))
	//sendMailReq, errSendMail := http.NewRequest(http.MethodPost, sendMailUrl, strings.NewReader(something))

	if errSendMail != nil {
		return false, errSendMail
	}

	sendMailReq.Header.Set("Authorization", fmt.Sprintf("%s %s", tokenType, accessToken))
	sendMailReq.Header.Set("Content-Type", "application/json")

	sendMailClient := &http.Client{}

	sendMailResponse, errSendMailReq := sendMailClient.Do(sendMailReq)
	defer sendMailResponse.Body.Close()

	log.Debug(fmt.Sprintf("Status code: %d", sendMailResponse.StatusCode))

	var responseBody map[string]interface{}
	if responseBodyDecodeErr := json.NewDecoder(sendMailResponse.Body).Decode(&responseBody); responseBodyDecodeErr != nil {
		return false, responseBodyDecodeErr
	}
	log.Debug(fmt.Sprintf("respoeBody: %s", responseBody))

	// status
	if sendMailResponse.StatusCode <= http.StatusAccepted {
		log.Info("Email sent!")
		return true, nil
	}

	if errSendMailReq != nil {
		return false, errSendMailReq
	}

	return false, errors.New("unknown error")
}
