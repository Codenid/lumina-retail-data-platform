import os
from google.cloud import bigquery

project = os.environ['PROJECT_ID']
gold = os.environ['GOLD_DATASET']
silver = os.environ['SILVER_DATASET']
run_id = os.environ.get('STREAMING_RUN_ID', 'streaming-auto')
window = int(os.environ.get('STREAMING_WINDOW_MINUTES', '1440'))
client = bigquery.Client(project=project)

queries = [
f"""MERGE `{project}.{gold}.cu03_kpis_operativos` T USING (SELECT @run_id scenario_id,CURRENT_DATE() period_date,'streaming' channel,COUNT(*) orders,COALESCE(SUM(quantity),0) units,CAST(NULL AS FLOAT64) conversion_rate,CAST(NULL AS NUMERIC) delivery_cost,CAST(NULL AS FLOAT64) sla_rate FROM `{project}.{silver}.pedidos` WHERE occurred_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(),INTERVAL @window MINUTE)) S ON T.scenario_id=S.scenario_id AND T.period_date=S.period_date AND T.channel=S.channel WHEN MATCHED THEN UPDATE SET orders=S.orders,units=S.units WHEN NOT MATCHED THEN INSERT ROW""",
f"""MERGE `{project}.{gold}.cu01_riesgo_quiebre_despacho` T USING (SELECT @run_id scenario_id,sku_id,store_id,CAST(GREATEST(0,1-SAFE_DIVIDE(on_hand_qty-reserved_qty,GREATEST(on_hand_qty,1))) AS FLOAT64) risk_score,on_hand_qty-reserved_qty available_qty,IF(on_hand_qty-reserved_qty<12,'REPOSICIONAR/DESPACHAR','MONITOREAR') recommended_action,CURRENT_TIMESTAMP() as_of FROM `{project}.{silver}.inventario` WHERE effective_at>=TIMESTAMP_SUB(CURRENT_TIMESTAMP(),INTERVAL @window MINUTE) QUALIFY ROW_NUMBER() OVER(PARTITION BY sku_id,store_id ORDER BY effective_at DESC)=1) S ON T.scenario_id=S.scenario_id AND T.sku_id=S.sku_id AND T.store_id=S.store_id WHEN MATCHED THEN UPDATE SET risk_score=S.risk_score,available_qty=S.available_qty,recommended_action=S.recommended_action,as_of=S.as_of WHEN NOT MATCHED THEN INSERT ROW""",
f"""MERGE `{project}.{gold}.cu02_plan_reposicion` T USING (SELECT @run_id scenario_id,sku_id,warehouse_id,CURRENT_DATE() plan_date,CAST(ROUND(SAFE_DIVIDE(on_hand_qty,7)+reserved_qty) AS INT64) forecast_qty,CAST(GREATEST(0,ROUND(SAFE_DIVIDE(on_hand_qty,7)+reserved_qty)-(on_hand_qty-reserved_qty)) AS INT64) recommended_qty,IF(on_hand_qty-reserved_qty<12,'HIGH','NORMAL') priority FROM `{project}.{silver}.inventario` WHERE effective_at>=TIMESTAMP_SUB(CURRENT_TIMESTAMP(),INTERVAL @window MINUTE) QUALIFY ROW_NUMBER() OVER(PARTITION BY sku_id,warehouse_id ORDER BY effective_at DESC)=1) S ON T.scenario_id=S.scenario_id AND T.sku_id=S.sku_id AND T.warehouse_id=S.warehouse_id AND T.plan_date=S.plan_date WHEN MATCHED THEN UPDATE SET forecast_qty=S.forecast_qty,recommended_qty=S.recommended_qty,priority=S.priority WHEN NOT MATCHED THEN INSERT ROW""",
f"""MERGE `{project}.{gold}.cu04_alertas_mantenimiento` T USING (SELECT @run_id scenario_id,asset_id,sensor_id,warehouse_id,IF(metric_value>=9,'TEMPERATURA_ANOMALA','LECTURA_SENSOR') anomaly_type,IF(metric_value>=9,'HIGH','NORMAL') severity,metric_value,occurred_at FROM `{project}.{silver}.telemetria_activos` WHERE occurred_at>=TIMESTAMP_SUB(CURRENT_TIMESTAMP(),INTERVAL @window MINUTE) QUALIFY ROW_NUMBER() OVER(PARTITION BY asset_id,sensor_id ORDER BY occurred_at DESC)=1) S ON T.scenario_id=S.scenario_id AND T.asset_id=S.asset_id AND T.sensor_id=S.sensor_id AND T.occurred_at=S.occurred_at WHEN MATCHED THEN UPDATE SET anomaly_type=S.anomaly_type,severity=S.severity,metric_value=S.metric_value WHEN NOT MATCHED THEN INSERT ROW""",
]
for sql in queries:
    client.query(sql, job_config=bigquery.QueryJobConfig(query_parameters=[bigquery.ScalarQueryParameter('run_id','STRING',run_id),bigquery.ScalarQueryParameter('window','INT64',window)]), location=os.environ.get('BQ_LOCATION','us-central1')).result()
print(f'Materialización automática completada: {run_id}, ventana={window}m')
