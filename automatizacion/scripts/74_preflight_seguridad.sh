#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 74 — contrato, APIs y preflight de seguridad'
STATE="$ROOT/state/$DEMO_RUN_ID"
CONTRACT="$ROOT/automatizacion/configuracion/contratos/security_controls.json"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --project="$PROJECT_ID" --format='value(projectNumber)')"
ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)')"
RUNTIME_SA="${PREFIX}-api@${PROJECT_ID}.iam.gserviceaccount.com"
[[ -n "$PROJECT_NUMBER" && -n "$ACCOUNT" ]] || { echo 'SCRIPT 74: 0 — no se determinó proyecto o cuenta activa'; exit 1; }

python3 -m json.tool "$CONTRACT" >/dev/null
python3 - "$CONTRACT" "$PROJECT_ID" "$REGION" "$RUNTIME_SA" "$PREFIX" <<'PY'
import json,sys
c=json.load(open(sys.argv[1],encoding='utf-8'))
def render(value):
    return value.replace('{{PROJECT_ID}}',sys.argv[2]).replace('{{REGION}}',sys.argv[3]).replace('{{PREFIX}}',sys.argv[5])
assert render(c['project'])==sys.argv[2]
assert render(c['region'])==sys.argv[3]
assert c['archimate_id']=='id-f6ff7f9f26f14cc8ab051979cca0dad6'
assert render(c['secret']['consumer_service_account'])==sys.argv[4]
assert c['kms']['purpose']=='ENCRYPT_DECRYPT'
assert c['kms']['protection_level']=='SOFTWARE'
assert c['kms']['rotation_period']=='7776000s'
assert c['secret']['access_role']=='roles/secretmanager.secretAccessor'
assert c['dlp']['include_quote'] is False
assert set(c['dlp']['info_types'])=={'EMAIL_ADDRESS','PHONE_NUMBER','CREDIT_CARD_NUMBER'}
print('Contrato de seguridad validado: KMS, Secret Manager y DLP')
PY

gcloud iam service-accounts describe "$RUNTIME_SA" --project="$PROJECT_ID" --format=json > "$STATE/security_runtime_sa.json"
python3 - "$STATE/security_runtime_sa.json" <<'PY'
import json,sys
s=json.load(open(sys.argv[1],encoding='utf-8'))
if s.get('disabled'): raise SystemExit('la cuenta de runtime está deshabilitada')
PY

gcloud services list --enabled --project="$PROJECT_ID" --format='value(config.name)' > "$STATE/security_services_before.txt"
mapfile -t APIS < <(python3 - "$CONTRACT" <<'PY'
import json,sys
print('\n'.join(json.load(open(sys.argv[1],encoding='utf-8'))['apis']))
PY
)
for api in "${APIS[@]}"; do
  if ! grep -qx "$api" "$STATE/security_services_before.txt"; then
    echo "Habilitando dependencia: $api"
    gcloud services enable "$api" --project="$PROJECT_ID"
  fi
done
gcloud services list --enabled --project="$PROJECT_ID" --format='value(config.name)' > "$STATE/security_services_after.txt"
for api in "${APIS[@]}"; do
  grep -qx "$api" "$STATE/security_services_after.txt" || { echo "SCRIPT 74: 0 — API no habilitada: $api"; exit 1; }
done

gcloud projects get-iam-policy "$PROJECT_ID" --project="$PROJECT_ID" --format=json > "$STATE/security_project_iam.json"
python3 - "$STATE/security_project_iam.json" "$ACCOUNT" <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8')); member='user:'+sys.argv[2]
roles=[b['role'] for b in p.get('bindings',[]) if member in b.get('members',[])]
if 'roles/owner' not in roles:
    raise SystemExit(f'cuenta activa sin Owner requerido para crear identidades de servicio: {roles}')
print('Identidad ejecutora verificada; no se añadirán roles al usuario')
PY

printf 'project=%s\nproject_number=%s\nregion=%s\naccount=%s\nruntime_service_account=%s\n' \
  "$PROJECT_ID" "$PROJECT_NUMBER" "$REGION" "$ACCOUNT" "$RUNTIME_SA" > "$STATE/security_preflight_ok.txt"
echo 'SCRIPT 74: 1 — contrato, identidad, runtime y tres APIs verificados'
