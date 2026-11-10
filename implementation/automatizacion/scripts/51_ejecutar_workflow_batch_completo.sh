#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 51 — ejecutar Workflow batch completo'
[[ -s "$ROOT/state/$DEMO_RUN_ID/workflow_deployed_ok.txt" ]] || { echo 'SCRIPT 51: 0'; echo 'Dependencia: SCRIPT 50'; exit 1; }
WORKFLOW_NAME="${WORKFLOW_NAME:-${PREFIX}-batch}"
gcloud workflows run "$WORKFLOW_NAME" --project="$PROJECT_ID" --location="$REGION" --data="{\"dataset\":\"$GOLD_DATASET\",\"run_id\":\"$DEMO_RUN_ID\"}" --format=json > "$ROOT/state/$DEMO_RUN_ID/workflow_execution.json"
EXECUTION="$(python3 - "$ROOT/state/$DEMO_RUN_ID/workflow_execution.json" <<'PY'
import json,sys
print(json.load(open(sys.argv[1])).get('name',''))
PY
)"
[[ -n "$EXECUTION" ]] || { echo 'SCRIPT 51: 0'; echo 'Motivo: falta execution name'; exit 1; }
printf '%s\n' "$EXECUTION" > "$ROOT/state/$DEMO_RUN_ID/workflow_execution_name.txt"
echo 'SCRIPT 51: 1 — ejecución iniciada'
