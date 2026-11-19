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
MAXIMUM_BYTES_BILLED = 104_857_600  # live-insights-read-v2
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
        "occurred_at DESC",
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
    risks AS (SELECT at_risk_skus AS at_risk, critical_skus AS critical FROM `{PROJECT_ID}.{GOLD_DATASET}.agg_inventario_resumen`),
    customers AS (SELECT active_customers FROM `{PROJECT_ID}.{GOLD_DATASET}.agg_clientes_mensual` ORDER BY period_date DESC LIMIT 1),
    categories AS (
      SELECT ARRAY_AGG(STRUCT(name, risk_count) ORDER BY risk_count DESC LIMIT 10) AS items
      FROM (
        SELECT p.category_name AS name, COUNT(*) AS risk_count
        FROM `{PROJECT_ID}.{GOLD_DATASET}.cu01_riesgo_quiebre_despacho` r
        JOIN `{PROJECT_ID}.{GOLD_DATASET}.dim_productos` p USING(sku_id)
        WHERE p.status='ACTIVE'
        GROUP BY p.category_name
      )
    ),
    kpis AS (
      SELECT COALESCE(SUM(orders),0) AS orders, COALESCE(SUM(units),0) AS units
      FROM `{PROJECT_ID}.{GOLD_DATASET}.cu03_kpis_operativos`
      WHERE channel='streaming' AND period_date=CURRENT_DATE()
    )
    SELECT stores.total_stores, products.total_products, risks.at_risk, risks.critical,
           kpis.orders, kpis.units, customers.active_customers, categories.items AS categories
    FROM stores CROSS JOIN products CROSS JOIN risks CROSS JOIN kpis CROSS JOIN customers CROSS JOIN categories
    """
    config = bigquery.QueryJobConfig(maximum_bytes_billed=MAXIMUM_BYTES_BILLED)
    row = next(iter(_get_client().query(sql, job_config=config, location=BQ_LOCATION).result(timeout=60)), None)
    return dict(row.items()) if row else {}


def fetch_stock_risk(limit: int) -> dict:
    base = f"`{PROJECT_ID}.{GOLD_DATASET}.cu01_riesgo_quiebre_despacho`"
    metrics_sql = f"""SELECT COUNT(*) AS risk_rows, COUNT(DISTINCT sku_id) AS monitored_skus,
      COUNTIF(risk_score>=0.5 OR STARTS_WITH(recommended_action,'REPOSICIONAR')) AS critical_rows,
      COUNT(DISTINCT store_id) AS affected_stores, ROUND(AVG(available_qty),2) AS avg_available_qty
      FROM {base}"""
    trend_sql = f"""SELECT CAST(DATE(as_of) AS STRING) AS period_date, COUNT(*) AS risk_rows,
      COUNTIF(risk_score>=0.5 OR STARTS_WITH(recommended_action,'REPOSICIONAR')) AS critical_rows
      FROM {base} GROUP BY period_date ORDER BY period_date DESC LIMIT @limit"""
    concentration_sql = f"""SELECT r.store_id, COALESCE(s.zone_name,s.city,'Sin zona') AS zone_name,
      COALESCE(p.category_name,'Sin categoría') AS category_name, COUNT(*) AS risk_rows,
      COUNTIF(r.risk_score>=0.5 OR STARTS_WITH(r.recommended_action,'REPOSICIONAR')) AS critical_rows
      FROM {base} r LEFT JOIN `{PROJECT_ID}.{GOLD_DATASET}.dim_tiendas` s USING(store_id)
      LEFT JOIN `{PROJECT_ID}.{GOLD_DATASET}.dim_productos` p USING(sku_id)
      GROUP BY r.store_id, zone_name, category_name ORDER BY risk_rows DESC LIMIT @limit"""
    def run(sql, label):
        cfg = bigquery.QueryJobConfig(query_parameters=[bigquery.ScalarQueryParameter('limit','INT64',limit)] if '@limit' in sql else [], maximum_bytes_billed=MAXIMUM_BYTES_BILLED, labels={'service':'retailsmart-api','table':label})
        return [dict(row.items()) for row in _get_client().query(sql, job_config=cfg, location=BQ_LOCATION).result(timeout=60)]
    metrics = run(metrics_sql, 'stock-risk-metrics')[0]
    return {'metrics': metrics, 'trend': run(trend_sql, 'stock-risk-trend'), 'concentration': run(concentration_sql, 'stock-risk-concentration')}


def fetch_forecast_replenishment(limit: int) -> dict:
    base = f"`{PROJECT_ID}.{GOLD_DATASET}.cu02_plan_reposicion`"
    metrics_sql = f"""SELECT COUNT(*) AS plan_rows, COUNT(DISTINCT sku_id) AS forecast_skus,
      COUNTIF(priority='HIGH') AS high_priority, COALESCE(SUM(forecast_qty),0) AS forecast_qty,
      COALESCE(SUM(recommended_qty),0) AS recommended_qty FROM {base}"""
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
    def run(sql, label):
        cfg = bigquery.QueryJobConfig(query_parameters=[bigquery.ScalarQueryParameter('limit','INT64',limit)] if '@limit' in sql else [], maximum_bytes_billed=MAXIMUM_BYTES_BILLED, labels={'service':'retailsmart-api','table':label})
        return [dict(row.items()) for row in _get_client().query(sql, job_config=cfg, location=BQ_LOCATION).result(timeout=60)]
    return {'metrics': run(metrics_sql, 'forecast-metrics')[0], 'trend': run(trend_sql, 'forecast-trend'), 'concentration': run(concentration_sql, 'forecast-concentration')}


def fetch_streaming_kpis() -> list[dict]:
    """Consolida las filas incrementales del Gold Insights Writer.

    Las filas cuyo scenario_id empieza por streaming- son snapshots históricos
    de materializaciones anteriores y no deben volver a sumarse.
    """
    sql = f"""
    SELECT 'streaming-live' AS scenario_id, CURRENT_DATE() AS period_date,
           'streaming' AS channel, COALESCE(SUM(orders), 0) AS orders,
           COALESCE(SUM(units), 0) AS units,
           CAST(NULL AS FLOAT64) AS conversion_rate,
           CAST(NULL AS NUMERIC) AS delivery_cost,
           CAST(NULL AS FLOAT64) AS sla_rate
    FROM `{PROJECT_ID}.{GOLD_DATASET}.cu03_kpis_operativos`
    WHERE channel = 'streaming'
      AND period_date = CURRENT_DATE()
      AND NOT STARTS_WITH(scenario_id, 'streaming-')
    """
    config = bigquery.QueryJobConfig(maximum_bytes_billed=MAXIMUM_BYTES_BILLED,
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

        if path == "/api/v1/kpis":
            rows = fetch_streaming_kpis()
            return 200, {"data": rows, "count": len(rows), "source_table": "cu03_kpis_operativos", "scenario_id": scenario_id}

        table_by_route = {
            "/api/v1/kpis": "cu03_kpis_operativos",
            "/api/v1/inventory-plans": "cu02_plan_reposicion",
            "/api/v1/maintenance-risks": "cu04_alertas_mantenimiento",
            "/api/v1/operations": "operational_mart",
        }
        table = table_by_route[path]
        try:
            rows = fetch_rows(table, limit, scenario_id)
            source_table = table
        except Exception:
            if path != "/api/v1/operations":
                raise
            LOGGER.exception("operational mart order feed unavailable")
            rows = fetch_streaming_kpis()
            source_table = "cu03_kpis_operativos"
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
