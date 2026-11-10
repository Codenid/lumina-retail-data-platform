#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 19 — verificación CU01–CU04'
run_query() { bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --format=csv --max_rows=20 --maximum_bytes_billed=10485760 "$1"; }
[[ -s "$ROOT/state/$DEMO_RUN_ID/silver_batch_ok.txt" ]] || { echo 'Falta 16'; exit 1; }
[[ -s "$ROOT/state/$DEMO_RUN_ID/gold_casos_ok.txt" ]] || { echo 'Falta 17'; exit 1; }
[[ -s "$ROOT/state/$DEMO_RUN_ID/mart_ok.txt" ]] || { echo 'Falta 18'; exit 1; }
for table in cu01_riesgo_quiebre_despacho cu02_plan_reposicion cu03_kpis_operativos cu04_alertas_mantenimiento operational_mart; do
  bq --project_id="$PROJECT_ID" ls "$GOLD_DATASET" | grep -q "$table" || { echo "Falta tabla Gold: $table"; exit 1; }
done
{
  echo "# Verificación CU01–CU04 — $DEMO_RUN_ID"
  for spec in "CU01|cu01_riesgo_quiebre_despacho" "CU02|cu02_plan_reposicion" "CU03|cu03_kpis_operativos" "CU04|cu04_alertas_mantenimiento" "MART|operational_mart"; do
    IFS='|' read -r label table <<< "$spec"
    result="$(run_query "SELECT COUNT(*) filas FROM \`$PROJECT_ID.$GOLD_DATASET.$table\` WHERE scenario_id='$DEMO_RUN_ID'")"
    [[ "$result" != *$'\n0' && "$result" != '0' ]] || { echo "$label sin filas"; exit 1; }
    echo "- $label: $table — filas verificadas"
  done
} | tee "$ROOT/state/$DEMO_RUN_ID/casos_uso_verificados.md"
echo 'OK: CU01–CU04 y mart operacional verificados'
