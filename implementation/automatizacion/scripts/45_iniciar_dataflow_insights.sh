#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 45 — iniciar Dataflow Insights'
[[ -s "$ROOT/state/$DEMO_RUN_ID/insights_tables_ok.txt" ]] || { echo 'SCRIPT 45: 0'; echo 'Dependencia faltante: SCRIPT 44'; exit 1; }
SUB="${PREFIX}-insights-dataflow"
if ! gcloud pubsub subscriptions describe "$SUB" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud pubsub subscriptions create "$SUB" --project="$PROJECT_ID" --topic="$INSIGHTS_TOPIC"
fi
gcloud pubsub subscriptions add-iam-policy-binding "$SUB" --project="$PROJECT_ID" --member="serviceAccount:$WORKER" --role=roles/pubsub.subscriber >/dev/null
NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
DATAFLOW_AGENT="service-$NUMBER@dataflow-service-producer-prod.iam.gserviceaccount.com"
gcloud pubsub subscriptions add-iam-policy-binding "$SUB" --project="$PROJECT_ID" --member="serviceAccount:$DATAFLOW_AGENT" --role=roles/pubsub.subscriber >/dev/null
for table in insights_streaming procesamiento_auditoria; do bq add-iam-policy-binding --member="serviceAccount:$WORKER" --role=roles/bigquery.dataEditor -t "$PROJECT_ID:$GOLD_DATASET.$table" >/dev/null; done
JOB="${PREFIX}-insights-${DEMO_RUN_ID}-$(date -u +%H%M%S)"
if ! "$ROOT/.venv/bin/python" -c 'import build' >/dev/null 2>&1; then
  "$ROOT/.venv/bin/python" -m pip install build >/dev/null || { echo 'SCRIPT 45: 0'; echo 'Motivo: no se pudo instalar build'; exit 1; }
fi
LOG="$ROOT/state/$DEMO_RUN_ID/insights_dataflow.log"
"$ROOT/.venv/bin/python" "$ROOT/soluciones/procesamiento-streaming/insights_streaming.py" --runner=DataflowRunner --project="$PROJECT_ID" --region="$REGION" --streaming --job_name="$JOB" --service_account_email="$WORKER" --num_workers=1 --max_num_workers=1 --autoscaling_algorithm=NONE --staging_location="gs://$ARTIFACTS/staging" --temp_location="gs://$ARTIFACTS/temp" --setup_file="$ROOT/soluciones/procesamiento-streaming/setup.py" --requirements_file="$ROOT/soluciones/procesamiento-streaming/requirements.txt" --input_subscription="projects/$PROJECT_ID/subscriptions/$SUB" --insights_table="$PROJECT_ID:$GOLD_DATASET.insights_streaming" --audit_table="$PROJECT_ID:$GOLD_DATASET.procesamiento_auditoria" > "$LOG" 2>&1 &
LAUNCHER_PID=$!
for attempt in $(seq 1 60); do
  ID="$(gcloud dataflow jobs list --project="$PROJECT_ID" --region="$REGION" --filter="name=$JOB" --format='value(id)' --limit=1 2>/dev/null || true)"
  if [[ -n "$ID" ]]; then printf '%s\n' "$ID" > "$ROOT/state/$DEMO_RUN_ID/insights_job_id.txt"; break; fi
  if ! kill -0 "$LAUNCHER_PID" 2>/dev/null && [[ "$attempt" -gt 10 ]]; then break; fi
  sleep 5
done
[[ -s "$ROOT/state/$DEMO_RUN_ID/insights_job_id.txt" ]] || { echo 'SCRIPT 45: 0'; echo 'Motivo: no se capturó job Dataflow'; exit 1; }
echo 'SCRIPT 45: 1'
