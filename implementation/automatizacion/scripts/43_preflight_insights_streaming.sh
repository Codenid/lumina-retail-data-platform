#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 43 — preflight de contrato y permisos Insights Streaming'
[[ -s "$ROOT/state/$DEMO_RUN_ID/preflight_batch_ok.txt" ]] || { echo 'SCRIPT 43: 0'; echo 'Dependencia faltante: SCRIPT 29'; exit 1; }
CONTRACT="$ROOT/automatizacion/configuracion/contratos/insights_streaming.json"
[[ -s "$CONTRACT" ]] || { echo 'SCRIPT 43: 0'; echo 'Dependencia faltante: contrato Insights'; exit 1; }
gcloud services list --enabled --project="$PROJECT_ID" --format='value(config.name)' | grep -qx dataflow.googleapis.com || { echo 'SCRIPT 43: 0'; echo 'Motivo: API Dataflow no habilitada'; exit 1; }
gcloud pubsub topics describe "$TOPIC" --project="$PROJECT_ID" >/dev/null || { echo 'SCRIPT 43: 0'; echo 'Motivo: tópico Eventos Retail inexistente'; exit 1; }
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["insight_fields"] and d["audit_fields"] and d["insight_key"]; print("Contrato Insights verificado")' "$CONTRACT"
printf 'Preflight Insights OK\n' > "$ROOT/state/$DEMO_RUN_ID/preflight_insights_ok.txt"
echo 'SCRIPT 43: 1'
echo 'Estado: contrato, API y tópico Insights verificados.'
