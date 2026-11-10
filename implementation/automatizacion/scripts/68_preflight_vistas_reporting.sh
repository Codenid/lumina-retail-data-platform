#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 68 — validar contrato y fuentes Gold para reporting BigQuery'
CONTRACT="$ROOT/automatizacion/configuracion/contratos/reporting_views.json"
[[ -s "$CONTRACT" ]] || { echo 'SCRIPT 68: 0 — falta contrato de vistas de reporting'; exit 1; }
python3 - "$CONTRACT" "$PROJECT_ID" "$GOLD_DATASET" "$REGION" <<'PY'
import json,sys
c=json.load(open(sys.argv[1],encoding='utf-8'))
def render(value):
    return (value.replace('{{PROJECT_ID}}',sys.argv[2])
                 .replace('{{PREFIX}}',sys.argv[3].removesuffix('_gold'))
                 .replace('{{REGION}}',sys.argv[4]))
assert render(c['project'])==sys.argv[2] and render(c['dataset'])==sys.argv[3] and render(c['location'])==sys.argv[4]
assert c['consumer']=='aplicacion_externa_opcional_futura'
expected={
 'riesgo_quiebre':('reporting_riesgo_quiebre','cu01_riesgo_quiebre_despacho'),
 'plan_reposicion':('reporting_plan_reposicion','cu02_plan_reposicion'),
 'kpis_operativos':('reporting_kpis_operativos','cu03_kpis_operativos'),
 'alertas_mantenimiento':('reporting_alertas_mantenimiento','cu04_alertas_mantenimiento')}
actual={k:(v['view'],v['source']) for k,v in c['products'].items()}
assert actual==expected, f'contrato divergente: {actual}'
print('Contrato de cuatro vistas Gold para consumo externo futuro verificado')
PY
LOCATION="$(bq --project_id="$PROJECT_ID" show --format=json "$PROJECT_ID:$GOLD_DATASET" | python3 -c 'import json,sys; print(json.load(sys.stdin)["location"])')"
[[ "$LOCATION" == "$REGION" ]] || { echo "SCRIPT 68: 0 — Gold está en $LOCATION, se esperaba $REGION"; exit 1; }
for table in cu01_riesgo_quiebre_despacho cu02_plan_reposicion cu03_kpis_operativos cu04_alertas_mantenimiento; do
  bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET.$table" >/dev/null
  rows="$(bq --project_id="$PROJECT_ID" --location="$LOCATION" query --use_legacy_sql=false --format=csv "SELECT COUNT(*) AS n FROM \`$PROJECT_ID.$GOLD_DATASET.$table\`" | tail -n1 | tr -d '\r')"
  [[ "$rows" =~ ^[1-9][0-9]*$ ]] || { echo "SCRIPT 68: 0 — fuente Gold vacía: $table"; exit 1; }
done
printf 'location=%s\nsources=4\nconsumer=aplicacion_externa_opcional_futura\n' "$LOCATION" > "$ROOT/state/$DEMO_RUN_ID/reporting_preflight.txt"
echo 'SCRIPT 68: 1 — cuatro fuentes Gold y ubicación verificadas; no se configura un consumidor'
