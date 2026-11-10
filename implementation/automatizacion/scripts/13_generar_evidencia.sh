#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
[[ -s "$ROOT/state/$DEMO_RUN_ID/verificado.txt" ]] || { echo 'Falta validación 09'; exit 1; }
[[ "$(cat "$ROOT/state/$DEMO_RUN_ID/estado_final.txt")" == JOB_STATE_CANCELLED ]] || { echo 'No se confirmó CANCELLED'; exit 1; }
ID="$(cat "$ROOT/state/$DEMO_RUN_ID/job_id.txt")"
gcloud dataflow jobs describe "$ID" --region="$REGION" --format=json > "$ROOT/state/$DEMO_RUN_ID/job_final.json"
BRONZE_ROWS="$(bq --project_id="$PROJECT_ID" query --use_legacy_sql=false --format=csv --max_rows=2 "SELECT COUNT(*) FROM \`$PROJECT_ID.$BRONZE_DATASET.eventos_raw_pubsub\` WHERE JSON_VALUE(data,'$.event_id')='evt-$DEMO_RUN_ID'" | tail -1)"
SILVER_ROWS="$(bq --project_id="$PROJECT_ID" query --use_legacy_sql=false --format=csv --max_rows=2 "SELECT COUNT(*) FROM \`$PROJECT_ID.$SILVER_DATASET.pedidos\` WHERE order_id IN (SELECT JSON_VALUE(data,'$.payload.order_id') FROM \`$PROJECT_ID.$BRONZE_DATASET.eventos_raw_pubsub\` WHERE JSON_VALUE(data,'$.event_id')='evt-$DEMO_RUN_ID')" | tail -1)"
GOLD_ROWS="$(bq --project_id="$PROJECT_ID" query --use_legacy_sql=false --format=csv --max_rows=2 "SELECT COUNT(*) FROM \`$PROJECT_ID.$GOLD_DATASET.insights_${DEMO_RUN_ID//-/_}\`" | tail -1)"
[[ "$BRONZE_ROWS" =~ ^[0-9]+$ && "$SILVER_ROWS" =~ ^[0-9]+$ && "$GOLD_ROWS" =~ ^[0-9]+$ && "$BRONZE_ROWS" -ge 1 && "$SILVER_ROWS" -ge 1 && "$GOLD_ROWS" -ge 1 ]] || { echo "Evidencia incompleta: bronze=$BRONZE_ROWS silver=$SILVER_ROWS gold=$GOLD_ROWS"; exit 1; }
cat > "$ROOT/state/$DEMO_RUN_ID/EVIDENCIA_RS009.md" <<EOF
# Evidencia técnica de demo — no cierra automáticamente el issue
- Proyecto: $PROJECT_ID
- Región: $REGION
- Job Dataflow: $ID
- Evento: evt-$DEMO_RUN_ID
- Bronze BigQuery: $PROJECT_ID.$BRONZE_DATASET.eventos_raw_pubsub ($BRONZE_ROWS fila)
- Silver BigQuery: $PROJECT_ID.$SILVER_DATASET.pedidos ($SILVER_ROWS fila)
- Gold BigQuery: $PROJECT_ID.$GOLD_DATASET.insights_${DEMO_RUN_ID//-/_} ($GOLD_ROWS filas)
- Duplicados Bronze observados: $((BRONZE_ROWS-1))
- Estado final: JOB_STATE_CANCELLED, consultado en GCP.
EOF
cat "$ROOT/state/$DEMO_RUN_ID/EVIDENCIA_RS009.md"
