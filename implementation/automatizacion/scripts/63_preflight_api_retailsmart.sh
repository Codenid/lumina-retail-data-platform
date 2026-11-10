#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 63 — preflight API RetailSmart Insights y dependencias'
CONTRACT="$ROOT/automatizacion/configuracion/contratos/retailsmart_api.json"
API_SERVICE="${PREFIX}-insights-api"
API_SA="${PREFIX}-api@${PROJECT_ID}.iam.gserviceaccount.com"
AR_REPO='cloud-run-source-deploy'
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --project="$PROJECT_ID" --format='value(projectNumber)')"
ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)')"
[[ -n "$ACCOUNT" && -n "$PROJECT_NUMBER" ]] || { echo 'SCRIPT 63: 0 — no se pudo determinar cuenta activa o número de proyecto'; exit 1; }

python3 -m json.tool "$CONTRACT" >/dev/null
python3 - "$CONTRACT" "$PREFIX" "$REGION" <<'PY'
import json,sys
c=json.load(open(sys.argv[1],encoding='utf-8'))
assert c['archimate_id']=='id-296ccb2b09fe45ae94d44b36120e3e3e'
assert c['service'].replace('{{PREFIX}}',sys.argv[2])==sys.argv[2]+'-insights-api'
assert c['region'].replace('{{REGION}}',sys.argv[3])==sys.argv[3]
assert c['authentication']=='Cloud Run IAM; private'
assert len(c['routes'])==4
assert c['limits']['maximum_rows']==100 and c['limits']['maximum_instances']==2
tables=set()
for route in c['routes'].values():
    if 'tables' in route: tables.update(v['table'] for v in route['tables'].values())
    else: tables.add(route['table'])
assert tables=={'insights_streaming','cu01_riesgo_quiebre_despacho','cu02_plan_reposicion','cu03_kpis_operativos','cu04_alertas_mantenimiento'}
print('Contrato: cuatro rutas y cinco tablas Gold')
PY

ENABLED_FILE="$ROOT/state/$DEMO_RUN_ID/api_enabled_services.txt"
gcloud services list --enabled --project="$PROJECT_ID" --format='value(config.name)' > "$ENABLED_FILE"
for api in run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com storage.googleapis.com; do
  if ! grep -qx "$api" "$ENABLED_FILE"; then
    echo "Habilitando API requerida: $api"
    gcloud services enable "$api" --project="$PROJECT_ID"
  fi
done
gcloud services list --enabled --project="$PROJECT_ID" --format='value(config.name)' > "$ENABLED_FILE"
for api in run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com storage.googleapis.com; do
  grep -qx "$api" "$ENABLED_FILE" || { echo "SCRIPT 63: 0 — API no habilitada: $api"; exit 1; }
done

DATASET_INFO="$ROOT/state/$DEMO_RUN_ID/api_gold_dataset.json"
bq --project_id="$PROJECT_ID" show --format=prettyjson "$PROJECT_ID:$GOLD_DATASET" > "$DATASET_INFO"
python3 - "$DATASET_INFO" "$REGION" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8'))
actual=d.get('location','').lower()
expected=sys.argv[2].lower()
if actual!=expected: raise SystemExit(f'ubicación Gold divergente: actual={actual} esperada={expected}')
print(f'Dataset Gold verificado: {d["datasetReference"]["datasetId"]}, {actual}')
PY

python3 - "$CONTRACT" <<'PY' > "$ROOT/state/$DEMO_RUN_ID/api_gold_tables.txt"
import json,sys
c=json.load(open(sys.argv[1],encoding='utf-8'))
tables=set()
for route in c['routes'].values():
    if 'tables' in route: tables.update(v['table'] for v in route['tables'].values())
    else: tables.add(route['table'])
print('\n'.join(sorted(tables)))
PY
while IFS= read -r table; do
  [[ -n "$table" ]] || continue
  INFO="$ROOT/state/$DEMO_RUN_ID/api_table_${table}.json"
  bq --project_id="$PROJECT_ID" show --format=prettyjson "$PROJECT_ID:$GOLD_DATASET.$table" > "$INFO"
  python3 - "$INFO" "$table" "$REGION" "$CONTRACT" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8'))
contract=json.load(open(sys.argv[4],encoding='utf-8'))
table=sys.argv[2]
entries=[]
for route in contract['routes'].values():
    if 'tables' in route: entries.extend(route['tables'].values())
    else: entries.append(route)
expected=next(e['columns'] for e in entries if e['table']==table)
actual={f['name'] for f in d.get('schema',{}).get('fields',[])}
missing=set(expected)-actual
if d.get('location','').lower()!=sys.argv[3].lower(): raise SystemExit(f'{table}: ubicación divergente {d.get("location")}')
if missing: raise SystemExit(f'{table}: columnas ausentes {sorted(missing)}')
if int(d.get('numRows',0))<1: raise SystemExit(f'{table}: tabla vacía; no hay respuesta demostrable')
print(f'{table}: esquema compatible; filas en metadatos={d["numRows"]}')
PY
done < "$ROOT/state/$DEMO_RUN_ID/api_gold_tables.txt"

REPO_INFO="$ROOT/state/$DEMO_RUN_ID/api_artifact_repo.json"
REPO_ERROR="$ROOT/state/$DEMO_RUN_ID/api_artifact_repo_error.txt"
if gcloud artifacts repositories describe "$AR_REPO" --project="$PROJECT_ID" --location="$REGION" --format=json > "$REPO_INFO" 2> "$REPO_ERROR"; then
  python3 - "$REPO_INFO" <<'PY'
import json,sys
r=json.load(open(sys.argv[1],encoding='utf-8'))
if r.get('format')!='DOCKER': raise SystemExit(f'repositorio existente con formato divergente: {r.get("format")}')
print(f'Repositorio Artifact Registry reutilizable: {r["name"]}')
PY
else
  rc=$?
  if grep -Eqi 'NOT_FOUND|not found|was not found' "$REPO_ERROR"; then
    gcloud artifacts repositories create "$AR_REPO" --project="$PROJECT_ID" --location="$REGION" --repository-format=docker --description='Imágenes de Cloud Run para RetailSmart Insights'
    gcloud artifacts repositories describe "$AR_REPO" --project="$PROJECT_ID" --location="$REGION" --format=json > "$REPO_INFO"
  else
    cat "$REPO_ERROR" >&2
    exit "$rc"
  fi
fi

gcloud run services list --project="$PROJECT_ID" --region="$REGION" --platform=managed --format='value(metadata.name)' > "$ROOT/state/$DEMO_RUN_ID/api_existing_services.txt"
printf 'project=%s\nproject_number=%s\nregion=%s\naccount=%s\nservice=%s\nservice_account=%s\nartifact_repository=%s\n' \
  "$PROJECT_ID" "$PROJECT_NUMBER" "$REGION" "$ACCOUNT" "$API_SERVICE" "$API_SA" "$AR_REPO" > "$ROOT/state/$DEMO_RUN_ID/api_preflight_ok.txt"
echo "SCRIPT 63: 1 — APIs, cinco tablas Gold, ubicación, repositorio e identidad de despliegue verificados"
