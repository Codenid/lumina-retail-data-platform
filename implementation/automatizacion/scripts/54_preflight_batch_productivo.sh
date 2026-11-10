#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 54 — preflight batch de seis fuentes'
CONTRACT="$ROOT/automatizacion/configuracion/contratos/batch_sources.json"
python3 - "$CONTRACT" "$ROOT/docs/arquitectura/productores.csv" <<'PY'
import csv,json,sys
c=json.load(open(sys.argv[1],encoding='utf-8'))
expected={'pedidos','inventario','entregas','benchmark_competidores','eventos_locales','redes_sociales'}
with open(sys.argv[2],newline='',encoding='utf-8') as f: producers={r['producer'] for r in csv.DictReader(f) if r['mode']=='batch'}
domains=c.get('domains',{})
assert set(domains)==expected, f'dominios esperados {expected}, recibidos {set(domains)}'
assert all(d.get('producer') in producers and d.get('key') and d.get('fields') for d in domains.values()), 'contrato/productor incompleto'
print('Contrato y seis productores verificados')
PY
ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)')"
NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
WORKFLOW_SA="${NUMBER}-compute@developer.gserviceaccount.com"
[[ "$ACCOUNT" == *"@"* ]] || { echo 'SCRIPT 54: 0 — identidad activa no detectada'; exit 1; }
for api in bigquery.googleapis.com workflows.googleapis.com storage.googleapis.com; do
  gcloud services list --enabled --project="$PROJECT_ID" --filter="config.name=$api" --format='value(config.name)' | grep -qx "$api" || { echo "SCRIPT 54: 0 — API no habilitada: $api"; exit 1; }
done
for dataset in "$BRONZE_DATASET" "$SILVER_DATASET" "$GOLD_DATASET"; do bq --project_id="$PROJECT_ID" show --format=json "$PROJECT_ID:$dataset" >/dev/null; done
DATASET_LOCATION="$(bq --project_id="$PROJECT_ID" show --format=json "$PROJECT_ID:$BRONZE_DATASET" | python3 -c 'import json,sys; print(json.load(sys.stdin)["location"])')"
for dataset in "$SILVER_DATASET" "$GOLD_DATASET"; do
  location="$(bq --project_id="$PROJECT_ID" show --format=json "$PROJECT_ID:$dataset" | python3 -c 'import json,sys; print(json.load(sys.stdin)["location"])')"
  [[ "$location" == "$DATASET_LOCATION" ]] || { echo "SCRIPT 54: 0 — ubicaciones incompatibles: $BRONZE_DATASET=$DATASET_LOCATION $dataset=$location"; exit 1; }
done
gcloud storage buckets describe "gs://$LANDING" --project="$PROJECT_ID" >/dev/null
if ! gcloud projects get-iam-policy "$PROJECT_ID" --flatten='bindings[].members' --filter="bindings.members:serviceAccount:$WORKFLOW_SA AND bindings.role:roles/bigquery.jobUser" --format='value(bindings.role)' | grep -qx roles/bigquery.jobUser; then
  echo "SCRIPT 54: 0 — $WORKFLOW_SA carece de roles/bigquery.jobUser"; exit 1
fi
for pair in "$BRONZE_DATASET:READER" "$SILVER_DATASET:WRITER" "$GOLD_DATASET:WRITER"; do
  dataset="${pair%%:*}"; wanted="${pair#*:}"
  access="$(bq --project_id="$PROJECT_ID" show --format=json "$PROJECT_ID:$dataset" | python3 -c 'import json,sys; d=json.load(sys.stdin); s=sys.argv[1]; print(",".join(x["role"] for x in d.get("access",[]) if x.get("userByEmail")==s))' "$WORKFLOW_SA")"
  [[ ",$access," == *",$wanted,"* || ",$access," == *",OWNER,"* ]] || { echo "SCRIPT 54: 0 — ACL $wanted faltante en $dataset para $WORKFLOW_SA"; exit 1; }
done
BATCH_RUN_ID="batch-$(date -u +%Y%m%d-%H%M%S)"
printf '%s\n' "$BATCH_RUN_ID" > "$ROOT/state/$DEMO_RUN_ID/batch_productivo_id.txt"
printf 'account=%s\nworkflow_sa=%s\nproject_number=%s\ndataset_location=%s\nlanding_bucket=%s\nbatch_id=%s\n' "$ACCOUNT" "$WORKFLOW_SA" "$NUMBER" "$DATASET_LOCATION" "$LANDING" "$BATCH_RUN_ID" > "$ROOT/state/$DEMO_RUN_ID/batch_productivo_preflight.txt"
echo 'SCRIPT 54: 1 — contrato, APIs, identidades, datasets, ubicación y permisos verificados'
