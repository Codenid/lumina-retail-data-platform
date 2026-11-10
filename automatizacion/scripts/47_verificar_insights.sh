#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 47 — verificar Insights y auditoría'
[[ -s "$ROOT/state/$DEMO_RUN_ID/insights_event_ok.txt" ]] || { echo 'SCRIPT 47: 0'; echo 'Dependencia faltante: SCRIPT 46'; exit 1; }
[[ -s "$ROOT/state/$DEMO_RUN_ID/insights_event_id.txt" ]] || { echo 'SCRIPT 47: 0'; echo 'Motivo: falta event_id real de SCRIPT 46'; exit 1; }
EVENT_ID="$(cat "$ROOT/state/$DEMO_RUN_ID/insights_event_id.txt")"
MESSAGE_ID="$(cat "$ROOT/state/$DEMO_RUN_ID/insights_message_id.txt" 2>/dev/null || true)"
for attempt in $(seq 1 30); do
  if ! INS_RAW="$(bq --project_id="$PROJECT_ID" query --use_legacy_sql=false --format=csv --max_rows=2 "SELECT COUNT(*) FROM \`$PROJECT_ID.$GOLD_DATASET.insights_streaming\` WHERE event_id='$EVENT_ID'" 2>&1)"; then
    echo 'SCRIPT 47: 0'; echo 'Etapa: consulta insights_streaming'; echo "$INS_RAW"; exit 1
  fi
  if ! AUD_RAW="$(bq --project_id="$PROJECT_ID" query --use_legacy_sql=false --format=csv --max_rows=2 "SELECT COUNT(*) FROM \`$PROJECT_ID.$GOLD_DATASET.procesamiento_auditoria\` WHERE event_id='$EVENT_ID'" 2>&1)"; then
    echo 'SCRIPT 47: 0'; echo 'Etapa: consulta procesamiento_auditoria'; echo "$AUD_RAW"; exit 1
  fi
  INS="$(printf '%s\n' "$INS_RAW" | tail -1)"; AUD="$(printf '%s\n' "$AUD_RAW" | tail -1)"
  if [[ "$INS" =~ ^[1-9][0-9]*$ && "$AUD" =~ ^[1-9][0-9]*$ ]]; then
    printf 'event_id=%s\nmessageId=%s\ninsights=%s\nauditoria=%s\n' "$EVENT_ID" "$MESSAGE_ID" "$INS" "$AUD" > "$ROOT/state/$DEMO_RUN_ID/insights_verified.txt"
    echo "SCRIPT 47: 1 — event_id=$EVENT_ID messageId=$MESSAGE_ID Insights=$INS Auditoria=$AUD"; exit 0
  fi
  sleep 10
done
echo 'SCRIPT 47: 0'; echo "Etapa: recepción/escritura; event_id=$EVENT_ID messageId=$MESSAGE_ID Insights=$INS Auditoria=$AUD"; exit 1
