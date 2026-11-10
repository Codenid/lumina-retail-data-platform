#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 61 — integrar streaming/batch y programar refresco'
[[ -s "$ROOT/state/$DEMO_RUN_ID/operational_mart_schema_ok.txt" ]] || { echo 'SCRIPT 61: 0 — dependencia: SCRIPT 60'; exit 1; }
LOCATION="$(sed -n 's/^location=//p' "$ROOT/state/$DEMO_RUN_ID/operational_mart_preflight.txt")"
MART_SA="$(sed -n 's/^service_account=//p' "$ROOT/state/$DEMO_RUN_ID/operational_mart_preflight.txt")"
SCHEDULE='every 6 hours'
SQL="$(python3 - "$ROOT/automatizacion/configuracion/contratos/operational_mart.sql" "$PROJECT_ID" "$GOLD_DATASET" "$SILVER_DATASET" <<'PY'
import sys
s=open(sys.argv[1],encoding='utf-8').read()
for key,value in zip(('PROJECT_ID','GOLD_DATASET','SILVER_DATASET'),sys.argv[2:]): s=s.replace('{{'+key+'}}',value)
print(s)
PY
)"
bq --project_id="$PROJECT_ID" --location="$LOCATION" query --use_legacy_sql=false --dry_run "$SQL" >/dev/null
bq --project_id="$PROJECT_ID" --location="$LOCATION" query --use_legacy_sql=false --maximum_bytes_billed=104857600 "$SQL"
PARAMS="$(printf '%s' "$SQL" | python3 -c 'import json,sys; print(json.dumps({"query":sys.stdin.read()},separators=(",",":")))')"
CONFIGS="$ROOT/state/$DEMO_RUN_ID/operational_mart_transfer_configs.json"
bq --project_id="$PROJECT_ID" ls --transfer_config --transfer_location="$LOCATION" --format=prettyjson > "$CONFIGS"
RESOURCE="$(python3 - "$CONFIGS" <<'PY'
import json,sys
raw=open(sys.argv[1],encoding='utf-8').read().strip()
for c in (json.loads(raw) if raw else []):
    if c.get('displayName')=='luminalab-operational-mart-refresh': print(c.get('name','')); break
PY
)"
if [[ -n "$RESOURCE" ]]; then
  bq --project_id="$PROJECT_ID" show --transfer_config --format=prettyjson "$RESOURCE" > "$ROOT/state/$DEMO_RUN_ID/operational_mart_transfer.json"
  python3 - "$ROOT/state/$DEMO_RUN_ID/operational_mart_transfer.json" "$PARAMS" "$SCHEDULE" "$MART_SA" "$GOLD_DATASET" <<'PY'
import json,sys
c=json.load(open(sys.argv[1],encoding='utf-8'))
assert c.get('params',{}).get('query')==json.loads(sys.argv[2])['query'], 'scheduled query existe con SQL distinto; se conserva sin modificar'
assert c.get('schedule')==sys.argv[3], 'scheduled query existe con frecuencia distinta; se conserva sin modificar'
actual_sa=c.get('serviceAccountName') or c.get('ownerInfo',{}).get('email')
assert actual_sa==sys.argv[4], f'scheduled query usa otra identidad: {actual_sa!r}; se conserva sin modificar'
assert c.get('destinationDatasetId')==sys.argv[5], 'scheduled query apunta a otro dataset; se conserva sin modificar'
assert not c.get('disabled',False), 'scheduled query está deshabilitada'
PY
else
  bq --project_id="$PROJECT_ID" mk --transfer_config --location="$LOCATION" --data_source=scheduled_query --target_dataset="$GOLD_DATASET" --display_name=luminalab-operational-mart-refresh --params="$PARAMS" --schedule="$SCHEDULE" --service_account_name="$MART_SA"
  bq --project_id="$PROJECT_ID" ls --transfer_config --transfer_location="$LOCATION" --format=prettyjson > "$CONFIGS"
RESOURCE="$(python3 - "$CONFIGS" <<'PY'
import json,sys
raw=open(sys.argv[1],encoding='utf-8').read().strip()
for c in (json.loads(raw) if raw else []):
    if c.get('displayName')=='luminalab-operational-mart-refresh': print(c.get('name','')); break
PY
)"
  [[ -n "$RESOURCE" ]] || { echo 'SCRIPT 61: 0 — configuración programada no visible tras crearla'; exit 1; }
  bq --project_id="$PROJECT_ID" show --transfer_config --format=prettyjson "$RESOURCE" > "$ROOT/state/$DEMO_RUN_ID/operational_mart_transfer.json"
fi
printf 'resource=%s\nschedule=%s\nservice_account=%s\nlocation=%s\n' "$RESOURCE" "$SCHEDULE" "$MART_SA" "$LOCATION" > "$ROOT/state/$DEMO_RUN_ID/operational_mart_schedule_ok.txt"
echo "SCRIPT 61: 1 — integración ejecutada y refresco programado ($SCHEDULE); $RESOURCE"
