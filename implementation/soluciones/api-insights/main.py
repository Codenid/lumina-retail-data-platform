"""Private, read-only REST API for Gold Insights, operational products and master data."""

from __future__ import annotations

import json
import logging
import os
import re
import traceback
from datetime import date, datetime
from decimal import Decimal
from urllib.parse import parse_qs

from google.cloud import bigquery

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
LOGGER = logging.getLogger("retailsmart_api")

PROJECT_ID = os.environ.get("PROJECT_ID", "")
GOLD_DATASET = os.environ.get("GOLD_DATASET", "")
BQ_LOCATION = os.environ.get("BQ_LOCATION", "us-central1")
DEFAULT_ROWS = 25
MAX_ROWS = 100
# The streaming insights table is append-only and has grown beyond 50 MiB.
# Keep a bounded per-request ceiling while allowing the live Gold endpoint to
# read its current window without returning query_failed.
MAXIMUM_BYTES_BILLED = 524_288_000
CURRENT_SCENARIO = os.getenv("CURRENT_SCENARIO", "operacion-vigente")
SCENARIO_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")

TABLES = {
    "insights_streaming": (
        "insight_id,event_id,insight_type,sku_id,store_id,score,created_at,status",
        "created_at DESC",
        False,
    ),
    "cu01_riesgo_quiebre_despacho": (
        "scenario_id,sku_id,store_id,risk_score,available_qty,recommended_action,as_of",
        "as_of DESC",
        True,
    ),
    "cu02_plan_reposicion": (
        "scenario_id,sku_id,warehouse_id,plan_date,forecast_qty,recommended_qty,priority",
        "plan_date DESC,priority,sku_id",
        True,
    ),
        "cu03_kpis_operativos": (
        "scenario_id,period_date,channel,orders,units,conversion_rate,delivery_cost,sla_rate",
            "period_date DESC, IF(channel='streaming', 0, 1), scenario_id DESC",
        True,
    ),
    "cu04_alertas_mantenimiento": (
        "scenario_id,asset_id,sensor_id,warehouse_id,anomaly_type,severity,metric_value,occurred_at",
        "occurred_at DESC, FARM_FINGERPRINT(asset_id)",
        True,
    ),
    "operational_mart": (
        "entity_type,entity_id,sku_id,store_id,warehouse_id,quantity,status,observed_at,ingestion_mode,source_domain,measure_value",
        "observed_at DESC",
        False,
    ),
}

MASTER_TABLES = {
    "stores": ("dim_tiendas", "store_id,store_name,zone_name,city,region_id,store_type,status", "store_name"),
    "products": ("dim_productos", "sku_id,product_name,category_id,category_name,brand,unit,status", "product_name"),
    "categories": ("dim_categorias", "category_id,category_name,department_name,status", "category_name"),
    "warehouses": ("dim_almacenes", "warehouse_id,warehouse_name,city,region_id,status", "warehouse_name"),
}

_client = None


def _get_client():
    global _client
    if not PROJECT_ID or not GOLD_DATASET:
        raise RuntimeError("PROJECT_ID y GOLD_DATASET deben estar configurados")
    if _client is None:
        _client = bigquery.Client(project=PROJECT_ID)
    return _client


def fetch_rows(table: str, limit: int, scenario_id: str | None = None) -> list[dict]:
    if table not in TABLES:
        raise ValueError("tabla fuera de la lista permitida")
    columns, order_by, has_scenario = TABLES[table]
    sql = f"SELECT {columns} FROM `{PROJECT_ID}.{GOLD_DATASET}.{table}`"
    parameters = [bigquery.ScalarQueryParameter("limit", "INT64", limit)]
    if has_scenario:
        sql += " WHERE (@scenario_id IS NULL OR scenario_id = @scenario_id)"
        parameters.append(bigquery.ScalarQueryParameter("scenario_id", "STRING", scenario_id))
    sql += f" ORDER BY {order_by} LIMIT @limit"
    job_config = bigquery.QueryJobConfig(
        query_parameters=parameters,
        maximum_bytes_billed=MAXIMUM_BYTES_BILLED,
        labels={"service": "retailsmart-api", "table": table.replace("_", "-")[:63]},
    )
    rows = _get_client().query(sql, job_config=job_config, location=BQ_LOCATION).result(timeout=60)
    return [dict(row.items()) for row in rows]


