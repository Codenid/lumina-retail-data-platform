#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 39 — registrar artefacto Forecast baseline'
[[ -s "$ROOT/state/$DEMO_RUN_ID/forecast_features_ok.txt" ]] || { echo 'SCRIPT 39: 0'; echo 'Dependencia faltante: SCRIPT 38'; exit 1; }
FEATURE_ROWS="$(bq --project_id="$PROJECT_ID" query --use_legacy_sql=false --format=csv --max_rows=2 "SELECT COUNT(*) FROM \`$PROJECT_ID.$GOLD_DATASET.forecast_features\` WHERE feature_run_id='$DEMO_RUN_ID'" | tail -1)"
[[ "$FEATURE_ROWS" =~ ^[1-9][0-9]*$ ]] || { echo 'SCRIPT 39: 0'; echo 'Motivo: no existen features válidas'; exit 1; }
MODEL_VERSION='moving_average_7d_v1'
MODEL_FILE="$ROOT/state/$DEMO_RUN_ID/model.json"
printf '{"model_version":"%s","algorithm":"moving_average_7d_baseline","training_run_id":"%s","feature_rows":%s}\n' "$MODEL_VERSION" "$DEMO_RUN_ID" "$FEATURE_ROWS" > "$MODEL_FILE"
gcloud storage cp "$MODEL_FILE" "gs://$MODELS/forecast/$DEMO_RUN_ID/$MODEL_VERSION/model.json" >/dev/null || { echo 'SCRIPT 39: 0'; echo 'Motivo: no se pudo guardar el artefacto'; exit 1; }
gcloud storage objects describe "gs://$MODELS/forecast/$DEMO_RUN_ID/$MODEL_VERSION/model.json" --format='value(name)' >/dev/null || { echo 'SCRIPT 39: 0'; echo 'Motivo: artefacto no verificable'; exit 1; }
printf '%s\n' "$MODEL_VERSION" > "$ROOT/state/$DEMO_RUN_ID/model_version.txt"
printf 'Artefacto Forecast verificado\n' > "$ROOT/state/$DEMO_RUN_ID/forecast_model_ok.txt"
echo 'SCRIPT 39: 1'
echo 'Estado: artefacto Forecast versionado y verificado.'
