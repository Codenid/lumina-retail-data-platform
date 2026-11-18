#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
heading 'Paso 90 — programar materialización Streaming → Gold'
gcloud services enable run.googleapis.com cloudscheduler.googleapis.com --project="$PROJECT_ID"
JOB="${PREFIX}-streaming-gold-materializer"
MATERIALIZER_SA="${PREFIX}-materializer@${PROJECT_ID}.iam.gserviceaccount.com"
gcloud iam service-accounts describe "$MATERIALIZER_SA" --project="$PROJECT_ID" >/dev/null 2>&1 || gcloud iam service-accounts create "${PREFIX}-materializer" --project="$PROJECT_ID" --display-name='Lumina streaming Gold materializer'
gcloud run jobs deploy "$JOB" --project="$PROJECT_ID" --region="$REGION" --source="$ROOT/soluciones/materializador-streaming" --service-account="$MATERIALIZER_SA" --set-env-vars="PROJECT_ID=$PROJECT_ID,GOLD_DATASET=$GOLD_DATASET,SILVER_DATASET=$SILVER_DATASET,BQ_LOCATION=$REGION,STREAMING_RUN_ID=streaming-auto,STREAMING_WINDOW_MINUTES=1440" --max-retries=1 --tasks=1 --quiet
SCHEDULER_SA="${PREFIX}-scheduler@${PROJECT_ID}.iam.gserviceaccount.com"
gcloud iam service-accounts describe "$SCHEDULER_SA" --project="$PROJECT_ID" >/dev/null 2>&1 || gcloud iam service-accounts create "${PREFIX}-scheduler" --project="$PROJECT_ID" --display-name='Lumina streaming Gold scheduler'
gcloud run jobs add-iam-policy-binding "$JOB" --project="$PROJECT_ID" --region="$REGION" --member="serviceAccount:$SCHEDULER_SA" --role=roles/run.developer --quiet >/dev/null
gcloud iam service-accounts add-iam-policy-binding "$PREFIX-api@$PROJECT_ID.iam.gserviceaccount.com" --project="$PROJECT_ID" --member="serviceAccount:$SCHEDULER_SA" --role=roles/iam.serviceAccountUser --quiet >/dev/null
if gcloud scheduler jobs describe "$JOB" --project="$PROJECT_ID" --location="$REGION" >/dev/null 2>&1; then
  gcloud scheduler jobs update http "$JOB" --project="$PROJECT_ID" --location="$REGION" --schedule='*/5 * * * *' --uri="https://run.googleapis.com/apis/run.googleapis.com/v1/projects/$PROJECT_ID/locations/$REGION/jobs/$JOB:run" --oauth-service-account-email="$SCHEDULER_SA" --oauth-token-scope='https://www.googleapis.com/auth/cloud-platform' --message-body='{}' --headers='Content-Type=application/json' --quiet
else
  gcloud scheduler jobs create http "$JOB" --project="$PROJECT_ID" --location="$REGION" --schedule='*/5 * * * *' --uri="https://run.googleapis.com/apis/run.googleapis.com/v1/projects/$PROJECT_ID/locations/$REGION/jobs/$JOB:run" --oauth-service-account-email="$SCHEDULER_SA" --oauth-token-scope='https://www.googleapis.com/auth/cloud-platform' --message-body='{}' --headers='Content-Type=application/json' --quiet
fi
echo "SCRIPT 90: 1 — $JOB programado cada 5 minutos"
