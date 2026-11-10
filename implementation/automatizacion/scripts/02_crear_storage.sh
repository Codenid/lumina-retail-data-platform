#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 02 — Landing, Bronze, Silver, artefactos y modelos'
for bucket in "$LANDING" "$BRONZE" "$SILVER" "$ARTIFACTS" "$MODELS"; do
 ensure "{\"location\":\"$REGION\",\"uniform_bucket_level_access\":true}" \
  gcloud storage buckets describe "gs://$bucket" --format=json ::: \
  gcloud storage buckets create "gs://$bucket" --location="$REGION" --uniform-bucket-level-access
 done
echo 'Consola: Cloud Storage > Buckets. Los prefijos aparecen cuando se escriben objetos.'
