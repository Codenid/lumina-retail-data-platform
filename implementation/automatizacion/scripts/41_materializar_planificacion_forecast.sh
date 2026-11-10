#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 41 — materializar planificación diaria Forecast'
[[ -s "$ROOT/state/$DEMO_RUN_ID/forecast_scoring_ok.txt" ]] || { echo 'SCRIPT 41: 0'; echo 'Dependencia faltante: SCRIPT 40'; exit 1; }
bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --maximum_bytes_billed=31457280 "DELETE FROM \`$PROJECT_ID.$GOLD_DATASET.cu02_plan_reposicion\` WHERE scenario_id='$DEMO_RUN_ID' AND plan_date=CURRENT_DATE()"
bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --maximum_bytes_billed=31457280 "INSERT INTO \`$PROJECT_ID.$GOLD_DATASET.cu02_plan_reposicion\` (scenario_id,sku_id,warehouse_id,plan_date,forecast_qty,recommended_qty,priority) SELECT '$DEMO_RUN_ID', sku_id, warehouse_id, forecast_date, CAST(ROUND(predicted_qty) AS INT64), CAST(ROUND(predicted_qty) AS INT64), IF(predicted_qty >= 10,'HIGH','NORMAL') FROM \`$PROJECT_ID.$GOLD_DATASET.forecast_predictions\` WHERE training_run_id='$DEMO_RUN_ID' AND prediction_status='VALID'"
printf 'Planificación Forecast verificada\n' > "$ROOT/state/$DEMO_RUN_ID/forecast_plan_ok.txt"
echo 'SCRIPT 41: 1'
echo 'Estado: planificación diaria materializada.'
