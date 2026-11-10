#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 08 — publicar un único evento válido'
ID="$(cat "$ROOT/state/$DEMO_RUN_ID/job_id.txt")"
STATUS="$(gcloud dataflow jobs describe "$ID" --region="$REGION" --format='value(currentState)')"
[[ "$STATUS" == JOB_STATE_RUNNING ]] || { echo "Estado $STATUS; espera RUNNING y revisa logs antes de publicar."; exit 1; }
export ROOT
python3 - <<'EVENT'
import datetime,json,os,pathlib,sys
root=pathlib.Path(os.environ['ROOT']);sys.path.insert(0,str(root/'python'))
from contract import normalize,canonical
x=json.loads((root/'docs/arquitectura/contrato-evento-original.json').read_text())
x['event_id']='evt-'+os.environ['DEMO_RUN_ID'];x['simulation_id']='sim-'+os.environ['DEMO_RUN_ID']
x['trace_id']='trace-'+os.environ['DEMO_RUN_ID']
x['occurred_at']=x['emitted_at']=datetime.datetime.now(datetime.timezone.utc).isoformat()
p=root/'state'/os.environ['DEMO_RUN_ID']/'evento.json'
if p.exists():
 x=normalize(p.read_text())  # republicar conserva exactamente el contenido
else:
 p.write_text(canonical(normalize(json.dumps(x))))
print(p)
EVENT
gcloud pubsub topics publish "$TOPIC" --message="$(cat "$ROOT/state/$DEMO_RUN_ID/evento.json")" --format=json | tee "$ROOT/state/$DEMO_RUN_ID/publicacion.json"
echo 'Pub/Sub confirmó publicación. Aún no es evidencia de escritura Silver.'
