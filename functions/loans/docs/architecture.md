# Architecture

## Multi-Module Structure

The project uses a multi-module structure with local `replace` directives in the root `go.mod`. Each sub-module has its own `go.mod`/`go.sum`.

```
loooans_cloud_functions/
├── loooans_cloud_functions.go   # Entry point — registers all functions in init()
├── api/                         # HTTP endpoint handlers
├── triggers/                    # Firestore-triggered CloudEvent handlers
├── utils/                       # Shared utilities
├── types/                       # Shared data types
└── job/                         # Scheduled/background jobs (currently disabled)
```

### Module Details

| Module | Purpose | Examples |
|---|---|---|
| **Root** (`com.loooans.app`) | Entry point. Registers all functions in `init()`, starts the Functions Framework. | `loooans_cloud_functions.go` |
| **`api/`** | HTTP endpoint handlers. Each sets CORS headers and validates Firebase JWT tokens. | `requestOtp`, `sendEmail` |
| **`triggers/`** | Firestore-triggered CloudEvent handlers. Unmarshal protobuf `DocumentEventData`, extract fields, perform side effects. | `userCreated`, `loanChanges`, `paymentCreated` |
| **`utils/`** | Shared utilities: Firebase init, zap logger, email (Microsoft Graph), JWT validation, environment config. | `InitializeLogger`, `ValidateRequestV2`, `GetEnvironment` |
| **`types/`** | Shared data types. | `User`, `Mail`, `FirebaseOptions` |
| **`job/`** | Scheduled/background jobs (currently disabled). | — |

## Function Registration

All cloud functions are registered in `loooans_cloud_functions.go`:

- **HTTP functions**: `functions.HTTP("name", handler)` — called via HTTP trigger
- **Firestore triggers**: `functions.CloudEvent("name", handler)` — fired on Firestore document events

Firestore triggers use collection paths with environment-based prefixes (e.g., `dev_users/{uid}`, `stg_loans/{uid}`).

## Key Patterns

### HTTP Handler Pattern

```
Set CORS headers → validate JWT → parse JSON body → perform operations → respond with JSON or HTTP error
```

- Auth validation via `utils.ValidateRequestV2()` — extracts and verifies Firebase JWT from `Authorization: Bearer <token>` header, returns user UID on success.

### Trigger Handler Pattern

```
Initialize logger → unmarshal CloudEvent protobuf → extract document fields → perform business logic (update Realtime DB, send notifications) → return error or nil
```

### Logging

Uber `zap` throughout. Initialize per function with `utils.InitializeLogger("name")`. Production uses zap production config; development uses dev config.

### Environment Branching

`utils.GetEnvironment()` returns config based on the `ENVIRONMENT` env var. This affects:
- Firestore collection prefixes
- Realtime Database URLs
- Subdomain routing
