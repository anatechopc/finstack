# CLAUDE.md

Instructions for Claude Code when working in the loans Cloud Functions.

> **Monorepo context**: These functions live at `functions/loans/` inside the **finstack** monorepo. CI/CD workflows are at `../../.github/workflows/loans-functions-*.yml`. See the root `CLAUDE.md` for the full monorepo layout.

For detailed documentation, see `docs/`.

## Build & Test

```bash
go build -v ./...     # Build all packages
go test -v ./...      # Run all tests
```

No Makefile or task runner — use standard Go tooling.

## Project Layout

```
loooans_cloud_functions.go   # Entry point — all functions registered in init()
api/                         # HTTP handlers
triggers/                    # Firestore CloudEvent handlers
utils/                       # Shared utilities (logger, auth, email, env config)
types/                       # Shared data types
job/                         # Scheduled jobs (currently disabled)
```

Each subdirectory is a separate Go module with its own `go.mod`/`go.sum`. The root `go.mod` uses `replace` directives to reference them locally.

## Rules

### Do

- Register every new function in `loooans_cloud_functions.go` `init()`
- Use `utils.InitializeLogger("functionName")` at the start of every handler
- Use `utils.ValidateRequestV2()` for auth in HTTP handlers
- Use `utils.GetEnvironment()` for environment-specific config (collection prefixes, URLs)
- Run `go mod tidy` in the sub-module directory when adding dependencies to a sub-module
- Follow the existing HTTP handler pattern: CORS headers → validate JWT → parse body → respond with JSON
- Follow the existing trigger pattern: init logger → unmarshal protobuf → extract fields → business logic → return error or nil
- Use environment-based collection prefixes for Firestore paths (e.g., `dev_users/{uid}`)

### Don't

- Don't hardcode collection prefixes — always use the environment config
- Don't skip JWT validation in HTTP handlers
- Don't add dependencies to the root `go.mod` if they belong to a sub-module
- Don't push directly to `master` — it deploys to production

## Common Tasks

### Add a new HTTP function

1. Create the handler in `api/` following existing patterns
2. Register it in `loooans_cloud_functions.go` with `functions.HTTP("name", handler)`
3. Run `go mod tidy` in `api/` if new dependencies were added
4. Run `go build -v ./...` to verify

### Add a new Firestore trigger

1. Create the handler in `triggers/` following existing patterns
2. Register it in `loooans_cloud_functions.go` with `functions.CloudEvent("name", handler)`
3. Use the environment-prefixed collection path
4. Run `go mod tidy` in `triggers/` if new dependencies were added
5. Run `go build -v ./...` to verify

### Add a new shared utility

1. Add it to `utils/`
2. Run `go mod tidy` in `utils/`
3. Run `go mod tidy` in any module that imports it

## Deployment

Automated via GitHub Actions — pushing to a branch triggers the corresponding deploy:

| Branch | Environment | GCP Project |
|---|---|---|
| `develop` | development | `loooans-dev-stg` |
| `release/**` | staging | `loooans-dev-stg` |
| `master` | production | `loooans-prod` |

The `ENVIRONMENT` env var (`development`, `staging`, `production`) is required at runtime.

## Reference Docs

- [Project Overview](docs/project-overview.md) — tech stack, integrations
- [Architecture](docs/architecture.md) — module details, patterns, function registration
- [Deployment](docs/deployment.md) — CI/CD pipeline, branch mapping, manual deploy