def fetch_master(kind: str, limit: int) -> list[dict]:
    table, columns, order_by = MASTER_TABLES[kind]
    sql = f"SELECT {columns} FROM `{PROJECT_ID}.{GOLD_DATASET}.{table}` WHERE status='ACTIVE' ORDER BY {order_by} LIMIT @limit"
    config = bigquery.QueryJobConfig(query_parameters=[bigquery.ScalarQueryParameter("limit", "INT64", limit)], maximum_bytes_billed=MAXIMUM_BYTES_BILLED)
    rows = _get_client().query(sql, job_config=config, location=BQ_LOCATION).result(timeout=60)
    return [dict(row.items()) for row in rows]


def fetch_market(limit: int) -> list[dict]:
    sql = f"""
    SELECT entity_type,entity_id,sku_id,store_id,status,observed_at,source_domain,measure_value
    FROM `{PROJECT_ID}.{GOLD_DATASET}.operational_mart`
    WHERE entity_type IN ('COMPETITOR_PRICE','LOCAL_EVENT','SOCIAL_POST')
    ORDER BY observed_at DESC LIMIT @limit
    """
    config = bigquery.QueryJobConfig(query_parameters=[bigquery.ScalarQueryParameter("limit", "INT64", limit)], maximum_bytes_billed=MAXIMUM_BYTES_BILLED)
    return [dict(row.items()) for row in _get_client().query(sql, job_config=config, location=BQ_LOCATION).result(timeout=60)]


def fetch_quality() -> dict:
    sql = f"""
    SELECT COUNT(*) AS records, COUNTIF(status IS NOT NULL) AS populated,
           MAX(observed_at) AS last_observed
    FROM `{PROJECT_ID}.{GOLD_DATASET}.operational_mart`
    """
    config = bigquery.QueryJobConfig(maximum_bytes_billed=MAXIMUM_BYTES_BILLED)
    row = next(iter(_get_client().query(sql, job_config=config, location=BQ_LOCATION).result(timeout=60)), None)
    return dict(row.items()) if row else {"records": 0, "populated": 0, "last_observed": None}


def fetch_summary() -> dict:
    sql = f"""
    WITH stores AS (SELECT COUNT(*) AS total_stores FROM `{PROJECT_ID}.{GOLD_DATASET}.dim_tiendas` WHERE status='ACTIVE'),
    products AS (SELECT COUNT(*) AS total_products FROM `{PROJECT_ID}.{GOLD_DATASET}.dim_productos` WHERE status='ACTIVE'),
    latest_risk AS (SELECT MAX(DATE(as_of)) AS business_date FROM `{PROJECT_ID}.{GOLD_DATASET}.cu01_riesgo_quiebre_despacho` WHERE scenario_id=@scenario_id),
    latest_kpi AS (SELECT MAX(period_date) AS business_date FROM `{PROJECT_ID}.{GOLD_DATASET}.cu03_kpis_operativos` WHERE scenario_id=@scenario_id),
    risks AS (
      SELECT COUNT(DISTINCT sku_id) AS at_risk,
             COUNT(DISTINCT IF(risk_score>=0.80,sku_id,NULL)) AS critical
      FROM `{PROJECT_ID}.{GOLD_DATASET}.cu01_riesgo_quiebre_despacho`
      WHERE scenario_id=@scenario_id AND DATE(as_of)=(SELECT business_date FROM latest_risk)
    ),
    categories AS (
      SELECT ARRAY_AGG(STRUCT(name, risk_count) ORDER BY risk_count DESC LIMIT 10) AS items
      FROM (
        SELECT p.category_name AS name, COUNT(*) AS risk_count
        FROM `{PROJECT_ID}.{GOLD_DATASET}.cu01_riesgo_quiebre_despacho` r
        JOIN `{PROJECT_ID}.{GOLD_DATASET}.dim_productos` p USING(sku_id)
        WHERE p.status='ACTIVE' AND r.scenario_id=@scenario_id AND DATE(r.as_of)=(SELECT business_date FROM latest_risk)
        GROUP BY p.category_name
      )
    ),
    kpis AS (
      SELECT COALESCE(SUM(IF(period_date=(SELECT business_date FROM latest_kpi),orders,0)),0) AS orders,
             COALESCE(SUM(IF(period_date=(SELECT business_date FROM latest_kpi),units,0)),0) AS units,
             CAST(ROUND(SUM(orders)*0.78) AS INT64) AS active_customers
      FROM `{PROJECT_ID}.{GOLD_DATASET}.cu03_kpis_operativos`
      WHERE scenario_id=@scenario_id
    )
    SELECT stores.total_stores, products.total_products, risks.at_risk, risks.critical,
           kpis.orders, kpis.units, kpis.active_customers, categories.items AS categories
    FROM stores CROSS JOIN products CROSS JOIN risks CROSS JOIN kpis CROSS JOIN categories
    """
    config = bigquery.QueryJobConfig(query_parameters=[bigquery.ScalarQueryParameter("scenario_id", "STRING", CURRENT_SCENARIO)], maximum_bytes_billed=MAXIMUM_BYTES_BILLED)
    row = next(iter(_get_client().query(sql, job_config=config, location=BQ_LOCATION).result(timeout=60)), None)
    return dict(row.items()) if row else {}


