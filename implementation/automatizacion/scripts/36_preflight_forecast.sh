#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 36 — preflight de contrato y permisos Forecast'
CONTRACT="$ROOT/automatizacion/configuracion/contratos/forecast.json"
[[ -s "$CONTRACT" ]] || { echo 'SCRIPT 36: 0 — falta contrato Forecast'; exit 1; }
for api in bigquery.googleapis.com dataproc.googleapis.com; do
  gcloud services list --enabled --project="$PROJECT_ID" --format='value(config.name)' | grep -qx "$api" || { echo "SCRIPT 36: 0 — API $api no habilitada"; exit 1; }
done
gcloud storage buckets describe "gs://$MODELS" --project="$PROJECT_ID" >/dev/null || { echo "SCRIPT 36: 0 — falta bucket $MODELS"; exit 1; }
bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$SILVER_DATASET" >/dev/null || { echo "SCRIPT 36: 0 — falta Silver"; exit 1; }
bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET" >/dev/null || { echo "SCRIPT 36: 0 — falta Gold"; exit 1; }
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["algorithm"] and d["features"] and d["predictions"] and d["feature_key"] and d["prediction_key"]; print("Contrato Forecast verificado")' "$CONTRACT"
printf 'Preflight Forecast OK\n' > "$ROOT/state/$DEMO_RUN_ID/preflight_forecast_ok.txt"
echo 'SCRIPT 36: 1 — contrato y dependencias Forecast verificadas'
