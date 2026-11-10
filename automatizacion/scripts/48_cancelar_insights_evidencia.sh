#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 48 — cancelar Dataflow Insights y generar evidencia'
[[ -s "$ROOT/state/$DEMO_RUN_ID/insights_job_id.txt" ]] || { echo 'SCRIPT 48: 0'; echo 'Dependencia faltante: SCRIPT 45'; exit 1; }
ID="$(cat "$ROOT/state/$DEMO_RUN_ID/insights_job_id.txt")"
VALIDATION='0'; [[ -s "$ROOT/state/$DEMO_RUN_ID/insights_verified.txt" ]] && VALIDATION='1'
STATE="$(gcloud dataflow jobs describe "$ID" --project="$PROJECT_ID" --region="$REGION" --format='value(currentState)')"
if [[ "$STATE" != JOB_STATE_CANCELLED && "$STATE" != JOB_STATE_DONE && "$STATE" != JOB_STATE_FAILED ]]; then gcloud dataflow jobs cancel "$ID" --project="$PROJECT_ID" --region="$REGION"; fi
for i in $(seq 1 30); do STATE="$(gcloud dataflow jobs describe "$ID" --project="$PROJECT_ID" --region="$REGION" --format='value(currentState)')"; case "$STATE" in JOB_STATE_CANCELLED|JOB_STATE_DONE|JOB_STATE_FAILED|JOB_STATE_DRAINED) break;; esac; sleep 10; done
[[ "$STATE" == JOB_STATE_CANCELLED || "$STATE" == JOB_STATE_DONE || "$STATE" == JOB_STATE_FAILED ]] || { echo 'SCRIPT 48: 0'; echo "Motivo: estado final $STATE"; exit 1; }
printf '# Evidencia Insights\n\nJob: %s\nEstado final: %s\nValidación SCRIPT 47: %s\n' "$ID" "$STATE" "$VALIDATION" > "$ROOT/state/$DEMO_RUN_ID/EVIDENCIA_INSIGHTS.md"
echo "SCRIPT 48: 1 — cancelación/evidencia OK; validación SCRIPT 47=$VALIDATION"
