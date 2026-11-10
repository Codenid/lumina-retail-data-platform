#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 29 — preflight de permisos y dependencias batch (solo lectura)'
fail=0
check() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then echo "OK: $label"; else echo "FALTA/BLOQUEADO: $label"; fail=1; fi; }
ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)')"
NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
WORKFLOW_SA="${NUMBER}-compute@developer.gserviceaccount.com"
DATAPROC_SA="${PREFIX}-spark@${PROJECT_ID}.iam.gserviceaccount.com"
TRANSFER_SA="project-${NUMBER}@storage-transfer-service.iam.gserviceaccount.com"
echo "Cuenta activa: $ACCOUNT"
echo "Proyecto: $PROJECT_ID ($NUMBER)"
echo "Región: $REGION"
for api in bigquery.googleapis.com workflows.googleapis.com dataproc.googleapis.com storagetransfer.googleapis.com; do
  check "API $api habilitada" gcloud services list --enabled --project="$PROJECT_ID" --filter="config.name=$api" --format='value(config.name)' --limit=1
done
for dataset in "$BRONZE_DATASET" "$SILVER_DATASET" "$GOLD_DATASET"; do
  check "dataset $dataset" bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$dataset"
done
for bucket in "$LANDING" "$BRONZE" "$SILVER" "$ARTIFACTS" "$MODELS"; do
  check "bucket $bucket" gcloud storage buckets describe "gs://$bucket" --project="$PROJECT_ID"
done
check "cuenta Dataproc $DATAPROC_SA" gcloud iam service-accounts describe "$DATAPROC_SA" --project="$PROJECT_ID"
check "cuenta Workflow $WORKFLOW_SA" gcloud iam service-accounts describe "$WORKFLOW_SA" --project="$PROJECT_ID"
echo "Agente Storage Transfer esperado: $TRANSFER_SA"
if gcloud projects get-iam-policy "$PROJECT_ID" --flatten='bindings[].members' --filter="bindings.members:serviceAccount:$WORKFLOW_SA AND bindings.role:roles/bigquery.jobUser" --format='value(bindings.role)' | grep -qx roles/bigquery.jobUser; then
  echo "OK: $WORKFLOW_SA tiene roles/bigquery.jobUser"
else
  echo "FALTA/BLOQUEADO: $WORKFLOW_SA requiere roles/bigquery.jobUser a nivel de proyecto"; fail=1
fi
if [[ "$fail" -ne 0 ]]; then
  echo 'PREFLIGHT FALLIDO: no se ejecutan procesos batch.' >&2; exit 1
fi
printf 'Preflight OK para %s\n' "$DEMO_RUN_ID" > "$ROOT/state/$DEMO_RUN_ID/preflight_batch_ok.txt"
echo 'PREFLIGHT OK: se puede continuar con el procesamiento batch.'
