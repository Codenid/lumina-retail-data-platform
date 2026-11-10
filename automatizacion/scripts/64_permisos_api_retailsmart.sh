#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 64 — identidad API y permisos mínimos'
[[ -s "$ROOT/state/$DEMO_RUN_ID/api_preflight_ok.txt" ]] || { echo 'SCRIPT 64: 0 — dependencia: SCRIPT 63'; exit 1; }
API_SA_ID="${PREFIX}-api"
API_SA="$API_SA_ID@$PROJECT_ID.iam.gserviceaccount.com"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --project="$PROJECT_ID" --format='value(projectNumber)')"
BUILD_SA="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"
AR_REPO='cloud-run-source-deploy'

SA_INFO="$ROOT/state/$DEMO_RUN_ID/api_service_account.json"
SA_ERROR="$ROOT/state/$DEMO_RUN_ID/api_service_account_error.txt"
if gcloud iam service-accounts describe "$API_SA" --project="$PROJECT_ID" --format=json > "$SA_INFO" 2> "$SA_ERROR"; then
  echo "Reutilizando cuenta de runtime $API_SA"
else
  rc=$?
  if grep -Eqi 'NOT_FOUND|not found|does not exist' "$SA_ERROR"; then
    gcloud iam service-accounts create "$API_SA_ID" --project="$PROJECT_ID" --display-name='RetailSmart Insights API' --description='Identidad de solo lectura para la API privada de RetailSmart Insights'
    gcloud iam service-accounts describe "$API_SA" --project="$PROJECT_ID" --format=json > "$SA_INFO"
  else
    cat "$SA_ERROR" >&2
    exit "$rc"
  fi
fi
python3 - "$SA_INFO" <<'PY'
import json,sys
s=json.load(open(sys.argv[1],encoding='utf-8'))
if s.get('disabled',False): raise SystemExit('la cuenta de runtime está deshabilitada')
PY

PROJECT_POLICY="$ROOT/state/$DEMO_RUN_ID/api_project_iam_before.json"
gcloud projects get-iam-policy "$PROJECT_ID" --project="$PROJECT_ID" --format=json > "$PROJECT_POLICY"
python3 - "$PROJECT_POLICY" "$API_SA" "$BUILD_SA" <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
for member in ('serviceAccount:'+sys.argv[2],'serviceAccount:'+sys.argv[3]):
    for b in p.get('bindings',[]):
        if member in b.get('members',[]) and b.get('condition'):
            raise SystemExit(f'{member} ya tiene binding condicional {b["role"]}; requiere revisión manual, no se amplía')
PY

for role_member in "roles/run.builder|serviceAccount:$BUILD_SA" "roles/bigquery.jobUser|serviceAccount:$API_SA"; do
  role="${role_member%%|*}"
  member="${role_member#*|}"
  if ! python3 - "$PROJECT_POLICY" "$role" "$member" <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
ok=any(b.get('role')==sys.argv[2] and sys.argv[3] in b.get('members',[]) and not b.get('condition') for b in p.get('bindings',[]))
raise SystemExit(0 if ok else 1)
PY
  then
    gcloud projects add-iam-policy-binding "$PROJECT_ID" --project="$PROJECT_ID" --member="$member" --role="$role" --quiet
    gcloud projects get-iam-policy "$PROJECT_ID" --project="$PROJECT_ID" --format=json > "$PROJECT_POLICY"
  fi
done

while IFS= read -r table; do
  [[ -n "$table" ]] || continue
  SQL="$(printf 'GRANT `%s` ON TABLE `%s.%s.%s` TO \"serviceAccount:%s\"' 'roles/bigquery.dataViewer' "$PROJECT_ID" "$GOLD_DATASET" "$table" "$API_SA")"
  bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false "$SQL"
  POLICY="$ROOT/state/$DEMO_RUN_ID/api_table_iam_${table}.json"
  bq --project_id="$PROJECT_ID" get-iam-policy --format=prettyjson "$PROJECT_ID:$GOLD_DATASET.$table" > "$POLICY"
  python3 - "$POLICY" "$API_SA" "$table" <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
member='serviceAccount:'+sys.argv[2]
ok=any(b.get('role')=='roles/bigquery.dataViewer' and member in b.get('members',[]) for b in p.get('bindings',[]))
if not ok: raise SystemExit(f'{sys.argv[3]}: no aparece Data Viewer de tabla para {member}')
print(f'{sys.argv[3]}: Data Viewer verificado a nivel de tabla')
PY
done < "$ROOT/state/$DEMO_RUN_ID/api_gold_tables.txt"

gcloud artifacts repositories add-iam-policy-binding "$AR_REPO" --project="$PROJECT_ID" --location="$REGION" --member="serviceAccount:$BUILD_SA" --role=roles/artifactregistry.writer --quiet
gcloud artifacts repositories get-iam-policy "$AR_REPO" --project="$PROJECT_ID" --location="$REGION" --format=json > "$ROOT/state/$DEMO_RUN_ID/api_artifact_iam.json"
PROJECT_POLICY="$ROOT/state/$DEMO_RUN_ID/api_project_iam_after.json"
gcloud projects get-iam-policy "$PROJECT_ID" --project="$PROJECT_ID" --format=json > "$PROJECT_POLICY"
python3 - "$PROJECT_POLICY" "$API_SA" "$BUILD_SA" <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
required={'serviceAccount:'+sys.argv[2]:'roles/bigquery.jobUser','serviceAccount:'+sys.argv[3]:'roles/run.builder'}
for member,role in required.items():
    if not any(b.get('role')==role and member in b.get('members',[]) and not b.get('condition') for b in p.get('bindings',[])):
        raise SystemExit(f'grant de proyecto no verificado: {role} a {member}')
print('BigQuery Job User y Cloud Run Builder verificados en sus identidades')
PY
python3 - "$ROOT/state/$DEMO_RUN_ID/api_artifact_iam.json" "$BUILD_SA" <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
member='serviceAccount:'+sys.argv[2]
if not any(b.get('role')=='roles/artifactregistry.writer' and member in b.get('members',[]) for b in p.get('bindings',[])):
    raise SystemExit(f'Artifact Registry Writer no verificado en el repositorio para {member}')
print('Artifact Registry Writer limitado al repositorio verificado')
PY
printf 'runtime_service_account=%s\nbuild_service_account=%s\n' "$API_SA" "$BUILD_SA" > "$ROOT/state/$DEMO_RUN_ID/api_iam_ok.txt"
echo "SCRIPT 64: 1 — runtime con Job User y lectura de cinco tablas; permisos de build acotados"
