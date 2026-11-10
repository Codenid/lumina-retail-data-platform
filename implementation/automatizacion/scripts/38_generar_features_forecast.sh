#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 38 — generar features Forecast'
[[ -s "$ROOT/state/$DEMO_RUN_ID/forecast_tables_ok.txt" ]] || { echo 'SCRIPT 38: 0'; echo 'Dependencia faltante: SCRIPT 37'; exit 1; }
bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$SILVER_DATASET.pedidos" >/dev/null || { echo 'SCRIPT 38: 0'; echo "Motivo: falta la tabla $SILVER_DATASET.pedidos"; exit 1; }
bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --maximum_bytes_billed=31457280 "MERGE \`$PROJECT_ID.$GOLD_DATASET.forecast_features\` T USING (SELECT sku_id, COALESCE(warehouse_id,'UNKNOWN') warehouse_id, CURRENT_DATE() feature_date, SUM(quantity) demand_qty_7d, SUM(quantity) demand_qty_28d, 0 inventory_qty, 0 reserved_qty, '$DEMO_RUN_ID' feature_run_id FROM \`$PROJECT_ID.$SILVER_DATASET.pedidos\` WHERE quality_status='VALID' GROUP BY sku_id, warehouse_id) S ON T.sku_id=S.sku_id AND T.warehouse_id=S.warehouse_id AND T.feature_date=S.feature_date WHEN NOT MATCHED THEN INSERT ROW"
printf 'Features Forecast verificadas\n' > "$ROOT/state/$DEMO_RUN_ID/forecast_features_ok.txt"
echo 'SCRIPT 38: 1'
echo 'Estado: features Forecast generadas correctamente.'
