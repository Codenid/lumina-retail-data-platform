#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 56 — Landing → Bronze para seis fuentes'
[[ -s "$ROOT/state/$DEMO_RUN_ID/batch_productivo_fixtures_ok.txt" ]] || { echo 'SCRIPT 56: 0 — dependencia: SCRIPT 55'; exit 1; }
BATCH_RUN_ID="$(cat "$ROOT/state/$DEMO_RUN_ID/batch_productivo_id.txt")"
LOCATION="$(sed -n 's/^dataset_location=//p' "$ROOT/state/$DEMO_RUN_ID/batch_productivo_preflight.txt")"
Q() { bq --project_id="$PROJECT_ID" --location="$LOCATION" query --use_legacy_sql=false "$1" >/dev/null; }
BRONZE_SCHEMA='(batch_id STRING NOT NULL,file_id STRING NOT NULL,source_file_uri STRING NOT NULL,source_system STRING NOT NULL,source_row_number INT64 NOT NULL,ingested_at TIMESTAMP NOT NULL,effective_at TIMESTAMP,record_hash STRING NOT NULL,payload_json JSON NOT NULL,is_valid BOOL NOT NULL,error_reason STRING)'
Q "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$BRONZE_DATASET.pedidos_raw\` $BRONZE_SCHEMA"
Q "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$BRONZE_DATASET.inventario_raw\` $BRONZE_SCHEMA"
Q "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$BRONZE_DATASET.entregas_raw\` $BRONZE_SCHEMA"
Q "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$BRONZE_DATASET.benchmark_competidores_raw\` $BRONZE_SCHEMA"
Q "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$BRONZE_DATASET.eventos_locales_raw\` $BRONZE_SCHEMA"
Q "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$BRONZE_DATASET.redes_sociales_raw\` $BRONZE_SCHEMA"
for domain in pedidos inventario entregas benchmark_competidores eventos_locales redes_sociales; do
  stage="$PROJECT_ID:$BRONZE_DATASET.${domain}_stage_${BATCH_RUN_ID//-/_}"
  source_uri="gs://$LANDING/batch/$BATCH_RUN_ID/$domain.jsonl"
  bq --project_id="$PROJECT_ID" --location="$LOCATION" load --replace --source_format=NEWLINE_DELIMITED_JSON --autodetect "$stage" "$source_uri"
  Q "MERGE \`$PROJECT_ID.$BRONZE_DATASET.${domain}_raw\` T USING \`$PROJECT_ID.$BRONZE_DATASET.${domain}_stage_${BATCH_RUN_ID//-/_}\` S ON T.batch_id=S.batch_id AND T.file_id=S.file_id AND T.source_row_number=S.source_row_number WHEN NOT MATCHED THEN INSERT (batch_id,file_id,source_file_uri,source_system,source_row_number,ingested_at,effective_at,record_hash,payload_json,is_valid,error_reason) VALUES (S.batch_id,S.file_id,S.source_file_uri,S.source_system,S.source_row_number,S.ingested_at,S.effective_at,S.record_hash,TO_JSON(S.payload_json),S.is_valid,S.error_reason)"
  count="$(bq --project_id="$PROJECT_ID" --location="$LOCATION" query --use_legacy_sql=false --format=csv --max_rows=2 "SELECT COUNT(*) FROM \`$PROJECT_ID.$BRONZE_DATASET.${domain}_raw\` WHERE batch_id='$BATCH_RUN_ID'" | tail -1)"
  [[ "$count" =~ ^[1-9][0-9]*$ ]] || { echo "SCRIPT 56: 0 — Bronze $domain count=$count"; exit 1; }
  echo "Bronze $domain: $count"
done
printf 'SCRIPT 56: 1 — seis fuentes verificadas en Bronze\n' > "$ROOT/state/$DEMO_RUN_ID/batch_productivo_bronze_ok.txt"
echo 'SCRIPT 56: 1 — seis fuentes verificadas en Bronze'
