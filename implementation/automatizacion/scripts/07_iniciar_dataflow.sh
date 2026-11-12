#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 07 — iniciar Dataflow (genera costo hasta cancelarlo)'
[[ -x "$ROOT/.venv/bin/python" ]] || { echo 'Ejecuta 06'; exit 1; }
# No se relanza silenciosamente el mismo recorrido. Usa 12 para ver el estado.
if [[ -e "$ROOT/state/$DEMO_RUN_ID/job_id.txt" ]]; then
  OLD_ID="$(cat "$ROOT/state/$DEMO_RUN_ID/job_id.txt")"
  OLD_STATE="$(gcloud dataflow jobs describe "$OLD_ID" --region="$REGION" --format='value(currentState)' 2>/dev/null || true)"
  case "$OLD_STATE" in
    JOB_STATE_PENDING|JOB_STATE_RUNNING|JOB_STATE_CANCELLING|JOB_STATE_QUEUED)
      echo "Este recorrido ya tiene un job activo ($OLD_ID, $OLD_STATE). Verifica/cancela antes de iniciar otro."; exit 1;;
    *)
      mv "$ROOT/state/$DEMO_RUN_ID/job_id.txt" "$ROOT/state/$DEMO_RUN_ID/job_id.previous-$OLD_STATE.txt"
      echo "Job anterior terminal ($OLD_STATE) conservado; se permite una nueva ejecución.";;
  esac
fi
JOBS="$(gcloud dataflow jobs list --region="$REGION" --status=active --format=json)"
export JOBS
python3 - <<'CHECK'
import json, os
assert not any(j['name'].startswith(os.environ['PREFIX']+'-silver-') for j in json.loads(os.environ['JOBS'])), 'Ya hay un job Silver activo de este paquete: cancélalo primero.'
CHECK
cd "$ROOT"
"$ROOT/.venv/bin/python" "$ROOT/soluciones/procesamiento-streaming/streaming.py" \
 --runner=DataflowRunner --project="$PROJECT_ID" --region="$REGION" --streaming \
 --job_name="$JOB_NAME" --service_account_email="$WORKER" --network="$NETWORK" \
 --num_workers=2 --max_num_workers=20 --autoscaling_algorithm=THROUGHPUT_BASED \
 --worker_machine_type=e2-standard-2 --disk_size_gb=30 \
 --staging_location="gs://$ARTIFACTS/staging" --temp_location="gs://$ARTIFACTS/temp" \
 --setup_file="$ROOT/soluciones/procesamiento-streaming/setup.py" --requirements_file="$ROOT/soluciones/procesamiento-streaming/requirements.txt" --save_main_session \
 --input_subscription="projects/$PROJECT_ID/subscriptions/$DF_SUB" \
 --silver_table="$PROJECT_ID:$SILVER_DATASET.pedidos" \
 --silver_inventory_table="$PROJECT_ID:$SILVER_DATASET.inventario" \
 --silver_delivery_table="$PROJECT_ID:$SILVER_DATASET.entregas" \
 --silver_telemetry_table="$PROJECT_ID:$SILVER_DATASET.telemetria_activos" 2>&1 | tee "$ROOT/state/$DEMO_RUN_ID/lanzamiento.log"
sed -n 's/^JOB_ID=//p' "$ROOT/state/$DEMO_RUN_ID/lanzamiento.log" > "$ROOT/state/$DEMO_RUN_ID/job_id.txt"
[[ -s "$ROOT/state/$DEMO_RUN_ID/job_id.txt" ]] || { echo 'No se capturó ID. Revisa la consola Dataflow antes de repetir.'; exit 1; }
echo 'Espera RUNNING y revisa el worker en Dataflow > Jobs. Luego ejecuta 08.'
