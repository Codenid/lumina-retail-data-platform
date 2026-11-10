#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 70 — preflight de gobierno, catálogo y activos BigQuery'
STATE="$ROOT/state/$DEMO_RUN_ID"
CONTRACT="$ROOT/automatizacion/configuracion/contratos/governance_catalog.json"
[[ -s "$CONTRACT" ]] || { echo 'SCRIPT 70: 0 — falta contrato de gobierno/catálogo'; exit 1; }
python3 -m json.tool "$CONTRACT" >/dev/null

python3 - "$CONTRACT" "$PROJECT_ID" "$REGION" "$PREFIX" <<'PY'
import json,sys
c=json.load(open(sys.argv[1],encoding='utf-8'))
def render(value):
    return value.replace('{{PROJECT_ID}}',sys.argv[2]).replace('{{REGION}}',sys.argv[3]).replace('{{PREFIX}}',sys.argv[4])
if render(c.get('project',''))!=sys.argv[2] or render(c.get('location',''))!=sys.argv[3]:
    raise SystemExit('contrato de gobierno no coincide con proyecto/región configurados')
if c.get('catalog',{}).get('overview_aspect')!='dataplex-types.global.overview':
    raise SystemExit('el contrato debe utilizar el aspecto reusable overview de Knowledge Catalog')
if len(c.get('lineage',{}).get('pairs',[]))!=4:
    raise SystemExit('el contrato debe declarar las cuatro dependencias Gold → vista')
print('Contrato de gobierno, aspecto overview y cuatro pares de linaje verificados')
PY

ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)')"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --project="$PROJECT_ID" --format='value(projectNumber)')"
[[ -n "$ACCOUNT" && -n "$PROJECT_NUMBER" ]] || { echo 'SCRIPT 70: 0 — no se pudo determinar cuenta activa o número de proyecto'; exit 1; }
POLICY="$STATE/governance_project_iam.json"
gcloud projects get-iam-policy "$PROJECT_ID" --project="$PROJECT_ID" --format=json > "$POLICY"
python3 - "$POLICY" "$ACCOUNT" <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
account=sys.argv[2]
roles={b.get('role') for b in p.get('bindings',[]) if 'user:'+account in b.get('members',[])}
enable={'roles/owner','roles/editor','roles/serviceusage.serviceUsageAdmin'}
modify={'roles/owner','roles/dataplex.entryOwner','roles/bigquery.dataEditor'}
lineage={'roles/owner','roles/datalineage.admin','roles/datalineage.viewer'}
missing=[]
if not roles & enable: missing.append('serviceusage.services.enable (Owner/Editor/Service Usage Admin)')
if not roles & modify: missing.append('dataplex.entries.modify (Entry Owner/BigQuery Data Editor)')
if not roles & lineage: missing.append('datalineage.events.get (Data Lineage Viewer/Admin)')
if missing: raise SystemExit('permisos requeridos no aparecen en IAM del proyecto para '+account+': '+', '.join(missing))
print('Identidad activa autorizada; roles de proyecto: '+', '.join(sorted(roles)))
PY

