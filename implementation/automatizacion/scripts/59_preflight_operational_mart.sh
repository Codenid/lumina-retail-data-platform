#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 59 — contrato, datos, ubicación e IAM del Operational Mart'
CONTRACT="$ROOT/automatizacion/configuracion/contratos/operational_mart.json"
SQL="$ROOT/automatizacion/configuracion/contratos/operational_mart.sql"
[[ -s "$CONTRACT" && -s "$SQL" ]] || { echo 'SCRIPT 59: 0 — falta contrato o SQL'; exit 1; }
python3 - "$CONTRACT" "$SQL" <<'PY'
import json,sys
c=json.load(open(sys.argv[1],encoding='utf-8')); q=open(sys.argv[2],encoding='utf-8').read()
expected={'pedidos','inventario','entregas','benchmark_competidores','eventos_locales','redes_sociales','insights_streaming','procesamiento_auditoria'}
assert set(c['sources'])==expected, f'fuentes incorrectas: {set(c["sources"])}'
assert c['merge_key']==['entity_type','entity_id','ingestion_mode','source_domain']
assert q.count('UNION ALL')==7 and 'WHEN MATCHED THEN UPDATE' in q and 'WHEN NOT MATCHED THEN INSERT' in q
print('Contrato y ocho fuentes verificados')
PY
ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)')"
NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
MART_SA="${NUMBER}-compute@developer.gserviceaccount.com"
[[ -n "$ACCOUNT" ]] || { echo 'SCRIPT 59: 0 — identidad activa no detectada'; exit 1; }
gcloud iam service-accounts describe "$MART_SA" --project="$PROJECT_ID" >/dev/null
gcloud services list --enabled --project="$PROJECT_ID" --filter='config.name=bigquerydatatransfer.googleapis.com' --format='value(config.name)' | grep -qx bigquerydatatransfer.googleapis.com || { echo 'SCRIPT 59: 0 — BigQuery Data Transfer API no habilitada'; exit 1; }
LOCATION="$(bq --project_id="$PROJECT_ID" show --format=json "$PROJECT_ID:$GOLD_DATASET" | python3 -c 'import json,sys; print(json.load(sys.stdin)["location"])')"
for dataset in "$SILVER_DATASET" "$GOLD_DATASET"; do
  actual="$(bq --project_id="$PROJECT_ID" show --format=json "$PROJECT_ID:$dataset" | python3 -c 'import json,sys; print(json.load(sys.stdin)["location"])')"
  [[ "$actual" == "$LOCATION" ]] || { echo "SCRIPT 59: 0 — ubicación incompatible: $dataset=$actual, Gold=$LOCATION"; exit 1; }
done
for table in pedidos inventario entregas benchmark_competidores eventos_locales redes_sociales; do bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$SILVER_DATASET.$table" >/dev/null; done
for table in operational_mart insights_streaming procesamiento_auditoria; do bq --project_id="$PROJECT_ID" show "$PROJECT_ID:$GOLD_DATASET.$table" >/dev/null; done
for dataset in "$SILVER_DATASET" "$GOLD_DATASET"; do
  bq --project_id="$PROJECT_ID" show --format=json "$PROJECT_ID:$dataset" | python3 -c 'import json,sys; d=json.load(sys.stdin); s=sys.argv[1]; roles={x.get("role") for x in d.get("access",[]) if x.get("userByEmail")==s}; assert roles & {"READER","WRITER","OWNER"}, "service account lacks dataset access"' "$MART_SA" || { echo "SCRIPT 59: 0 — falta acceso de dataset para $MART_SA en $dataset"; exit 1; }
done
if ! gcloud projects get-iam-policy "$PROJECT_ID" --flatten='bindings[].members' --filter="bindings.members:serviceAccount:$MART_SA AND bindings.role:roles/bigquery.jobUser" --format='value(bindings.role)' | grep -qx roles/bigquery.jobUser; then echo "SCRIPT 59: 0 — falta roles/bigquery.jobUser para $MART_SA"; exit 1; fi
printf 'account=%s\nservice_account=%s\nlocation=%s\nschedule=every 6 hours\n' "$ACCOUNT" "$MART_SA" "$LOCATION" > "$ROOT/state/$DEMO_RUN_ID/operational_mart_preflight.txt"
echo 'SCRIPT 59: 1 — contrato, ocho tablas, APIs, ubicación e identidad verificados'
