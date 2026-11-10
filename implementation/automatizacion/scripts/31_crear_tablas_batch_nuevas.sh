#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 31 — crear/verificar tablas Bronze y Silver batch'
[[ -s "$ROOT/state/$DEMO_RUN_ID/contracts_batch_ok.txt" ]] || { echo 'SCRIPT 31: 0 — falta 30'; exit 1; }
run_query() { bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --maximum_bytes_billed=31457280 "$1"; }
for table in benchmark_competidores_raw eventos_locales_raw redes_sociales_raw; do
  run_query "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$BRONZE_DATASET.$table\` (batch_id STRING NOT NULL, file_id STRING NOT NULL, source_file_uri STRING NOT NULL, source_system STRING NOT NULL, source_row_number INT64 NOT NULL, ingested_at TIMESTAMP NOT NULL, effective_at TIMESTAMP, record_hash STRING NOT NULL, payload_json JSON NOT NULL, is_valid BOOL NOT NULL, error_reason STRING)"
done
run_query "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$SILVER_DATASET.benchmark_competidores\` (benchmark_id STRING NOT NULL, competitor_id STRING NOT NULL, sku_id STRING NOT NULL, store_id STRING, observed_at TIMESTAMP NOT NULL, competitor_price NUMERIC NOT NULL, availability STRING, quality_status STRING NOT NULL)"
run_query "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$SILVER_DATASET.eventos_locales\` (local_event_id STRING NOT NULL, store_id STRING NOT NULL, event_type STRING NOT NULL, start_at TIMESTAMP NOT NULL, end_at TIMESTAMP, impact_score FLOAT64 NOT NULL, quality_status STRING NOT NULL)"
run_query "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$SILVER_DATASET.redes_sociales\` (post_id STRING NOT NULL, platform STRING NOT NULL, published_at TIMESTAMP NOT NULL, sku_id STRING NOT NULL, sentiment_score FLOAT64 NOT NULL, engagement_count INT64 NOT NULL, text_hash STRING NOT NULL, quality_status STRING NOT NULL)"
printf 'Tablas batch verificadas\n' > "$ROOT/state/$DEMO_RUN_ID/tablas_batch_ok.txt"
echo 'SCRIPT 31: 1 — tablas Bronze/Silver verificadas'
