#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 05 — tópicos y dos ramas independientes'
if ! bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$BRONZE_DATASET.eventos_raw_pubsub" >/dev/null 2>&1; then
  echo "Falta la tabla $PROJECT_ID:$BRONZE_DATASET.eventos_raw_pubsub. Ejecuta primero: bash automatizacion/scripts/04_crear_bigquery.sh" >&2
  exit 1
fi
echo "Verificado: tabla destino $PROJECT_ID:$BRONZE_DATASET.eventos_raw_pubsub"
for topic in "$TOPIC" "$INSIGHTS_TOPIC" "$AUDIT_TOPIC"; do
 ensure "{\"name\":\"projects/$PROJECT_ID/topics/$topic\"}" \
  gcloud pubsub topics describe "$topic" --format=json ::: gcloud pubsub topics create "$topic"
done
ensure "{\"topic\":\"projects/$PROJECT_ID/topics/$TOPIC\",\"ackDeadlineSeconds\":60}" \
 gcloud pubsub subscriptions describe "$DF_SUB" --format=json ::: \
 gcloud pubsub subscriptions create "$DF_SUB" --topic="$TOPIC" --ack-deadline=60
# Comprueba que la suscripción Dataflow no sea una suscripción push/export.
gcloud pubsub subscriptions describe "$DF_SUB" --format=json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert not any(d.get(k) for k in ["cloudStorageConfig","bigqueryConfig","pushConfig"]), "La suscripción Dataflow debe ser pull"'
ensure "{\"topic\":\"projects/$PROJECT_ID/topics/$TOPIC\",\"cloudStorageConfig.bucket\":\"$BRONZE\",\"cloudStorageConfig.filenamePrefix\":\"streaming/\",\"cloudStorageConfig.filenameSuffix\":\".jsonl\",\"cloudStorageConfig.maxDuration\":\"60s\",\"cloudStorageConfig.textConfig\":{}}" \
 gcloud pubsub subscriptions describe "$RAW_SUB" --format=json ::: \
 gcloud pubsub subscriptions create "$RAW_SUB" --topic="$TOPIC" --cloud-storage-bucket="$BRONZE" \
 --cloud-storage-file-prefix=streaming/ --cloud-storage-file-suffix=.jsonl \
 --cloud-storage-output-format=text --cloud-storage-max-duration=60s
ensure "{\"topic\":\"projects/$PROJECT_ID/topics/$TOPIC\",\"bigqueryConfig.table\":\"$PROJECT_ID:$BRONZE_DATASET.eventos_raw_pubsub\",\"bigqueryConfig.writeMetadata\":true}" \
 gcloud pubsub subscriptions describe "$RAW_BQ_SUB" --format=json ::: \
 gcloud pubsub subscriptions create "$RAW_BQ_SUB" --topic="$TOPIC" \
 --bigquery-table="$PROJECT_ID:$BRONZE_DATASET.eventos_raw_pubsub" --write-metadata
gcloud pubsub subscriptions add-iam-policy-binding "$DF_SUB" --member="serviceAccount:$WORKER" --role=roles/pubsub.subscriber >/dev/null
gcloud pubsub subscriptions list --filter="name:$PREFIX" --format='table(name,topic,cloudStorageConfig.bucket,bigqueryConfig.table)'
echo 'No hagas pull manual de la suscripción Dataflow. Bronze escribe por lotes; puede tardar varios minutos.'
