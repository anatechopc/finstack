package types

type MailContainer struct {
	Message Mail `json:"message"`
}
type Mail struct {
	Subject      string                  `json:"subject"`
	ToRecipients []EmailAddressContainer `json:"toRecipients"`
	Body         MailBody                `json:"body"`
}

type EmailAddressContainer struct {
	Email EmailAddress `json:"emailAddress"`
}

type EmailAddress struct {
	Address string `json:"address"`
}

type MailBody struct {
	ContentType string `json:"contentType"`
	Content     string `json:"content"`
}
