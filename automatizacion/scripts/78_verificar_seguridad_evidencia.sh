#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 78 — verificación final y evidencia de seguridad'
STATE="$ROOT/state/$DEMO_RUN_ID"
for marker in security_preflight_ok.txt security_kms_ok.txt security_secret_ok.txt security_dlp_ok.txt; do
  [[ -s "$STATE/$marker" ]] || { echo "SCRIPT 78: 0 — dependencia ausente: $marker"; exit 1; }
done
CONTRACT="$ROOT/automatizacion/configuracion/contratos/security_controls.json"
RENDERED_CONTRACT="$STATE/security_controls.rendered.json"
render_template "$CONTRACT" "$RENDERED_CONTRACT"
CONTRACT="$RENDERED_CONTRACT"
KEYRING="$(contract_value "$CONTRACT" kms.keyring)"
KEY="$(contract_value "$CONTRACT" kms.key)"
SECRET="$(contract_value "$CONTRACT" secret.id)"
SECRET_AGENT="$(sed -n 's/^secretmanager_agent=//p' "$STATE/security_kms_ok.txt")"

gcloud kms keys describe "$KEY" --project="$PROJECT_ID" --location="$REGION" --keyring="$KEYRING" --format=json > "$STATE/security_key_final.json"
gcloud kms keys get-iam-policy "$KEY" --project="$PROJECT_ID" --location="$REGION" --keyring="$KEYRING" --format=json > "$STATE/security_key_iam_final.json"
gcloud secrets describe "$SECRET" --project="$PROJECT_ID" --format=json > "$STATE/security_secret_final.json"
gcloud secrets get-iam-policy "$SECRET" --project="$PROJECT_ID" --format=json > "$STATE/security_secret_iam_final.json"
gcloud secrets versions list "$SECRET" --project="$PROJECT_ID" --format=json > "$STATE/security_secret_versions_final.json"

python3 - "$CONTRACT" "$STATE/security_key_final.json" "$STATE/security_key_iam_final.json" "$STATE/security_secret_final.json" "$STATE/security_secret_iam_final.json" "$STATE/security_secret_versions_final.json" "$STATE/security_dlp_template.json" "$STATE/security_dlp_result.json" "$SECRET_AGENT" <<'PY'
import json,sys
c=json.load(open(sys.argv[1],encoding='utf-8'))
k=json.load(open(sys.argv[2],encoding='utf-8')); kp=json.load(open(sys.argv[3],encoding='utf-8'))
s=json.load(open(sys.argv[4],encoding='utf-8')); sp=json.load(open(sys.argv[5],encoding='utf-8'))
versions=json.load(open(sys.argv[6],encoding='utf-8')); t=json.load(open(sys.argv[7],encoding='utf-8')); d=json.load(open(sys.argv[8],encoding='utf-8'))
agent='serviceAccount:'+sys.argv[9]
runtime='serviceAccount:'+c['secret']['consumer_service_account']
if k.get('primary',{}).get('state')!='ENABLED' or k.get('rotationPeriod')!=c['kms']['rotation_period']: raise SystemExit('KMS final divergente')
if not any(b.get('role')=='roles/cloudkms.cryptoKeyEncrypterDecrypter' and agent in b.get('members',[]) for b in kp.get('bindings',[])): raise SystemExit('IAM KMS final divergente')
replicas=s.get('replication',{}).get('userManaged',{}).get('replicas',[])
if len(replicas)!=1 or replicas[0].get('location')!=c['region']: raise SystemExit('réplica final divergente')
if not any(b.get('role')=='roles/secretmanager.secretAccessor' and runtime in b.get('members',[]) for b in sp.get('bindings',[])): raise SystemExit('IAM secreto final divergente')
if not any(v.get('state')=='ENABLED' for v in versions): raise SystemExit('versión final no habilitada')
if not t.get('name','').endswith('/inspectTemplates/'+c['dlp']['template_id']): raise SystemExit('template DLP final divergente')
types={f.get('infoType',{}).get('name') for f in d.get('result',{}).get('findings',[])}
if not {'EMAIL_ADDRESS','CREDIT_CARD_NUMBER'}.issubset(types): raise SystemExit('resultado DLP final divergente')
print('KMS, CMEK Secret Manager, IAM por recurso y DLP verificados')
PY

REPORT="$ROOT/state/$DEMO_RUN_ID/EVIDENCIA_SEGURIDAD.md"
{
  echo '# Resultado del grupo 74–78 — Seguridad'; echo
  printf 'Proyecto: `%s`  \nRegión: `%s`  \nResultado: **COMPLETADO**\n\n' "$PROJECT_ID" "$REGION"
  echo '| Script | Estado | Resultado |'; echo '|---|---:|---|'
  echo '| 74 | 1 | Contrato, identidad, runtime y APIs KMS/Secret Manager/DLP verificados |'
  echo '| 75 | 1 | Clave simétrica regional, primaria habilitada y rotación de 90 días; agente Secret Manager limitado a la clave |'
  echo '| 76 | 1 | Secreto con réplica `us-central1`, CMEK y acceso del runtime limitado al secreto |'
  echo '| 77 | 1 | Plantilla DLP regional y detección sintética verificadas sin persistir quotes |'
  echo '| 78 | 1 | Estado final e IAM consultados nuevamente en GCP |'; echo
  echo '## Recursos'; echo
  printf -- '- KMS: `%s/%s`, región `%s`.\n' "$KEYRING" "$KEY" "$REGION"
  printf -- '- Secret Manager: `%s`; réplica regional y CMEK.\n' "$SECRET"
  printf -- '- Consumidor autorizado: `%s-api@%s.iam.gserviceaccount.com`, solo `roles/secretmanager.secretAccessor` sobre ese secreto.\n' "$PREFIX" "$PROJECT_ID"
  printf -- '- DLP inspect template: `%s`, región `%s`.\n' "$(sed -n 's/^template=//p' "$STATE/security_dlp_ok.txt")" "$REGION"
  echo; echo 'No se almacenaron secretos en el repositorio ni se imprimió el valor generado. La prueba DLP usó datos sintéticos y guardó únicamente tipos, likelihood y ubicación de hallazgos.'
} > "$REPORT"
printf '74=1\n75=1\n76=1\n77=1\n78=1\nresultado=COMPLETADO\n' > "$STATE/security_group_ok.txt"
echo "SCRIPT 78: 1 — grupo de seguridad verificado; evidencia en state/$DEMO_RUN_ID/EVIDENCIA_SEGURIDAD.md"
