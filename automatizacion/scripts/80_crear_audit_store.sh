#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 80 — sink de Cloud Logging hacia Audit Store BigQuery'
STATE="$ROOT/state/$DEMO_RUN_ID"; CONTRACT="$ROOT/automatizacion/configuracion/contratos/observability_controls.json"
[[ -s "$STATE/observability_preflight_ok.txt" ]] || { echo 'SCRIPT 80: 0 — dependencia: SCRIPT 79'; exit 1; }
DATASET="$(sed -n 's/^audit_dataset=//p' "$STATE/observability_preflight_ok.txt")"; SINK="$(contract_value "$CONTRACT" audit_store.sink)"; LOG_ID="$(contract_value "$CONTRACT" audit_store.log_id)"
DEST="bigquery.googleapis.com/projects/$PROJECT_ID/datasets/$DATASET"; FILTER="(logName=\"projects/$PROJECT_ID/logs/$LOG_ID\") OR protoPayload.serviceName=(\"run.googleapis.com\" OR \"bigquery.googleapis.com\" OR \"secretmanager.googleapis.com\" OR \"cloudkms.googleapis.com\")"
if gcloud logging sinks describe "$SINK" --project="$PROJECT_ID" --format=json > "$STATE/observability_sink.json" 2> "$STATE/observability_sink_error.txt"; then echo "Reutilizando sink $SINK"; else rc=$?; if rg -qi 'NOT_FOUND|not found|does not exist' "$STATE/observability_sink_error.txt"; then gcloud logging sinks create "$SINK" "$DEST" --project="$PROJECT_ID" --log-filter="$FILTER" --use-partitioned-tables --description='Audit Store interno para auditoría y evidencia de RetailSmart'; gcloud logging sinks describe "$SINK" --project="$PROJECT_ID" --format=json > "$STATE/observability_sink.json"; else cat "$STATE/observability_sink_error.txt" >&2; exit "$rc"; fi; fi
python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); assert s.get("destination")==sys.argv[2]; assert s.get("filter")==sys.argv[3]; assert not s.get("disabled"); assert s.get("writerIdentity"); print("Sink verificado")' "$STATE/observability_sink.json" "$DEST" "$FILTER"
WRITER="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["writerIdentity"])' "$STATE/observability_sink.json")"; [[ "$WRITER" == serviceAccount:* ]] || { echo "SCRIPT 80: 0 — writerIdentity inesperada: $WRITER"; exit 1; }
SQL="GRANT \`roles/bigquery.dataEditor\` ON SCHEMA \`$PROJECT_ID\`.$DATASET TO \"$WRITER\""; bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false "$SQL"
echo "writer_identity=$WRITER" > "$STATE/observability_sink_iam_ok.txt"; echo "destination=$DEST" >> "$STATE/observability_sink_iam_ok.txt"; echo "log_id=$LOG_ID" >> "$STATE/observability_sink_iam_ok.txt"
PAYLOAD="{\"event_id\":\"obs-${DEMO_RUN_ID}\",\"component\":\"luminalab-observability\",\"status\":\"AUDIT_STORE_TEST\"}"; gcloud logging write "$LOG_ID" "$PAYLOAD" --payload-type=json --severity=NOTICE --project="$PROJECT_ID"
echo "event_id=obs-$DEMO_RUN_ID" > "$STATE/observability_test_event.txt"
echo 'SCRIPT 80: 1 — sink, writer IAM de dataset y evento sintético enviados'
