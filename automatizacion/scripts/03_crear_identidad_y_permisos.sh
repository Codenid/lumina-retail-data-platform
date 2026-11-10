#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 03 — cuenta Dataflow y permisos por recurso'
ensure "{\"email\":\"$WORKER\"}" \
 gcloud iam service-accounts describe "$WORKER" --format=json ::: \
 gcloud iam service-accounts create "${PREFIX}-worker" --display-name='RetailSmart demo Dataflow'
gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$WORKER" --role=roles/dataflow.worker --condition=None >/dev/null
for bucket in "$ARTIFACTS" "$SILVER"; do
 # Silver: lectura para verificar reintentos, creación y gestión de objetos de esta demo.
 gcloud storage buckets add-iam-policy-binding "gs://$bucket" --member="serviceAccount:$WORKER" --role=roles/storage.objectUser >/dev/null
 done
NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
AGENT="service-$NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com"
for role in roles/storage.objectCreator roles/storage.legacyBucketReader; do
 gcloud storage buckets add-iam-policy-binding "gs://$BRONZE" --member="serviceAccount:$AGENT" --role="$role" >/dev/null
done
ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)')"
[[ "$ACCOUNT" != *$'\n'* && -n "$ACCOUNT" ]] || { echo 'Debe haber una única cuenta activa'; exit 1; }
if [[ "$ACCOUNT" == *.gserviceaccount.com ]]; then MEMBER="serviceAccount:$ACCOUNT"; else MEMBER="user:$ACCOUNT"; fi
gcloud iam service-accounts add-iam-policy-binding "$WORKER" --member="$MEMBER" --role=roles/iam.serviceAccountUser --condition=None >/dev/null
echo 'Consola: IAM > Cuentas de servicio. No se generan claves JSON.'
