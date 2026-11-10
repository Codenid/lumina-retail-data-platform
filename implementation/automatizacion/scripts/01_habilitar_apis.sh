#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 01 — APIs del recorrido principal'
gcloud services enable serviceusage.googleapis.com compute.googleapis.com iam.googleapis.com \
 pubsub.googleapis.com storage.googleapis.com dataflow.googleapis.com bigquery.googleapis.com \
 logging.googleapis.com monitoring.googleapis.com
# Se materializa el agente requerido por la exportación Pub/Sub -> Bronze.
gcloud beta services identity create --service=pubsub.googleapis.com --project="$PROJECT_ID"
echo 'Consola: APIs y servicios > APIs habilitadas.'
