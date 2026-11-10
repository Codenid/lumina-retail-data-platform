#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 76 — secreto regional cifrado con CMEK y acceso del runtime'
STATE="$ROOT/state/$DEMO_RUN_ID"
CONTRACT="$ROOT/automatizacion/configuracion/contratos/security_controls.json"
[[ -s "$STATE/security_kms_ok.txt" ]] || { echo 'SCRIPT 76: 0 — dependencia: SCRIPT 75'; exit 1; }
KEY_RESOURCE="$(sed -n 's/^key_resource=//p' "$STATE/security_kms_ok.txt")"
SECRET="$(contract_value "$CONTRACT" secret.id)"
RUNTIME_SA="$(contract_value "$CONTRACT" secret.consumer_service_account)"
POLICY_FILE="$STATE/security_secret_replication.json"
printf '{"userManaged":{"replicas":[{"location":"%s","customerManagedEncryption":{"kmsKeyName":"%s"}}]}}\n' "$REGION" "$KEY_RESOURCE" > "$POLICY_FILE"

SECRET_ERROR="$STATE/security_secret_error.txt"
if gcloud secrets describe "$SECRET" --project="$PROJECT_ID" --format=json > "$STATE/security_secret.json" 2> "$SECRET_ERROR"; then
  echo "Reutilizando secreto $SECRET"
else
  rc=$?
  if rg -qi 'NOT_FOUND|not found|does not exist' "$SECRET_ERROR"; then
    gcloud secrets create "$SECRET" --project="$PROJECT_ID" --replication-policy-file="$POLICY_FILE" --labels=component=security,environment=lab
    gcloud secrets describe "$SECRET" --project="$PROJECT_ID" --format=json > "$STATE/security_secret.json"
  else
    cat "$SECRET_ERROR" >&2; exit "$rc"
  fi
fi

python3 - "$STATE/security_secret.json" "$REGION" "$KEY_RESOURCE" <<'PY'
import json,sys
s=json.load(open(sys.argv[1],encoding='utf-8'))
replicas=(s.get('replication',{}).get('userManaged',{}).get('replicas') or [])
if len(replicas)!=1: raise SystemExit(f'replicación divergente: {replicas}')
r=replicas[0]
if r.get('location')!=sys.argv[2]: raise SystemExit(f'ubicación divergente: {r.get("location")}')
actual=r.get('customerManagedEncryption',{}).get('kmsKeyName')
if actual!=sys.argv[3]: raise SystemExit(f'CMEK divergente: {actual}')
print('Secreto con réplica única regional y CMEK esperado')
PY

gcloud secrets versions list "$SECRET" --project="$PROJECT_ID" --format=json > "$STATE/security_secret_versions_before.json"
if ! python3 - "$STATE/security_secret_versions_before.json" <<'PY'
import json,sys
versions=json.load(open(sys.argv[1],encoding='utf-8'))
raise SystemExit(0 if any(v.get('state')=='ENABLED' for v in versions) else 1)
PY
then
  TOKEN="$(openssl rand -hex 32)"
  printf '%s' "$TOKEN" | gcloud secrets versions add "$SECRET" --project="$PROJECT_ID" --data-file=- >/dev/null
  unset TOKEN
fi

gcloud secrets add-iam-policy-binding "$SECRET" --project="$PROJECT_ID" --member="serviceAccount:$RUNTIME_SA" --role=roles/secretmanager.secretAccessor --quiet
gcloud secrets get-iam-policy "$SECRET" --project="$PROJECT_ID" --format=json > "$STATE/security_secret_iam.json"
gcloud secrets versions list "$SECRET" --project="$PROJECT_ID" --format=json > "$STATE/security_secret_versions.json"
python3 - "$STATE/security_secret_iam.json" "$STATE/security_secret_versions.json" "$RUNTIME_SA" <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8')); versions=json.load(open(sys.argv[2],encoding='utf-8'))
member='serviceAccount:'+sys.argv[3]
ok=any(b.get('role')=='roles/secretmanager.secretAccessor' and member in b.get('members',[]) and not b.get('condition') for b in p.get('bindings',[]))
if not ok: raise SystemExit(f'Secret Accessor no verificado para {member}')
enabled=[v for v in versions if v.get('state')=='ENABLED']
if not enabled: raise SystemExit('no existe una versión ENABLED')
print(f'Acceso limitado al secreto y versión ENABLED verificados; versiones habilitadas={len(enabled)}')
PY
printf 'secret=%s\nruntime_service_account=%s\nkey_resource=%s\n' "$SECRET" "$RUNTIME_SA" "$KEY_RESOURCE" > "$STATE/security_secret_ok.txt"
echo 'SCRIPT 76: 1 — secreto CMEK, versión y acceso mínimo del runtime verificados'
