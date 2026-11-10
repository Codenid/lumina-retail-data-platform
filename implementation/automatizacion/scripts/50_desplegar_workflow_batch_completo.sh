#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 50 — desplegar Workflow Bronze-Silver-Gold-mart'
[[ -s "$ROOT/state/$DEMO_RUN_ID/workflow_preflight_ok.txt" ]] || { echo 'SCRIPT 50: 0'; echo 'Dependencia: SCRIPT 49'; exit 1; }
WORKFLOW_NAME="${WORKFLOW_NAME:-${PREFIX}-batch}"
RENDERED_WORKFLOW="$ROOT/state/$DEMO_RUN_ID/workflow_batch.rendered.yaml"
render_template "$ROOT/soluciones/orquestacion-batch/batch.yaml" "$RENDERED_WORKFLOW"
gcloud workflows deploy "$WORKFLOW_NAME" --project="$PROJECT_ID" --location="$REGION" --source="$RENDERED_WORKFLOW" --description='RetailSmart: Bronze-Silver-Gold-mart idempotente'
STATE="$(gcloud workflows describe "$WORKFLOW_NAME" --project="$PROJECT_ID" --location="$REGION" --format='value(state)')"
[[ "$STATE" == ACTIVE ]] || { echo 'SCRIPT 50: 0'; echo "Motivo: Workflow en estado $STATE"; exit 1; }
printf 'workflow=%s\nstate=%s\n' "$WORKFLOW_NAME" "$STATE" > "$ROOT/state/$DEMO_RUN_ID/workflow_deployed_ok.txt"
echo 'SCRIPT 50: 1 — Workflow ACTIVE'
