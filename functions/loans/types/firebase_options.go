package types

type FirebaseOptions struct {
	Type string `json:"type"`

	// Service Account fields
	ClientEmail             string `json:"client_email"`
	ClientID                string `json:"client_id"`
	PrivateKeyID            string `json:"private_key_id"`
	PrivateKey              string `json:"private_key"`
	AuthURL                 string `json:"auth_uri"`
	TokenURL                string `json:"token_uri"`
	ProjectID               string `json:"project_id"`
	AuthProviderX509CertUrl string `json:"auth_provider_x509_cert_url"`
	ClientX509CertUrl       string `json:"client_x509_cert_url"`
	UniverseDomain          string `json:"universe_domain"`
}
