#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
heading 'Paso 94 — precargar volumen operativo para pedidos y entregas'
Q() { bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --maximum_bytes_billed=104857600 "$1" >/dev/null; }

# Mantiene una serie reproducible de periodos para comparar operación anterior vs. actual.
Q "DELETE FROM \`$PROJECT_ID.$GOLD_DATASET.cu03_kpis_operativos\` WHERE STARTS_WITH(scenario_id,'ops-ui-')"
Q "INSERT INTO \`$PROJECT_ID.$GOLD_DATASET.cu03_kpis_operativos\` (scenario_id,period_date,channel,orders,units,conversion_rate,delivery_cost,sla_rate) SELECT CONCAT('ops-ui-',CAST(n AS STRING)),DATE_SUB(CURRENT_DATE(),INTERVAL (14-n) DAY),'batch',CAST(98000+n*7300+MOD(n*917,4800) AS INT64),CAST(250000+n*18500+MOD(n*1301,9000) AS INT64),0.12+MOD(n,7)/100,42000+n*1250,0.91+MOD(n,8)/100 FROM UNNEST(GENERATE_ARRAY(1,14)) n"
Q "INSERT INTO \`$PROJECT_ID.$GOLD_DATASET.cu03_kpis_operativos\` (scenario_id,period_date,channel,orders,units,conversion_rate,delivery_cost,sla_rate) VALUES ('ops-ui-current',CURRENT_DATE(),'streaming',284221,749221,0.18,125000,0.96)"
echo 'SCRIPT 94: 1'
echo 'Serie operativa de pedidos y entregas precargada.'
