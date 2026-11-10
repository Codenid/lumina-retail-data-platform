#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 79 — contrato, APIs y preflight de auditoría/observabilidad'
STATE="$ROOT/state/$DEMO_RUN_ID"
CONTRACT="$ROOT/automatizacion/configuracion/contratos/observability_controls.json"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --project="$PROJECT_ID" --format='value(projectNumber)')"
ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)')"
[[ -n "$PROJECT_NUMBER" && -n "$ACCOUNT" ]] || { echo 'SCRIPT 79: 0 — no se determinó proyecto o cuenta activa'; exit 1; }
python3 -m json.tool "$CONTRACT" >/dev/null
python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); project,region,prefix=sys.argv[2:]; render=lambda v:v.replace("{{PROJECT_ID}}",project).replace("{{REGION}}",region).replace("{{PREFIX}}",prefix); assert render(c["project"])==project and render(c["region"])==region; assert c["archimate_id"]=="id-91fc8e972e2e420e8a86c3afc6a260c8"; print("Contrato de auditoría y observabilidad validado")' "$CONTRACT" "$PROJECT_ID" "$REGION" "$PREFIX"
gcloud services list --enabled --project="$PROJECT_ID" --format='value(config.name)' > "$STATE/observability_services_before.txt"
for api in logging.googleapis.com monitoring.googleapis.com; do if ! grep -qx "$api" "$STATE/observability_services_before.txt"; then echo "Habilitando dependencia: $api"; gcloud services enable "$api" --project="$PROJECT_ID"; fi; done
gcloud services list --enabled --project="$PROJECT_ID" --format='value(config.name)' > "$STATE/observability_services_after.txt"
for api in logging.googleapis.com monitoring.googleapis.com; do grep -qx "$api" "$STATE/observability_services_after.txt" || { echo "SCRIPT 79: 0 — API no habilitada: $api"; exit 1; }; done
gcloud run services describe "${PREFIX}-insights-api" --project="$PROJECT_ID" --region="$REGION" --platform=managed --format=json > "$STATE/observability_api_service.json"
DATASET="$(contract_value "$CONTRACT" audit_store.dataset)"
if bq --project_id="$PROJECT_ID" show --format=prettyjson "$PROJECT_ID:$DATASET" > "$STATE/observability_dataset.json" 2> "$STATE/observability_dataset_error.txt"; then echo "Reutilizando dataset $DATASET"; else rc=$?; cat "$STATE/observability_dataset.json" >> "$STATE/observability_dataset_error.txt"; if rg -qi 'Not found|NOT_FOUND|not found' "$STATE/observability_dataset_error.txt"; then bq --project_id="$PROJECT_ID" mk --dataset --location="$REGION" --description='Audit Store de logs de plataforma y evidencia del laboratorio' "$PROJECT_ID:$DATASET"; bq --project_id="$PROJECT_ID" show --format=prettyjson "$PROJECT_ID:$DATASET" > "$STATE/observability_dataset.json"; else cat "$STATE/observability_dataset_error.txt" >&2; exit "$rc"; fi; fi
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d.get("location","").lower()==sys.argv[2].lower(); print("Audit Store verificado")' "$STATE/observability_dataset.json" "$REGION"
gcloud beta services identity create --service=logging.googleapis.com --project="$PROJECT_ID" --quiet > "$STATE/observability_logging_identity.txt"
echo "project=$PROJECT_ID" > "$STATE/observability_preflight_ok.txt"
echo "project_number=$PROJECT_NUMBER" >> "$STATE/observability_preflight_ok.txt"
echo "region=$REGION" >> "$STATE/observability_preflight_ok.txt"
echo "account=$ACCOUNT" >> "$STATE/observability_preflight_ok.txt"
echo "audit_dataset=$DATASET" >> "$STATE/observability_preflight_ok.txt"
echo "logging_agent=service-$PROJECT_NUMBER@gcp-sa-logging.iam.gserviceaccount.com" >> "$STATE/observability_preflight_ok.txt"
echo 'SCRIPT 79: 1 — contrato, APIs, Cloud Run y Audit Store verificados'
