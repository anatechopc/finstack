#!/usr/bin/env bash
# Read recent logs for a deployed finstack Cloud Function (gen2).
#
# Usage:
#   fn-logs.sh <entryPoint> <development|staging|production> [limit]
# Examples:
#   fn-logs.sh notificationCreated development
#   fn-logs.sh requestOtp production 100
#
# Function names in GCP are "<entryPoint>_<environment>" (see
# .github/scripts/deploy_functions.sh). Region is asia-east1 for all
# functions. dev+staging live in loooans-dev-stg; prod in loooans-prod.
# Full log-reading runbook: ../references/cloud-functions-logs.md
set -euo pipefail

usage="usage: fn-logs.sh <entryPoint> <development|staging|production> [limit]"
fn="${1:?$usage}"
env="${2:?$usage}"
limit="${3:-50}"

case "$env" in
  development|staging) project="loooans-dev-stg" ;;
  production)          project="loooans-prod" ;;
  *) echo "env must be development|staging|production (got: $env)" >&2; exit 2 ;;
esac

exec gcloud functions logs read "${fn}_${env}" \
  --region=asia-east1 \
  --project="$project" \
  --limit="$limit" \
  --gen2
