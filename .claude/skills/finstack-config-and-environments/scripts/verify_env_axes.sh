#!/usr/bin/env bash
# verify_env_axes.sh — print every environment/prefix implementation side by
# side so a human or model can eyeball drift between them.
# READ-ONLY: greps and prints; changes nothing, calls no cloud APIs.
# Usage: .claude/skills/finstack-config-and-environments/scripts/verify_env_axes.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"

section() { printf '\n=== %s ===\n' "$1"; }

section "Firestore prefix 1/3 — Flutter (base_firestore_service.dart)"
grep -n -A 10 "String get collectionPrefix" \
  packages/core/loooans_helpers/lib/src/data_helpers/database/base_firestore_service.dart

section "Firestore prefix 2/3 — Go (environment_utils.go, full file)"
cat functions/loans/utils/environment_utils.go

section "Firestore prefix 3/3 — deploy script computation"
grep -n -B 1 -A 8 'collectionPrefix="dev_"' .github/scripts/deploy_functions.sh

section "Deploy-script trigger path patterns (must all carry \${collectionPrefix})"
grep -n -o 'path-pattern=document="[^"]*"' .github/scripts/deploy_functions.sh

section "RTDB env node — Flutter base service (dbRef getter)"
sed -n '7,19p' packages/core/loooans_helpers/lib/src/data_helpers/database/base_realtime_database_service.dart

section "RTDB env node — Flutter chat typing (_prefix)"
grep -n -A 9 "String get _prefix" \
  packages/core/chat_repository/lib/src/data/database/typing_service.dart

section "RTDB env node — Go local getPathEnv (loan_changes.go)"
grep -n -A 13 "func getPathEnv" functions/loans/triggers/loan_changes.go

section "RTDB instance URLs (initialize_firebase.go)"
grep -n "firebasedatabase.app" functions/loans/utils/initialize_firebase.go

section "Go ENVIRONMENT fatal-if-unset guard"
grep -n -A 4 "Runtime environment not defined" functions/loans/loooans_cloud_functions.go

section "Flutter ENVIRONMENT dart-define carriers (launch.json + CI web builds)"
grep -n "ENVIRONMENT=" apps/loans/.vscode/launch.json || true
grep -n -- "--dart-define=ENVIRONMENT" .github/workflows/loans-app-*.yml

section "Function deploy count (script says N in two places; deploy lines below)"
printf 'deploy lines: %s\n' "$(grep -c 'gcloud functions deploy' .github/scripts/deploy_functions.sh)"
grep -n 'All [0-9]* functions' .github/scripts/deploy_functions.sh

section "CI identities (WIF providers + service accounts)"
grep -n "workload_identity_provider\|service_account:" .github/workflows/loans-functions-*.yml

section "Secret mounts"
grep -n "ms-graph-client-secret" .github/scripts/deploy_functions.sh | head -2

section "Project aliases (.firebaserc)"
grep -n -A 4 '"projects"' apps/loans/.firebaserc

printf '\nDone. Compare the three Firestore prefix implementations and the three\n'
printf 'RTDB env-node implementations above — they must agree per environment.\n'
