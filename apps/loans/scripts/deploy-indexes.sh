#!/bin/bash

# This script automates the deployment of Firestore indexes for different environments.
# It handles fetching, filtering, and transforming indexes for dev, stg, and prod.
#
# Usage: ./deploy-indexes.sh <environment>
# Example: ./deploy-indexes.sh dev
#
# Prerequisites:
# - firebase-cli installed and logged in.
# - jq (https://stedolan.github.io/jq/) installed.
# - Firebase projects aliased as 'loooans-dev-stg' and 'loooans-prod'.
#   (e.g., `firebase use --add`, then select project, and enter alias)

set -e # Exit immediately if a command exits with a non-zero status.

ENV=$1  # Pass environment as a parameter (e.g., dev, stg, prod)

if [ -z "$ENV" ]; then
  echo "Usage: $0 <dev|stg|prod>"
  exit 1
fi

DEV_STG_PROJECT="loooans-dev-stg"
PROD_PROJECT="loooans-prod"

echo "Fetching latest indexes from Firestore..."
firebase firestore:indexes > firestore.indexes.tmp.json

echo "Preparing indexes for '$ENV' environment..."

if [[ "$ENV" == "dev" || "$ENV" == "stg" ]]; then
  echo "Switching to project '$DEV_STG_PROJECT'..."
  firebase use $DEV_STG_PROJECT

  echo "Generating 'firestore.indexes.$ENV.json'..."

  if ["$ENV" == "dev"]; then
    jq '{indexes: [.indexes[] | select(.collectionGroup | startswith("dev_"))], fieldOverrides: .fieldOverrides}' firestore.indexes.tmp.json > firestore.indexes.dev.json
  else
    echo "Generating 'firestore.indexes.stg.json'..."
    jq '{indexes: [.indexes[] | select(.collectionGroup | startswith("stg_"))], fieldOverrides: .fieldOverrides}' firestore.indexes.tmp.json > firestore.indexes.stg.json
  fi

  rm firestore.indexes.tmp.json
  echo "Generated index files for $ENV."

elif [ "$ENV" == "prod" ]; then
  echo "Switching to project '$PROD_PROJECT'..."
  firebase use $PROD_PROJECT

  echo "Generating 'firestore.indexes.prod.json'..."
  jq '{indexes: [.indexes[] | select((.collectionGroup | startswith("dev_") | not) and (.collectionGroup | startswith("stg_") | not))], fieldOverrides: .fieldOverrides}' firestore.indexes.tmp.json > firestore.indexes.prod.json
  rm firestore.indexes.tmp.json

else
  echo "Invalid environment '$ENV'. Please use 'dev', 'stg', or 'prod'."
  exit 1
fi

TARGET_INDEX_FILE="firestore.indexes.$ENV.json"

echo "-----------------------------------------------------"
echo "Deploying Firestore indexes for '$ENV' environment..."
echo "Using index file: $TARGET_INDEX_FILE"
echo "-----------------------------------------------------"

# Copy the correct environment's index file to the one Firebase uses
cp $TARGET_INDEX_FILE firestore.indexes.json

# Deploy the indexes
firebase deploy --only firestore:indexes --debug

echo "Deployment for '$ENV' environment completed."
