#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 60 — extender el esquema del Operational Mart sin borrar datos'
[[ -s "$ROOT/state/$DEMO_RUN_ID/operational_mart_preflight.txt" ]] || { echo 'SCRIPT 60: 0 — dependencia: SCRIPT 59'; exit 1; }
LOCATION="$(sed -n 's/^location=//p' "$ROOT/state/$DEMO_RUN_ID/operational_mart_preflight.txt")"
TABLE_REF="\`$PROJECT_ID.$GOLD_DATASET.operational_mart\`"
bq --project_id="$PROJECT_ID" --location="$LOCATION" query --use_legacy_sql=false "CREATE TABLE IF NOT EXISTS $TABLE_REF (scenario_id STRING,entity_type STRING,entity_id STRING,sku_id STRING,store_id STRING,warehouse_id STRING,quantity INT64,status STRING,observed_at TIMESTAMP,ingestion_mode STRING,source_domain STRING,correlation_id STRING,measure_value FLOAT64,attributes JSON)"
for definition in 'source_domain STRING' 'correlation_id STRING' 'measure_value FLOAT64' 'attributes JSON'; do
  field="${definition%% *}"; type="${definition#* }"
  bq --project_id="$PROJECT_ID" --location="$LOCATION" query --use_legacy_sql=false "ALTER TABLE $TABLE_REF ADD COLUMN IF NOT EXISTS $field $type"
done
bq --project_id="$PROJECT_ID" show --format=prettyjson "$PROJECT_ID:$GOLD_DATASET.operational_mart" | python3 -c 'import json,sys; names={f["name"] for f in json.load(sys.stdin)["schema"]["fields"]}; required={"scenario_id","entity_type","entity_id","sku_id","store_id","warehouse_id","quantity","status","observed_at","ingestion_mode","source_domain","correlation_id","measure_value","attributes"}; missing=required-names; print("Faltan columnas: "+str(sorted(missing))) if missing else print("14 columnas verificadas"); sys.exit(bool(missing))'
printf 'SCRIPT 60: 1 — esquema extendido sin reemplazar filas\n' > "$ROOT/state/$DEMO_RUN_ID/operational_mart_schema_ok.txt"
echo 'SCRIPT 60: 1 — esquema extendido y verificado'
