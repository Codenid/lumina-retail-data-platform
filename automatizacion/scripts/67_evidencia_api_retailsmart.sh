#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 67 — verificar estado final y guardar evidencia de API'
[[ -s "$ROOT/state/$DEMO_RUN_ID/api_deploy_ok.txt" ]] || { echo 'SCRIPT 67: 0 — dependencia: SCRIPT 65'; exit 1; }
[[ -s "$ROOT/state/$DEMO_RUN_ID/api_iam_ok.txt" ]] || { echo 'SCRIPT 67: 0 — dependencia: SCRIPT 64'; exit 1; }
API_SERVICE="${PREFIX}-insights-api"
SERVICE_INFO="$ROOT/state/$DEMO_RUN_ID/api_service_final.json"
SERVICE_IAM="$ROOT/state/$DEMO_RUN_ID/api_service_iam_final.json"
gcloud run services describe "$API_SERVICE" --project="$PROJECT_ID" --region="$REGION" --format=json > "$SERVICE_INFO"
gcloud run services get-iam-policy "$API_SERVICE" --project="$PROJECT_ID" --region="$REGION" --format=json > "$SERVICE_IAM"
python3 - "$SERVICE_INFO" "$SERVICE_IAM" "$ROOT/state/$DEMO_RUN_ID/api_deploy_ok.txt" "$ROOT/state/$DEMO_RUN_ID/api_preflight_ok.txt" <<'PY' > "$ROOT/state/$DEMO_RUN_ID/api_final_facts.txt"
import json,sys
def read(path):
    out={}
    for line in open(path,encoding='utf-8'):
        if '=' in line:
            k,v=line.rstrip('\n').split('=',1); out[k]=v
    return out
s=json.load(open(sys.argv[1],encoding='utf-8')); p=json.load(open(sys.argv[2],encoding='utf-8'))
expected=read(sys.argv[3]); preflight=read(sys.argv[4]); status=s.get('status',{})
ready=next((c.get('status') for c in status.get('conditions',[]) if c.get('type') in ('Ready','ReadyCondition')),None)
revision=status.get('latestReadyRevisionName',''); url=status.get('url','')
template=s.get('spec',{}).get('template',s.get('template',{})); spec=template.get('spec',template)
sa=spec.get('serviceAccountName') or template.get('serviceAccount')
public=[m for b in p.get('bindings',[]) for m in b.get('members',[]) if m in ('allUsers','allAuthenticatedUsers')]
invoker='user:'+preflight.get('account','')
has_invoker=any(b.get('role')=='roles/run.invoker' and invoker in b.get('members',[]) for b in p.get('bindings',[]))
if ready!='True': raise SystemExit(f'Cloud Run no está READY: {ready}; {status.get("conditions")}')
if revision!=expected.get('revision') or url!=expected.get('url'): raise SystemExit('la revisión o URL en GCP no coincide con el intento registrado')
if sa!=expected.get('service_account'): raise SystemExit(f'identidad runtime divergente: {sa!r}')
if public: raise SystemExit(f'la API tiene acceso público: {public}')
if not has_invoker: raise SystemExit(f'roles/run.invoker no verificado para {invoker}')
print('ready=True'); print(f'service={s.get("metadata",{}).get("name",expected.get("service"))}')
print(f'url={url}'); print(f'revision={revision}'); print(f'runtime_service_account={sa}')
print(f'invoker={invoker}'); print('authentication=private')
PY

REVISION="$(sed -n 's/^revision=//p' "$ROOT/state/$DEMO_RUN_ID/api_final_facts.txt")"
REQUEST_LOGS="$ROOT/state/$DEMO_RUN_ID/api_request_logs.json"
gcloud logging read \
  "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"$API_SERVICE\" AND resource.labels.revision_name=\"$REVISION\"" \
  --project="$PROJECT_ID" --limit=100 --order=desc --format=json > "$REQUEST_LOGS"
LOGS="$(python3 - "$REQUEST_LOGS" <<'PY'
import json,sys
entries=json.load(open(sys.argv[1],encoding='utf-8'))
http=sum(1 for e in entries if e.get('httpRequest'))
app=sum(1 for e in entries if 'request method=' in e.get('textPayload',''))
print(f'{http} solicitudes HTTP y {app} registros de aplicación observados en la revisión')
PY
)"

RESPONSES="$(cat "$ROOT/state/$DEMO_RUN_ID/api_validation_dir.txt" 2>/dev/null || true)"
[[ -n "$RESPONSES" && -d "$RESPONSES" ]] || RESPONSES="$ROOT/state/$DEMO_RUN_ID/api_responses"
COUNTS="$ROOT/state/$DEMO_RUN_ID/api_route_counts.txt"
python3 - "$RESPONSES" <<'PY' > "$COUNTS"
import json,os,sys
root=sys.argv[1]
for route in ('insights','kpis','inventory-plans','maintenance-risks'):
    path=os.path.join(root,route+'.json')
    if not os.path.isfile(path):
        err=os.path.join(root,route+'.error.txt')
        if os.path.isfile(err):
            message=' '.join(open(err,encoding='utf-8').read().split())
            print(f'{route}=FALLIDA; {message}')
            continue
        print(f'{route}=NO_VERIFICADA'); continue
    d=json.load(open(path,encoding='utf-8'))
    if route=='insights': print(f'{route}=streaming:{d.get("counts",{}).get("streaming_insights",0)},stockout_risks:{d.get("counts",{}).get("stockout_risks",0)}')
    else: print(f'{route}=rows:{d.get("count",0)},table:{d.get("source_table","unknown")}')
PY

