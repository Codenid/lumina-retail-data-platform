#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 18 — mart operativo streaming + batch'
run_query() { bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --maximum_bytes_billed=31457280 "$1"; }
run_query "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$GOLD_DATASET.operational_mart\` (scenario_id STRING, entity_type STRING, entity_id STRING, sku_id STRING, store_id STRING, warehouse_id STRING, quantity INT64, status STRING, observed_at TIMESTAMP, ingestion_mode STRING)"
run_query "DELETE FROM \`$PROJECT_ID.$GOLD_DATASET.operational_mart\` WHERE scenario_id='$DEMO_RUN_ID'"
run_query "INSERT INTO \`$PROJECT_ID.$GOLD_DATASET.operational_mart\` SELECT '$DEMO_RUN_ID','ORDER',order_id,sku_id,store_id,warehouse_id,quantity,quality_status,occurred_at,'streaming_or_batch' FROM \`$PROJECT_ID.$SILVER_DATASET.pedidos\` WHERE quality_status='VALID'"
run_query "INSERT INTO \`$PROJECT_ID.$GOLD_DATASET.operational_mart\` SELECT '$DEMO_RUN_ID','INVENTORY',snapshot_id,sku_id,store_id,warehouse_id,on_hand_qty-reserved_qty,quality_status,effective_at,'batch' FROM \`$PROJECT_ID.$SILVER_DATASET.inventario\` WHERE quality_status='VALID'"
printf 'Mart operacional verificado para %s\n' "$DEMO_RUN_ID" > "$ROOT/state/$DEMO_RUN_ID/mart_ok.txt"
echo 'OK: mart operacional materializado'
