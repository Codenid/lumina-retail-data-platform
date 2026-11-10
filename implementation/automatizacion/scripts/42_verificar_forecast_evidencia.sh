#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 42 — verificar Forecast y generar evidencia'
[[ -s "$ROOT/state/$DEMO_RUN_ID/forecast_plan_ok.txt" ]] || { echo 'SCRIPT 42: 0'; echo 'Dependencia faltante: SCRIPT 41'; exit 1; }
MODEL_VERSION="$(cat "$ROOT/state/$DEMO_RUN_ID/model_version.txt")"
gcloud storage objects describe "gs://$MODELS/forecast/$DEMO_RUN_ID/$MODEL_VERSION/model.json" --format='value(name)' >/dev/null || { echo 'SCRIPT 42: 0'; echo 'Motivo: falta artefacto'; exit 1; }
PREDICTIONS="$(bq --project_id="$PROJECT_ID" query --use_legacy_sql=false --format=csv --max_rows=2 "SELECT COUNT(*) FROM \`$PROJECT_ID.$GOLD_DATASET.forecast_predictions\` WHERE training_run_id='$DEMO_RUN_ID' AND prediction_status='VALID'" | tail -1)"
PLAN="$(bq --project_id="$PROJECT_ID" query --use_legacy_sql=false --format=csv --max_rows=2 "SELECT COUNT(*) FROM \`$PROJECT_ID.$GOLD_DATASET.cu02_plan_reposicion\` WHERE scenario_id='$DEMO_RUN_ID'" | tail -1)"
[[ "$PREDICTIONS" =~ ^[1-9][0-9]*$ && "$PLAN" =~ ^[1-9][0-9]*$ ]] || { echo 'SCRIPT 42: 0'; echo 'Motivo: predicciones o planificación sin filas'; exit 1; }
REPORT="$ROOT/state/$DEMO_RUN_ID/EVIDENCIA_FORECAST.md"
printf '# Evidencia Forecast — %s\n\nPredicciones: %s\nPlanificación CU02: %s\nModelo: %s\n' "$DEMO_RUN_ID" "$PREDICTIONS" "$PLAN" "$MODEL_VERSION" | tee "$REPORT"
echo 'SCRIPT 42: 1'
echo 'Estado: Forecast, scoring y planificación verificados.'
