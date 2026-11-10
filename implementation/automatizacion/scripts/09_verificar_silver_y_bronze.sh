#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 09 — verificar Bronze y Silver BigQuery'
ORDER_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["payload"]["order_id"])' "$ROOT/state/$DEMO_RUN_ID/evento.json")"
BRONZE_QUERY="SELECT COUNTIF(JSON_VALUE(data,'$.event_id')='evt-$DEMO_RUN_ID') AS filas FROM \`$PROJECT_ID.$BRONZE_DATASET.eventos_raw_pubsub\`"
SILVER_QUERY="SELECT COUNTIF(order_id='$ORDER_ID') AS filas FROM \`$PROJECT_ID.$SILVER_DATASET.pedidos\`"
B="$(bq --project_id="$PROJECT_ID" query --use_legacy_sql=false --format=csv --max_rows=2 "$BRONZE_QUERY" | tail -1)"
S="$(bq --project_id="$PROJECT_ID" query --use_legacy_sql=false --format=csv --max_rows=2 "$SILVER_QUERY" | tail -1)"
[[ "$B" =~ ^[0-9]+$ && "$S" =~ ^[0-9]+$ && "$B" -ge 1 && "$S" -ge 1 ]] || { echo "Bronze/Silver no verificados: bronze=$B silver=$S"; exit 1; }
printf '{"bronze_rows":%s,"silver_rows":%s,"order_id":"%s"}\n' "$B" "$S" "$ORDER_ID" > "$ROOT/state/$DEMO_RUN_ID/bigquery_verificacion.json"
[[ "$B" -gt 1 ]] && echo "Advertencia: $((B-1)) coincidencia(s) adicional(es) en Bronze; revisar deduplicación por event_id."
printf 'Bronze y Silver BigQuery verificados para %s\n' "$DEMO_RUN_ID" | tee "$ROOT/state/$DEMO_RUN_ID/verificado.txt"