def fetch_stock_risk(limit: int) -> dict:
    base = f"(SELECT * FROM `{PROJECT_ID}.{GOLD_DATASET}.cu01_riesgo_quiebre_despacho` WHERE scenario_id='{CURRENT_SCENARIO}')"
    latest_date = f"(SELECT MAX(DATE(as_of)) FROM `{PROJECT_ID}.{GOLD_DATASET}.cu01_riesgo_quiebre_despacho` WHERE scenario_id='{CURRENT_SCENARIO}')"
    metrics_sql = f"""SELECT COUNT(DISTINCT sku_id) AS risk_rows,
      (SELECT COUNT(*) FROM `{PROJECT_ID}.{GOLD_DATASET}.dim_productos` WHERE status='ACTIVE') AS monitored_skus,
      COUNT(DISTINCT IF(risk_score>=0.8 OR STARTS_WITH(recommended_action,'REPOSICIONAR'), sku_id, NULL)) AS critical_rows,
      COUNT(DISTINCT store_id) AS affected_stores, ROUND(AVG(available_qty),2) AS avg_available_qty
      FROM {base} WHERE DATE(as_of)={latest_date}"""
    trend_sql = f"""SELECT CAST(DATE(as_of) AS STRING) AS period_date, COUNT(DISTINCT sku_id) AS risk_rows,
      COUNT(DISTINCT IF(risk_score>=0.8 OR STARTS_WITH(recommended_action,'REPOSICIONAR'), sku_id, NULL)) AS critical_rows
      FROM {base} GROUP BY period_date ORDER BY period_date DESC LIMIT @limit"""
    concentration_sql = f"""SELECT r.store_id, COALESCE(s.zone_name,s.city,'Sin zona') AS zone_name,
      COUNT(DISTINCT r.sku_id) AS risk_rows,
      COUNT(DISTINCT IF(r.risk_score>=0.8 OR STARTS_WITH(r.recommended_action,'REPOSICIONAR'), r.sku_id, NULL)) AS critical_rows
      FROM {base} r LEFT JOIN `{PROJECT_ID}.{GOLD_DATASET}.dim_tiendas` s USING(store_id)
      WHERE DATE(r.as_of)={latest_date}
      GROUP BY r.store_id, zone_name ORDER BY critical_rows DESC, risk_rows DESC, r.store_id LIMIT @limit"""
    critical_sql = f"""SELECT r.sku_id, COALESCE(p.product_name,r.sku_id) AS product_name,
      COALESCE(p.category_name,'Sin categoría') AS category_name, r.store_id,
      COALESCE(s.zone_name,s.city,'Sin zona') AS zone_name, r.available_qty,
      ROUND(r.risk_score,3) AS risk_score, r.recommended_action, CAST(r.as_of AS STRING) AS as_of
      FROM {base} r LEFT JOIN `{PROJECT_ID}.{GOLD_DATASET}.dim_tiendas` s USING(store_id)
      LEFT JOIN `{PROJECT_ID}.{GOLD_DATASET}.dim_productos` p USING(sku_id)
      WHERE DATE(r.as_of)={latest_date}
        AND (r.risk_score>=0.8 OR STARTS_WITH(r.recommended_action,'REPOSICIONAR'))
      QUALIFY ROW_NUMBER() OVER(PARTITION BY r.store_id, r.sku_id ORDER BY r.as_of DESC) = 1
      ORDER BY r.risk_score DESC, r.available_qty ASC LIMIT @limit"""
    def run(sql, label):
        cfg = bigquery.QueryJobConfig(query_parameters=[bigquery.ScalarQueryParameter('limit','INT64',limit)] if '@limit' in sql else [], maximum_bytes_billed=MAXIMUM_BYTES_BILLED, labels={'service':'retailsmart-api','table':label})
        return [dict(row.items()) for row in _get_client().query(sql, job_config=cfg, location=BQ_LOCATION).result(timeout=60)]
    metrics = run(metrics_sql, 'stock-risk-metrics')[0]
    return {'metrics': metrics, 'trend': run(trend_sql, 'stock-risk-trend'), 'concentration': run(concentration_sql, 'stock-risk-concentration'), 'critical_skus': run(critical_sql, 'stock-risk-critical-skus')}


