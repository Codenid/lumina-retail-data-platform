#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 27 — verificar transferencia y Workflow'
[[ -s "$ROOT/state/$DEMO_RUN_ID/storage_transfer_requested.txt" ]] || { echo 'Falta 24.'; exit 1; }
[[ -s "$ROOT/state/$DEMO_RUN_ID/workflow_run_requested.txt" ]] || { echo 'Falta 26.'; exit 1; }
WORKFLOW_STATE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("state", "UNKNOWN"))' "$ROOT/state/$DEMO_RUN_ID/workflow_run.json")"
[[ "$WORKFLOW_STATE" == SUCCEEDED ]] || { echo "Workflow no exitoso: $WORKFLOW_STATE"; exit 1; }
gcloud storage objects describe "gs://$BRONZE/batch/$DEMO_RUN_ID/evento.json" --format='table(name,size,contentType)'
gcloud workflows executions list "${WORKFLOW_NAME:-${PREFIX}-batch}" \
  --project="$PROJECT_ID" --location="$REGION" --limit=1 --format='table(name,state,startTime,endTime)'
printf 'Transferencia y Workflow verificados para %s\n' "$DEMO_RUN_ID" > "$ROOT/state/$DEMO_RUN_ID/batch_orchestration_verified.txt"
