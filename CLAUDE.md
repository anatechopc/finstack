# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Structure

This is a monorepo (**finstack**) with shared packages and multiple apps/functions sharing Firebase backends:

| Directory | Stack | Purpose |
|-----------|-------|---------|
| `apps/loans/` | Flutter (Dart) | Loans marketplace mobile/web app |
| `functions/loans/` | Go | Serverless Cloud Functions (Firestore triggers + HTTP endpoints) |
| `packages/core/` | Flutter (Dart) | Shared packages reusable across all future apps |
| `packages/loans/` | Flutter (Dart) | Loans-domain-specific packages |

Each sub-project has its own CLAUDE.md with project-specific rules and commands:
- **Flutter App**: `apps/loans/CLAUDE.md` (also see `ARCHITECTURE.md`)
- **Go Functions**: `functions/loans/CLAUDE.md` (also see `docs/`)

## High-Level Architecture

```
┌─────────────────────────┐     ┌──────────────────────────────┐
│   Flutter App (Dart)    │     │   Go Cloud Functions (GCP)   │
│                         │     │                              │
│  BLoC → Repositories    │────▶│  HTTP: requestOtp, sendEmail │
│  → Firebase Services    │     │  Triggers: loanChanges,      │
│                         │     │    paymentCreated,            │
│  Reads/writes Firestore │     │    notificationCreated, etc.  │
│  Reads notifications    │     │  Writes reports to RTDB       │
│  Manages FCM tokens     │     │  Sends FCM push via triggers  │
└─────────────────────────┘     └──────────────────────────────┘
         │                                    │
         └──────────┐    ┌────────────────────┘
                    ▼    ▼
           ┌─────────────────────┐
           │   Firebase Backend  │
           │  Firestore (docs)   │
           │  Realtime DB (RTDB) │
           │  Cloud Storage      │
           │  Auth / FCM         │
           └─────────────────────┘
```

**Data flow**: The Flutter app writes documents to Firestore. Go Cloud Functions fire on document mutations (loans, payments, reviews) to update RTDB reports, create notification documents, and send FCM push notifications. The Flutter app reads those notifications and RTDB reports in real-time.

**Notification ownership**: Notification creation is server-side (Go triggers), not in the Flutter app. The Flutter `NotificationService` only manages FCM tokens and displays notifications.

## Package Organization

Packages under `packages/` are split into two groups:

- **`packages/core/`** — Generic, reusable packages (helpers, auth, user, company, address, bank_details, notification, storage repositories). These can be shared by future apps (budgeting, HRIS, etc.).
- **`packages/loans/`** — Loans-domain packages (loan, payment, capital, product, review, etc. repositories). These are specific to the loans app.

Cross-boundary dependencies exist:
- `packages/core/user_repository` → `packages/loans/user_loan_view_repository`
- `packages/core/company_repository` → `packages/loans/product_view_repository`
- All loans packages → `packages/core/loooans_helpers`

## Environments

| Environment | Firebase Project | Flutter Flavor | Go Branch |
|-------------|-----------------|----------------|-----------|
| Development | `loooans-dev-stg` | `development` | `develop` |
| Staging | `loooans-dev-stg` | `staging` | `release/**` |
| Production | `loooans-prod` | `production` | `master` |

Development and staging share the Firebase project `loooans-dev-stg` but are separated by Firestore collection prefixes (`dev_`, `stg_`). Production uses `loooans-prod` with no prefix.

## Quick Reference Commands

### Flutter App (`apps/loans/`)

```bash
# Always use fvm — never bare flutter
cd apps/loans
fvm flutter run --flavor development --target lib/main_development.dart
fvm flutter analyze
fvm flutter test --coverage --test-randomize-ordering-seed random
fvm flutter gen-l10n --arb-dir="lib/l10n/arb"  # Regenerate translations
```

### Packages (`packages/`)

```bash
cd packages
./get_dependencies.sh       # pub get all packages (core + loans)
./build_models.sh           # Regenerate all model code (core + loans)
./clean_package.sh          # Clean all packages
./update_dependencies.sh    # Upgrade all package dependencies
```

### Go Functions (`functions/loans/`)

```bash
cd functions/loans
go build -v ./...
go test -v ./...
# go mod tidy in sub-module dirs when adding deps
```

## Cross-Project Conventions

- Firestore collection paths must use environment-based prefixes — never hardcode `dev_` or `stg_`
- Both projects reference the same Firestore document schemas; changes to document structure must be coordinated
- Go triggers reference the same collection/document paths that Flutter repositories read/write
- Never push directly to `master` — it deploys the Go backend to production
