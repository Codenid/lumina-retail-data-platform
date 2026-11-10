#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 10 — cargar Silver a BigQuery y materializar Gold'
[[ -s "$ROOT/state/$DEMO_RUN_ID/verificado.txt" ]] || { echo 'Completa 09'; exit 1; }
# Solo reemplaza las tablas de ESTA ejecución desde Silver BigQuery.
SQL="CREATE OR REPLACE TABLE \`$PROJECT_ID.$GOLD_DATASET.$TABLE\` AS SELECT '$DEMO_RUN_ID' AS scenario_id, sku_id, SUM(quantity) AS unidades, COUNT(DISTINCT order_id) AS pedidos FROM \`$PROJECT_ID.$SILVER_DATASET.pedidos\` WHERE quality_status='VALID' GROUP BY sku_id"
bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --maximum_bytes_billed=10485760 "$SQL"
SQL="CREATE OR REPLACE TABLE \`$PROJECT_ID.$GOLD_DATASET.insights_${DEMO_RUN_ID//-/_}\` AS SELECT 'order_created' AS event_type, COUNT(DISTINCT order_id) AS eventos, SUM(quantity) AS unidades FROM \`$PROJECT_ID.$SILVER_DATASET.pedidos\` WHERE quality_status='VALID'"
bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --maximum_bytes_billed=10485760 "$SQL"
bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --maximum_bytes_billed=10485760 \
 "SELECT * FROM \`$PROJECT_ID.$GOLD_DATASET.insights_${DEMO_RUN_ID//-/_}\`"
echo 'Gold de demostración materializado desde Silver BigQuery.'
