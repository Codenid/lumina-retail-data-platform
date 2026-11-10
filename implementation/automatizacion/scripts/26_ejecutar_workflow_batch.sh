#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 26 — ejecutar Workflow batch'
WORKFLOW_NAME="${WORKFLOW_NAME:-${PREFIX}-batch}"
[[ -s "$ROOT/state/$DEMO_RUN_ID/workflow_deployed.txt" ]] || { echo 'Falta 25; despliega el Workflow primero.'; exit 1; }
OUTPUT="$ROOT/state/$DEMO_RUN_ID/workflow_run.json"
gcloud workflows run "$WORKFLOW_NAME" --project="$PROJECT_ID" --location="$REGION" \
  --data="{\"dataset\":\"$GOLD_DATASET\",\"run_id\":\"$DEMO_RUN_ID\"}" \
  --format=json | tee "$OUTPUT"
STATE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("state", "UNKNOWN"))' "$OUTPUT")"
[[ "$STATE" == SUCCEEDED ]] || { echo "Workflow terminó en estado $STATE; revisar $OUTPUT" >&2; exit 1; }
printf 'Ejecución solicitada para %s\n' "$DEMO_RUN_ID" > "$ROOT/state/$DEMO_RUN_ID/workflow_run_requested.txt"
