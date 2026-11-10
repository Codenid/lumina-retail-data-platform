#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 83 — verificación final de auditoría y observabilidad'
STATE="$ROOT/state/$DEMO_RUN_ID"; CONTRACT="$ROOT/automatizacion/configuracion/contratos/observability_controls.json"
for marker in observability_preflight_ok.txt observability_sink_iam_ok.txt observability_metric.json observability_alert_policy.json observability_slo_ok.txt; do [[ -s "$STATE/$marker" ]] || { echo "SCRIPT 83: 0 — dependencia ausente: $marker"; exit 1; }; done
DATASET="$(sed -n 's/^audit_dataset=//p' "$STATE/observability_preflight_ok.txt")"; SINK="$(contract_value "$CONTRACT" audit_store.sink)"; METRIC="$(contract_value "$CONTRACT" metric.id)"; ALERT="$(contract_value "$CONTRACT" metric.alert_display_name)"; EVENT_ID="$(sed -n 's/^event_id=//p' "$STATE/observability_test_event.txt")"
gcloud logging sinks describe "$SINK" --project="$PROJECT_ID" --format=json > "$STATE/observability_sink_final.json"; gcloud logging metrics describe "$METRIC" --project="$PROJECT_ID" --format=json > "$STATE/observability_metric_final.json"; gcloud monitoring policies list --project="$PROJECT_ID" --filter="displayName=\"$ALERT\"" --format=json > "$STATE/observability_alert_final.json"
FOUND=0
for attempt in $(seq 1 8); do bq --project_id="$PROJECT_ID" ls --format=json "$PROJECT_ID:$DATASET" > "$STATE/observability_audit_tables.json"; mapfile -t TABLES < <(python3 -c 'import json,sys; raw=open(sys.argv[1]).read().strip(); rows=json.loads(raw) if raw else []; print("\n".join(x.get("tableReference",{}).get("tableId","") for x in rows))' "$STATE/observability_audit_tables.json"); for table in "${TABLES[@]}"; do [[ -n "$table" ]] || continue; COUNT="$(bq --project_id="$PROJECT_ID" query --use_legacy_sql=false --format=csv --max_rows=2 "SELECT COUNTIF(JSON_VALUE(TO_JSON_STRING(t), '$.jsonPayload.event_id') = '$EVENT_ID') FROM \`$PROJECT_ID.$DATASET.$table\` t" 2>/dev/null | tail -n 1 || true)"; if [[ "$COUNT" =~ ^[1-9][0-9]*$ ]]; then FOUND="$COUNT"; echo "Audit event encontrado en $table: $COUNT"; break 2; fi; done; if [[ "$attempt" != 8 ]]; then echo "Audit Store pendiente; intento $attempt/8"; sleep 15; fi; done
if [[ "$FOUND" == 0 ]]; then echo 'SCRIPT 83: 0 — sink, métrica y SLO existen, pero el evento sintético aún no aparece en BigQuery' >&2; exit 1; fi
python3 - "$STATE/observability_sink_final.json" "$STATE/observability_metric_final.json" "$STATE/observability_alert_final.json" "$STATE/observability_slo.json" <<'PY'
import json,sys
sink=json.load(open(sys.argv[1])); metric=json.load(open(sys.argv[2])); alerts=json.load(open(sys.argv[3])); slo=json.load(open(sys.argv[4]))
if sink.get('disabled') or not metric.get('name') or not alerts or not alerts[0].get('enabled') or slo.get('goal')!=0.99: raise SystemExit('verificación final divergente')
print('Audit Store, métrica, alerta y SLO verificados')
PY
REPORT="$ROOT/state/$DEMO_RUN_ID/EVIDENCIA_AUDITORIA_OBSERVABILIDAD.md"
{
  printf '%s\n' '# Resultado del grupo 79–83 — Auditoría y observabilidad' ''
  printf 'Proyecto: `%s`\nRegión: `%s`\nResultado: **COMPLETADO**\n\n' "$PROJECT_ID" "$REGION"
  printf '%s\n' '| Script | Estado | Resultado |' '|---|---:|---|' '| 79 | 1 | APIs, Cloud Run y dataset Audit Store verificados |' '| 80 | 1 | Sink de Cloud Logging, IAM del writer y evento sintético enviados |' '| 81 | 1 | Métrica basada en logs y alert policy habilitadas |' '| 82 | 1 | Servicio Cloud Monitoring y SLO de disponibilidad del 99% verificados |' '| 83 | 1 | Evento encontrado en Audit Store y recursos consultados nuevamente |' '' '## Recursos' ''
  printf -- '- Audit Store: `%s.%s`.\n- Sink: `%s`; evento de prueba: `%s`.\n- Métrica: `logging.googleapis.com/user/%s`.\n' "$PROJECT_ID" "$DATASET" "$SINK" "$EVENT_ID" "$METRIC"
  printf '%s\n\n' '- Alert policy habilitada y SLO de disponibilidad 99% sobre ventana móvil de 24 horas.' 'No se creó cómputo persistente ni se modificaron datos de negocio.'
} > "$REPORT"
echo '79=1' > "$STATE/observability_group_ok.txt"; echo '80=1' >> "$STATE/observability_group_ok.txt"; echo '81=1' >> "$STATE/observability_group_ok.txt"; echo '82=1' >> "$STATE/observability_group_ok.txt"; echo '83=1' >> "$STATE/observability_group_ok.txt"; echo 'resultado=COMPLETADO' >> "$STATE/observability_group_ok.txt"
echo "SCRIPT 83: 1 — grupo de auditoría y observabilidad verificado; evidencia en state/$DEMO_RUN_ID/EVIDENCIA_AUDITORIA_OBSERVABILIDAD.md"
