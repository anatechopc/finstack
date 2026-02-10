# Project Overview

Loooans Cloud Functions is a Google Cloud Functions (gen2) backend for the Loooans lending platform, written in Go 1.22. It uses the [Functions Framework for Go](https://github.com/GoogleCloudPlatform/functions-framework-go) and deploys to GCP region `asia-east1`.

## Tech Stack

- **Language**: Go 1.22
- **Runtime**: Google Cloud Functions (2nd generation)
- **Database**: Cloud Firestore (document DB) + Firebase Realtime Database (OTP, real-time state)
- **Auth**: Firebase Authentication with JWT token validation
- **Email**: Microsoft Graph API (tenant/client credentials)
- **SMS**: TransmitSMS API
- **Logging**: Uber zap
- **CI/CD**: GitHub Actions with OIDC workload identity federation

## Key Integrations

- **OTP**: HMAC-SHA256 based, stored in Realtime Database at `otp/{userId}` with 5-minute expiry. Delivered via email or SMS.
- **Email**: Sent via Microsoft Graph API using Azure AD tenant/client credentials.
- **Notifications**: Triggered by Firestore document events (user creation, loan changes, payments).