def fetch_forecast_replenishment(limit: int) -> dict:
    base = f"(SELECT * FROM `{PROJECT_ID}.{GOLD_DATASET}.cu02_plan_reposicion` WHERE scenario_id='{CURRENT_SCENARIO}')"
    latest_risk_date = f"(SELECT MAX(DATE(as_of)) FROM `{PROJECT_ID}.{GOLD_DATASET}.cu01_riesgo_quiebre_despacho` WHERE scenario_id='{CURRENT_SCENARIO}')"
    risk = f"""(SELECT sku_id, store_id, available_qty, risk_score, recommended_action
      FROM `{PROJECT_ID}.{GOLD_DATASET}.cu01_riesgo_quiebre_despacho`
      WHERE scenario_id='{CURRENT_SCENARIO}' AND DATE(as_of)={latest_risk_date}
      QUALIFY ROW_NUMBER() OVER(PARTITION BY sku_id ORDER BY risk_score DESC, as_of DESC)=1)"""
    metrics_sql = f"""SELECT COUNT(*) AS plan_rows, COUNT(DISTINCT p.sku_id) AS forecast_skus,
      COUNTIF(p.priority='HIGH') AS high_priority, COUNT(DISTINCT r.store_id) AS affected_stores,
      COALESCE(SUM(p.forecast_qty),0) AS forecast_qty,
      COALESCE(SUM(p.recommended_qty),0) AS recommended_qty,
      ROUND(AVG(r.risk_score),3) AS average_risk FROM {base} p LEFT JOIN {risk} r USING(sku_id)"""
    trend_sql = f"""SELECT CAST(plan_date AS STRING) AS plan_date, COUNT(*) AS plan_rows,
      COUNTIF(priority='HIGH') AS high_priority, SUM(forecast_qty) AS forecast_qty,
      SUM(recommended_qty) AS recommended_qty FROM {base}
      GROUP BY plan_date ORDER BY plan_date LIMIT @limit"""
    concentration_sql = f"""SELECT p.warehouse_id, COALESCE(w.warehouse_name,w.city,'Sin almacén') AS warehouse_name,
      COALESCE(d.category_name,'Sin categoría') AS category_name, COUNT(*) AS plan_rows,
      COUNTIF(p.priority='HIGH') AS high_priority, SUM(p.recommended_qty) AS recommended_qty
      FROM {base} p LEFT JOIN `{PROJECT_ID}.{GOLD_DATASET}.dim_almacenes` w USING(warehouse_id)
      LEFT JOIN `{PROJECT_ID}.{GOLD_DATASET}.dim_productos` d USING(sku_id)
      GROUP BY p.warehouse_id, warehouse_name, category_name ORDER BY plan_rows DESC LIMIT @limit"""
    plans_sql = f"""SELECT p.sku_id, COALESCE(d.product_name,p.sku_id) AS product_name,
      COALESCE(d.category_name,'Sin categoría') AS category_name, p.warehouse_id,
      COALESCE(w.warehouse_name,p.warehouse_id) AS warehouse_name,
      r.store_id, COALESCE(s.zone_name,s.city,r.store_id) AS store_name,
      r.available_qty, ROUND(r.risk_score,3) AS risk_score, r.recommended_action,
      CAST(p.plan_date AS STRING) AS plan_date, p.forecast_qty, p.recommended_qty, p.priority
      FROM {base} p JOIN `{PROJECT_ID}.{GOLD_DATASET}.dim_productos` d USING(sku_id)
      LEFT JOIN `{PROJECT_ID}.{GOLD_DATASET}.dim_almacenes` w USING(warehouse_id)
      LEFT JOIN {risk} r USING(sku_id)
      LEFT JOIN `{PROJECT_ID}.{GOLD_DATASET}.dim_tiendas` s USING(store_id)
      WHERE d.status='ACTIVE' AND p.recommended_qty>0
      ORDER BY CASE p.priority WHEN 'HIGH' THEN 0 WHEN 'MEDIUM' THEN 1 ELSE 2 END,
        r.risk_score DESC, p.recommended_qty DESC LIMIT @limit"""
    def run(sql, label):
        cfg = bigquery.QueryJobConfig(query_parameters=[bigquery.ScalarQueryParameter('limit','INT64',limit)] if '@limit' in sql else [], maximum_bytes_billed=MAXIMUM_BYTES_BILLED, labels={'service':'retailsmart-api','table':label})
        return [dict(row.items()) for row in _get_client().query(sql, job_config=cfg, location=BQ_LOCATION).result(timeout=60)]
    return {'metrics': run(metrics_sql, 'forecast-metrics')[0], 'trend': run(trend_sql, 'forecast-trend'), 'concentration': run(concentration_sql, 'forecast-concentration'), 'plans': run(plans_sql, 'forecast-priority-plans')}

