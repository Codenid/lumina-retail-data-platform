#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'OPCIONAL — definir job de Storage Transfer, sin ejecutarlo'
echo '[1/5] Habilitando/verificando Storage Transfer API'
gcloud services enable storagetransfer.googleapis.com --project="$PROJECT_ID"
NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
AGENT="project-${NUMBER}@storage-transfer-service.iam.gserviceaccount.com"
echo "[2/5] Agente: $AGENT"
echo '[3/5] Aplicando permisos limitados por bucket'
for role in roles/storage.legacyBucketReader; do
  gcloud storage buckets add-iam-policy-binding "gs://$LANDING" --member="serviceAccount:$AGENT" --role="$role" >/dev/null
  gcloud storage buckets add-iam-policy-binding "gs://$BRONZE" --member="serviceAccount:$AGENT" --role="$role" >/dev/null
done
gcloud storage buckets add-iam-policy-binding "gs://$LANDING" \
  --member="serviceAccount:$AGENT" --role=roles/storage.objectViewer >/dev/null
gcloud storage buckets add-iam-policy-binding "gs://$BRONZE" \
  --member="serviceAccount:$AGENT" --role=roles/storage.objectCreator >/dev/null
echo '[4/5] Verificando permisos efectivos del agente'
for bucket in "$LANDING" "$BRONZE"; do
  gcloud storage buckets get-iam-policy "gs://$bucket" --format=json \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); a="serviceAccount:'"$AGENT"'"; print(sys.argv[1], [b["role"] for b in d.get("bindings",[]) if a in b.get("members",[])])' "$bucket"
done
JOB="transferJobs/${PREFIX}-landing-bronze"
echo '[5/5] Creando o verificando job --do-not-run'
ensure "{\"transferSpec.gcsDataSource.bucketName\":\"$LANDING\",\"transferSpec.gcsDataSink.bucketName\":\"$BRONZE\",\"transferSpec.gcsDataSource.path\":\"batch/\",\"transferSpec.gcsDataSink.path\":\"batch/\"}" \
 gcloud transfer jobs describe "$JOB" --project="$PROJECT_ID" --format=json ::: \
 gcloud transfer jobs create "gs://$LANDING/batch/" "gs://$BRONZE/batch/" --project="$PROJECT_ID" --name="$JOB" \
 --description='RetailSmart demo: Landing a Bronze batch; pendiente permisos y primera ejecución' --do-not-run
gcloud transfer jobs describe "$JOB" --project="$PROJECT_ID" --format='yaml(name,status,creationTime,transferSpec)'
echo 'Job definido y verificado; --do-not-run conserva la transferencia sin ejecutarla.'
