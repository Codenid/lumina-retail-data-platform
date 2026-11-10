"""Private, read-only REST API for Gold Insights and operational products."""

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
MAXIMUM_BYTES_BILLED = 52_428_800
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
        "period_date DESC",
        True,
    ),
    "cu04_alertas_mantenimiento": (
        "scenario_id,asset_id,sensor_id,warehouse_id,anomaly_type,severity,metric_value,occurred_at",
        "occurred_at DESC",
        True,
    ),
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
    }
    if path not in routes:
        return 404, {"error": "route_not_found"}
    try:
        limit, scenario_id = _parse_request(query_string)
    except ValueError as exc:
        return 400, {"error": "invalid_query", "message": str(exc)}

    try:
        if path == "/api/v1/insights":
            insights = fetch_rows("insights_streaming", limit)
            risks = fetch_rows("cu01_riesgo_quiebre_despacho", limit, scenario_id)
            return 200, {
                "streaming_insights": insights,
                "stockout_risks": risks,
                "counts": {"streaming_insights": len(insights), "stockout_risks": len(risks)},
                "scenario_id": scenario_id,
            }

        table_by_route = {
            "/api/v1/kpis": "cu03_kpis_operativos",
            "/api/v1/inventory-plans": "cu02_plan_reposicion",
            "/api/v1/maintenance-risks": "cu04_alertas_mantenimiento",
        }
        table = table_by_route[path]
        rows = fetch_rows(table, limit, scenario_id)
        return 200, {
            "data": rows,
            "count": len(rows),
            "source_table": table,
            "scenario_id": scenario_id,
        }
    except Exception:
        LOGGER.error("BigQuery query failed for %s\n%s", path, traceback.format_exc())
        return 500, {"error": "query_failed"}


def app(environ, start_response):
    method = environ.get("REQUEST_METHOD", "GET").upper()
    path = environ.get("PATH_INFO", "/")
    LOGGER.info("request method=%s path=%s", method, path)
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
        ]
    )
    phrases = {200: "OK", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed", 500: "Internal Server Error"}
    start_response(f"{status} {phrases[status]}", headers)
    return [payload]
