MERGE `{{PROJECT_ID}}.{{GOLD_DATASET}}.operational_mart` AS T
USING (
  SELECT * FROM (
    SELECT 'operational' scenario_id, 'ORDER' entity_type, order_id entity_id,
      sku_id, store_id, warehouse_id, quantity, quality_status status, occurred_at observed_at,
      'batch' ingestion_mode, 'pedidos' source_domain, CAST(NULL AS STRING) correlation_id,
      CAST(quantity AS FLOAT64) measure_value,
      TO_JSON(STRUCT(order_line_id, customer_id)) attributes
    FROM `{{PROJECT_ID}}.{{SILVER_DATASET}}.pedidos` WHERE quality_status='VALID'
    UNION ALL
    SELECT 'operational','INVENTORY',snapshot_id,sku_id,store_id,warehouse_id,
      on_hand_qty-reserved_qty,quality_status,effective_at,'batch','inventario',CAST(NULL AS STRING),
      CAST(on_hand_qty-reserved_qty AS FLOAT64),
      TO_JSON(STRUCT(on_hand_qty,reserved_qty))
    FROM `{{PROJECT_ID}}.{{SILVER_DATASET}}.inventario` WHERE quality_status='VALID'
    UNION ALL
    SELECT 'operational','DELIVERY',e.delivery_id,p.sku_id,e.store_id,p.warehouse_id,p.quantity,
      IF(e.delivered_at IS NULL,'PENDING','DELIVERED'),COALESCE(e.delivered_at,e.promised_at),
      'batch','entregas',e.order_id,CAST(e.delivery_cost AS FLOAT64),
      TO_JSON(STRUCT(e.region_id,e.promised_at,e.delivered_at,e.delivery_cost))
    FROM `{{PROJECT_ID}}.{{SILVER_DATASET}}.entregas` e
    LEFT JOIN `{{PROJECT_ID}}.{{SILVER_DATASET}}.pedidos` p ON p.order_id=e.order_id AND p.quality_status='VALID'
    WHERE e.quality_status='VALID'
    UNION ALL
    SELECT 'operational','COMPETITOR_PRICE',benchmark_id,sku_id,store_id,CAST(NULL AS STRING),
      CAST(NULL AS INT64),availability,observed_at,'batch','benchmark_competidores',CAST(NULL AS STRING),
      CAST(competitor_price AS FLOAT64),TO_JSON(STRUCT(competitor_id,competitor_price,availability))
    FROM `{{PROJECT_ID}}.{{SILVER_DATASET}}.benchmark_competidores` WHERE quality_status='VALID'
    UNION ALL
    SELECT 'operational','LOCAL_EVENT',local_event_id,CAST(NULL AS STRING),store_id,CAST(NULL AS STRING),
      CAST(NULL AS INT64),event_type,start_at,'batch','eventos_locales',CAST(NULL AS STRING),impact_score,
      TO_JSON(STRUCT(event_type,start_at,end_at,impact_score))
    FROM `{{PROJECT_ID}}.{{SILVER_DATASET}}.eventos_locales` WHERE quality_status='VALID'
    UNION ALL
    SELECT 'operational','SOCIAL_POST',post_id,sku_id,CAST(NULL AS STRING),CAST(NULL AS STRING),
      engagement_count,quality_status,published_at,'batch','redes_sociales',CAST(NULL AS STRING),sentiment_score,
      TO_JSON(STRUCT(platform,sentiment_score,engagement_count,text_hash))
    FROM `{{PROJECT_ID}}.{{SILVER_DATASET}}.redes_sociales` WHERE quality_status='VALID'
    UNION ALL
    SELECT 'operational','INSIGHT',insight_id,sku_id,store_id,CAST(NULL AS STRING),CAST(NULL AS INT64),
      status,created_at,'streaming','insights_streaming',event_id,score,
      TO_JSON(STRUCT(event_id,insight_type,score,status))
    FROM `{{PROJECT_ID}}.{{GOLD_DATASET}}.insights_streaming`
    UNION ALL
    SELECT 'operational','AUDIT',audit_id,CAST(NULL AS STRING),CAST(NULL AS STRING),CAST(NULL AS STRING),
      CAST(NULL AS INT64),status,observed_at,'streaming','procesamiento_auditoria',event_id,CAST(NULL AS FLOAT64),
      TO_JSON(STRUCT(event_id,component,status,detail))
    FROM `{{PROJECT_ID}}.{{GOLD_DATASET}}.procesamiento_auditoria`
  )
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY entity_type,entity_id,ingestion_mode,source_domain
    ORDER BY observed_at DESC,entity_id DESC
  )=1
) AS S
ON T.entity_type=S.entity_type AND T.entity_id=S.entity_id
  AND (T.ingestion_mode=S.ingestion_mode OR T.source_domain IS NULL)
  AND (T.source_domain=S.source_domain OR T.source_domain IS NULL)
WHEN MATCHED THEN UPDATE SET
  scenario_id=S.scenario_id,sku_id=S.sku_id,store_id=S.store_id,warehouse_id=S.warehouse_id,
  quantity=S.quantity,status=S.status,observed_at=S.observed_at,ingestion_mode=S.ingestion_mode,
  source_domain=S.source_domain,correlation_id=S.correlation_id,measure_value=S.measure_value,
  attributes=S.attributes
WHEN NOT MATCHED THEN INSERT (
  scenario_id,entity_type,entity_id,sku_id,store_id,warehouse_id,quantity,status,observed_at,
  ingestion_mode,source_domain,correlation_id,measure_value,attributes
) VALUES (
  S.scenario_id,S.entity_type,S.entity_id,S.sku_id,S.store_id,S.warehouse_id,S.quantity,S.status,
  S.observed_at,S.ingestion_mode,S.source_domain,S.correlation_id,S.measure_value,S.attributes
);
