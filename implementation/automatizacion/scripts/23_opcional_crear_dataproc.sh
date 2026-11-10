#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'OPCIONAL — cluster Dataproc single-node; genera costo hasta borrarlo'
[[ -s "$ROOT/state/$DEMO_RUN_ID/evento.json" ]] || { echo 'Ejecuta 08 y 22 primero.'; exit 1; }
echo '[1/8] Verificando fixture Bronze'
gcloud storage objects describe "gs://$BRONZE/batch/$DEMO_RUN_ID/evento.json" --project="$PROJECT_ID" --format='value(name)'
echo '[2/8] Habilitando/verificando Dataproc API'
gcloud services enable dataproc.googleapis.com --project="$PROJECT_ID"
SA="${PREFIX}-spark@${PROJECT_ID}.iam.gserviceaccount.com"
echo '[3/8] Verificando/creando cuenta de servicio Dataproc'
ensure "{\"email\":\"$SA\"}" gcloud iam service-accounts describe "$SA" --project="$PROJECT_ID" --format=json ::: \
 gcloud iam service-accounts create "${PREFIX}-spark" --project="$PROJECT_ID"
echo '[4/8] Aplicando permisos Dataproc y buckets'
gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$SA" --role=roles/dataproc.worker --condition=None >/dev/null
for bucket in "$ARTIFACTS" "$BRONZE" "$SILVER" "$MODELS"; do
 gcloud storage buckets add-iam-policy-binding "gs://$bucket" --member="serviceAccount:$SA" --role=roles/storage.objectUser >/dev/null
done
ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)')"
if [[ "$ACCOUNT" == *.gserviceaccount.com ]]; then MEMBER="serviceAccount:$ACCOUNT"; else MEMBER="user:$ACCOUNT"; fi
gcloud iam service-accounts add-iam-policy-binding "$SA" --project="$PROJECT_ID" --member="$MEMBER" --role=roles/iam.serviceAccountUser --condition=None >/dev/null
# Para la demo se usa una red EXISTENTE con conectividad requerida por Dataproc.
# No se crean reglas de firewall amplias. Si falla red/cuota, recoger error y detenerse.
echo '[5/8] Verificando/creando clúster Dataproc'
ensure "{\"config.gceClusterConfig.serviceAccount\":\"$SA\"}" \
 gcloud dataproc clusters describe "${PREFIX}-spark" --project="$PROJECT_ID" --region="$REGION" --format=json ::: \
 gcloud dataproc clusters create "${PREFIX}-spark" --project="$PROJECT_ID" --region="$REGION" --zone=us-central1-a --single-node \
 --master-machine-type=e2-standard-4 --master-boot-disk-size=50 --image-version=2.2-debian12 \
 --network="$NETWORK" --service-account="$SA" --scopes=cloud-platform \
 --bucket="$ARTIFACTS" --temp-bucket="$ARTIFACTS" --max-idle=30m --max-age=2h
# El job verifica Spark -> Bronze -> Silver Parquet, usando el evento ya validado de esta demo.
echo '[6/8] Ejecutando job Spark'
gcloud dataproc jobs submit pyspark "$ROOT/soluciones/procesamiento-batch/batch_demo.py" --project="$PROJECT_ID" --cluster="${PREFIX}-spark" --region="$REGION" -- \
 "gs://$BRONZE/batch/$DEMO_RUN_ID/evento.json" "gs://$SILVER/batch/$DEMO_RUN_ID/"
echo '[7/8] Verificando job Spark'
gcloud dataproc jobs list --project="$PROJECT_ID" --region="$REGION" --filter="labels.goog-dataproc-cluster-name:${PREFIX}-spark" --limit=5 --format='table(reference.jobId,status.state)'
echo '[8/8] Dataproc creado y job enviado; autoeliminación configurada.'
