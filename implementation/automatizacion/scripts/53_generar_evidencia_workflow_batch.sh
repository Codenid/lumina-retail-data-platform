#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 53 — evidencia de orquestación batch'
[[ -s "$ROOT/state/$DEMO_RUN_ID/workflow_verified_ok.txt" ]] || { echo 'SCRIPT 53: 0'; echo 'Dependencia: SCRIPT 52'; exit 1; }
{
  echo "# Evidencia Workflow batch — $DEMO_RUN_ID"
  echo
  echo "Proyecto: $PROJECT_ID"
  echo "Región: $REGION"
  echo
  cat "$ROOT/state/$DEMO_RUN_ID/workflow_verified_ok.txt"
  echo
  echo 'Cadena verificada: Bronze → Silver → Gold → operational_mart.'
} > "$ROOT/state/$DEMO_RUN_ID/EVIDENCIA_WORKFLOW_BATCH.md"
echo 'SCRIPT 53: 1 — evidencia guardada'
