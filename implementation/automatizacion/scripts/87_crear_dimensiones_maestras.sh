#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 87 — crear dimensiones maestras en Gold'
LOCATION="$(bq --project_id="$PROJECT_ID" show --format=json "$PROJECT_ID:$GOLD_DATASET" | python3 -c 'import json,sys; print(json.load(sys.stdin)["location"])')"
bq --project_id="$PROJECT_ID" --location="$LOCATION" query --use_legacy_sql=false "
CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$GOLD_DATASET.dim_tiendas\` (store_id STRING,store_name STRING,zone_name STRING,city STRING,region_id STRING,store_type STRING,status STRING);
CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$GOLD_DATASET.dim_productos\` (sku_id STRING,product_name STRING,category_id STRING,category_name STRING,brand STRING,unit STRING,status STRING);
CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$GOLD_DATASET.dim_categorias\` (category_id STRING,category_name STRING,department_name STRING,status STRING);
CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$GOLD_DATASET.dim_almacenes\` (warehouse_id STRING,warehouse_name STRING,city STRING,region_id STRING,status STRING)" >/dev/null
printf 'SCRIPT 87: 1 — dimensiones maestras creadas\n' > "$ROOT/state/$DEMO_RUN_ID/master_dimensions_created.txt"
echo 'SCRIPT 87: 1 — dimensiones maestras creadas'
