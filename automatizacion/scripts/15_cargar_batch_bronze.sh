#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 15 — Landing batch → Bronze BigQuery'
[[ -d "$ROOT/state/$DEMO_RUN_ID/batch-fixtures" ]] || { echo 'Falta ejecutar 14'; exit 1; }
for domain in pedidos inventario entregas telemetria; do
  target="$PROJECT_ID:$BRONZE_DATASET.${domain}_raw"
  staging="${PROJECT_ID}:${BRONZE_DATASET}.${domain}_staging_${DEMO_RUN_ID//-/_}"
  target_ref="$PROJECT_ID.$BRONZE_DATASET.${domain}_raw"
  staging_ref="$PROJECT_ID.$BRONZE_DATASET.${domain}_staging_${DEMO_RUN_ID//-/_}"
  bq --project_id="$PROJECT_ID" --location="$REGION" load --replace --source_format=NEWLINE_DELIMITED_JSON --autodetect "$staging" "$ROOT/state/$DEMO_RUN_ID/batch-fixtures/$domain.jsonl"
  bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --maximum_bytes_billed=20971520 \
    "MERGE \`$target_ref\` T USING \`$staging_ref\` S ON T.batch_id=S.batch_id AND T.file_id=S.file_id AND T.source_row_number=S.source_row_number WHEN NOT MATCHED THEN INSERT (batch_id,file_id,source_file_uri,source_system,source_row_number,ingested_at,effective_at,record_hash,payload_json,is_valid,error_reason) VALUES (S.batch_id,S.file_id,S.source_file_uri,S.source_system,S.source_row_number,S.ingested_at,S.effective_at,S.record_hash,TO_JSON(S.payload_json),S.is_valid,S.error_reason)"
done
echo 'OK: carga Bronze solicitada; deduplicación por file_id/record_hash será obligatoria en la curación.'
