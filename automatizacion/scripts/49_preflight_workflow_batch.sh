#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 49 — preflight e IAM mínimo de Workflows batch'
WORKFLOW_NAME="${WORKFLOW_NAME:-${PREFIX}-batch}"
NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
WORKFLOW_SA="${NUMBER}-compute@developer.gserviceaccount.com"
gcloud services enable workflows.googleapis.com bigquery.googleapis.com --project="$PROJECT_ID"
gcloud iam service-accounts describe "$WORKFLOW_SA" --project="$PROJECT_ID" >/dev/null
if ! gcloud projects get-iam-policy "$PROJECT_ID" --flatten='bindings[].members' --filter="bindings.members:serviceAccount:$WORKFLOW_SA AND bindings.role:roles/bigquery.jobUser" --format='value(bindings.role)' | grep -qx roles/bigquery.jobUser; then
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$WORKFLOW_SA" --role=roles/bigquery.jobUser --condition=None >/dev/null
fi
for dataset in "$BRONZE_DATASET" "$SILVER_DATASET" "$GOLD_DATASET"; do
  bq show --project_id="$PROJECT_ID" "$PROJECT_ID:$dataset" >/dev/null
done
DATASET_LOCATION="$(bq show --project_id="$PROJECT_ID" --format=json "$PROJECT_ID:$GOLD_DATASET" | python3 -c 'import json,sys; print(json.load(sys.stdin)["location"])')"
run_dcl() { bq --project_id="$PROJECT_ID" --location="$DATASET_LOCATION" query --use_legacy_sql=false "$1" >/dev/null; }
run_dcl "GRANT \`roles/bigquery.dataViewer\` ON SCHEMA \`$PROJECT_ID\`.$BRONZE_DATASET TO \"serviceAccount:$WORKFLOW_SA\""
run_dcl "GRANT \`roles/bigquery.dataEditor\` ON SCHEMA \`$PROJECT_ID\`.$SILVER_DATASET TO \"serviceAccount:$WORKFLOW_SA\""
run_dcl "GRANT \`roles/bigquery.dataEditor\` ON SCHEMA \`$PROJECT_ID\`.$GOLD_DATASET TO \"serviceAccount:$WORKFLOW_SA\""
for dataset in "$BRONZE_DATASET" "$SILVER_DATASET" "$GOLD_DATASET"; do
  bq show --project_id="$PROJECT_ID" --format=json "$PROJECT_ID:$dataset" | python3 -c 'import json,sys; dataset,account=sys.argv[1:]; access=json.load(sys.stdin).get("access", []); ok=any(a.get("userByEmail")==account and a.get("role") in {"READER","WRITER","OWNER"} for a in access); print(f"ACL verificado en {dataset}") if ok else sys.exit(f"ACL DCL ausente en {dataset}")' "$dataset" "$WORKFLOW_SA"
done
printf 'workflow_sa=%s\nworkflow=%s\n' "$WORKFLOW_SA" "$WORKFLOW_NAME" > "$ROOT/state/$DEMO_RUN_ID/workflow_preflight_ok.txt"
echo 'SCRIPT 49: 1 — dependencias, APIs y permisos verificados'
