#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 00 — acceso; solo lectura'
gcloud auth list --filter=status:ACTIVE --format='table(account,status)'
gcloud projects describe "$PROJECT_ID" --format='table(projectId,projectNumber,lifecycleState)'
gcloud billing projects describe "$PROJECT_ID" --format='yaml(billingEnabled,billingAccountName)'
gcloud compute networks describe "$NETWORK" --format='table(name,autoCreateSubnetworks)'
command -v bq >/dev/null
python3 --version
echo "Proyecto: $PROJECT_ID | Región: $REGION | Prefijo: $PREFIX"
echo 'Si billingEnabled no es true, habilita facturación antes de continuar.'
echo 'Si Compute API aún no está habilitada, ejecuta 01 y repite 00.'
