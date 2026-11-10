#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 58 — verificar el lote de seis fuentes y cerrar evidencia'
[[ -s "$ROOT/state/$DEMO_RUN_ID/batch_productivo_gold_ok.txt" ]] || { echo 'SCRIPT 58: 0 — dependencia: SCRIPT 57'; exit 1; }
BATCH_RUN_ID="$(cat "$ROOT/state/$DEMO_RUN_ID/batch_productivo_id.txt")"
LOCATION="$(sed -n 's/^dataset_location=//p' "$ROOT/state/$DEMO_RUN_ID/batch_productivo_preflight.txt")"
REPORT="$ROOT/state/$DEMO_RUN_ID/EVIDENCIA_BATCH_PRODUCTIVO.md"
for domain in pedidos inventario entregas benchmark_competidores eventos_locales redes_sociales; do
  raw="$(bq --project_id="$PROJECT_ID" --location="$LOCATION" query --use_legacy_sql=false --format=csv --max_rows=2 "SELECT COUNT(*) FROM \`$PROJECT_ID.$BRONZE_DATASET.${domain}_raw\` WHERE batch_id='$BATCH_RUN_ID'" | tail -1)"
  [[ "$raw" =~ ^[1-9][0-9]*$ ]] || { echo "SCRIPT 58: 0 — Bronze $domain count=$raw"; exit 1; }
  echo "Bronze $domain=$raw"
done
for item in 'pedidos:order_id:ORD' 'inventario:snapshot_id:' 'entregas:delivery_id:DEL' 'benchmark_competidores:benchmark_id:BENCH' 'eventos_locales:local_event_id:LOCAL' 'redes_sociales:post_id:POST'; do
  IFS=: read -r table key prefix <<< "$item"
  if [[ "$table" == inventario ]]; then predicate="snapshot_id LIKE CONCAT('$BATCH_RUN_ID',':%')"; else predicate="$key='${prefix}-${BATCH_RUN_ID}'"; fi
  count="$(bq --project_id="$PROJECT_ID" --location="$LOCATION" query --use_legacy_sql=false --format=csv --max_rows=2 "SELECT COUNT(*) FROM \`$PROJECT_ID.$SILVER_DATASET.$table\` WHERE quality_status='VALID' AND $predicate" | tail -1)"
  [[ "$count" =~ ^[1-9][0-9]*$ ]] || { echo "SCRIPT 58: 0 — Silver $table count=$count"; exit 1; }
  echo "Silver $table=$count"
done
for table in cu01_riesgo_quiebre_despacho cu02_plan_reposicion cu03_kpis_operativos; do
  count="$(bq --project_id="$PROJECT_ID" --location="$LOCATION" query --use_legacy_sql=false --format=csv --max_rows=2 "SELECT COUNT(*) FROM \`$PROJECT_ID.$GOLD_DATASET.$table\` WHERE scenario_id='$BATCH_RUN_ID'" | tail -1)"
  [[ "$count" =~ ^[1-9][0-9]*$ ]] || { echo "SCRIPT 58: 0 — Gold $table count=$count"; exit 1; }
  echo "Gold $table=$count"
done
MART="$(bq --project_id="$PROJECT_ID" --location="$LOCATION" query --use_legacy_sql=false --format=csv --max_rows=2 "SELECT COUNT(*) FROM \`$PROJECT_ID.$GOLD_DATASET.operational_mart\` WHERE scenario_id='$BATCH_RUN_ID'" | tail -1)"
[[ "$MART" =~ ^[1-9][0-9]*$ ]] || { echo "SCRIPT 58: 0 — operational_mart count=$MART"; exit 1; }
{
  echo "# Evidencia batch productivo — $BATCH_RUN_ID"
  echo
  cat "$ROOT/state/$DEMO_RUN_ID/batch_productivo_preflight.txt"
  echo
  echo 'Bronze y Silver verificados: pedidos, inventario, entregas, benchmark_competidores, eventos_locales y redes_sociales.'
  echo 'Gold verificado: CU01 riesgo de quiebre, CU02 reposición y CU03 KPIs/entregas.'
  echo "operational_mart=$MART"
  echo 'Ejecución idempotente por batch_id y claves de negocio.'
} > "$REPORT"
printf '%s\n' "$REPORT" > "$ROOT/state/$DEMO_RUN_ID/batch_productivo_verified.txt"
echo "SCRIPT 58: 1 — seis fuentes verificadas; operational_mart=$MART; evidencia=$REPORT"
