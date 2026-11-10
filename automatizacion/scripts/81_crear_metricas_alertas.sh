#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 81 — métrica basada en logs y alert policy'
STATE="$ROOT/state/$DEMO_RUN_ID"; CONTRACT="$ROOT/automatizacion/configuracion/contratos/observability_controls.json"
[[ -s "$STATE/observability_sink_iam_ok.txt" ]] || { echo 'SCRIPT 81: 0 — dependencia: SCRIPT 80'; exit 1; }
METRIC="$(contract_value "$CONTRACT" metric.id)"; ALERT="$(contract_value "$CONTRACT" metric.alert_display_name)"; LOG_ID="$(contract_value "$CONTRACT" audit_store.log_id)"
METRIC_FILTER="logName=\"projects/$PROJECT_ID/logs/$LOG_ID\" AND jsonPayload.component=\"luminalab-observability\" AND severity>=ERROR"
if gcloud logging metrics describe "$METRIC" --project="$PROJECT_ID" --format=json > "$STATE/observability_metric.json" 2> "$STATE/observability_metric_error.txt"; then echo "Reutilizando métrica $METRIC"; else rc=$?; if rg -qi 'NOT_FOUND|not found|does not exist' "$STATE/observability_metric_error.txt"; then gcloud logging metrics create "$METRIC" --project="$PROJECT_ID" --description='Errores de la API RetailSmart observados en logs' --log-filter="$METRIC_FILTER"; gcloud logging metrics describe "$METRIC" --project="$PROJECT_ID" --format=json > "$STATE/observability_metric.json"; else cat "$STATE/observability_metric_error.txt" >&2; exit "$rc"; fi; fi
python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); assert m.get("filter")==sys.argv[2]; print("Métrica verificada")' "$STATE/observability_metric.json" "$METRIC_FILTER"
POLICY_FILE="$STATE/observability_alert_policy.yaml"
printf '%s\n' "displayName: \"$ALERT\"" 'combiner: OR' 'enabled: true' 'conditions:' '- displayName: "API errors above threshold"' '  conditionThreshold:' "    filter: 'metric.type=\"logging.googleapis.com/user/$METRIC\" resource.type=\"global\"'" '    comparison: COMPARISON_GT' '    thresholdValue: 10' '    duration: 300s' '    aggregations:' '    - alignmentPeriod: 60s' '      perSeriesAligner: ALIGN_RATE' '      crossSeriesReducer: REDUCE_SUM' 'alertStrategy:' '  autoClose: 604800s' > "$POLICY_FILE"
gcloud monitoring policies list --project="$PROJECT_ID" --filter="displayName=\"$ALERT\"" --format=json > "$STATE/observability_alert_matches.json"
if python3 -c 'import json,sys; raise SystemExit(0 if json.load(open(sys.argv[1])) else 1)' "$STATE/observability_alert_matches.json"; then :; else gcloud monitoring policies create --project="$PROJECT_ID" --policy-from-file="$POLICY_FILE"; gcloud monitoring policies list --project="$PROJECT_ID" --filter="displayName=\"$ALERT\"" --format=json > "$STATE/observability_alert_matches.json"; fi
python3 - "$STATE/observability_alert_matches.json" "$ALERT" "$METRIC" <<'PY'
import json,sys
items=json.load(open(sys.argv[1],encoding='utf-8'))
if len(items)!=1: raise SystemExit(f'alert policy esperada única, encontradas={len(items)}')
p=items[0]
if p.get('displayName')!=sys.argv[2] or not p.get('enabled'): raise SystemExit('alert policy divergente o deshabilitada')
if 'logging.googleapis.com/user/'+sys.argv[3] not in json.dumps(p): raise SystemExit('alert policy no referencia la métrica esperada')
json.dump(p,open(sys.argv[1].replace('_matches','_policy'),'w',encoding='utf-8'),ensure_ascii=False,indent=2)
print('Alert policy habilitada verificada')
PY
echo 'SCRIPT 81: 1 — métrica basada en logs y alert policy verificadas'