def fetch_operations_analytics(limit: int) -> dict:
    base = f"`{PROJECT_ID}.{GOLD_DATASET}.cu03_kpis_operativos`"
    detail = f"`{PROJECT_ID}.{GOLD_DATASET}.cu03_operacion_detalle`"
    latest_period = f"(SELECT MAX(period_date) FROM {base} WHERE scenario_id='{CURRENT_SCENARIO}')"
    metrics_sql = f"""SELECT COALESCE(SUM(orders),0) AS total_records,
      COALESCE(SUM(units),0) AS units, COALESCE(AVG(sla_rate),0) AS sla_rate,
      CAST(ROUND(SUM(orders)*(1-AVG(sla_rate))) AS INT64) AS attention
      FROM {base} WHERE scenario_id='{CURRENT_SCENARIO}' AND period_date={latest_period}"""
    trend_sql = f"""SELECT CAST(period_date AS STRING) AS period_date,
      SUM(orders) AS orders, SUM(units) AS units, ROUND(AVG(sla_rate),3) AS sla_rate,
      CAST(ROUND(SUM(orders)*AVG(sla_rate)) AS INT64) AS delivered,
      CAST(ROUND(SUM(orders)*(1-AVG(sla_rate))) AS INT64) AS attention
      FROM {base} WHERE scenario_id='{CURRENT_SCENARIO}' GROUP BY period_date ORDER BY period_date DESC LIMIT @limit"""
    status_sql = f"""SELECT status, COUNT(*) AS operations, SUM(units) AS units
      FROM {detail} WHERE scenario_id='{CURRENT_SCENARIO}'
      GROUP BY status ORDER BY CASE status WHEN 'AT_RISK' THEN 0 WHEN 'IN_TRANSIT' THEN 1 ELSE 2 END"""
    details_sql = f"""SELECT d.operation_id,d.order_id,d.store_id,
      COALESCE(s.zone_name,s.city,d.store_id) AS store_name,d.warehouse_id,
      COALESCE(w.warehouse_name,d.warehouse_id) AS warehouse_name,
      CAST(d.promised_at AS STRING) AS promised_at,d.units,d.status,d.delay_hours,
      ROUND(d.fulfillment_rate,3) AS fulfillment_rate,d.recommended_action,
      CAST(d.observed_at AS STRING) AS observed_at
      FROM {detail} d
      LEFT JOIN `{PROJECT_ID}.{GOLD_DATASET}.dim_tiendas` s USING(store_id)
      LEFT JOIN `{PROJECT_ID}.{GOLD_DATASET}.dim_almacenes` w USING(warehouse_id)
      WHERE d.scenario_id='{CURRENT_SCENARIO}'
      ORDER BY CASE d.status WHEN 'AT_RISK' THEN 0 WHEN 'IN_TRANSIT' THEN 1 ELSE 2 END,
        d.delay_hours DESC,d.promised_at LIMIT @limit"""
    def run(sql, label):
        cfg = bigquery.QueryJobConfig(query_parameters=[bigquery.ScalarQueryParameter('limit','INT64',limit)] if '@limit' in sql else [], maximum_bytes_billed=MAXIMUM_BYTES_BILLED, labels={'service':'retailsmart-api','table':label})
        return [dict(row.items()) for row in _get_client().query(sql, job_config=cfg, location=BQ_LOCATION).result(timeout=60)]
    metrics = run(metrics_sql, 'operations-metrics')[0]
    return {'metrics': metrics, 'trend': run(trend_sql, 'operations-trend'),
            'status_distribution': run(status_sql, 'operations-status'),
            'operations': run(details_sql, 'operations-detail')}

