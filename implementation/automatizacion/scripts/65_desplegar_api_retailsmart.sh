#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 65 — desplegar API privada en Cloud Run'
[[ -s "$ROOT/state/$DEMO_RUN_ID/api_preflight_ok.txt" ]] || { echo 'SCRIPT 65: 0 — dependencia: SCRIPT 63'; exit 1; }
[[ -s "$ROOT/state/$DEMO_RUN_ID/api_iam_ok.txt" ]] || { echo 'SCRIPT 65: 0 — dependencia: SCRIPT 64'; exit 1; }
API_SERVICE="${PREFIX}-insights-api"
API_SA="${PREFIX}-api@$PROJECT_ID.iam.gserviceaccount.com"
DEPLOYER_ACCOUNT="$(sed -n 's/^account=//p' "$ROOT/state/$DEMO_RUN_ID/api_preflight_ok.txt")"
API_DIR="$ROOT/soluciones/api-insights"
SERVICE_INFO="$ROOT/state/$DEMO_RUN_ID/api_service.json"
SERVICE_ERROR="$ROOT/state/$DEMO_RUN_ID/api_service_error.txt"
SOURCE_HASH="$(python3 - "$API_DIR" <<'PY'
import hashlib,os,sys
root=sys.argv[1]; digest=hashlib.sha256()
for base,dirs,files in os.walk(root):
    dirs[:] = sorted(d for d in dirs if d!='__pycache__')
    for name in sorted(files):
        path=os.path.join(base,name)
        digest.update(os.path.relpath(path,root).encode()); digest.update(b'\0')
        with open(path,'rb') as f: digest.update(f.read())
print(digest.hexdigest()[:10])
PY
)"
REVISION_SUFFIX="r$SOURCE_HASH"

SERVICE_EXISTS=0
if gcloud run services describe "$API_SERVICE" --project="$PROJECT_ID" --region="$REGION" --format=json > "$SERVICE_INFO" 2> "$SERVICE_ERROR"; then
  SERVICE_EXISTS=1
else
  rc=$?
  if ! grep -Eqi 'NOT_FOUND|not found|was not found|cannot find service' "$SERVICE_ERROR"; then
    cat "$SERVICE_ERROR" >&2
    exit "$rc"
  fi
fi

if [[ "$SERVICE_EXISTS" == 1 ]]; then
  gcloud run services get-iam-policy "$API_SERVICE" --project="$PROJECT_ID" --region="$REGION" --format=json > "$ROOT/state/$DEMO_RUN_ID/api_service_iam.json"
  python3 - "$SERVICE_INFO" "$ROOT/state/$DEMO_RUN_ID/api_service_iam.json" "$API_SA" "$PROJECT_ID" "$GOLD_DATASET" "$REGION" <<'PY'
import json,sys
s=json.load(open(sys.argv[1],encoding='utf-8'))
p=json.load(open(sys.argv[2],encoding='utf-8'))
template=s.get('spec',{}).get('template',s.get('template',{}))
spec=template.get('spec',template)
sa=spec.get('serviceAccountName') or template.get('serviceAccount')
if sa!=sys.argv[3]: raise SystemExit(f'Servicio existente con service account divergente: {sa!r}; se conserva sin actualizar')
public=[m for b in p.get('bindings',[]) for m in b.get('members',[]) if m in ('allUsers','allAuthenticatedUsers')]
if public: raise SystemExit(f'Servicio existente con acceso público {public}; se conserva sin actualizar')
env={e.get('name'):e.get('value') for c in spec.get('containers',[]) for e in c.get('env',[]) if 'value' in e}
expected={'PROJECT_ID':sys.argv[4],'GOLD_DATASET':sys.argv[5],'BQ_LOCATION':sys.argv[6]}
if env and any(env.get(k)!=v for k,v in expected.items()): raise SystemExit(f'Servicio existente con variables divergentes: {env}; se conserva sin actualizar')
unexpected=set(env)-set(expected)
if unexpected: raise SystemExit(f'Servicio existente con variables no administradas: {sorted(unexpected)}; se conserva sin actualizar')
print('Servicio existente: identidad y política compatibles; se verificará revisión/configuración antes de reutilizarlo')
PY
fi

