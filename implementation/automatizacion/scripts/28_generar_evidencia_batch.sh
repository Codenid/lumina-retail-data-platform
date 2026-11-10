#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 28 — generar evidencia del bloque batch'
[[ -s "$ROOT/state/$DEMO_RUN_ID/batch_orchestration_verified.txt" ]] || { echo 'Falta 27.'; exit 1; }
{
  echo "# Evidencia batch — $DEMO_RUN_ID"
  echo
  echo "Proyecto: $PROJECT_ID"
  echo "Región: $REGION"
  echo
  echo '- Storage Transfer solicitado y destino Bronze verificado.'
  echo '- Workflow ejecutado y última ejecución registrada.'
  echo '- No se afirma que el Workflow implemente aún todas las transformaciones de negocio.'
} | tee "$ROOT/state/$DEMO_RUN_ID/EVIDENCIA_BATCH.md"
echo 'OK: evidencia batch generada'
