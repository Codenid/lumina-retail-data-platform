#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 37 — crear/verificar tablas Forecast'
[[ -s "$ROOT/state/$DEMO_RUN_ID/preflight_forecast_ok.txt" ]] || {
  echo 'SCRIPT 37: 0'
  echo 'Dependencia faltante: SCRIPT 36'
  echo 'Motivo: no existe preflight_forecast_ok.txt'
  exit 1
}

run_query() {
  bq --project_id="$PROJECT_ID" --location="$REGION" query \
    --use_legacy_sql=false --maximum_bytes_billed=31457280 "$1"
}

run_query "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$GOLD_DATASET.forecast_features\` (sku_id STRING NOT NULL, warehouse_id STRING NOT NULL, feature_date DATE NOT NULL, demand_qty_7d INT64 NOT NULL, demand_qty_28d INT64 NOT NULL, inventory_qty INT64 NOT NULL, reserved_qty INT64 NOT NULL, feature_run_id STRING NOT NULL)"
run_query "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$GOLD_DATASET.forecast_predictions\` (sku_id STRING NOT NULL, warehouse_id STRING NOT NULL, forecast_date DATE NOT NULL, horizon_days INT64 NOT NULL, predicted_qty FLOAT64 NOT NULL, model_version STRING NOT NULL, training_run_id STRING NOT NULL, prediction_status STRING NOT NULL)"

for table in forecast_features forecast_predictions; do
  bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET.$table" >/dev/null || {
    echo "SCRIPT 37: 0"
    echo "Motivo: no se pudo verificar la tabla $GOLD_DATASET.$table"
    exit 1
  }
done

printf 'Tablas Forecast verificadas\n' > "$ROOT/state/$DEMO_RUN_ID/forecast_tables_ok.txt"
echo 'SCRIPT 37: 1'
echo 'Estado: tablas Forecast creadas/verificadas correctamente.'
