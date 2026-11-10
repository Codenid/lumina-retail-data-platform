#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 33 — cargar nuevos productores en Bronze'
[[ -s "$ROOT/state/$DEMO_RUN_ID/fixtures_nuevos_ok.txt" ]] || { echo 'SCRIPT 33: 0 — falta 32'; exit 1; }
for domain in benchmark_competidores eventos_locales redes_sociales; do
  staging="$PROJECT_ID:$BRONZE_DATASET.${domain}_staging_${DEMO_RUN_ID//-/_}"
  ref="$PROJECT_ID.$BRONZE_DATASET.${domain}_raw"
  bq --project_id="$PROJECT_ID" --location="$REGION" load --replace --source_format=NEWLINE_DELIMITED_JSON --autodetect "$staging" "$ROOT/state/$DEMO_RUN_ID/batch-fixtures/$domain.jsonl"
  bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --maximum_bytes_billed=31457280 "MERGE \`$ref\` T USING \`$PROJECT_ID.$BRONZE_DATASET.${domain}_staging_${DEMO_RUN_ID//-/_}\` S ON T.batch_id=S.batch_id AND T.file_id=S.file_id AND T.source_row_number=S.source_row_number WHEN NOT MATCHED THEN INSERT (batch_id,file_id,source_file_uri,source_system,source_row_number,ingested_at,effective_at,record_hash,payload_json,is_valid,error_reason) VALUES (S.batch_id,S.file_id,S.source_file_uri,S.source_system,S.source_row_number,S.ingested_at,S.effective_at,S.record_hash,TO_JSON(S.payload_json),S.is_valid,S.error_reason)"
done
printf 'Bronze nuevos cargado\n' > "$ROOT/state/$DEMO_RUN_ID/bronze_nuevos_ok.txt"
echo 'SCRIPT 33: 1 — Bronze cargado'
