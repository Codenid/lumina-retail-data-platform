#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 75 — clave KMS y permiso mínimo para Secret Manager'
STATE="$ROOT/state/$DEMO_RUN_ID"
CONTRACT="$ROOT/automatizacion/configuracion/contratos/security_controls.json"
[[ -s "$STATE/security_preflight_ok.txt" ]] || { echo 'SCRIPT 75: 0 — dependencia: SCRIPT 74'; exit 1; }
PROJECT_NUMBER="$(sed -n 's/^project_number=//p' "$STATE/security_preflight_ok.txt")"
KEYRING="$(contract_value "$CONTRACT" kms.keyring)"
KEY="$(contract_value "$CONTRACT" kms.key)"
AGENT="service-${PROJECT_NUMBER}@gcp-sa-secretmanager.iam.gserviceaccount.com"
KEY_RESOURCE="projects/${PROJECT_ID}/locations/${REGION}/keyRings/${KEYRING}/cryptoKeys/${KEY}"

gcloud beta services identity create --service=secretmanager.googleapis.com --project="$PROJECT_ID" --quiet > "$STATE/security_secretmanager_identity.txt"

KEYRING_ERROR="$STATE/security_keyring_error.txt"
if gcloud kms keyrings describe "$KEYRING" --project="$PROJECT_ID" --location="$REGION" --format=json > "$STATE/security_keyring.json" 2> "$KEYRING_ERROR"; then
  echo "Reutilizando keyring $KEYRING"
else
  rc=$?
  if rg -qi 'NOT_FOUND|not found|does not exist' "$KEYRING_ERROR"; then
    gcloud kms keyrings create "$KEYRING" --project="$PROJECT_ID" --location="$REGION"
    gcloud kms keyrings describe "$KEYRING" --project="$PROJECT_ID" --location="$REGION" --format=json > "$STATE/security_keyring.json"
  else
    cat "$KEYRING_ERROR" >&2; exit "$rc"
  fi
fi

KEY_ERROR="$STATE/security_key_error.txt"
if gcloud kms keys describe "$KEY" --project="$PROJECT_ID" --location="$REGION" --keyring="$KEYRING" --format=json > "$STATE/security_key.json" 2> "$KEY_ERROR"; then
  echo "Reutilizando clave $KEY"
else
  rc=$?
  if rg -qi 'NOT_FOUND|not found|does not exist' "$KEY_ERROR"; then
    NEXT_ROTATION="$(date -u -d '+90 days' '+%Y-%m-%dT%H:%M:%SZ')"
    gcloud kms keys create "$KEY" --project="$PROJECT_ID" --location="$REGION" --keyring="$KEYRING" --purpose=encryption --protection-level=software --rotation-period=90d --next-rotation-time="$NEXT_ROTATION"
    gcloud kms keys describe "$KEY" --project="$PROJECT_ID" --location="$REGION" --keyring="$KEYRING" --format=json > "$STATE/security_key.json"
  else
    cat "$KEY_ERROR" >&2; exit "$rc"
  fi
fi

python3 - "$STATE/security_key.json" "$CONTRACT" "$KEY_RESOURCE" <<'PY'
import json,sys
k=json.load(open(sys.argv[1],encoding='utf-8')); c=json.load(open(sys.argv[2],encoding='utf-8'))['kms']
if k.get('name')!=sys.argv[3]: raise SystemExit(f'nombre de clave divergente: {k.get("name")}')
if k.get('purpose')!=c['purpose']: raise SystemExit(f'propósito divergente: {k.get("purpose")}')
if k.get('rotationPeriod')!=c['rotation_period']: raise SystemExit(f'rotación divergente: {k.get("rotationPeriod")}')
primary=k.get('primary',{})
if primary.get('state')!='ENABLED': raise SystemExit(f'versión primaria no habilitada: {primary}')
if primary.get('protectionLevel')!=c['protection_level']: raise SystemExit(f'protección divergente: {primary.get("protectionLevel")}')
print('Clave simétrica SOFTWARE, primaria ENABLED y rotación de 90 días verificadas')
PY

gcloud kms keys get-iam-policy "$KEY" --project="$PROJECT_ID" --location="$REGION" --keyring="$KEYRING" --format=json > "$STATE/security_key_iam_before.json"
if ! python3 - "$STATE/security_key_iam_before.json" "$AGENT" <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8')); member='serviceAccount:'+sys.argv[2]
ok=any(b.get('role')=='roles/cloudkms.cryptoKeyEncrypterDecrypter' and member in b.get('members',[]) and not b.get('condition') for b in p.get('bindings',[]))
raise SystemExit(0 if ok else 1)
PY
then
  gcloud kms keys add-iam-policy-binding "$KEY" --project="$PROJECT_ID" --location="$REGION" --keyring="$KEYRING" --member="serviceAccount:$AGENT" --role=roles/cloudkms.cryptoKeyEncrypterDecrypter --quiet
fi
gcloud kms keys get-iam-policy "$KEY" --project="$PROJECT_ID" --location="$REGION" --keyring="$KEYRING" --format=json > "$STATE/security_key_iam.json"
python3 - "$STATE/security_key_iam.json" "$AGENT" <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8')); member='serviceAccount:'+sys.argv[2]
ok=any(b.get('role')=='roles/cloudkms.cryptoKeyEncrypterDecrypter' and member in b.get('members',[]) and not b.get('condition') for b in p.get('bindings',[]))
if not ok: raise SystemExit(f'binding KMS no verificado para {member}')
print('Encrypter/Decrypter limitado a la clave y al agente de Secret Manager')
PY
printf 'key_resource=%s\nsecretmanager_agent=%s\n' "$KEY_RESOURCE" "$AGENT" > "$STATE/security_kms_ok.txt"
echo 'SCRIPT 75: 1 — clave KMS y binding mínimo del agente verificados'
