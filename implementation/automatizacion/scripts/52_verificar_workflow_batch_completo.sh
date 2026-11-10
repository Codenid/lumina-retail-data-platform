#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 52 — verificar ejecución y productos batch'
[[ -s "$ROOT/state/$DEMO_RUN_ID/workflow_execution_name.txt" ]] || { echo 'SCRIPT 52: 0'; echo 'Dependencia: SCRIPT 51'; exit 1; }
WORKFLOW_NAME="${WORKFLOW_NAME:-${PREFIX}-batch}"
EXECUTION="$(cat "$ROOT/state/$DEMO_RUN_ID/workflow_execution_name.txt")"
STATE='RUNNING'
for attempt in $(seq 1 30); do
  STATE="$(gcloud workflows executions describe "$EXECUTION" --project="$PROJECT_ID" --location="$REGION" --workflow="$WORKFLOW_NAME" --format='value(state)')"
  case "$STATE" in
    SUCCEEDED) break ;;
    FAILED|CANCELLED|UNKNOWN) echo 'SCRIPT 52: 0'; echo "Motivo: ejecución $STATE"; exit 1 ;;
  esac
  sleep 10
done
[[ "$STATE" == SUCCEEDED ]] || { echo 'SCRIPT 52: 0'; echo "Motivo: timeout, estado $STATE"; exit 1; }
COUNT="$(bq --project_id="$PROJECT_ID" query --use_legacy_sql=false --format=csv --max_rows=2 "SELECT COUNT(*) FROM \`$PROJECT_ID.$GOLD_DATASET.operational_mart\` WHERE scenario_id='$DEMO_RUN_ID'" | tail -1)"
[[ "$COUNT" =~ ^[1-9][0-9]*$ ]] || { echo 'SCRIPT 52: 0'; echo "Motivo: mart sin filas (count=$COUNT)"; exit 1; }
printf 'state=%s\nmart_rows=%s\nexecution=%s\n' "$STATE" "$COUNT" "$EXECUTION" > "$ROOT/state/$DEMO_RUN_ID/workflow_verified_ok.txt"
echo "SCRIPT 52: 1 — Workflow SUCCEEDED; operational_mart=$COUNT"