def fetch_maintenance_analytics(limit: int) -> dict:
    base = f"(SELECT * FROM `{PROJECT_ID}.{GOLD_DATASET}.cu04_alertas_mantenimiento` WHERE scenario_id='{CURRENT_SCENARIO}')"
    latest_date = f"(SELECT MAX(DATE(occurred_at)) FROM `{PROJECT_ID}.{GOLD_DATASET}.cu04_alertas_mantenimiento` WHERE scenario_id='{CURRENT_SCENARIO}')"
    metrics_sql = f"""SELECT COUNT(DISTINCT asset_id) AS monitored_assets,
      COUNT(DISTINCT IF(UPPER(severity)='HIGH', asset_id, NULL)) AS high_alerts,
      COUNT(DISTINCT IF(UPPER(severity)='MEDIUM', asset_id, NULL)) AS medium_alerts,
      COUNT(DISTINCT IF(UPPER(severity) NOT IN ('HIGH','MEDIUM'), asset_id, NULL)) AS normal_alerts,
      COUNT(DISTINCT asset_id) AS total_alerts, ROUND(AVG(metric_value),2) AS avg_metric_value
      FROM {base} WHERE DATE(occurred_at)={latest_date}"""
    trend_sql = f"""SELECT CAST(DATE(occurred_at) AS STRING) AS period_date,
      COUNT(DISTINCT asset_id) AS alerts, COUNT(DISTINCT IF(UPPER(severity)='HIGH', asset_id, NULL)) AS high_alerts,
      COUNT(DISTINCT IF(UPPER(severity)='MEDIUM', asset_id, NULL)) AS medium_alerts
      FROM {base} GROUP BY period_date ORDER BY period_date DESC LIMIT @limit"""
    concentration_sql = f"""SELECT a.warehouse_id,
      COALESCE(w.warehouse_name,a.warehouse_id) AS warehouse_name,
      COUNT(DISTINCT a.asset_id) AS monitored_assets,
      COUNT(DISTINCT IF(UPPER(a.severity)='HIGH',a.asset_id,NULL)) AS high_alerts,
      COUNT(DISTINCT IF(UPPER(a.severity)='MEDIUM',a.asset_id,NULL)) AS medium_alerts
      FROM {base} a LEFT JOIN `{PROJECT_ID}.{GOLD_DATASET}.dim_almacenes` w USING(warehouse_id)
      WHERE DATE(a.occurred_at)={latest_date}
      GROUP BY a.warehouse_id,warehouse_name
      ORDER BY high_alerts DESC,medium_alerts DESC,monitored_assets DESC"""
    def run(sql, label):
        cfg = bigquery.QueryJobConfig(query_parameters=[bigquery.ScalarQueryParameter('limit','INT64',limit)] if '@limit' in sql else [], maximum_bytes_billed=MAXIMUM_BYTES_BILLED, labels={'service':'retailsmart-api','table':label})
        return [dict(row.items()) for row in _get_client().query(sql, job_config=cfg, location=BQ_LOCATION).result(timeout=60)]
    return {'metrics': run(metrics_sql, 'maintenance-metrics')[0],
            'trend': run(trend_sql, 'maintenance-trend'),
            'concentration': run(concentration_sql, 'maintenance-concentration')}


def fetch_maintenance_events(limit: int) -> list[dict]:
    sql = f"""SELECT a.scenario_id,a.asset_id,a.sensor_id,a.warehouse_id,
      COALESCE(w.warehouse_name,a.warehouse_id) AS warehouse_name,a.anomaly_type,
      a.severity,a.metric_value,CAST(a.occurred_at AS STRING) AS occurred_at,
      CASE UPPER(a.severity) WHEN 'HIGH' THEN 'INSPECCIONAR Y AISLAR ACTIVO'
        WHEN 'MEDIUM' THEN 'PROGRAMAR REVISIÓN PREVENTIVA' ELSE 'CONTINUAR MONITOREO' END AS recommended_action,
      CASE a.anomaly_type WHEN 'TEMPERATURA_ANOMALA' THEN '°C'
        WHEN 'VIBRACION_ELEVADA' THEN 'mm/s' ELSE 'nivel' END AS metric_unit
      FROM `{PROJECT_ID}.{GOLD_DATASET}.cu04_alertas_mantenimiento` a
      LEFT JOIN `{PROJECT_ID}.{GOLD_DATASET}.dim_almacenes` w USING(warehouse_id)
      WHERE a.scenario_id=@scenario_id AND DATE(a.occurred_at)=(SELECT MAX(DATE(occurred_at)) FROM `{PROJECT_ID}.{GOLD_DATASET}.cu04_alertas_mantenimiento` WHERE scenario_id=@scenario_id)
      ORDER BY CASE UPPER(a.severity) WHEN 'HIGH' THEN 0 WHEN 'MEDIUM' THEN 1 ELSE 2 END,
        a.metric_value DESC LIMIT @limit"""
    config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("scenario_id", "STRING", CURRENT_SCENARIO),
            bigquery.ScalarQueryParameter("limit", "INT64", limit),
        ],
        maximum_bytes_billed=MAXIMUM_BYTES_BILLED,
        labels={"service": "retailsmart-api", "table": "maintenance-events"},
    )
    return [dict(row.items()) for row in _get_client().query(sql, job_config=config, location=BQ_LOCATION).result(timeout=60)]


