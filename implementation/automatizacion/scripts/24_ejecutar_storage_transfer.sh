#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 24 — ejecutar una transferencia Storage Transfer controlada'
JOB="transferJobs/${PREFIX}-landing-bronze"
[[ -s "$ROOT/state/$DEMO_RUN_ID/evento.json" ]] || { echo 'Falta el evento local; ejecuta 08.'; exit 1; }
gcloud transfer jobs describe "$JOB" --project="$PROJECT_ID" --format='value(name)' >/dev/null
gcloud storage objects describe "gs://$LANDING/batch/$DEMO_RUN_ID/evento.json" --format='value(name)' >/dev/null
gcloud transfer jobs run "$JOB" --project="$PROJECT_ID" --format=json | tee "$ROOT/state/$DEMO_RUN_ID/storage_transfer_run.json"
printf 'Transferencia solicitada para %s\n' "$DEMO_RUN_ID" > "$ROOT/state/$DEMO_RUN_ID/storage_transfer_requested.txt"
echo 'Transferencia solicitada; 27 verificará el objeto destino y el estado de la operación.'
