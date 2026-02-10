# Loooans Cloud Functions

Backend for the Loooans lending platform, built with Google Cloud Functions (2nd generation) in Go.

## Project Overview

Loooans Cloud Functions provides the serverless backend for the Loooans lending platform. It handles user authentication, OTP verification, email notifications, and reacts to Firestore document events (user creation, loan changes, payments, and more). The functions deploy to GCP region `asia-east1` using the [Functions Framework for Go](https://github.com/GoogleCloudPlatform/functions-framework-go).

## Tech Stack

- **Language**: Go 1.22
- **Runtime**: Google Cloud Functions (2nd generation)
- **Database**: Cloud Firestore (document DB) + Firebase Realtime Database (OTP, real-time state)
- **Auth**: Firebase Authentication with JWT token validation
- **Email**: Microsoft Graph API (Azure AD tenant/client credentials)
- **SMS**: TransmitSMS API
- **Logging**: Uber zap
- **CI/CD**: GitHub Actions with OIDC workload identity federation

## Project Structure

```
loooans_cloud_functions/
├── loooans_cloud_functions.go   # Entry point — registers all functions in init()
├── api/                         # HTTP endpoint handlers
├── triggers/                    # Firestore-triggered CloudEvent handlers
├── utils/                       # Shared utilities (logger, auth, email, env config)
├── types/                       # Shared data types
└── job/                         # Scheduled/background jobs (currently disabled)
```

Each subdirectory is a separate Go module with its own `go.mod`/`go.sum`. The root `go.mod` uses `replace` directives to reference them locally.

## Registered Functions

### HTTP Functions

| Function | Description |
|---|---|
| `requestOtp` | Request a one-time password for user verification |
| `sendEmail` | Send an email via Microsoft Graph API |
| `sometest` | Test endpoint |

### Firestore Triggers

| Function | Description |
|---|---|
| `userCreated` | Fires when a new user document is created |
| `loanChanges` | Fires when a loan document is updated |
| `loanScheduleChanges` | Fires when a loan schedule document changes |
| `capitalCreated` | Fires when a new capital document is created |
| `notificationCreated` | Fires when a new notification document is created |
| `reviewCreated` | Fires when a new review document is created |
| `paymentCreated` | Fires when a new payment document is created |

## Key Integrations

- **OTP**: HMAC-SHA256 based, stored in Realtime Database at `otp/{userId}` with 5-minute expiry. Delivered via email or SMS.
- **Email**: Sent via Microsoft Graph API using Azure AD tenant/client credentials.
- **Notifications**: Triggered by Firestore document events (user creation, loan changes, payments).

## Build & Test

```bash
go build -v ./...     # Build all packages
go test -v ./...      # Run all tests
```

## Deployment

Automated via GitHub Actions. Pushing to a branch triggers the corresponding workflow:

| Branch | Environment | GCP Project | Collection Prefix |
|---|---|---|---|
| `develop` | development | `loooans-dev-stg` | `dev_` |
| `release/**` | staging | `loooans-dev-stg` | `stg_` |
| `master` | production | `loooans-prod` | (none) |

The `ENVIRONMENT` env var (`development`, `staging`, `production`) is required at runtime.

### Manual Deployment

```bash
.github/scripts/deploy_functions.sh -e <environment> -p <project>
```

## Environment Configuration

The app uses the `ENVIRONMENT` env var to determine runtime behavior:

- **Firestore collection prefixes** (e.g., `dev_users`, `stg_loans`)
- **Realtime Database URLs**
- **Subdomain routing**

The application will exit if `ENVIRONMENT` is not set.
