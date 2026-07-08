#!/usr/bin/env bash
# check-deploy-status.sh — read-only deploy/ops status for finstack.
#
# Usage: check-deploy-status.sh [dev|stg|prod] [--gateway]
#
#   Lists the Cloud Functions actually deployed for the environment and diffs
#   them against the entry points declared in .github/scripts/deploy_functions.sh
#   on the CURRENT branch. With --gateway, also prints the SMS-gateway
#   heartbeat age from RTDB /gateway_status.
#
# Requirements: gcloud (authenticated via `gcloud auth login` — uses CLI
# credentials, NOT ADC), jq, python3. Read-only: only list/get calls.

set -euo pipefail

ENV="${1:-dev}"
CHECK_GATEWAY="${2:-}"

case "$ENV" in
  dev)  PROJECT="loooans-dev-stg"; SUFFIX="_development"
        RTDB="https://loooans-dev-stg-default-rtdb.asia-southeast1.firebasedatabase.app" ;;
  stg)  PROJECT="loooans-dev-stg"; SUFFIX="_staging"
        RTDB="https://loooans-dev-stg-default-rtdb.asia-southeast1.firebasedatabase.app" ;;
  prod) PROJECT="loooans-prod";    SUFFIX="_production"
        RTDB="https://loooans-prod-default-rtdb.asia-southeast1.firebasedatabase.app" ;;
  *) echo "Usage: $0 [dev|stg|prod] [--gateway]"; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
DEPLOY_SCRIPT="$REPO_ROOT/.github/scripts/deploy_functions.sh"

if [ ! -f "$DEPLOY_SCRIPT" ]; then
  echo "ERROR: cannot find $DEPLOY_SCRIPT" >&2
  exit 1
fi

echo "== Expected functions (entry points in deploy_functions.sh, current branch) =="
# HTTP blocks use '--entry-point name', trigger blocks use '--entry-point=name'.
expected="$(grep -oE -- '--entry-point[= ][A-Za-z]+' "$DEPLOY_SCRIPT" \
  | sed -E 's/--entry-point[= ]//' | sort -u)"
echo "$expected" | sed 's/^/  /'
echo "  (total: $(echo "$expected" | wc -l | tr -d ' '))"
echo

echo "== Deployed functions in $PROJECT (region asia-east1, suffix $SUFFIX) =="
deployed_raw="$(gcloud functions list --project "$PROJECT" --regions asia-east1 \
  --format='value(name,state)' 2>&1)" || {
    echo "gcloud functions list failed (auth? run: gcloud auth login):"
    echo "$deployed_raw"
    exit 1
  }
# v2 list may return full resource names; keep the last path segment.
deployed="$(echo "$deployed_raw" | awk '{n=$1; sub(".*/","",n); print n"\t"$2}' \
  | grep -E "^[A-Za-z]+${SUFFIX}\b" || true)"
if [ -z "$deployed" ]; then
  echo "  (none found with suffix $SUFFIX)"
else
  echo "$deployed" | sed 's/^/  /'
fi
echo

echo "== Diff (expected vs deployed) =="
deployed_names="$(echo "$deployed" | cut -f1 | sed "s/${SUFFIX}\$//" | sort -u)"
missing="$(comm -23 <(echo "$expected") <(echo "$deployed_names") || true)"
extra="$(comm -13 <(echo "$expected") <(echo "$deployed_names") || true)"
[ -n "$missing" ] && { echo "  MISSING (in script, not deployed):"; echo "$missing" | sed 's/^/    /'; }
[ -n "$extra" ]   && { echo "  EXTRA (deployed, not in script — orphan? e.g. old verifyPaymentOtp):"; echo "$extra" | sed 's/^/    /'; }
[ -z "$missing" ] && [ -z "$extra" ] && echo "  In sync."

if [ "$CHECK_GATEWAY" = "--gateway" ]; then
  echo
  echo "== SMS gateway heartbeat (/gateway_status on $RTDB) =="
  token="$(gcloud auth print-access-token)"
  status_json="$(curl -sf -H "Authorization: Bearer $token" "$RTDB/gateway_status.json")" || {
    echo "  RTDB read failed (needs RTDB read access for your gcloud CLI account)."
    exit 1
  }
  if [ "$status_json" = "null" ] || [ -z "$status_json" ]; then
    echo "  No gateway_status entries — gateway has never reported on this project."
  else
    echo "$status_json" | jq -r 'to_entries[] |
      "  device \(.key): \(.value.device_name // "?") status=\(.value.status // "?") last_heartbeat=\(.value.last_heartbeat // 0)"'
    now_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
    echo "$status_json" | jq -r --argjson now "$now_ms" 'to_entries[] |
      "  device \(.key): heartbeat age \((($now - (.value.last_heartbeat // 0)) / 1000 | floor))s \(if ($now - (.value.last_heartbeat // 0)) > 90000 then "-- STALE (>90s): gateway likely DOWN" else "-- OK" end)"'
  fi
fi
