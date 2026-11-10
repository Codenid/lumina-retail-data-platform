#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 44 — crear/verificar tablas Gold Insights y auditoría'
[[ -s "$ROOT/state/$DEMO_RUN_ID/preflight_insights_ok.txt" ]] || { echo 'SCRIPT 44: 0'; echo 'Dependencia faltante: SCRIPT 43'; exit 1; }
Q(){ bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --maximum_bytes_billed=31457280 "$1"; }
Q "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$GOLD_DATASET.insights_streaming\` (insight_id STRING NOT NULL, event_id STRING NOT NULL, insight_type STRING NOT NULL, sku_id STRING, store_id STRING, score FLOAT64, created_at TIMESTAMP NOT NULL, status STRING NOT NULL)"
Q "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$GOLD_DATASET.procesamiento_auditoria\` (audit_id STRING NOT NULL, event_id STRING NOT NULL, component STRING NOT NULL, status STRING NOT NULL, observed_at TIMESTAMP NOT NULL, detail STRING)"
printf 'Tablas Insights verificadas\n' > "$ROOT/state/$DEMO_RUN_ID/insights_tables_ok.txt"
echo 'SCRIPT 44: 1'
echo 'Estado: tablas Insights y auditoría verificadas.'
