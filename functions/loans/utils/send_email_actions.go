package utils

import "fmt"

func SendEmailActions(action string, recipients []string) error {
	log, errLog := InitializeLogger("send_email_actions")

	if errLog != nil {
		return errLog
	}

	log.Debug(fmt.Sprintf("ACTION: %s", action))

	subject := "Thank you"
	body := "Hello world"

	if action == "new_user" {
		subject = "Verify your account"
		/**
		Hi Ka-Loooans!

		Welcome to Loooans! where we empower individuals and micro enterprises alike to leverage their financial capabilities to its fullest.

		In this time of need, some people resort to scamming and identity fraud. This is something we don't want to happen as it will reduce our capacity to serve the people that really needs our help.

		To combat these, we will be verifying your identity through the following methods:
		1. AI Verification - We will verify your identity through a third party application called Veriff.
		2. Mobile number authentication- Upon your first login, we will verify your mobile number as well. This will increase the confidence of the loan providers that you will really be contacted when they needed.

		To start, please open the following link: <veriff link here>

		Thank you for your cooperation.

		From: Ka-Loooans! Team
		*/
		body = fmt.Sprintf(`<p>Hi Ka-Loooans!</p><p>Welcome to Loooans! where we empower individuals and micro enterprises alike to leverage their financial capabilities to its fullest.</p><p>In this time of need, some people resort to scamming and identity fraud. This is something we don't want to happen as it will reduce our capacity to serve the people that really needs our help.</p><p>To combat these, we will be verifying your identity through the following methods:</br><ol><li>AI Verification - We will verify your identity through a third party application called Veriff.</li><li>Mobile number authentication- Upon your first login, we will verify your mobile number as well. This will increase the confidence of the loan providers that you will really be contacted when they needed.</li></ol></p><p>To start, please open the following link:%s</p><p>Thank you for your cooperation.</p></br><p>From: Ka-Loooans! team</p>`, "https://someverifflinkhere.com")
	}

	if _, err := SendEmail(subject, body, recipients); err != nil {
		return err
	}

	return nil
}
