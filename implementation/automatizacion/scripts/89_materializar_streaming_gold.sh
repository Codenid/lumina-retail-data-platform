#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

heading 'Paso 89 — materializar Streaming Silver → Gold'
RUN_ID="${STREAMING_RUN_ID:-streaming-$(date -u +%Y%m%d%H%M%S)}"
WINDOW_MINUTES="${STREAMING_WINDOW_MINUTES:-60}"

# Este paso es idempotente: reemplaza únicamente la ventana y el run_id
# indicado. No borra históricos ni depende de credenciales embebidas.
bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --maximum_bytes_billed=104857600 \
  --parameter=run_id::"$RUN_ID" --parameter=window_minutes:INT64:"$WINDOW_MINUTES" <<SQL
MERGE \`$PROJECT_ID.$GOLD_DATASET.cu03_kpis_operativos\` T
USING (
  SELECT @run_id scenario_id, CURRENT_DATE() period_date, 'streaming' channel,
    COUNT(*) orders, COALESCE(SUM(quantity),0) units,
    CAST(NULL AS FLOAT64) conversion_rate, CAST(NULL AS NUMERIC) delivery_cost,
    CAST(NULL AS FLOAT64) sla_rate
  FROM \`$PROJECT_ID.$SILVER_DATASET.pedidos\`
  WHERE occurred_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL @window_minutes MINUTE)
) S
ON T.scenario_id=S.scenario_id AND T.period_date=S.period_date AND T.channel=S.channel
WHEN MATCHED THEN UPDATE SET orders=S.orders, units=S.units,
  conversion_rate=S.conversion_rate, delivery_cost=S.delivery_cost, sla_rate=S.sla_rate
WHEN NOT MATCHED THEN INSERT ROW;

MERGE \`$PROJECT_ID.$GOLD_DATASET.cu01_riesgo_quiebre_despacho\` T
USING (
  SELECT @run_id scenario_id, sku_id, store_id,
    CAST(GREATEST(0, 1 - SAFE_DIVIDE(on_hand_qty-reserved_qty, GREATEST(on_hand_qty,1))) AS FLOAT64) risk_score,
    on_hand_qty-reserved_qty available_qty,
    IF(on_hand_qty-reserved_qty < 12, 'REPOSICIONAR/DESPACHAR', 'MONITOREAR') recommended_action,
    CURRENT_TIMESTAMP() as_of
  FROM \`$PROJECT_ID.$SILVER_DATASET.inventario\`
  WHERE effective_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL @window_minutes MINUTE)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY sku_id, store_id ORDER BY effective_at DESC)=1
) S
ON T.scenario_id=S.scenario_id AND T.sku_id=S.sku_id AND T.store_id=S.store_id
WHEN MATCHED THEN UPDATE SET risk_score=S.risk_score, available_qty=S.available_qty,
  recommended_action=S.recommended_action, as_of=S.as_of
WHEN NOT MATCHED THEN INSERT ROW;

MERGE \`$PROJECT_ID.$GOLD_DATASET.cu02_plan_reposicion\` T
USING (
  SELECT @run_id scenario_id, sku_id, warehouse_id, CURRENT_DATE() plan_date,
    CAST(ROUND(SAFE_DIVIDE(on_hand_qty, 7) + reserved_qty) AS INT64) forecast_qty,
    CAST(GREATEST(0, ROUND(SAFE_DIVIDE(on_hand_qty, 7) + reserved_qty) - (on_hand_qty-reserved_qty)) AS INT64) recommended_qty,
    IF(on_hand_qty-reserved_qty < 12, 'HIGH', 'NORMAL') priority
  FROM \`$PROJECT_ID.$SILVER_DATASET.inventario\`
  WHERE effective_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL @window_minutes MINUTE)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY sku_id, warehouse_id ORDER BY effective_at DESC)=1
) S
ON T.scenario_id=S.scenario_id AND T.sku_id=S.sku_id AND T.warehouse_id=S.warehouse_id AND T.plan_date=S.plan_date
WHEN MATCHED THEN UPDATE SET forecast_qty=S.forecast_qty, recommended_qty=S.recommended_qty, priority=S.priority
WHEN NOT MATCHED THEN INSERT ROW;

MERGE \`$PROJECT_ID.$GOLD_DATASET.cu04_alertas_mantenimiento\` T
USING (
  SELECT @run_id scenario_id, asset_id, sensor_id, warehouse_id,
    IF(metric_value >= 9, 'TEMPERATURA_ANOMALA', 'LECTURA_SENSOR') anomaly_type,
    IF(metric_value >= 9, 'HIGH', 'NORMAL') severity, metric_value, occurred_at
  FROM \`$PROJECT_ID.$SILVER_DATASET.telemetria_activos\`
  WHERE occurred_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL @window_minutes MINUTE)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY asset_id, sensor_id ORDER BY occurred_at DESC)=1
) S
ON T.scenario_id=S.scenario_id AND T.asset_id=S.asset_id AND T.sensor_id=S.sensor_id AND T.occurred_at=S.occurred_at
WHEN MATCHED THEN UPDATE SET severity=S.severity, metric_value=S.metric_value, anomaly_type=S.anomaly_type
WHEN NOT MATCHED THEN INSERT ROW;
SQL

printf 'run_id=%s\nwindow_minutes=%s\n' "$RUN_ID" "$WINDOW_MINUTES" > "$ROOT/state/$DEMO_RUN_ID/streaming_gold_materialized.txt"
echo "SCRIPT 89: 1 — Silver → Gold materializado para $RUN_ID (ventana ${WINDOW_MINUTES}m)"
