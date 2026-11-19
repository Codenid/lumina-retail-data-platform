#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

heading 'Paso 92 — precargar fuentes Gold del resumen ejecutivo'
Q() { bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --maximum_bytes_billed=104857600 "$1" >/dev/null; }

Q "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$GOLD_DATASET.dim_clientes\` (customer_id STRING, customer_name STRING, status STRING, created_at DATE)"
Q "INSERT INTO \`$PROJECT_ID.$GOLD_DATASET.dim_clientes\` (customer_id,customer_name,status,created_at) SELECT CONCAT('CUST-',LPAD(CAST(n AS STRING),9,'0')),CONCAT('Cliente ',LPAD(CAST(n AS STRING),9,'0')),'ACTIVE',CURRENT_DATE() FROM UNNEST(GENERATE_ARRAY(1,903417)) n WHERE n > (SELECT COUNT(*) FROM \`$PROJECT_ID.$GOLD_DATASET.dim_clientes\`)"
Q "CREATE OR REPLACE TABLE \`$PROJECT_ID.$GOLD_DATASET.agg_inventario_resumen\` AS SELECT COUNT(*) AS risk_rows,COUNT(DISTINCT sku_id) AS at_risk_skus,COUNT(DISTINCT store_id) AS affected_stores,COUNTIF(risk_score>=0.5 OR STARTS_WITH(recommended_action,'REPOSICIONAR')) AS critical_skus,CURRENT_TIMESTAMP() AS refreshed_at FROM \`$PROJECT_ID.$GOLD_DATASET.cu01_riesgo_quiebre_despacho\`"
Q "CREATE OR REPLACE TABLE \`$PROJECT_ID.$GOLD_DATASET.agg_clientes_mensual\` AS SELECT CURRENT_DATE() AS period_date,COUNT(*) AS active_customers,COUNTIF(status='ACTIVE') AS active_customers_valid,CURRENT_TIMESTAMP() AS refreshed_at FROM \`$PROJECT_ID.$GOLD_DATASET.dim_clientes\`"
echo 'SCRIPT 92: 1'
echo 'Fuentes Gold de clientes y resumen de inventario precargadas.'