def fetch_streaming_kpis() -> list[dict]:
    """Consolida las filas incrementales del Gold Insights Writer.

    Las filas cuyo scenario_id empieza por streaming- son snapshots históricos
    de materializaciones anteriores y no deben volver a sumarse.
    """
    sql = f"""
    SELECT @scenario_id AS scenario_id, (SELECT MAX(period_date) FROM `{PROJECT_ID}.{GOLD_DATASET}.cu03_kpis_operativos` WHERE scenario_id=@scenario_id) AS period_date,
           'batch' AS channel, COALESCE(SUM(orders), 0) AS orders,
           COALESCE(SUM(units), 0) AS units,
           CAST(NULL AS FLOAT64) AS conversion_rate,
           CAST(NULL AS NUMERIC) AS delivery_cost,
           CAST(NULL AS FLOAT64) AS sla_rate
    FROM `{PROJECT_ID}.{GOLD_DATASET}.cu03_kpis_operativos`
    WHERE scenario_id=@scenario_id AND period_date=(SELECT MAX(period_date) FROM `{PROJECT_ID}.{GOLD_DATASET}.cu03_kpis_operativos` WHERE scenario_id=@scenario_id)
    """
    config = bigquery.QueryJobConfig(query_parameters=[bigquery.ScalarQueryParameter("scenario_id", "STRING", CURRENT_SCENARIO)], maximum_bytes_billed=MAXIMUM_BYTES_BILLED,
                                     labels={"service": "retailsmart-api", "table": "cu03-kpis-live"})
    rows = _get_client().query(sql, job_config=config, location=BQ_LOCATION).result(timeout=60)
    return [dict(row.items()) for row in rows]


def _to_json_default(value):
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return str(value)
    raise TypeError(f"No se puede serializar {type(value).__name__}")


def _parse_request(query_string: str) -> tuple[int, str | None]:
    params = parse_qs(query_string, keep_blank_values=True, strict_parsing=False)
    raw_limit = params.get("limit", [str(DEFAULT_ROWS)])[0]
    try:
        limit = int(raw_limit)
    except ValueError as exc:
        raise ValueError("limit debe ser un entero") from exc
    if not 1 <= limit <= MAX_ROWS:
        raise ValueError(f"limit debe estar entre 1 y {MAX_ROWS}")
    scenario_id = params.get("scenario_id", [None])[0]
    if scenario_id == "":
        scenario_id = None
    if scenario_id is not None and not SCENARIO_ID_RE.fullmatch(scenario_id):
        raise ValueError("scenario_id contiene caracteres no permitidos")
    return limit, scenario_id


