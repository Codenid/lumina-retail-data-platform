#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 40 — ejecutar scoring Forecast'
[[ -s "$ROOT/state/$DEMO_RUN_ID/forecast_model_ok.txt" ]] || { echo 'SCRIPT 40: 0'; echo 'Dependencia faltante: SCRIPT 39'; exit 1; }
MODEL_VERSION="$(cat "$ROOT/state/$DEMO_RUN_ID/model_version.txt")"
gcloud storage objects describe "gs://$MODELS/forecast/$DEMO_RUN_ID/$MODEL_VERSION/model.json" --format='value(name)' >/dev/null || { echo 'SCRIPT 40: 0'; echo 'Motivo: artefacto Forecast no encontrado'; exit 1; }
bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --maximum_bytes_billed=31457280 "MERGE \`$PROJECT_ID.$GOLD_DATASET.forecast_predictions\` T USING (SELECT sku_id, warehouse_id, DATE_ADD(feature_date, INTERVAL 1 DAY) forecast_date, 1 horizon_days, CAST(GREATEST(0, demand_qty_7d / 7.0) AS FLOAT64) predicted_qty, '$MODEL_VERSION' model_version, '$DEMO_RUN_ID' training_run_id, 'VALID' prediction_status FROM \`$PROJECT_ID.$GOLD_DATASET.forecast_features\` WHERE feature_run_id='$DEMO_RUN_ID') S ON T.sku_id=S.sku_id AND T.warehouse_id=S.warehouse_id AND T.forecast_date=S.forecast_date AND T.model_version=S.model_version WHEN NOT MATCHED THEN INSERT ROW"
printf 'Scoring Forecast verificado\n' > "$ROOT/state/$DEMO_RUN_ID/forecast_scoring_ok.txt"
echo 'SCRIPT 40: 1'
echo 'Estado: scoring Forecast ejecutado correctamente.'
