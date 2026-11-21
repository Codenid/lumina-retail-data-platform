#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
heading 'Paso 95 — materializar escenario operativo vigente'
Q() { bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --maximum_bytes_billed=524288000 "$1" >/dev/null; }
SCENARIO_ID="operacion-vigente"

Q "DELETE FROM \`$PROJECT_ID.$GOLD_DATASET.cu01_riesgo_quiebre_despacho\` WHERE TRUE"
Q "DELETE FROM \`$PROJECT_ID.$GOLD_DATASET.cu02_plan_reposicion\` WHERE TRUE"
Q "DELETE FROM \`$PROJECT_ID.$GOLD_DATASET.cu03_kpis_operativos\` WHERE TRUE"
Q "DELETE FROM \`$PROJECT_ID.$GOLD_DATASET.cu04_alertas_mantenimiento\` WHERE TRUE"

Q "INSERT INTO \`$PROJECT_ID.$GOLD_DATASET.cu01_riesgo_quiebre_despacho\`
WITH base AS (
  SELECT day_offset,n,FORMAT('SKU-%05d',1+MOD(n*29,3200)) sku_id,
    FORMAT('STORE-%03d',1+MOD(n*7+day_offset,32)) store_id,
    ROUND(0.40+MOD(n*11+day_offset*7,60)/100,2) risk_score
  FROM UNNEST(GENERATE_ARRAY(0,6)) day_offset CROSS JOIN UNNEST(GENERATE_ARRAY(1,101)) n
  WHERE n<=CASE day_offset WHEN 0 THEN 96 WHEN 1 THEN 101 WHEN 2 THEN 93
    WHEN 3 THEN 87 WHEN 4 THEN 91 WHEN 5 THEN 88 ELSE 82 END)
SELECT '$SCENARIO_ID',sku_id,store_id,risk_score,
  CAST(GREATEST(2,72-ROUND(risk_score*68)+MOD(n,9)) AS INT64),
  CASE WHEN risk_score>=0.80 THEN 'REPOSICIONAR/DESPACHAR'
       WHEN risk_score>=0.65 THEN 'PRIORIZAR' ELSE 'MONITOREAR' END,
  TIMESTAMP(DATE_SUB(CURRENT_DATE(),INTERVAL day_offset DAY))+INTERVAL MOD(n,18)+5 HOUR
FROM base"

Q "INSERT INTO \`$PROJECT_ID.$GOLD_DATASET.cu02_plan_reposicion\`
WITH latest AS (
  SELECT sku_id,risk_score,available_qty,
    ROW_NUMBER() OVER(PARTITION BY sku_id ORDER BY risk_score DESC,as_of DESC) rn
  FROM \`$PROJECT_ID.$GOLD_DATASET.cu01_riesgo_quiebre_despacho\`
  WHERE scenario_id='$SCENARIO_ID' AND DATE(as_of)=CURRENT_DATE())
SELECT '$SCENARIO_ID',sku_id,FORMAT('WH-%03d',1+MOD(ABS(FARM_FINGERPRINT(sku_id)),8)),
  DATE_ADD(CURRENT_DATE(),INTERVAL 1+MOD(ABS(FARM_FINGERPRINT(sku_id)),7) DAY),
  CAST(28+ROUND(risk_score*72) AS INT64),
  CAST(GREATEST(0,28+ROUND(risk_score*72)-available_qty) AS INT64),
  CASE WHEN risk_score>=0.80 THEN 'HIGH' WHEN risk_score>=0.65 THEN 'MEDIUM' ELSE 'NORMAL' END
FROM latest WHERE rn=1"

Q "INSERT INTO \`$PROJECT_ID.$GOLD_DATASET.cu03_kpis_operativos\`
SELECT '$SCENARIO_ID',DATE_SUB(CURRENT_DATE(),INTERVAL day_offset DAY),'batch',
  CAST(760+MOD((14-day_offset)*47,240) AS INT64),
  CAST((760+MOD((14-day_offset)*47,240))*(2.4+MOD(day_offset,4)/10) AS INT64),
  ROUND(0.145+MOD(day_offset,5)/100,3),
  CAST(ROUND((760+MOD((14-day_offset)*47,240))*(12.5+MOD(day_offset,3)),2) AS NUMERIC),
  ROUND(0.915+MOD(14-day_offset,6)/100,3)
FROM UNNEST(GENERATE_ARRAY(0,13)) day_offset"

Q "INSERT INTO \`$PROJECT_ID.$GOLD_DATASET.cu04_alertas_mantenimiento\`
SELECT '$SCENARIO_ID',FORMAT('ASSET-%04d',asset),FORMAT('SENSOR-%04d',asset),
  FORMAT('WH-%03d',1+MOD(asset-1,8)),
  CASE WHEN MOD(asset+day_offset,17)=0 THEN 'TEMPERATURA_ANOMALA'
       WHEN MOD(asset+day_offset,9)=0 THEN 'VIBRACION_ELEVADA' ELSE 'LECTURA_SENSOR' END,
  CASE WHEN MOD(asset+day_offset,17)=0 THEN 'HIGH'
       WHEN MOD(asset+day_offset,9)=0 THEN 'MEDIUM' ELSE 'NORMAL' END,
  CASE WHEN MOD(asset+day_offset,17)=0 THEN ROUND(8.2+MOD(asset,8)/10,2)
       WHEN MOD(asset+day_offset,9)=0 THEN ROUND(5.6+MOD(asset,10)/10,2)
       ELSE ROUND(3.4+MOD(asset,12)/20,2) END,
  TIMESTAMP(DATE_SUB(CURRENT_DATE(),INTERVAL day_offset DAY))+INTERVAL MOD(asset,18)+4 HOUR
FROM UNNEST(GENERATE_ARRAY(0,6)) day_offset CROSS JOIN UNNEST(GENERATE_ARRAY(1,60)) asset"

Q "CREATE OR REPLACE TABLE \`$PROJECT_ID.$GOLD_DATASET.agg_inventario_resumen\` AS
SELECT COUNT(*) risk_rows,COUNT(DISTINCT sku_id) at_risk_skus,COUNT(DISTINCT store_id) affected_stores,
  COUNT(DISTINCT IF(risk_score>=0.80,sku_id,NULL)) critical_skus,CURRENT_TIMESTAMP() refreshed_at
FROM \`$PROJECT_ID.$GOLD_DATASET.cu01_riesgo_quiebre_despacho\`
WHERE scenario_id='$SCENARIO_ID' AND DATE(as_of)=CURRENT_DATE()"

echo 'SCRIPT 95: 1 — escenario operativo vigente materializado'