def dispatch(path: str, query_string: str) -> tuple[int, dict]:
    if path == "/healthz":
        return 200, {"status": "ok"}
    routes = {
        "/api/v1/insights",
        "/api/v1/kpis",
        "/api/v1/inventory-plans",
        "/api/v1/maintenance-risks",
        "/api/v1/operations",
        "/api/v1/market",
        "/api/v1/quality",
        "/api/v1/summary",
        "/api/v1/stock-risk",
        "/api/v1/forecast",
        "/api/v1/operations-analytics",
        "/api/v1/maintenance-analytics",
        "/api/v1/catalog/stores",
        "/api/v1/catalog/products",
        "/api/v1/catalog/categories",
        "/api/v1/catalog/warehouses",
    }
    if path not in routes:
        return 404, {"error": "route_not_found"}
    try:
        limit, scenario_id = _parse_request(query_string)
    except ValueError as exc:
        return 400, {"error": "invalid_query", "message": str(exc)}

    try:
        if path.startswith("/api/v1/catalog/"):
            kind = path.rsplit("/", 1)[-1]
            rows = fetch_master(kind, limit)
            return 200, {"data": rows, "count": len(rows), "source": "master_data"}
        if path == "/api/v1/insights":
            try:
                risks = fetch_rows("cu01_riesgo_quiebre_despacho", limit, scenario_id)
            except Exception:
                LOGGER.exception("stockout risk feed unavailable")
                risks = []
            # CU01 must remain available even while the append-only insight
            # feed is being compacted. The feed is optional for the stock and
            # market consumers; a failed feed query must not take down Gold.
            try:
                insights = fetch_rows("insights_streaming", limit)
            except Exception:
                LOGGER.exception("streaming insight feed unavailable")
                insights = []
            return 200, {
                "streaming_insights": insights,
                "stockout_risks": risks,
                "counts": {"streaming_insights": len(insights), "stockout_risks": len(risks)},
                "scenario_id": scenario_id,
            }
        if path == "/api/v1/market":
            try:
                rows = fetch_market(limit)
                source = "operational_mart"
            except Exception:
                LOGGER.exception("operational mart market feed unavailable")
                rows = fetch_rows("insights_streaming", limit)
                source = "insights_streaming"
            return 200, {"data": rows, "count": len(rows), "source_table": source}
        if path == "/api/v1/quality":
            try:
                quality = fetch_quality()
                source = "operational_mart"
            except Exception:
                LOGGER.exception("operational mart quality feed unavailable")
                rows = fetch_streaming_kpis()
                quality = {"records": len(rows), "populated": len(rows), "last_observed": rows[0].get("period_date") if rows else None}
                source = "cu03_kpis_operativos"
            return 200, {"data": quality, "source_table": source}
        if path == "/api/v1/summary":
            return 200, {"data": fetch_summary(), "source_table": "Gold dimensions + cu01_riesgo_quiebre_despacho + cu03_kpis_operativos"}
        if path == "/api/v1/stock-risk":
            return 200, {"data": fetch_stock_risk(limit), "source_table": "cu01_riesgo_quiebre_despacho + Gold dimensions"}
        if path == "/api/v1/forecast":
            return 200, {"data": fetch_forecast_replenishment(limit), "source_table": "cu02_plan_reposicion + Gold dimensions"}
        if path == "/api/v1/operations-analytics":
            return 200, {"data": fetch_operations_analytics(limit), "source_table": "cu03_kpis_operativos"}
        if path == "/api/v1/maintenance-analytics":
            return 200, {"data": fetch_maintenance_analytics(limit), "source_table": "cu04_alertas_mantenimiento"}

        if path == "/api/v1/maintenance-risks":
            rows = fetch_maintenance_events(limit)
            return 200, {"data": rows, "count": len(rows), "source_table": "cu04_alertas_mantenimiento", "scenario_id": CURRENT_SCENARIO}

        if path == "/api/v1/operations":
            rows = fetch_operations_analytics(limit)["trend"]
            return 200, {"data": rows, "count": len(rows), "source_table": "cu03_kpis_operativos", "scenario_id": CURRENT_SCENARIO}

        if path == "/api/v1/kpis":
            rows = fetch_streaming_kpis()
            return 200, {"data": rows, "count": len(rows), "source_table": "cu03_kpis_operativos", "scenario_id": scenario_id}

        table_by_route = {
            "/api/v1/kpis": "cu03_kpis_operativos",
            "/api/v1/inventory-plans": "cu02_plan_reposicion",
        }
        table = table_by_route[path]
        rows = fetch_rows(table, limit, scenario_id)
        source_table = table
        return 200, {
            "data": rows,
            "count": len(rows),
            "source_table": source_table,
            "scenario_id": scenario_id,
        }
    except Exception:
        LOGGER.error("BigQuery query failed for %s\n%s", path, traceback.format_exc())
        return 500, {"error": "query_failed"}


def app(environ, start_response):
    method = environ.get("REQUEST_METHOD", "GET").upper()
    path = environ.get("PATH_INFO", "/")
    LOGGER.info("request method=%s path=%s", method, path)
    cors_origin = os.getenv("CORS_ORIGIN", "*")
    if method == "OPTIONS":
        start_response("204 No Content", [("Access-Control-Allow-Origin", cors_origin), ("Access-Control-Allow-Methods", "GET, OPTIONS"), ("Access-Control-Allow-Headers", "Content-Type, Authorization")])
        return [b""]
    if method != "GET":
        status, body = 405, {"error": "method_not_allowed"}
        headers = [("Allow", "GET")]
    else:
        status, body = dispatch(path, environ.get("QUERY_STRING", ""))
        headers = []
    payload = json.dumps(body, default=_to_json_default, separators=(",", ":")).encode("utf-8")
    headers.extend(
        [
            ("Content-Type", "application/json; charset=utf-8"),
            ("Content-Length", str(len(payload))),
            ("Cache-Control", "private, no-store"),
            ("X-Content-Type-Options", "nosniff"),
            ("Access-Control-Allow-Origin", cors_origin),
            ("Access-Control-Allow-Methods", "GET, OPTIONS"),
            ("Access-Control-Allow-Headers", "Content-Type, Authorization"),
        ]
    )
    phrases = {200: "OK", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed", 500: "Internal Server Error"}
    start_response(f"{status} {phrases[status]}", headers)
    return [payload]
