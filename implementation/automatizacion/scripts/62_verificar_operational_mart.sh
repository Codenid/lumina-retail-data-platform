#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 62 — ejecutar refresco programado y verificar las ocho fuentes'
[[ -s "$ROOT/state/$DEMO_RUN_ID/operational_mart_schedule_ok.txt" ]] || { echo 'SCRIPT 62: 0 — dependencia: SCRIPT 61'; exit 1; }
RESOURCE="$(sed -n 's/^resource=//p' "$ROOT/state/$DEMO_RUN_ID/operational_mart_schedule_ok.txt")"
LOCATION="$(sed -n 's/^location=//p' "$ROOT/state/$DEMO_RUN_ID/operational_mart_schedule_ok.txt")"
RUN_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RUNS_FILE="$ROOT/state/$DEMO_RUN_ID/operational_mart_runs.json"
STATE='PENDING'
RUN_NAME=''
# Reuse a recent run after a local validation failure; never launch a duplicate.
bq --project_id="$PROJECT_ID" ls --transfer_run --transfer_location="$LOCATION" --format=prettyjson "$RESOURCE" > "$RUNS_FILE"
RECENT_RUN="$(python3 - "$RUNS_FILE" <<'PY'
import json,sys,datetime
raw=json.load(open(sys.argv[1],encoding='utf-8'))
runs=raw if isinstance(raw,list) else raw.get('runs',[])
now=datetime.datetime.now(datetime.timezone.utc)
def stamp(r):
    s=r.get('startTime') or r.get('runTime') or ''
    try: return datetime.datetime.fromisoformat(s.replace('Z','+00:00'))
    except ValueError: return datetime.datetime.min.replace(tzinfo=datetime.timezone.utc)
recent=[r for r in runs if now-stamp(r) < datetime.timedelta(minutes=15)]
if recent:
    r=max(recent,key=stamp)
    print(r.get('name','')); print(r.get('state','PENDING'))
PY
)"
if [[ -n "$RECENT_RUN" ]]; then
  RUN_NAME="$(printf '%s\n' "$RECENT_RUN" | sed -n '1p')"
  STATE="$(printf '%s\n' "$RECENT_RUN" | sed -n '2p')"
else
  bq --project_id="$PROJECT_ID" mk --transfer_run --run_time="$RUN_TIME" "$RESOURCE" >/dev/null
fi
for attempt in $(seq 1 30); do
  bq --project_id="$PROJECT_ID" ls --transfer_run --transfer_location="$LOCATION" --format=prettyjson "$RESOURCE" > "$RUNS_FILE"
  RUN_INFO="$(python3 - "$RUNS_FILE" "$RUN_TIME" "$RUN_NAME" <<'PY'
import json,sys
runs=json.load(open(sys.argv[1],encoding='utf-8'))
if isinstance(runs,dict): runs=runs.get('runs',[])
requested=sys.argv[2]
eligible=[r for r in runs if r.get('name')==sys.argv[3]] if len(sys.argv)>3 and sys.argv[3] else []
if not eligible: eligible=[r for r in runs if r.get('runTime','')>=requested or r.get('startTime','')>=requested]
run=max(eligible,key=lambda r:(r.get('runTime') or r.get('startTime') or ''),default=max(runs,key=lambda r:(r.get('runTime') or r.get('startTime') or ''),default={}))
print(run.get('state','PENDING'))
print(run.get('name',''))
print((run.get('errorStatus') or {}).get('message',''))
PY
)"
  STATE="$(printf '%s\n' "$RUN_INFO" | sed -n '1p')"
  RUN_NAME="$(printf '%s\n' "$RUN_INFO" | sed -n '2p')"
  RUN_ERROR="$(printf '%s\n' "$RUN_INFO" | sed -n '3p')"
  case "$STATE" in
    SUCCEEDED) break ;;
    FAILED|CANCELLED) echo 'SCRIPT 62: 0'; echo "Transfer run: $RUN_NAME state=$STATE error=$RUN_ERROR"; exit 1 ;;
  esac
  sleep 10
done
[[ "$STATE" == SUCCEEDED ]] || { echo 'SCRIPT 62: 0'; echo "Transfer run no terminó; run=$RUN_NAME state=$STATE"; exit 1; }
bq --project_id="$PROJECT_ID" --location="$LOCATION" query --use_legacy_sql=false --maximum_bytes_billed=104857600 --format=prettyjson "SELECT source_domain,COUNT(DISTINCT entity_id) AS entity_count FROM \`$PROJECT_ID.$GOLD_DATASET.operational_mart\` WHERE source_domain IS NOT NULL GROUP BY source_domain" > "$ROOT/state/$DEMO_RUN_ID/operational_mart_source_counts.json"
python3 - "$ROOT/state/$DEMO_RUN_ID/operational_mart_source_counts.json" <<'PY'
import json,sys
data=json.load(open(sys.argv[1],encoding='utf-8'))
if isinstance(data,list): counts={r['source_domain']:int(r['entity_count']) for r in data}
else: counts={r['f'][0]['v']:int(r['f'][1]['v']) for r in data.get('rows',[])}
expected={'pedidos','inventario','entregas','benchmark_competidores','eventos_locales','redes_sociales','insights_streaming','procesamiento_auditoria'}
missing=expected-set(counts); empty={k for k in expected if counts.get(k,0)<1}
if missing or empty: raise SystemExit(f'fuentes faltantes={sorted(missing)} vacías={sorted(empty)} conteos={counts}')
print(counts)
PY
{
  echo "# Operational Mart integrado — $DEMO_RUN_ID"
  echo
  echo "Proyecto: $PROJECT_ID"
  echo "Ubicación: $LOCATION"
  sed -n 's/^service_account=/Cuenta de ejecución: /p' "$ROOT/state/$DEMO_RUN_ID/operational_mart_schedule_ok.txt"
  sed -n 's/^schedule=/Frecuencia: /p' "$ROOT/state/$DEMO_RUN_ID/operational_mart_schedule_ok.txt"
  sed -n 's/^resource=/Scheduled query: /p' "$ROOT/state/$DEMO_RUN_ID/operational_mart_schedule_ok.txt"
  echo "Ejecución verificada: $RUN_NAME — $STATE"
  echo
  echo 'Conteos por source_domain:'
  python3 - "$ROOT/state/$DEMO_RUN_ID/operational_mart_source_counts.json" <<'PY'
import json,sys
data=json.load(open(sys.argv[1],encoding='utf-8'))
if isinstance(data,list):
    for r in sorted(data,key=lambda x:x['source_domain']): print(f"- {r['source_domain']}: {r['entity_count']}")
else:
    for r in sorted(data.get('rows',[]),key=lambda x:x['f'][0]['v']): print(f"- {r['f'][0]['v']}: {r['f'][1]['v']}")
PY
} > "$ROOT/state/$DEMO_RUN_ID/EVIDENCIA_OPERATIONAL_MART.md"
printf 'run=%s\nstate=%s\n' "$RUN_NAME" "$STATE" > "$ROOT/state/$DEMO_RUN_ID/operational_mart_verified.txt"
echo "SCRIPT 62: 1 — Transfer Run SUCCEEDED; ocho fuentes verificadas; $RUN_NAME"
