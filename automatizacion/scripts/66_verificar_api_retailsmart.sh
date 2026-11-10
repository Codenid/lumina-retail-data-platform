#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 66 — verificar Cloud Run y las cuatro rutas funcionales'
STATE="$ROOT/state/$DEMO_RUN_ID"
[[ -s "$STATE/api_deploy_ok.txt" ]] || { echo 'SCRIPT 66: 0 — dependencia: SCRIPT 65'; exit 1; }

API_SERVICE="${PREFIX}-insights-api"
URL="$(sed -n 's/^url=//p' "$STATE/api_deploy_ok.txt")"
EXPECTED_REVISION="$(sed -n 's/^revision=//p' "$STATE/api_deploy_ok.txt")"
EXPECTED_SA="$(sed -n 's/^service_account=//p' "$STATE/api_deploy_ok.txt")"
[[ "$URL" == https://* && -n "$EXPECTED_REVISION" && -n "$EXPECTED_SA" ]] || {
  echo 'SCRIPT 66: 0 — marcador de despliegue incompleto o URL Cloud Run inválida'; exit 1;
}

ATTEMPT_ID="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$STATE/api_validation_$ATTEMPT_ID"
mkdir -p "$OUT"
printf '%s\n' "$OUT" > "$STATE/api_validation_dir.txt"
printf 'attempt=%s\n' "$ATTEMPT_ID" > "$OUT/status.txt"

SERVICE_INFO="$OUT/service.json"
gcloud run services describe "$API_SERVICE" \
  --project="$PROJECT_ID" --region="$REGION" --format=json > "$SERVICE_INFO"
python3 - "$SERVICE_INFO" "$URL" "$EXPECTED_REVISION" "$EXPECTED_SA" <<'PY'
import json,sys
s=json.load(open(sys.argv[1],encoding='utf-8'))
status=s.get('status',{})
ready=next((c.get('status') for c in status.get('conditions',[]) if c.get('type') in ('Ready','ReadyCondition')),None)
template=s.get('spec',{}).get('template',s.get('template',{}))
spec=template.get('spec',template)
sa=spec.get('serviceAccountName') or template.get('serviceAccount')
actual=(status.get('url',''),status.get('latestReadyRevisionName',''),sa)
expected=tuple(sys.argv[2:5])
if ready!='True': raise SystemExit(f'Cloud Run no está READY: {ready}')
if actual!=expected: raise SystemExit(f'Cloud Run difiere del intento 65: actual={actual!r}; esperado={expected!r}')
print(f'Cloud Run: READY; revisión={actual[1]}; runtime={sa}')
PY
printf 'service_ready=1\nrevision=%s\n' "$EXPECTED_REVISION" >> "$OUT/status.txt"

TOKEN="$(gcloud auth print-identity-token)"
[[ -n "$TOKEN" ]] || { echo 'SCRIPT 66: 0 — no se pudo obtener token de identidad para la cuenta activa'; exit 1; }

# Confirma que el servicio no expone la ruta de negocio sin autenticación.
UNAUTH_ERROR="$OUT/unauthenticated.error.txt"
if ! UNAUTH_STATUS="$(curl --silent --show-error --max-time 30 \
  --output "$OUT/unauthenticated.json" --write-out '%{http_code}' \
  "$URL/api/v1/insights?limit=1" 2> "$UNAUTH_ERROR")"; then
  echo 'SCRIPT 66: 0 — no se pudo verificar el rechazo de acceso anónimo'
  cat "$UNAUTH_ERROR" >&2
  exit 1
fi
[[ "$UNAUTH_STATUS" == 401 || "$UNAUTH_STATUS" == 403 || "$UNAUTH_STATUS" == 404 ]] || {
  echo "SCRIPT 66: 0 — acceso anónimo inesperado a API privada, HTTP $UNAUTH_STATUS"; exit 1;
}
printf 'unauthenticated_http=%s\n' "$UNAUTH_STATUS" >> "$OUT/status.txt"

for route in insights kpis inventory-plans maintenance-risks; do
  case "$route" in
    insights) path='/api/v1/insights?limit=5' ;;
    kpis) path='/api/v1/kpis?limit=5' ;;
    inventory-plans) path='/api/v1/inventory-plans?limit=5' ;;
    maintenance-risks) path='/api/v1/maintenance-risks?limit=5' ;;
  esac
  BODY="$OUT/$route.json"
  ERROR="$OUT/$route.error.txt"
  if ! HTTP_STATUS="$(curl --silent --show-error --max-time 120 \
    --header "Authorization: Bearer $TOKEN" --output "$BODY" \
    --write-out '%{http_code}' "$URL$path" 2> "$ERROR")"; then
    echo "SCRIPT 66: 0 — fallo de transporte invocando $path"
    cat "$ERROR" >&2
    exit 1
  fi
  if ! python3 - "$route" "$BODY" "$HTTP_STATUS" <<'PY'
import json,sys
route,path,status=sys.argv[1:]
if status!='200': raise SystemExit(f'{route}: HTTP {status}')
data=json.load(open(path,encoding='utf-8'))
if route=='insights':
    counts=data.get('counts',{})
    a=int(counts.get('streaming_insights',0)); b=int(counts.get('stockout_risks',0))
    if a<1 or b<1: raise SystemExit(f'insights sin datos: streaming={a}, stockout={b}')
    print(f'insights: HTTP 200; streaming={a}; stockout_risks={b}')
else:
    expected={'kpis':'cu03_kpis_operativos','inventory-plans':'cu02_plan_reposicion','maintenance-risks':'cu04_alertas_mantenimiento'}[route]
    n=int(data.get('count',0)); table=data.get('source_table')
    if n<1 or table!=expected: raise SystemExit(f'{route}: filas={n}; tabla={table!r}; esperada={expected!r}')
    print(f'{route}: HTTP 200; filas={n}; tabla={table}')
PY
  then
    echo "SCRIPT 66: 0 — respuesta funcional no válida para $path"
    [[ -f "$BODY" ]] && cat "$BODY" >&2
    exit 1
  fi
  printf '%s_http=%s\n' "$route" "$HTTP_STATUS" >> "$OUT/status.txt"
done

printf 'result=1\n' >> "$OUT/status.txt"
printf 'attempt=%s\nrevision=%s\nresult=1\n' "$ATTEMPT_ID" "$EXPECTED_REVISION" > "$STATE/api_66_ok.txt"
echo "SCRIPT 66: 1 — servicio existente y READY; cuatro rutas con datos; anónimo rechazado (HTTP $UNAUTH_STATUS); intento $ATTEMPT_ID"
