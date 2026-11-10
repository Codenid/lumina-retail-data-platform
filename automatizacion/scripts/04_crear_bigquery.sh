#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 04 — datasets y contratos Bronze/Silver/Gold'
for dataset in "$BRONZE_DATASET" "$SILVER_DATASET" "$GOLD_DATASET"; do
  ensure "{\"location\":\"$REGION\"}" \
    bq --project_id="$PROJECT_ID" --format=prettyjson show "$PROJECT_ID:$dataset" ::: \
    bq --project_id="$PROJECT_ID" --location="$REGION" mk --dataset "$PROJECT_ID:$dataset"
done

run_query() { bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --maximum_bytes_billed=10485760 "$1"; }
run_query "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$BRONZE_DATASET.eventos_raw\` (schema_version STRING NOT NULL, simulation_id STRING NOT NULL, scenario_id STRING NOT NULL, producer_id STRING NOT NULL, event_type STRING NOT NULL, event_id STRING NOT NULL, occurred_at TIMESTAMP NOT NULL, emitted_at TIMESTAMP NOT NULL, ingested_at TIMESTAMP, trace_id STRING NOT NULL, source_system STRING, payload_json JSON, is_valid BOOL)"
run_query "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$BRONZE_DATASET.eventos_raw_pubsub\` (data JSON, subscription_name STRING, message_id STRING, publish_time TIMESTAMP, attributes JSON, ordering_key STRING)"
bq --project_id="$PROJECT_ID" --format=prettyjson show "$PROJECT_ID:$BRONZE_DATASET.eventos_raw_pubsub" | python3 -c 'import json,sys; d=json.load(sys.stdin); got={f["name"] for f in d.get("schema",{}).get("fields",[])}; required={"data","subscription_name","message_id","publish_time","attributes","ordering_key"}; missing=required-got; assert not missing, f"Esquema incompatible de eventos_raw_pubsub; faltan: {sorted(missing)}"'
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
PUBSUB_AGENT="service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com"
bq add-iam-policy-binding \
  --member="serviceAccount:${PUBSUB_AGENT}" \
  --role="roles/bigquery.dataEditor" \
  -t "$PROJECT_ID:$BRONZE_DATASET.eventos_raw_pubsub" >/dev/null
echo "OK: $PUBSUB_AGENT tiene BigQuery Data Editor sobre la tabla eventos_raw_pubsub"
for table in pedidos inventario entregas telemetria; do
  run_query "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$BRONZE_DATASET.${table}_raw\` (batch_id STRING NOT NULL, file_id STRING NOT NULL, source_file_uri STRING NOT NULL, source_system STRING NOT NULL, source_row_number INT64 NOT NULL, ingested_at TIMESTAMP NOT NULL, effective_at TIMESTAMP, record_hash STRING NOT NULL, payload_json JSON NOT NULL, is_valid BOOL NOT NULL, error_reason STRING)"
done
run_query "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$SILVER_DATASET.pedidos\` (order_id STRING NOT NULL, order_line_id STRING, customer_id STRING, store_id STRING, warehouse_id STRING, sku_id STRING NOT NULL, quantity INT64 NOT NULL, occurred_at TIMESTAMP NOT NULL, quality_status STRING NOT NULL)"
run_query "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$SILVER_DATASET.inventario\` (snapshot_id STRING NOT NULL, warehouse_id STRING NOT NULL, store_id STRING, sku_id STRING NOT NULL, on_hand_qty INT64 NOT NULL, reserved_qty INT64 NOT NULL, effective_at TIMESTAMP NOT NULL, quality_status STRING NOT NULL)"
run_query "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$SILVER_DATASET.entregas\` (delivery_id STRING NOT NULL, order_id STRING NOT NULL, store_id STRING, region_id STRING, promised_at TIMESTAMP, delivered_at TIMESTAMP, delivery_cost NUMERIC, quality_status STRING NOT NULL)"
run_query "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$SILVER_DATASET.telemetria_activos\` (asset_id STRING NOT NULL, sensor_id STRING NOT NULL, warehouse_id STRING, store_id STRING, metric_name STRING NOT NULL, metric_value FLOAT64 NOT NULL, unit STRING NOT NULL, occurred_at TIMESTAMP NOT NULL, quality_status STRING NOT NULL)"
for table in pedidos inventario entregas telemetria_activos; do
  bq add-iam-policy-binding \
    --member="serviceAccount:$WORKER" \
    --role="roles/bigquery.dataEditor" \
    -t "$PROJECT_ID:$SILVER_DATASET.$table" >/dev/null
done
echo "OK: $WORKER tiene BigQuery Data Editor sobre tablas Silver"
while IFS= read -r statement; do
  [[ -z "$statement" ]] && continue
  statement="${statement//\{\{PROJECT_ID\}\}/$PROJECT_ID}"
  statement="${statement//\{\{GOLD_DATASET\}\}/$GOLD_DATASET}"
  run_query "$statement"
done < <(sed '/^[[:space:]]*--/d;/^[[:space:]]*$/d' "$ROOT/automatizacion/configuracion/contratos/gold_tables.sql")
echo "OK: datasets $BRONZE_DATASET, $SILVER_DATASET y $GOLD_DATASET"
