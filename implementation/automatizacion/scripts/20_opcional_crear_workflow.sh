#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'OPCIONAL — crear orquestación batch con Google Cloud Workflows'

WORKFLOW_NAME="${WORKFLOW_NAME:-${PREFIX}-batch}"
WORKFLOW_FILE="$ROOT/soluciones/orquestacion-batch/batch.yaml"
[[ -f "$WORKFLOW_FILE" ]] || { echo "Falta definición: $WORKFLOW_FILE"; exit 1; }
RENDERED_WORKFLOW="$ROOT/state/$DEMO_RUN_ID/workflow_batch.rendered.yaml"
render_template "$WORKFLOW_FILE" "$RENDERED_WORKFLOW"

gcloud services enable workflows.googleapis.com --project="$PROJECT_ID"

ensure "{\"name\":\"projects/$PROJECT_ID/locations/$REGION/workflows/$WORKFLOW_NAME\"}" \
  gcloud workflows describe "$WORKFLOW_NAME" --project="$PROJECT_ID" --location="$REGION" --format=json ::: \
  gcloud workflows deploy "$WORKFLOW_NAME" --project="$PROJECT_ID" --location="$REGION" \
    --source="$RENDERED_WORKFLOW" --description='RetailSmart: orquestación batch Bronze-Silver-Gold'

gcloud workflows describe "$WORKFLOW_NAME" --project="$PROJECT_ID" --location="$REGION" \
  --format='table(name,state,revisionId)'
echo "Workflow creado/verificado: $WORKFLOW_NAME"
echo 'La ejecución del workflow es independiente; no se inicia automáticamente.'
