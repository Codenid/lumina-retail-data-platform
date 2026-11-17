#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 86 — generar carga operativa de retail'

OPERATING_RUN_ID="${OPERATING_RUN_ID:-operacion-$(date -u +%Y%m)}"
OUTPUT="$ROOT/state/$DEMO_RUN_ID/operating-load/$OPERATING_RUN_ID"
ORDERS_PER_MONTH="${ORDERS_PER_MONTH:-900000}"
STORES="${STORES:-86}"
CATALOG_SKUS="${CATALOG_SKUS:-18420}"
INVENTORY_PER_STORE="${INVENTORY_PER_STORE:-300}"
SHARD_ROWS="${SHARD_ROWS:-100000}"
export OPERATING_RUN_ID OUTPUT

python3 "$ROOT/automatizacion/utilidades/generate_operational_load.py" \
  --output "$OUTPUT" --run-id "$OPERATING_RUN_ID" \
  --orders "$ORDERS_PER_MONTH" --stores "$STORES" \
  --catalog-skus "$CATALOG_SKUS" --inventory-per-store "$INVENTORY_PER_STORE" \
  --shard-rows "$SHARD_ROWS" | tee "$ROOT/state/$DEMO_RUN_ID/operating_load_manifest.json"

printf 'run_id=%s\npath=%s\norders=%s\nstores=%s\ncatalog_skus=%s\n' \
  "$OPERATING_RUN_ID" "$OUTPUT" "$ORDERS_PER_MONTH" "$STORES" "$CATALOG_SKUS" \
  > "$ROOT/state/$DEMO_RUN_ID/operating_load_generated.txt"
echo "SCRIPT 86: 1 — carga operativa generada en $OUTPUT"
