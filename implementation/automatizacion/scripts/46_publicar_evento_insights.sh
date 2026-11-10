#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 46 — publicar evento Insights'
[[ -s "$ROOT/state/$DEMO_RUN_ID/insights_job_id.txt" ]] || { echo 'SCRIPT 46: 0'; echo 'Dependencia faltante: SCRIPT 45'; exit 1; }
ID="$(cat "$ROOT/state/$DEMO_RUN_ID/insights_job_id.txt")"
STATE=''; for attempt in $(seq 1 30); do STATE="$(gcloud dataflow jobs describe "$ID" --project="$PROJECT_ID" --region="$REGION" --format='value(currentState)')"; [[ "$STATE" == JOB_STATE_RUNNING ]] && break; case "$STATE" in JOB_STATE_FAILED|JOB_STATE_CANCELLED|JOB_STATE_DONE|JOB_STATE_DRAINED) echo "SCRIPT 46: 0"; echo "Motivo: Dataflow terminó en $STATE"; exit 1;; esac; sleep 10; done
[[ "$STATE" == JOB_STATE_RUNNING ]] || { echo 'SCRIPT 46: 0'; echo 'Motivo: Dataflow no llegó a RUNNING en 5 minutos'; exit 1; }
EVENT_ID="evt-${DEMO_RUN_ID}-insights-$(date -u +%Y%m%d%H%M%S)"
EVENT_FILE="$ROOT/state/$DEMO_RUN_ID/insights_evento.json"
python3 - "$ROOT/state/$DEMO_RUN_ID/evento.json" "$EVENT_FILE" "$EVENT_ID" <<'PY'
import json, sys
source, target, event_id = sys.argv[1:]
with open(source, encoding='utf-8') as fh:
    event = json.load(fh)
event['event_id'] = event_id
with open(target, 'w', encoding='utf-8') as fh:
    json.dump(event, fh, separators=(',', ':'))
PY
MESSAGE="$(cat "$EVENT_FILE")"
gcloud pubsub topics publish "$INSIGHTS_TOPIC" --project="$PROJECT_ID" --message="$MESSAGE" --format=json > "$ROOT/state/$DEMO_RUN_ID/insights_publicacion.json"
MESSAGE_ID="$(python3 - "$ROOT/state/$DEMO_RUN_ID/insights_publicacion.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as fh:
    result = json.load(fh)
print(result.get('messageIds', [''])[0])
PY
)"
printf '%s\n' "$EVENT_ID" > "$ROOT/state/$DEMO_RUN_ID/insights_event_id.txt"
printf '%s\n' "$MESSAGE_ID" > "$ROOT/state/$DEMO_RUN_ID/insights_message_id.txt"
printf 'Evento Insights publicado\nevent_id=%s\nmessageId=%s\n' "$EVENT_ID" "$MESSAGE_ID" > "$ROOT/state/$DEMO_RUN_ID/insights_event_ok.txt"
echo 'SCRIPT 46: 1'
