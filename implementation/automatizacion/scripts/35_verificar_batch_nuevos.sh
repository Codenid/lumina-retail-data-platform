#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 35 — verificar batch completo y generar evidencia'
[[ -s "$ROOT/state/$DEMO_RUN_ID/silver_nuevos_ok.txt" ]] || { echo 'SCRIPT 35: 0 — falta 34'; exit 1; }
REPORT="$ROOT/state/$DEMO_RUN_ID/EVIDENCIA_BATCH_COMPLETA.md"
for table in benchmark_competidores eventos_locales redes_sociales; do
  rows="$(bq --project_id="$PROJECT_ID" query --use_legacy_sql=false --format=csv --max_rows=2 "SELECT COUNT(*) FROM \`$PROJECT_ID.$SILVER_DATASET.$table\` WHERE quality_status='VALID'" | tail -1)"
  [[ "$rows" =~ ^[1-9][0-9]*$ ]] || { echo "SCRIPT 35: 0 — $table sin filas válidas" >&2; exit 1; }
done
{
  echo "# Evidencia batch completa — $DEMO_RUN_ID"
  echo "Proyecto: $PROJECT_ID"
  echo "Dominios nuevos: benchmark_competidores, eventos_locales, redes_sociales"
} | tee "$REPORT"
printf 'Batch nuevo verificado\n' > "$ROOT/state/$DEMO_RUN_ID/batch_nuevos_ok.txt"
echo 'SCRIPT 35: 1 — batch nuevo verificado y evidencia generada'
