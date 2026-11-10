#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Inventario del paquete: solo lectura'
gcloud storage buckets list --filter="name:${PROJECT_ID}-${PREFIX}-" --format='table(name,location)'
gcloud pubsub topics list --filter="name:$PREFIX" --format='table(name)'
gcloud pubsub subscriptions list --filter="name:$PREFIX" --format='table(name,topic,cloudStorageConfig.bucket,bigqueryConfig.table)'
gcloud dataflow jobs list --region="$REGION" --filter="name:$PREFIX" --format='table(id,name,state)'
for dataset in "$BRONZE_DATASET" "$SILVER_DATASET" "$GOLD_DATASET"; do
  echo "== $dataset =="
  bq --project_id="$PROJECT_ID" ls "$dataset"
done
echo 'Habilitado != creado != ejecutándose != validado. 09 verifica Bronze/Silver; 11 guarda estado final.'
