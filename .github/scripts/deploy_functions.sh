#!/bin/bash

helpFunction()
{
   echo "$0 is a tool to deploy all cloud functions in this repo."
   echo "Usage: "
   echo -e "\t $0 <arguments>"
   echo ""
   echo -e "\t-e \t(required) environment where the cloud functions will be deployed [values: development, staging, production]"
   echo -e "\t-p \t(required) firebase project where the cloud functions will be deployed"
#   echo -e "\t-o \t(optional) if we will deploy only 1 function"
   exit 1 # Exit script after printing help
}

while getopts "e:o:p:" opt
do
   case "$opt" in
      e ) environment="$OPTARG" ;;
#      o ) only_function="$OPTARG" ;;
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
echo ""
#echo "$only_function"

# add all functions to be deployed here
#echo "Deploying addUser"
#gcloud functions deploy addUser_$environment --set-env-vars ENVIRONMENT=$environment --runtime go121 --trigger-http --project $project --region asia-east1 --allow-unauthenticated --gen2 --entry-point addUser
#echo ""
#echo "Deploying updateUser"
#gcloud functions deploy updateUser_$environment --set-env-vars ENVIRONMENT=$environment --runtime go120 --trigger-http --project $project --region asia-southeast1 --allow-unauthenticated --gen2 --entry-point updateUser
#echo "Deploying requestOtp"
#gcloud functions deploy requestOtp_$environment --set-env-vars ENVIRONMENT=$environment --runtime go121 --trigger-http --project $project --region asia-southeast1 --allow-unauthenticated --gen2 --entry-point requestOtp
#echo "Deploying verifyUserEmail"
#gcloud functions deploy verifyUserEmail_$environment --set-env-vars ENVIRONMENT=$environment --runtime go121 --trigger-http --project $project --region asia-southeast1 --allow-unauthenticated --gen2 --entry-point verifyUserEmail
#echo "Deploying subscriptionJob"
#gcloud functions deploy subscriptionJob_$environment --set-env-vars ENVIRONMENT=$environment --runtime go121 --trigger-http --project $project --region asia-southeast1 --allow-unauthenticated --gen2 --entry-point subscriptionJob
#echo "Deploying updateUserEmail"
#gcloud functions deploy updateUserEmail_$environment --set-env-vars ENVIRONMENT=$environment --runtime go121 --trigger-http --project $project --region asia-southeast1 --allow-unauthenticated --gen2 --entry-point updateUserEmail
echo "Deploying sendEmail"
gcloud functions deploy sendEmail_$environment --set-env-vars ENVIRONMENT=$environment --runtime go122 --trigger-http --project $project --region asia-east1 --allow-unauthenticated --gen2 --entry-point sendEmail
echo "Deploying UserCreated trigger"
gcloud functions deploy userCreated_$environment --gen2 --runtime=go122 --region=asia-east1 --trigger-location=asia-east1 --source=. --entry-point=userCreated --trigger-event-filters=type=google.cloud.firestore.document.v1.created --trigger-event-filters=database='(default)' --trigger-event-filters-path-pattern=document="${collectionPrefix}users/{uid}" --set-env-vars=ENVIRONMENT=$environment --project=$project
echo "Deploying LoanChanges trigger"
gcloud functions deploy loanChanges_$environment --gen2 --runtime=go122 --region=asia-east1 --trigger-location=asia-east1 --source=. --entry-point=loanChanges --trigger-event-filters=type=google.cloud.firestore.document.v1.written --trigger-event-filters=database='(default)' --trigger-event-filters-path-pattern=document="${collectionPrefix}loans/{uid}" --set-env-vars=ENVIRONMENT=$environment --project=$project
echo "Deploying LoanScheduleChanges trigger"
gcloud functions deploy loanScheduleChanges_$environment --gen2 --runtime=go122 --region=asia-east1 --trigger-location=asia-east1 --source=. --entry-point=loanScheduleChanges --trigger-event-filters=type=google.cloud.firestore.document.v1.created --trigger-event-filters=database='(default)' --trigger-event-filters-path-pattern=document="${collectionPrefix}loan_schedules/{uid}" --set-env-vars=ENVIRONMENT=$environment --project=$project
echo "Deploying CapitalCreated trigger"
gcloud functions deploy capitalCreated_$environment --gen2 --runtime=go122 --region=asia-east1 --trigger-location=asia-east1 --source=. --entry-point=capitalCreated --trigger-event-filters=type=google.cloud.firestore.document.v1.created --trigger-event-filters=database='(default)' --trigger-event-filters-path-pattern=document="${collectionPrefix}capital/{uid}" --set-env-vars=ENVIRONMENT=$environment --project=$project
echo "Deploying NotificationCreated trigger"
gcloud functions deploy notificationCreated_$environment --gen2 --runtime=go122 --region=asia-east1 --trigger-location=asia-east1 --source=. --entry-point=notificationCreated --trigger-event-filters=type=google.cloud.firestore.document.v1.created --trigger-event-filters=database='(default)' --trigger-event-filters-path-pattern=document="${collectionPrefix}notifications/{uid}" --set-env-vars=ENVIRONMENT=$environment --project=$project
echo "Deploying ReviewCreated trigger"
gcloud functions deploy reviewCreated_$environment --gen2 --runtime=go122 --region=asia-east1 --trigger-location=asia-east1 --source=. --entry-point=reviewCreated --trigger-event-filters=type=google.cloud.firestore.document.v1.created --trigger-event-filters=database='(default)' --trigger-event-filters-path-pattern=document="${collectionPrefix}reviews/{uid}" --set-env-vars=ENVIRONMENT=$environment --project=$project
echo "Deploying PaymentCreated trigger"
gcloud functions deploy paymentCreated_$environment --gen2 --runtime=go122 --region=asia-east1 --trigger-location=asia-east1 --source=. --entry-point=paymentCreated --trigger-event-filters=type=google.cloud.firestore.document.v1.created --trigger-event-filters=database='(default)' --trigger-event-filters-path-pattern=document="${collectionPrefix}payments/{uid}" --set-env-vars=ENVIRONMENT=$environment --project=$project
echo ""
echo ""
echo "Deployment done."
