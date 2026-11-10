#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 71 — habilitar Knowledge Catalog y Data Lineage API'
STATE="$ROOT/state/$DEMO_RUN_ID"
[[ -s "$STATE/governance_preflight.txt" ]] || { echo 'SCRIPT 71: 0 — dependencia: SCRIPT 70'; exit 1; }
ACCOUNT="$(sed -n 's/^account=//p' "$STATE/governance_preflight.txt")"
ACTIVE="$(gcloud auth list --filter=status:ACTIVE --format='value(account)')"
[[ "$ACCOUNT" == "$ACTIVE" ]] || { echo "SCRIPT 71: 0 — cambió la identidad activa: preflight=$ACCOUNT actual=$ACTIVE"; exit 1; }

for api in dataplex.googleapis.com datalineage.googleapis.com; do
  ENABLED="$STATE/governance_${api}.before.txt"
  gcloud services list --enabled --project="$PROJECT_ID" --filter="config.name=$api" --format='value(config.name)' > "$ENABLED"
  if ! grep -qx "$api" "$ENABLED"; then
    echo "Habilitando API requerida: $api"
    gcloud services enable "$api" --project="$PROJECT_ID"
  else
    echo "API reutilizada: $api"
  fi
done

gcloud services list --enabled --project="$PROJECT_ID" --format='value(config.name)' > "$STATE/governance_services_after.txt"
for api in dataplex.googleapis.com datalineage.googleapis.com; do
  grep -qx "$api" "$STATE/governance_services_after.txt" || { echo "SCRIPT 71: 0 — API no quedó habilitada: $api"; exit 1; }
done

PROJECT_NUMBER="$(sed -n 's/^project_number=//p' "$STATE/governance_preflight.txt")"
AGENT="service-${PROJECT_NUMBER}@gcp-sa-dataplex.iam.gserviceaccount.com"
AGENT_INFO="$STATE/governance_dataplex_agent.json"
gcloud beta services identity create --service=dataplex.googleapis.com --project="$PROJECT_ID" --format=json > "$AGENT_INFO"
echo "Identidad administrada Dataplex verificada por services identity: $AGENT"
gcloud projects get-iam-policy "$PROJECT_ID" --project="$PROJECT_ID" --format=json > "$STATE/governance_project_iam_after.json"
HAS_AGENT_ROLE="$(python3 - "$STATE/governance_project_iam_after.json" "$AGENT" <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
member='serviceAccount:'+sys.argv[2]
print('yes' if any(b.get('role')=='roles/dataplex.serviceAgent' and member in b.get('members',[]) for b in p.get('bindings',[])) else 'no')
PY
 )"
if [[ "$HAS_AGENT_ROLE" != yes ]]; then
  echo "Falta el rol administrado roles/dataplex.serviceAgent para $AGENT; se añade solo a esa identidad de servicio"
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --project="$PROJECT_ID" \
    --member="serviceAccount:$AGENT" --role=roles/dataplex.serviceAgent --quiet
fi
gcloud projects get-iam-policy "$PROJECT_ID" --project="$PROJECT_ID" --format=json > "$STATE/governance_project_iam_after.json"
python3 - "$STATE/governance_project_iam_after.json" "$AGENT" <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
member='serviceAccount:'+sys.argv[2]
found=any(b.get('role')=='roles/dataplex.serviceAgent' and member in b.get('members',[]) for b in p.get('bindings',[]))
if not found: raise SystemExit(f'no se verificó el binding roles/dataplex.serviceAgent para {sys.argv[2]}')
print(f'Binding mínimo verificado: roles/dataplex.serviceAgent → {sys.argv[2]}')
PY

printf 'dataplex_api=enabled\ndatalineage_api=enabled\nproject=%s\nproject_number=%s\naccount=%s\nautomatic_lineage=enabled\n' \
  "$PROJECT_ID" "$PROJECT_NUMBER" "$ACCOUNT" > "$STATE/governance_api_ok.txt"
cat <<'EOF'

Nota de costo: Data Lineage habilita captura automática para servicios compatibles.
La interpretación automática de linaje puede generar cargos variables por los jobs
que produzcan eventos; el API permanece habilitado para capturar transformaciones
posteriores de la arquitectura.
EOF
echo 'SCRIPT 71: 1 — APIs y agente verificados; rol de servicio mínimo aplicado al agente Dataplex, sin grants al usuario'
