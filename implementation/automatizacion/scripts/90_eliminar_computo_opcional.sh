#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Eliminación manual de cómputo OPCIONAL; conserva buckets, tablas y datos'
[[ "${1:-}" == "$PROJECT_ID" ]] || { echo "Uso: bash automatizacion/scripts/90_eliminar_computo_opcional.sh $PROJECT_ID workflow|spark"; exit 1; }
case "${2:-}" in
 workflow) gcloud workflows delete "${WORKFLOW_NAME:-${PREFIX}-batch}" --project="$PROJECT_ID" --location="$REGION";;
 spark) gcloud dataproc clusters delete "${PREFIX}-spark" --region="$REGION";;
 *) echo 'Selecciona workflow o spark'; exit 1;;
esac
