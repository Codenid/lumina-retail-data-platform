#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 69 — crear vistas BigQuery para consumo externo futuro'
[[ -s "$ROOT/state/$DEMO_RUN_ID/reporting_preflight.txt" ]] || { echo 'SCRIPT 69: 0 — dependencia: SCRIPT 68'; exit 1; }
LOCATION="$(sed -n 's/^location=//p' "$ROOT/state/$DEMO_RUN_ID/reporting_preflight.txt")"
create_view() {
  local target="$1" source="$2"
  bq --project_id="$PROJECT_ID" --location="$LOCATION" query --use_legacy_sql=false \
    "CREATE OR REPLACE VIEW \`$PROJECT_ID.$GOLD_DATASET.$target\` AS SELECT * FROM \`$PROJECT_ID.$GOLD_DATASET.$source\`"
}
create_view reporting_riesgo_quiebre cu01_riesgo_quiebre_despacho
create_view reporting_plan_reposicion cu02_plan_reposicion
create_view reporting_kpis_operativos cu03_kpis_operativos
create_view reporting_alertas_mantenimiento cu04_alertas_mantenimiento
OUT="$ROOT/state/$DEMO_RUN_ID/reporting_view_counts.txt"
: > "$OUT"
for view in reporting_riesgo_quiebre reporting_plan_reposicion reporting_kpis_operativos reporting_alertas_mantenimiento; do
  TYPE="$(bq --project_id="$PROJECT_ID" show --format=json "$PROJECT_ID:$GOLD_DATASET.$view" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("type",""))')"
  [[ "$TYPE" == VIEW ]] || { echo "SCRIPT 69: 0 — $view no es VIEW"; exit 1; }
  rows="$(bq --project_id="$PROJECT_ID" --location="$LOCATION" query --use_legacy_sql=false --format=csv "SELECT COUNT(*) AS n FROM \`$PROJECT_ID.$GOLD_DATASET.$view\`" | tail -n1 | tr -d '\r')"
  [[ "$rows" =~ ^[1-9][0-9]*$ ]] || { echo "SCRIPT 69: 0 — vista vacía: $view"; exit 1; }
  printf '%s=%s\n' "$view" "$rows" >> "$OUT"
done
printf 'SCRIPT 69: 1 — cuatro vistas BigQuery creadas y verificadas\n' > "$ROOT/state/$DEMO_RUN_ID/reporting_views_ok.txt"
echo 'SCRIPT 69: 1 — cuatro vistas BigQuery creadas y verificadas; consumidor externo queda fuera del alcance'
