#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 85 — verificar salidas de los cuatro consumidores'
[[ -s "$ROOT/state/$DEMO_RUN_ID/batch_productivo_gold_ok.txt" ]] || { echo 'SCRIPT 85: 0 — ejecuta primero SCRIPT 57'; exit 1; }
BATCH_RUN_ID="$(cat "$ROOT/state/$DEMO_RUN_ID/batch_productivo_id.txt")"
LOCATION="$(sed -n 's/^dataset_location=//p' "$ROOT/state/$DEMO_RUN_ID/batch_productivo_preflight.txt")"
for table in cu01_riesgo_quiebre_despacho cu02_plan_reposicion cu03_kpis_operativos cu04_alertas_mantenimiento; do
  count="$(bq --project_id="$PROJECT_ID" --location="$LOCATION" query --use_legacy_sql=false --format=csv --max_rows=2 "SELECT COUNT(*) FROM \`$PROJECT_ID.$GOLD_DATASET.$table\` WHERE scenario_id='$BATCH_RUN_ID'" | tail -1)"
  [[ "$count" =~ ^[1-9][0-9]*$ ]] || { echo "SCRIPT 85: 0 — $table sin filas para $BATCH_RUN_ID"; exit 1; }
  echo "$table=$count"
done
echo 'SCRIPT 85: 1 — cuatro salidas Gold listas para API/dashboard/reporting'
