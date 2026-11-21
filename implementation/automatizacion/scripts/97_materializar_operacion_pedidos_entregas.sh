#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
heading 'Paso 97 — materializar operación vigente de pedidos y entregas'
Q() { bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --maximum_bytes_billed=524288000 "$1" >/dev/null; }
SCENARIO_ID="operacion-vigente"

Q "CREATE TABLE IF NOT EXISTS \`$PROJECT_ID.$GOLD_DATASET.cu03_operacion_detalle\` (
  scenario_id STRING, operation_id STRING, order_id STRING, store_id STRING,
  warehouse_id STRING, promised_at TIMESTAMP, units INT64, status STRING,
  delay_hours INT64, fulfillment_rate FLOAT64, recommended_action STRING,
  observed_at TIMESTAMP)"

Q "BEGIN TRANSACTION;
DELETE FROM \`$PROJECT_ID.$GOLD_DATASET.cu03_kpis_operativos\` WHERE scenario_id='$SCENARIO_ID';
INSERT INTO \`$PROJECT_ID.$GOLD_DATASET.cu03_kpis_operativos\`
SELECT '$SCENARIO_ID',DATE_SUB(CURRENT_DATE(),INTERVAL day_offset DAY),'batch',
  CAST(760+MOD((14-day_offset)*47,240) AS INT64),
  CAST((760+MOD((14-day_offset)*47,240))*(2.4+MOD(day_offset,4)/10) AS INT64),
  ROUND(0.145+MOD(day_offset,5)/100,3),
  CAST(ROUND((760+MOD((14-day_offset)*47,240))*(12.5+MOD(day_offset,3)),2) AS NUMERIC),
  ROUND(0.925+MOD(14-day_offset,5)/100,3)
FROM UNNEST(GENERATE_ARRAY(0,13)) day_offset;

DELETE FROM \`$PROJECT_ID.$GOLD_DATASET.cu03_operacion_detalle\` WHERE scenario_id='$SCENARIO_ID';
INSERT INTO \`$PROJECT_ID.$GOLD_DATASET.cu03_operacion_detalle\`
WITH base AS (
  SELECT n,
    FORMAT('STORE-%03d',1+MOD(n*7,32)) store_id,
    FORMAT('WH-%03d',1+MOD(n*5,8)) warehouse_id,
    CASE WHEN n IN (7,19,31,43) THEN 'AT_RISK'
         WHEN MOD(n,4)=0 THEN 'IN_TRANSIT' ELSE 'DELIVERED' END status
  FROM UNNEST(GENERATE_ARRAY(1,48)) n)
SELECT '$SCENARIO_ID',FORMAT('OP-%s-%03d',FORMAT_DATE('%Y%m%d',CURRENT_DATE()),n),
  FORMAT('ORD-%s-%04d',FORMAT_DATE('%Y%m%d',CURRENT_DATE()),1000+n),store_id,warehouse_id,
  TIMESTAMP(CURRENT_DATE())+INTERVAL 16+MOD(n,5) HOUR,
  CAST(12+MOD(n*13,74) AS INT64),status,
  CASE status WHEN 'AT_RISK' THEN 3+MOD(n,5) ELSE 0 END,
  CASE status WHEN 'AT_RISK' THEN ROUND(0.72+MOD(n,8)/100,2)
              WHEN 'IN_TRANSIT' THEN ROUND(0.94+MOD(n,4)/100,2) ELSE 1.0 END,
  CASE status WHEN 'AT_RISK' THEN IF(MOD(n,2)=0,'REPROGRAMAR RUTA','PRIORIZAR DESPACHO')
              WHEN 'IN_TRANSIT' THEN 'MONITOREAR ENTREGA' ELSE 'SIN ACCIÓN' END,
  CURRENT_TIMESTAMP()
FROM base;
COMMIT TRANSACTION;"

echo 'SCRIPT 97: 1 — operación de pedidos y entregas materializada'
