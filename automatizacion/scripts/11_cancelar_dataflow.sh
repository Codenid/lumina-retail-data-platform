#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 11 — cancelar el job registrado; conserva los datos'
ID="$(cat "$ROOT/state/$DEMO_RUN_ID/job_id.txt")"
ACTUAL="$(gcloud dataflow jobs describe "$ID" --region="$REGION" --format='value(name)')"
[[ "$ACTUAL" == "$JOB_NAME" ]] || { echo 'El job no corresponde a esta ejecución'; exit 1; }
STATUS="$(gcloud dataflow jobs describe "$ID" --region="$REGION" --format='value(currentState)')"
if [[ "$STATUS" != JOB_STATE_CANCELLED && "$STATUS" != JOB_STATE_DONE && "$STATUS" != JOB_STATE_FAILED && "$STATUS" != JOB_STATE_DRAINED ]]; then
 gcloud dataflow jobs cancel "$ID" --region="$REGION"
fi
for attempt in $(seq 1 30); do
 STATUS="$(gcloud dataflow jobs describe "$ID" --region="$REGION" --format='value(currentState)')"
 echo "$STATUS"
 case "$STATUS" in
 JOB_STATE_CANCELLED|JOB_STATE_DONE|JOB_STATE_FAILED|JOB_STATE_DRAINED)
  echo "$STATUS" > "$ROOT/state/$DEMO_RUN_ID/estado_final.txt"
  echo 'Estado terminal confirmado. Revisa que no queden otros jobs anteriores activos.'; exit 0;;
 esac
 sleep 10
done
echo 'No se confirmó estado terminal en 5 min; revisa la consola. El job puede seguir generando costo.'; exit 1
