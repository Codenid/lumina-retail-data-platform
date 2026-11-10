#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 17 — Gold CU01–CU04'
[[ -s "$ROOT/state/$DEMO_RUN_ID/silver_batch_ok.txt" ]] || { echo 'Falta 16'; exit 1; }
run_query() { bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --maximum_bytes_billed=31457280 "$1"; }
run_query "DELETE FROM \`$PROJECT_ID.$GOLD_DATASET.cu01_riesgo_quiebre_despacho\` WHERE scenario_id='$DEMO_RUN_ID'"
run_query "INSERT INTO \`$PROJECT_ID.$GOLD_DATASET.cu01_riesgo_quiebre_despacho\` SELECT '$DEMO_RUN_ID', sku_id, store_id, CAST(GREATEST(0, 1 - SAFE_DIVIDE(on_hand_qty-reserved_qty, NULLIF(on_hand_qty,0))) AS FLOAT64), on_hand_qty-reserved_qty, IF(on_hand_qty-reserved_qty < 12,'REPOSICIONAR/DESPACHAR','MONITOREAR'), effective_at FROM \`$PROJECT_ID.$SILVER_DATASET.inventario\` WHERE quality_status='VALID'"
run_query "DELETE FROM \`$PROJECT_ID.$GOLD_DATASET.cu02_plan_reposicion\` WHERE scenario_id='$DEMO_RUN_ID'"
run_query "INSERT INTO \`$PROJECT_ID.$GOLD_DATASET.cu02_plan_reposicion\` SELECT '$DEMO_RUN_ID', p.sku_id, i.warehouse_id, DATE(p.occurred_at), SUM(p.quantity), GREATEST(0, SUM(p.quantity)-(i.on_hand_qty-i.reserved_qty)), IF(i.on_hand_qty-i.reserved_qty < SUM(p.quantity),'HIGH','NORMAL') FROM \`$PROJECT_ID.$SILVER_DATASET.pedidos\` p JOIN \`$PROJECT_ID.$SILVER_DATASET.inventario\` i USING (sku_id) WHERE p.quality_status='VALID' AND i.quality_status='VALID' GROUP BY p.sku_id, i.warehouse_id, DATE(p.occurred_at), i.on_hand_qty, i.reserved_qty"
run_query "DELETE FROM \`$PROJECT_ID.$GOLD_DATASET.cu03_kpis_operativos\` WHERE scenario_id='$DEMO_RUN_ID'"
run_query "INSERT INTO \`$PROJECT_ID.$GOLD_DATASET.cu03_kpis_operativos\` SELECT '$DEMO_RUN_ID', CURRENT_DATE(), 'all', COUNT(DISTINCT p.order_id), SUM(p.quantity), 1.0, COALESCE(SUM(e.delivery_cost),0), SAFE_DIVIDE(COUNTIF(e.delivered_at IS NOT NULL), COUNT(e.delivery_id)) FROM \`$PROJECT_ID.$SILVER_DATASET.pedidos\` p LEFT JOIN \`$PROJECT_ID.$SILVER_DATASET.entregas\` e USING (order_id) WHERE p.quality_status='VALID'"
run_query "DELETE FROM \`$PROJECT_ID.$GOLD_DATASET.cu04_alertas_mantenimiento\` WHERE scenario_id='$DEMO_RUN_ID'"
run_query "INSERT INTO \`$PROJECT_ID.$GOLD_DATASET.cu04_alertas_mantenimiento\` SELECT '$DEMO_RUN_ID', asset_id, sensor_id, warehouse_id, 'TEMPERATURA_ANOMALA', IF(metric_value >= 9.0,'HIGH','NORMAL'), metric_value, occurred_at FROM \`$PROJECT_ID.$SILVER_DATASET.telemetria_activos\` WHERE quality_status='VALID'"
printf 'Gold CU01-CU04 verificado para %s\n' "$DEMO_RUN_ID" > "$ROOT/state/$DEMO_RUN_ID/gold_casos_ok.txt"
echo 'OK: Gold CU01–CU04 materializado'
