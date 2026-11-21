#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
heading 'Paso 96 — actualizar exclusivamente forecast y reposición'
SCENARIO_ID="operacion-vigente"

bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --maximum_bytes_billed=268435456 "
BEGIN TRANSACTION;
DELETE FROM \`$PROJECT_ID.$GOLD_DATASET.cu02_plan_reposicion\`
WHERE scenario_id='$SCENARIO_ID';

INSERT INTO \`$PROJECT_ID.$GOLD_DATASET.cu02_plan_reposicion\`
WITH current_risk AS (
  SELECT sku_id,risk_score,available_qty,
    ROW_NUMBER() OVER(PARTITION BY sku_id ORDER BY risk_score DESC,as_of DESC) AS rn
  FROM \`$PROJECT_ID.$GOLD_DATASET.cu01_riesgo_quiebre_despacho\`
  WHERE scenario_id='$SCENARIO_ID' AND DATE(as_of)=CURRENT_DATE()
)
SELECT '$SCENARIO_ID',sku_id,
  FORMAT('WH-%03d',1+MOD(ABS(FARM_FINGERPRINT(sku_id)),8)),
  DATE_ADD(CURRENT_DATE(),INTERVAL 1+MOD(ABS(FARM_FINGERPRINT(sku_id)),7) DAY),
  CAST(28+ROUND(risk_score*72) AS INT64),
  CAST(GREATEST(0,28+ROUND(risk_score*72)-available_qty) AS INT64),
  CASE WHEN risk_score>=0.80 THEN 'HIGH'
       WHEN risk_score>=0.65 THEN 'MEDIUM' ELSE 'NORMAL' END
FROM current_risk WHERE rn=1;
COMMIT TRANSACTION;"

bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --format=prettyjson "
SELECT COUNT(*) AS planes,
  COUNTIF(priority='HIGH') AS inmediatos,
  COUNTIF(priority='MEDIUM') AS proximos,
  COUNTIF(priority='NORMAL') AS programados,
  SUM(recommended_qty) AS unidades_recomendadas
FROM \`$PROJECT_ID.$GOLD_DATASET.cu02_plan_reposicion\`
WHERE scenario_id='$SCENARIO_ID'"

echo 'SCRIPT 96: 1 — forecast y reposición actualizados sin modificar otros casos de uso'
