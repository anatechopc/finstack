#!/bin/bash

helpFunction()
{
   echo "$0 is a tool to deploy all cloud functions in this repo."
   echo "Usage: "
   echo -e "\t $0 <arguments>"
   echo ""
   echo -e "\t-e \t(required) environment where the cloud functions will be deployed [values: development, staging, production]"
   echo -e "\t-p \t(required) firebase project where the cloud functions will be deployed"
   exit 1 # Exit script after printing help
}

while getopts "e:p:" opt
do
   case "$opt" in
      e ) environment="$OPTARG" ;;
      p ) project="$OPTARG" ;;
      ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done

# Print helpFunction in case parameters are empty
if [ -z "$environment" ] || [ -z "$project" ]
then
   echo "Please enter required parameter"
   echo ""
   helpFunction
fi

if [ "$environment" != "development" ] && [ "$environment" != "staging" ] && [ "$environment" != "production" ]
then
  echo "Please enter accepted environment values"
  echo ""
  helpFunction
  exit
fi

if [ "$environment" == "development" ]
then
  collectionPrefix="dev_"
elif [ "$environment" == "staging" ]
then
  collectionPrefix="stg_"
else
  collectionPrefix=""
fi

# Begin script in case all parameters are correct
echo "Deploying cloud functions..."
echo "environment: $environment"
echo "project: $project"
echo ""

# Microsoft Graph credentials for SendEmail. Tenant + client IDs are not
# secrets and are injected as plain env vars. The client secret is stored in
# Google Secret Manager (secret name: ms-graph-client-secret) and mounted as
# an env var via --set-secrets. Rotate the secret by adding a new version
# in Secret Manager — no code change required.
MS_GRAPH_TENANT_ID="9df89475-8709-4ec5-82f0-4cb73ebdc92b"
MS_GRAPH_CLIENT_ID="d5b456ce-6c94-47e9-a904-f071382fb4f6"
MS_GRAPH_ENV_VARS="ENVIRONMENT=$environment,MS_GRAPH_TENANT_ID=$MS_GRAPH_TENANT_ID,MS_GRAPH_CLIENT_ID=$MS_GRAPH_CLIENT_ID"
MS_GRAPH_SECRETS="MS_GRAPH_CLIENT_SECRET=ms-graph-client-secret:latest"

# Run the functions keyless: as the project's Firebase Admin SDK service
# account (it already has Firestore / RTDB / Auth access) via Application
# Default Credentials, instead of an embedded service-account key. The
# deploying identity needs roles/iam.serviceAccountUser (actAs) on this SA.
serviceAccount=$(gcloud iam service-accounts list --project="$project" \
  --filter="email ~ ^firebase-adminsdk-" --format="value(email)" --limit=1)
if [ -z "$serviceAccount" ]; then
  echo "ERROR: no firebase-adminsdk service account found for project $project"
  exit 1
fi
echo "Functions will run as service account: $serviceAccount"
echo ""

# Track background process PIDs and their function names
declare -A pids

# Deploy each function in the background
echo "Deploying requestOtp"
gcloud functions deploy requestOtp_$environment --set-env-vars "$MS_GRAPH_ENV_VARS" --set-secrets "$MS_GRAPH_SECRETS" --runtime go122 --trigger-http --project $project --region asia-east1 --allow-unauthenticated --gen2 --service-account="$serviceAccount" --entry-point requestOtp &
pids[$!]="requestOtp"

# NOTE: Old verifyPaymentOtp_<env> Cloud Run services are no longer redeployed
# by this script (renamed to verifyOtp in 2026-04 for issue #13). The orphaned
# services should be deleted manually from the GCP console after the first
# successful deploy on each environment.
echo "Deploying verifyOtp"
gcloud functions deploy verifyOtp_$environment --set-env-vars ENVIRONMENT=$environment --runtime go122 --trigger-http --project $project --region asia-east1 --allow-unauthenticated --gen2 --service-account="$serviceAccount" --entry-point verifyOtp &
pids[$!]="verifyOtp"

echo "Deploying sendEmail"
gcloud functions deploy sendEmail_$environment --set-env-vars "$MS_GRAPH_ENV_VARS" --set-secrets "$MS_GRAPH_SECRETS" --runtime go122 --trigger-http --project $project --region asia-east1 --allow-unauthenticated --gen2 --service-account="$serviceAccount" --entry-point sendEmail &
pids[$!]="sendEmail"

echo "Deploying UserCreated trigger"
gcloud functions deploy userCreated_$environment --gen2 --service-account="$serviceAccount" --runtime=go122 --region=asia-east1 --trigger-location=asia-east1 --source=. --entry-point=userCreated --trigger-event-filters=type=google.cloud.firestore.document.v1.created --trigger-event-filters=database='(default)' --trigger-event-filters-path-pattern=document="${collectionPrefix}users/{uid}" --set-env-vars=ENVIRONMENT=$environment --project=$project &
pids[$!]="userCreated"