deploy_api() {
  gcloud run deploy "$API_SERVICE" \
    --project="$PROJECT_ID" --region="$REGION" \
    --source="$API_DIR" \
    --service-account="$API_SA" \
    --set-env-vars="PROJECT_ID=$PROJECT_ID,GOLD_DATASET=$GOLD_DATASET,BQ_LOCATION=$REGION" \
    --set-build-env-vars=GOOGLE_PYTHON_VERSION=3.14 \
    --cpu=1 --memory=512Mi --concurrency=4 --timeout=90 \
    --min=0 --max=2 --ingress=all --no-allow-unauthenticated \
    --revision-suffix="$REVISION_SUFFIX" \
    --labels=archimate-id=id-296ccb2b09fe45ae94d44b36120e3e3e \
    --quiet
}

if [[ "$SERVICE_EXISTS" == 0 ]]; then
  deploy_api
else
  LATEST_CREATED_REVISION="$(python3 - "$SERVICE_INFO" <<'PY'
import json,sys
s=json.load(open(sys.argv[1],encoding='utf-8'))
print(s.get('status',{}).get('latestCreatedRevisionName',''))
PY
)"
  if [[ "$LATEST_CREATED_REVISION" != "$API_SERVICE-$REVISION_SUFFIX" ]]; then
    deploy_api
  else
    echo "Código ya creado como $LATEST_CREATED_REVISION; no se crea una revisión duplicada"
  fi
fi

gcloud run services update-traffic "$API_SERVICE" \
  --project="$PROJECT_ID" --region="$REGION" \
  --to-revisions="$API_SERVICE-$REVISION_SUFFIX=100" --quiet
gcloud run services describe "$API_SERVICE" --project="$PROJECT_ID" --region="$REGION" --format=json > "$SERVICE_INFO"
gcloud run services add-iam-policy-binding "$API_SERVICE" --project="$PROJECT_ID" --region="$REGION" --member="user:$DEPLOYER_ACCOUNT" --role=roles/run.invoker --quiet
gcloud run services get-iam-policy "$API_SERVICE" --project="$PROJECT_ID" --region="$REGION" --format=json > "$ROOT/state/$DEMO_RUN_ID/api_service_iam.json"
python3 - "$SERVICE_INFO" "$ROOT/state/$DEMO_RUN_ID/api_service_iam.json" "$API_SERVICE" "$API_SA" "$REVISION_SUFFIX" "$DEPLOYER_ACCOUNT" <<'PY'
import json,sys
s=json.load(open(sys.argv[1],encoding='utf-8'))
p=json.load(open(sys.argv[2],encoding='utf-8'))
name=sys.argv[3]; expected_sa=sys.argv[4]; suffix=sys.argv[5]; deployer='user:'+sys.argv[6]
status=s.get('status',{})
conditions=status.get('conditions',[])
ready=next((c.get('status') for c in conditions if c.get('type') in ('Ready','ReadyCondition')),None)
revision=status.get('latestReadyRevisionName','')
url=status.get('url','')
template=s.get('spec',{}).get('template',s.get('template',{}))
spec=template.get('spec',template)
sa=spec.get('serviceAccountName') or template.get('serviceAccount')
if ready not in (None,'True'): raise SystemExit(f'Cloud Run no Ready: {ready}; conditions={conditions}')
if not url or revision!=name+'-'+suffix: raise SystemExit(f'revisión/URL no corresponden: revision={revision} url={url}')
if sa!=expected_sa: raise SystemExit(f'identidad runtime incorrecta: {sa!r}')
public=[m for b in p.get('bindings',[]) for m in b.get('members',[]) if m in ('allUsers','allAuthenticatedUsers')]
if not any(b.get('role')=='roles/run.invoker' and deployer in b.get('members',[]) for b in p.get('bindings',[])):
    raise SystemExit(f'roles/run.invoker no verificado para {deployer}')
if public: raise SystemExit(f'el servicio quedó público: {public}')
print(f'ready={ready or "True"}; revision={revision}; url={url}; service_account={sa}; private=1')
PY
SERVICE_RESULT="$(python3 - "$SERVICE_INFO" <<'PY'
import json,sys
s=json.load(open(sys.argv[1],encoding='utf-8'))
print(s.get('status',{}).get('url',''))
print(s.get('status',{}).get('latestReadyRevisionName',''))
PY
)"
URL="$(printf '%s\n' "$SERVICE_RESULT" | sed -n '1p')"
REVISION="$(printf '%s\n' "$SERVICE_RESULT" | sed -n '2p')"
printf 'service=%s\nurl=%s\nrevision=%s\nservice_account=%s\nsource_hash=%s\nprivate=true\n' \
  "$API_SERVICE" "$URL" "$REVISION" "$API_SA" "$SOURCE_HASH" > "$ROOT/state/$DEMO_RUN_ID/api_deploy_ok.txt"
echo "SCRIPT 65: 1 — Cloud Run READY, API privada, $REVISION"
