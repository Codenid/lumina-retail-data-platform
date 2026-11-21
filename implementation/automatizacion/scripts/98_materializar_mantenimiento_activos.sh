#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
heading 'Paso 98 — materializar mantenimiento vigente de activos'
Q() { bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --maximum_bytes_billed=524288000 "$1" >/dev/null; }
SCENARIO_ID="operacion-vigente"

Q "BEGIN TRANSACTION;
DELETE FROM \`$PROJECT_ID.$GOLD_DATASET.cu04_alertas_mantenimiento\` WHERE scenario_id='$SCENARIO_ID';
INSERT INTO \`$PROJECT_ID.$GOLD_DATASET.cu04_alertas_mantenimiento\`
WITH periods AS (
  SELECT day_offset,
    CASE day_offset WHEN 0 THEN 3 WHEN 1 THEN 4 WHEN 2 THEN 3 WHEN 3 THEN 4 WHEN 4 THEN 4 WHEN 5 THEN 5 ELSE 5 END high_count,
    CASE day_offset WHEN 0 THEN 6 WHEN 1 THEN 7 WHEN 2 THEN 7 WHEN 3 THEN 8 WHEN 4 THEN 8 WHEN 5 THEN 9 ELSE 9 END medium_count
  FROM UNNEST(GENERATE_ARRAY(0,6)) day_offset),
base AS (
  SELECT p.*,n,1+MOD(n+day_offset*3-1,60) rotated
  FROM periods p CROSS JOIN UNNEST(GENERATE_ARRAY(1,60)) n)
SELECT '$SCENARIO_ID',FORMAT('ASSET-%04d',rotated),FORMAT('SENSOR-%04d',rotated),
  FORMAT('WH-%03d',1+MOD(rotated-1,8)),
  CASE WHEN n<=high_count THEN 'TEMPERATURA_ANOMALA'
       WHEN n<=high_count+medium_count THEN 'VIBRACION_ELEVADA' ELSE 'LECTURA_SENSOR' END,
  CASE WHEN n<=high_count THEN 'HIGH'
       WHEN n<=high_count+medium_count THEN 'MEDIUM' ELSE 'NORMAL' END,
  CASE WHEN n<=high_count THEN ROUND(8.1+MOD(rotated,8)/10,2)
       WHEN n<=high_count+medium_count THEN ROUND(5.6+MOD(rotated,10)/10,2)
       ELSE ROUND(3.4+MOD(rotated,12)/20,2) END,
  TIMESTAMP(DATE_SUB(CURRENT_DATE(),INTERVAL day_offset DAY))+INTERVAL MOD(rotated,18)+4 HOUR
FROM base;
COMMIT TRANSACTION;"

echo 'SCRIPT 98: 1 — mantenimiento de activos materializado'
