package utils

import (
	"context"
	"os"

	firebase "firebase.google.com/go/v4"
)

// InitializeFirebase initializes the Firebase Admin app.
//
// Credentials come from Application Default Credentials: on Cloud Functions
// this is the function's runtime service account (resolved via the metadata
// server), so deploy the functions with --service-account set to an identity
// that has Firebase access (Firestore / RTDB / Auth). No service-account key is
// embedded in the source — a previously hardcoded key was exposed and disabled
// by Google; never re-embed one.
//
// For local runs, provide ADC out of band, e.g.
// `gcloud auth application-default login` or GOOGLE_APPLICATION_CREDENTIALS.
func InitializeFirebase(ctx context.Context) (*firebase.App, error) {
	dbURL := "https://loooans-dev-stg-default-rtdb.asia-southeast1.firebasedatabase.app"
	if os.Getenv("ENVIRONMENT") == "production" {
		dbURL = "https://loooans-prod-default-rtdb.asia-southeast1.firebasedatabase.app"
	}

	conf := &firebase.Config{
		DatabaseURL: dbURL,
	}

	app, err := firebase.NewApp(ctx, conf)
	if err != nil {
		return nil, err
	}

	return app, nil
}