echo "Deploying LoanChanges trigger"
gcloud functions deploy loanChanges_$environment --gen2 --service-account="$serviceAccount" --runtime=go122 --region=asia-east1 --trigger-location=asia-east1 --source=. --entry-point=loanChanges --trigger-event-filters=type=google.cloud.firestore.document.v1.written --trigger-event-filters=database='(default)' --trigger-event-filters-path-pattern=document="${collectionPrefix}loans/{uid}" --set-env-vars=ENVIRONMENT=$environment --project=$project &
pids[$!]="loanChanges"

echo "Deploying LoanScheduleChanges trigger"
gcloud functions deploy loanScheduleChanges_$environment --gen2 --service-account="$serviceAccount" --runtime=go122 --region=asia-east1 --trigger-location=asia-east1 --source=. --entry-point=loanScheduleChanges --trigger-event-filters=type=google.cloud.firestore.document.v1.created --trigger-event-filters=database='(default)' --trigger-event-filters-path-pattern=document="${collectionPrefix}loan_schedules/{uid}" --set-env-vars=ENVIRONMENT=$environment --project=$project &
pids[$!]="loanScheduleChanges"

echo "Deploying CapitalCreated trigger"
gcloud functions deploy capitalCreated_$environment --gen2 --service-account="$serviceAccount" --runtime=go122 --region=asia-east1 --trigger-location=asia-east1 --source=. --entry-point=capitalCreated --trigger-event-filters=type=google.cloud.firestore.document.v1.created --trigger-event-filters=database='(default)' --trigger-event-filters-path-pattern=document="${collectionPrefix}capital/{uid}" --set-env-vars=ENVIRONMENT=$environment --project=$project &
pids[$!]="capitalCreated"

echo "Deploying NotificationCreated trigger"
gcloud functions deploy notificationCreated_$environment --gen2 --service-account="$serviceAccount" --runtime=go122 --region=asia-east1 --trigger-location=asia-east1 --source=. --entry-point=notificationCreated --trigger-event-filters=type=google.cloud.firestore.document.v1.created --trigger-event-filters=database='(default)' --trigger-event-filters-path-pattern=document="${collectionPrefix}notifications/{uid}" --set-env-vars=ENVIRONMENT=$environment --project=$project &
pids[$!]="notificationCreated"

echo "Deploying ReviewCreated trigger"
gcloud functions deploy reviewCreated_$environment --gen2 --service-account="$serviceAccount" --runtime=go122 --region=asia-east1 --trigger-location=asia-east1 --source=. --entry-point=reviewCreated --trigger-event-filters=type=google.cloud.firestore.document.v1.created --trigger-event-filters=database='(default)' --trigger-event-filters-path-pattern=document="${collectionPrefix}reviews/{uid}" --set-env-vars=ENVIRONMENT=$environment --project=$project &
pids[$!]="reviewCreated"

echo "Deploying ReviewUpdated trigger"
gcloud functions deploy reviewUpdated_$environment --gen2 --service-account="$serviceAccount" --runtime=go122 --region=asia-east1 --trigger-location=asia-east1 --source=. --entry-point=reviewUpdated --trigger-event-filters=type=google.cloud.firestore.document.v1.updated --trigger-event-filters=database='(default)' --trigger-event-filters-path-pattern=document="${collectionPrefix}reviews/{uid}" --set-env-vars=ENVIRONMENT=$environment --project=$project &
pids[$!]="reviewUpdated"

echo "Deploying PaymentCreated trigger"
gcloud functions deploy paymentCreated_$environment --gen2 --service-account="$serviceAccount" --runtime=go122 --region=asia-east1 --trigger-location=asia-east1 --source=. --entry-point=paymentCreated --trigger-event-filters=type=google.cloud.firestore.document.v1.created --trigger-event-filters=database='(default)' --trigger-event-filters-path-pattern=document="${collectionPrefix}payments/{uid}" --set-env-vars=ENVIRONMENT=$environment --project=$project &
pids[$!]="paymentCreated"

echo "Deploying UserChanges trigger"
gcloud functions deploy userChanges_$environment --gen2 --service-account="$serviceAccount" --runtime=go122 --region=asia-east1 --trigger-location=asia-east1 --source=. --entry-point=userChanges --trigger-event-filters=type=google.cloud.firestore.document.v1.updated --trigger-event-filters=database='(default)' --trigger-event-filters-path-pattern=document="${collectionPrefix}users/{uid}" --set-env-vars=ENVIRONMENT=$environment --project=$project &
pids[$!]="userChanges"

echo ""
echo "All 12 functions deploying in parallel. Waiting for completion..."
echo ""

# Wait for all background processes and track failures
failed=()
for pid in "${!pids[@]}"; do
  if ! wait "$pid"; then
    failed+=("${pids[$pid]}")
  fi
done

echo ""
if [ ${#failed[@]} -eq 0 ]; then
  echo "Deployment done. All 12 functions deployed successfully."
else
  echo "Deployment finished with errors. Failed functions: ${failed[*]}"
  exit 1
fi
