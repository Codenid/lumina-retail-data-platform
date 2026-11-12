#!/usr/bin/env bash
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPL_DIR="$(cd "$APP_DIR/../.." && pwd)"
source "$IMPL_DIR/automatizacion/scripts/common.sh"

ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -n1)"
[[ -n "$ACTIVE_ACCOUNT" ]] || { echo 'No hay credenciales activas. Ejecuta gcloud auth login y gcloud auth application-default login.' >&2; exit 1; }
SERVICE="${PREFIX}-productor-datos"
RUNTIME_SA="${PREFIX}-productor@${PROJECT_ID}.iam.gserviceaccount.com"
WORKFLOW_NAME="${WORKFLOW_NAME:-${PREFIX}-batch}"
REPOSITORY="${PREFIX}-services"
IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/${SERVICE}:latest"

heading 'Preflight de los puntos de entrada existentes'
gcloud pubsub topics describe "$TOPIC" --project="$PROJECT_ID" >/dev/null
gcloud storage buckets describe "gs://$LANDING" >/dev/null
gcloud workflows describe "$WORKFLOW_NAME" --project="$PROJECT_ID" --location="$REGION" >/dev/null
ACTIVE_STREAM_JOB="$(gcloud dataflow jobs list --project="$PROJECT_ID" --region="$REGION" --status=active --format='value(name)' | awk -v prefix="${PREFIX}-silver-" 'index($0,prefix)==1 {print; exit}')"
[[ -n "$ACTIVE_STREAM_JOB" ]] || { echo 'No hay un Dataflow Silver activo. Actualiza/reinicia el consumidor antes de desplegar la productora.' >&2; exit 1; }
bq show --project_id="$PROJECT_ID" "$PROJECT_ID:$BRONZE_DATASET.pedidos_raw" >/dev/null
for domain in pedidos inventario entregas benchmark_competidores eventos_locales redes_sociales; do
  bq show --project_id="$PROJECT_ID" "$PROJECT_ID:$BRONZE_DATASET.${domain}_raw" >/dev/null
  bq show --project_id="$PROJECT_ID" "$PROJECT_ID:$SILVER_DATASET.$domain" >/dev/null
done
for table in cu01_riesgo_quiebre_despacho cu02_plan_reposicion cu03_kpis_operativos operational_mart; do
  bq show --project_id="$PROJECT_ID" "$PROJECT_ID:$GOLD_DATASET.$table" >/dev/null
done
bq show --project_id="$PROJECT_ID" --format=prettyjson "$PROJECT_ID:$GOLD_DATASET.operational_mart" | python3 -c 'import json,sys; names={f["name"] for f in json.load(sys.stdin)["schema"]["fields"]}; required={"scenario_id","entity_type","entity_id","sku_id","store_id","warehouse_id","quantity","status","observed_at","ingestion_mode","source_domain","correlation_id","measure_value","attributes"}; missing=required-names; sys.exit("Operational mart incompleto: "+str(sorted(missing)) if missing else 0)'

gcloud services enable run.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com \
  pubsub.googleapis.com storage.googleapis.com bigquery.googleapis.com workflows.googleapis.com \
  --project="$PROJECT_ID"

heading 'Identidad de ejecución y permisos mínimos'
if ! gcloud iam service-accounts describe "$RUNTIME_SA" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${PREFIX}-productor" --project="$PROJECT_ID" \
    --display-name='Lumina productora de datos'
fi
gcloud pubsub topics add-iam-policy-binding "$TOPIC" --project="$PROJECT_ID" \
  --member="serviceAccount:$RUNTIME_SA" --role=roles/pubsub.publisher >/dev/null
gcloud pubsub topics add-iam-policy-binding "$TOPIC" --project="$PROJECT_ID" \
  --member="serviceAccount:$RUNTIME_SA" --role=roles/pubsub.viewer >/dev/null
gcloud storage buckets add-iam-policy-binding "gs://$LANDING" \
  --member="serviceAccount:$RUNTIME_SA" --role=roles/storage.objectCreator >/dev/null
gcloud storage buckets add-iam-policy-binding "gs://$LANDING" \
  --member="serviceAccount:$RUNTIME_SA" --role=roles/storage.legacyBucketReader >/dev/null
gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$RUNTIME_SA" \
  --role=roles/bigquery.jobUser --condition=None >/dev/null
bq add-iam-policy-binding --project_id="$PROJECT_ID" --member="serviceAccount:$RUNTIME_SA" \
  --role=roles/bigquery.dataEditor "$PROJECT_ID:$BRONZE_DATASET" >/dev/null
gcloud workflows add-iam-policy-binding "$WORKFLOW_NAME" --project="$PROJECT_ID" --location="$REGION" \
  --member="serviceAccount:$RUNTIME_SA" --role=roles/workflows.invoker >/dev/null

if ! gcloud artifacts repositories describe "$REPOSITORY" --project="$PROJECT_ID" --location="$REGION" >/dev/null 2>&1; then
  gcloud artifacts repositories create "$REPOSITORY" --project="$PROJECT_ID" --location="$REGION" \
    --repository-format=docker --description='Servicios Lumina Retail'
fi

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
cp "$APP_DIR/Dockerfile" "$APP_DIR/app.py" "$APP_DIR/requirements.txt" "$BUILD_DIR/"
cp -R "$APP_DIR/static" "$BUILD_DIR/static"
mkdir -p "$BUILD_DIR/contracts"
cp "$IMPL_DIR/automatizacion/configuracion/contratos/productor_datos.json" \
   "$IMPL_DIR/automatizacion/configuracion/contratos/bigquery_schema.json" \
   "$IMPL_DIR/docs/arquitectura/productores.csv" "$BUILD_DIR/contracts/"
cp "$IMPL_DIR/docs/arquitectura/contrato-evento-original.json" \
   "$BUILD_DIR/contracts/contrato-evento-original.json"
cp "$IMPL_DIR/soluciones/procesamiento-streaming/contract.py" "$BUILD_DIR/contracts/streaming_contract.py"

heading 'Construcción y despliegue privado en Cloud Run'
gcloud builds submit "$BUILD_DIR" --project="$PROJECT_ID" --tag="$IMAGE"
gcloud run deploy "$SERVICE" --project="$PROJECT_ID" --region="$REGION" --image="$IMAGE" \
  --service-account="$RUNTIME_SA" --no-allow-unauthenticated --cpu=1 --memory=1Gi \
  --min=1 --max=1 --no-cpu-throttling --timeout=600 \
  --set-env-vars="PROJECT_ID=$PROJECT_ID,REGION=$REGION,PREFIX=$PREFIX,LANDING_BUCKET=$LANDING,BRONZE_DATASET=$BRONZE_DATASET,TOPIC_NAME=$TOPIC,WORKFLOW_NAME=$WORKFLOW_NAME"

if [[ "$ACTIVE_ACCOUNT" != *.gserviceaccount.com ]]; then
  gcloud run services add-iam-policy-binding "$SERVICE" --project="$PROJECT_ID" --region="$REGION" \
    --member="user:$ACTIVE_ACCOUNT" --role=roles/run.invoker >/dev/null
fi
echo "Desplegado: $SERVICE"
echo "Acceso privado: gcloud run services proxy $SERVICE --project=$PROJECT_ID --region=$REGION --port=8080"
echo 'Abrir: http://localhost:8080'