SERVICES="$STATE/governance_services_before.txt"
gcloud services list --enabled --project="$PROJECT_ID" --format='value(config.name)' > "$SERVICES"
grep -qx 'bigquery.googleapis.com' "$SERVICES" || { echo 'SCRIPT 70: 0 — BigQuery API no está habilitada'; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ASSETS_JSON="$STATE/governance_assets.json"
: > "$TMP/assets.ndjson"
for layer in bronze silver gold; do
  dataset="$(contract_value "$CONTRACT" "datasets.$layer.id")"
  DATASET_INFO="$TMP/${layer}_dataset.json"
  bq --project_id="$PROJECT_ID" show --format=prettyjson "$PROJECT_ID:$dataset" > "$DATASET_INFO"
  python3 - "$DATASET_INFO" "$dataset" "$REGION" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8'))
if d.get('datasetReference',{}).get('datasetId')!=sys.argv[2]: raise SystemExit('datasetReference no coincide: '+sys.argv[2])
if d.get('location','').lower()!=sys.argv[3].lower(): raise SystemExit(f"{sys.argv[2]} location={d.get('location')!r}; esperado={sys.argv[3]!r}")
PY
  SQL="SELECT table_name, table_type FROM \`$PROJECT_ID.$dataset.INFORMATION_SCHEMA.TABLES\` ORDER BY table_name"
  bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --format=prettyjson "$SQL" > "$TMP/${layer}_tables.json"
  python3 - "$TMP/${layer}_tables.json" "$layer" "$dataset" >> "$TMP/assets.ndjson" <<'PY'
import json,sys
rows=json.load(open(sys.argv[1],encoding='utf-8'))
layer,dataset=sys.argv[2:]
if not rows: raise SystemExit(f'{dataset}: no hay activos BigQuery que catalogar')
for row in rows:
    typ=row.get('table_type')
    if typ not in ('BASE TABLE','VIEW','MATERIALIZED VIEW','EXTERNAL'):
        raise SystemExit(f"tipo de activo no soportado en {dataset}.{row.get('table_name')}: {typ}")
    print(json.dumps({'layer':layer,'dataset':dataset,'asset':row['table_name'],'type':typ},ensure_ascii=False))
print(f'{dataset}: {len(rows)} activos {sorted({r.get("table_type") for r in rows})}',file=sys.stderr)
PY
done

python3 - "$TMP/assets.ndjson" "$ASSETS_JSON" "$CONTRACT" <<'PY'
import json,sys
assets=[json.loads(line) for line in open(sys.argv[1],encoding='utf-8') if line.strip()]
c=json.load(open(sys.argv[3],encoding='utf-8'))
gold_dataset=c['datasets']['gold']['id'].replace('{{PREFIX}}', __import__('os').environ['PREFIX'])
present={(a['dataset'],a['asset']) for a in assets}
for pair in c['lineage']['pairs']:
    for name in (pair['source'],pair['target']):
        if (gold_dataset,name) not in present:
            raise SystemExit('falta el activo Gold requerido para linaje: '+name)
json.dump(assets,open(sys.argv[2],'w',encoding='utf-8'),ensure_ascii=False,indent=2)
print(f'Inventario de catálogo: {len(assets)} tablas/vistas; cuatro pares de linaje presentes')
PY

TOKEN="$(gcloud auth print-access-token)"
for sample in 'bronze eventos_raw' 'silver pedidos' 'gold cu03_kpis_operativos'; do
  read -r layer asset <<< "$sample"
  dataset="$(contract_value "$CONTRACT" "datasets.$layer.id")"
  ENTRY="projects/$PROJECT_ID/locations/$REGION/entryGroups/@bigquery/entries/bigquery.googleapis.com/projects/$PROJECT_ID/datasets/$dataset/tables/$asset"
  CODE="$(curl --silent --show-error --get --output "$TMP/catalog_${layer}.json" --write-out '%{http_code}' \
    --header "Authorization: Bearer $TOKEN" --header "x-goog-user-project: $PROJECT_ID" \
    --data-urlencode "entry=$ENTRY" --data-urlencode 'view=FULL' \
    "https://dataplex.googleapis.com/v1/projects/$PROJECT_ID/locations/$REGION:lookupEntry")"
  [[ "$CODE" == 200 ]] || { echo "SCRIPT 70: 0 — lookupEntry $dataset.$asset devolvió HTTP $CODE"; cat "$TMP/catalog_${layer}.json" >&2; exit 1; }
done

printf 'project=%s\nproject_number=%s\nregion=%s\naccount=%s\nasset_count=%s\ndataplex_api=%s\ndatalineage_api=%s\n' \
  "$PROJECT_ID" "$PROJECT_NUMBER" "$REGION" "$ACCOUNT" "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$ASSETS_JSON")" \
  "$(grep -qx 'dataplex.googleapis.com' "$SERVICES" && echo enabled || echo disabled)" \
  "$(grep -qx 'datalineage.googleapis.com' "$SERVICES" && echo enabled || echo disabled)" > "$STATE/governance_preflight.txt"
echo 'SCRIPT 70: 1 — identidad/permisos, datasets, activos y entradas de catálogo verificados; no se cambiaron recursos ni IAM'