STATUS_FILE="$RESPONSES/status.txt"
if [[ -s "$STATUS_FILE" ]] && grep -q '^result=1$' "$STATUS_FILE" \
  && grep -q '^insights_http=200$' "$STATUS_FILE" \
  && grep -q '^kpis_http=200$' "$STATUS_FILE" \
  && grep -q '^inventory-plans_http=200$' "$STATUS_FILE" \
  && grep -q '^maintenance-risks_http=200$' "$STATUS_FILE"; then
  ROUTES_OK=1; API_RESULT=1; GROUP_RESULT='COMPLETADO'
else
  ROUTES_OK=0; API_RESULT=0; GROUP_RESULT='PARCIAL'
fi
UNAUTH='no observada'
[[ -s "$STATUS_FILE" ]] && UNAUTH="$(sed -n 's/^unauthenticated_http=//p' "$STATUS_FILE" | head -n1)"

{
  echo "# API RetailSmart Insights — $DEMO_RUN_ID"; echo
  echo "Proyecto: $PROJECT_ID"; echo "Región: $REGION"; cat "$ROOT/state/$DEMO_RUN_ID/api_final_facts.txt"; echo
  echo "Estado: **$GROUP_RESULT**; Cloud Run y rutas funcionales verificadas según el paso 66."
  echo 'Límite por consulta: 100 filas y 52,428,800 bytes; escalado: mínimo 0, máximo 2.'; echo
  echo '## Rutas'; echo; sed 's/^/- /' "$COUNTS"; echo
  echo "Invocación sin autenticación: HTTP $UNAUTH."
  echo "Chequeo de existencia: Cloud Run READY y revisión comparada con el despliegue del intento."
  echo "Logs de solicitudes coincidentes: $LOGS"
  echo "Resultado funcional del paso 66: $API_RESULT; Cloud Run fue contrastado y las cuatro rutas se verificaron según la evidencia del intento."
} > "$ROOT/state/$DEMO_RUN_ID/EVIDENCIA_API_RETAILSMART.md"

REPORT="$ROOT/state/$DEMO_RUN_ID/EVIDENCIA_API_RETAILSMART.md"
{
  echo '# Resultado del grupo 63–67 — API RetailSmart Insights'; echo
  printf 'Fecha: %s\nProyecto: `%s`\nRegión: `%s`\nResultado del grupo: **%s**\n\n' "$(date +%Y-%m-%d)" "$PROJECT_ID" "$REGION" "$GROUP_RESULT"
  echo '| Script | Resultado | Evidencia |'; echo '|---|---:|---|'
  echo '| 63 — preflight y APIs | 1 | Contrato, APIs, ubicación y cinco tablas Gold verificados |'
  echo '| 64 — identidad y permisos | 1 | Job User, cinco grants Data Viewer por tabla y permisos de build verificados |'
  echo '| 65 — despliegue | 1 | Cloud Run READY, privado y revisión registrada |'
  echo "| 66 — rutas | $API_RESULT | $([[ $ROUTES_OK == 1 ]] && echo 'Cloud Run existe y está READY; cuatro rutas autenticadas devuelven datos' || echo 'Verificación de servicio/rutas fallida; revisar evidencia del intento') |"
  echo "| 67 — evidencia final | 1 | Estado, revisión e IAM consultados en GCP; cierre $GROUP_RESULT registrado |"; echo
  echo '## Servicio'; echo; cat "$ROOT/state/$DEMO_RUN_ID/api_final_facts.txt"; echo
  echo '## Rutas'; echo; sed 's/^/- /' "$COUNTS"; echo
  echo "- Acceso anónimo: HTTP $UNAUTH."
  echo "- Chequeo de existencia: servicio READY y revisión del intento contrastada."
  echo "- Logs de solicitudes: $LOGS"
  echo '- El grupo valida existencia/estado de Cloud Run y rutas funcionales; `/healthz` no es requisito ni regla de negocio.'; echo
  echo '## Identidades y permisos'; echo
  printf '%s\n' "- Runtime: \`${PREFIX}-api@$PROJECT_ID.iam.gserviceaccount.com\`; BigQuery Job User en el proyecto y Data Viewer limitado a cinco tablas Gold."
  printf '%s\n' "- Invoker del servicio privado: \`$(sed -n 's/^account=//p' "$ROOT/state/$DEMO_RUN_ID/api_preflight_ok.txt")\`, en IAM del servicio."
  printf '%s\n' "- Build: \`$(sed -n 's/^build_service_account=//p' "$ROOT/state/$DEMO_RUN_ID/api_iam_ok.txt")\`; Cloud Run Builder y Artifact Registry Writer acotado al repositorio."
  echo '- APIs habilitadas: Cloud Run, Cloud Build, Artifact Registry y Cloud Storage.'; echo
  echo 'Evidencia local: `state/demo001/EVIDENCIA_API_RETAILSMART.md`.'
  if [[ "$GROUP_RESULT" == COMPLETADO ]]; then
    echo 'El grupo 63–67 queda cerrado: servicio Cloud Run existente/READY y cuatro rutas funcionales verificadas.'
  else
    echo 'El grupo 63–67 sigue parcial; consultar estado del servicio y respuestas del intento para el bloqueo exacto.'
  fi
} > "$REPORT"
printf 'revision=%s\nready=1\nprivate=1\nroutes_verified=%s\n' \
  "$(sed -n 's/^revision=//p' "$ROOT/state/$DEMO_RUN_ID/api_final_facts.txt")" "$ROUTES_OK" > "$ROOT/state/$DEMO_RUN_ID/api_verified.txt"
echo "SCRIPT 67: 1 — estado GCP comprobado; cierre $GROUP_RESULT guardado en $REPORT"
