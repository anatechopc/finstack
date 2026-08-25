#!/bin/bash

# Deploy Firestore composite indexes for one environment.
#
# Usage:
#   ./deploy-indexes.sh <dev|stg|prod>              deploy the committed snapshot
#   ./deploy-indexes.sh <dev|stg|prod> --refresh    pull live indexes INTO the
#                                                   committed snapshot, no deploy
#
# The committed per-env files are the source of truth:
#
#   firestore.indexes.dev.json    dev_*       -> loooans-dev-stg
#   firestore.indexes.stg.json    stg_*       -> loooans-dev-stg
#   firestore.indexes.prod.json   unprefixed  -> loooans-prod
#
# Development and staging share ONE project and ONE (default) database; they are
# separated only by the collection prefix, which is why each file is filtered by
# prefix rather than by project.
#
# `firestore.indexes.json` is a scratch artifact: firebase.json points at that
# path, so the chosen env file is copied over it immediately before deploying.
# Never edit it directly and never treat it as the source of truth.
#
# Prerequisites: firebase-cli (logged in), jq, and the projects below reachable.

set -euo pipefail

ENV="${1:-}"
MODE="${2:-deploy}"

if [ -z "$ENV" ]; then
  echo "Usage: $0 <dev|stg|prod> [--refresh]"
  exit 1
fi

case "$ENV" in
  dev|stg) PROJECT="loooans-dev-stg" ;;
  prod)    PROJECT="loooans-prod" ;;
  *)       echo "Invalid environment '$ENV'. Use 'dev', 'stg', or 'prod'."; exit 1 ;;
esac

case "$MODE" in
  deploy|--refresh) ;;
  *) echo "Invalid mode '$MODE'. Use '--refresh' or omit."; exit 1 ;;
esac

cd "$(dirname "$0")/.."

TARGET_INDEX_FILE="firestore.indexes.$ENV.json"

if [ ! -f "$TARGET_INDEX_FILE" ]; then
  echo "Missing $TARGET_INDEX_FILE"
  exit 1
fi

# --refresh pulls the live index set into the committed snapshot so console-made
# changes can be reviewed and committed. It deliberately does NOT deploy: the
# previous version of this script refreshed and deployed in one step, which meant
# a newly added index was overwritten by live state before it could ever ship.
if [ "$MODE" == "--refresh" ]; then
  echo "Fetching live indexes from '$PROJECT'..."
  firebase firestore:indexes --project "$PROJECT" > firestore.indexes.tmp.json

  echo "Filtering into '$TARGET_INDEX_FILE'..."
  if [ "$ENV" == "prod" ]; then
    FILTER='{indexes: [.indexes[] | select((.collectionGroup | startswith("dev_") | not) and (.collectionGroup | startswith("stg_") | not))], fieldOverrides: .fieldOverrides}'
  else
    FILTER="{indexes: [.indexes[] | select(.collectionGroup | startswith(\"${ENV}_\"))], fieldOverrides: .fieldOverrides}"
  fi
  jq "$FILTER" firestore.indexes.tmp.json > "$TARGET_INDEX_FILE.new"
  rm firestore.indexes.tmp.json
  mv "$TARGET_INDEX_FILE.new" "$TARGET_INDEX_FILE"

  echo "Updated $TARGET_INDEX_FILE from live. Review and commit it; nothing was deployed."
  exit 0
fi

# Deploy path: ship exactly what is committed, so a newly added index actually
# reaches the project.
COUNT=$(jq '.indexes | length' "$TARGET_INDEX_FILE")

echo "-----------------------------------------------------"
echo "Deploying Firestore indexes"
echo "  environment: $ENV"
echo "  project:     $PROJECT"
echo "  file:        $TARGET_INDEX_FILE ($COUNT indexes)"
echo "-----------------------------------------------------"

# firebase.json wires firestore.indexes -> firestore.indexes.json, so the chosen
# env file has to land there before the deploy.
cp "$TARGET_INDEX_FILE" firestore.indexes.json

firebase deploy --only firestore:indexes --project "$PROJECT"

echo "Deployment for '$ENV' completed."
echo "Note: index builds continue in the background; new indexes are not queryable until they finish."
