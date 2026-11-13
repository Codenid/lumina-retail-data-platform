from __future__ import annotations

import csv
import hashlib
import importlib.util
import json
import logging
import os
import re
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Annotated
from uuid import uuid4
from concurrent.futures import wait

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from google.api_core.exceptions import NotFound
from google.cloud import bigquery, pubsub_v1, storage
from pydantic import BaseModel

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
LOGGER = logging.getLogger("lumina_productor")
APP_DIR = Path(__file__).resolve().parent
STATIC_DIR = APP_DIR / "static"
CONTRACTS_DIR = APP_DIR / "contracts"
IMPLEMENTATION_DIR = APP_DIR.parents[1] if len(APP_DIR.parents) > 1 else APP_DIR
if not (CONTRACTS_DIR / "productor_datos.json").exists():
    CONTRACTS_DIR = IMPLEMENTATION_DIR / "automatizacion" / "configuracion" / "contratos"
    STREAMING_CONTRACT = IMPLEMENTATION_DIR / "soluciones" / "procesamiento-streaming" / "contract.py"
    PRODUCERS_CSV = IMPLEMENTATION_DIR / "docs" / "arquitectura" / "productores.csv"
    EVENT_CONTRACT = IMPLEMENTATION_DIR / "docs" / "arquitectura" / "contrato-evento-original.json"
else:
    STREAMING_CONTRACT = CONTRACTS_DIR / "streaming_contract.py"
    PRODUCERS_CSV = CONTRACTS_DIR / "productores.csv"
    EVENT_CONTRACT = CONTRACTS_DIR / "contrato-evento-original.json"

CONFIG = json.loads((CONTRACTS_DIR / "productor_datos.json").read_text(encoding="utf-8"))
BATCH_SCHEMA = json.loads((CONTRACTS_DIR / "bigquery_schema.json").read_text(encoding="utf-8"))
EVENT_TEMPLATE = json.loads(EVENT_CONTRACT.read_text(encoding="utf-8"))
PROJECT_ID = os.getenv("PROJECT_ID", "")
REGION = os.getenv("REGION", "us-central1")
PREFIX = os.getenv("PREFIX", "")
LANDING_BUCKET = os.getenv("LANDING_BUCKET", f"{PROJECT_ID}-{PREFIX}-landing" if PROJECT_ID and PREFIX else "")
BRONZE_DATASET = os.getenv("BRONZE_DATASET", f"{PREFIX.replace('-', '_')}_bronze" if PREFIX else "")
TOPIC_NAME = os.getenv("TOPIC_NAME", f"{PREFIX}-eventos-retail" if PREFIX else "")
WORKFLOW_NAME = os.getenv("WORKFLOW_NAME", f"{PREFIX}-batch" if PREFIX else "")
MAX_UPLOAD_BYTES = 25 * 1024 * 1024
MAX_REQUEST_UPLOAD_BYTES = 20 * 1024 * 1024
MAX_ROWS_PER_FILE = 100_000
RUN_ID_RE = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9_-]{2,63}$")
_clients: dict[str, object] = {}
_runs: dict[str, dict] = {}
_runs_lock = threading.Lock()

spec = importlib.util.spec_from_file_location("streaming_contract", STREAMING_CONTRACT)
if spec is None or spec.loader is None:
    raise RuntimeError(f"No se pudo cargar el contrato streaming: {STREAMING_CONTRACT}")
streaming_contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(streaming_contract)

app = FastAPI(title="Lumina · Productora de datos", docs_url=None, redoc_url=None)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


class StreamingRequest(BaseModel):
    event: dict


class RunRequest(BaseModel):
    mode: str
    producers: list[str]
    duration_seconds: int = 60
    rate_per_second: int = 10
    batch_rows_per_file: int = 1000
    interval_seconds: int = 60


def _require_config() -> None:
    missing = [key for key, value in {
        "PROJECT_ID": PROJECT_ID, "PREFIX": PREFIX, "LANDING_BUCKET": LANDING_BUCKET,
        "BRONZE_DATASET": BRONZE_DATASET, "TOPIC_NAME": TOPIC_NAME,
    }.items() if not value]
    if missing:
        raise HTTPException(503, f"Falta configuración: {', '.join(missing)}")


def _client(name: str):
    if name not in _clients:
        if name == "publisher":
            _clients[name] = pubsub_v1.PublisherClient()
        elif name == "storage":
            _clients[name] = storage.Client(project=PROJECT_ID)
        elif name == "bigquery":
            _clients[name] = bigquery.Client(project=PROJECT_ID, location=REGION)
        elif name == "workflows":
            from google.cloud.workflows import executions_v1
            _clients[name] = executions_v1.ExecutionsClient()
    return _clients[name]


def _producer_rows() -> list[dict]:
    if not PRODUCERS_CSV.exists():
        return []
    with PRODUCERS_CSV.open(encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def _iso_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _synthetic_payload(domain: str, index: int, run_id: str) -> dict:
    now = _iso_now()
    sku = f"SKU-{index % 500 + 1:04d}"
    store = f"STORE-{index % 8 + 1:03d}"
    warehouse = f"WH-{index % 4 + 1:03d}"
    common = {"store_id": store, "source_uri": f"generated://{run_id}/{domain}/{index}"}
    if domain == "pedidos":
        return {"order_id": f"ORD-{run_id}-{index:09d}", "order_line_id": f"LINE-{index:03d}", "customer_id": f"CUS-{index % 9000000 + 1:07d}", "store_id": store, "warehouse_id": warehouse, "sku_id": sku, "quantity": index % 5 + 1, "occurred_at": now}
    if domain == "inventario":
        return {"snapshot_id": f"INV-{run_id}-{index:09d}", "warehouse_id": warehouse, "store_id": store, "sku_id": sku, "on_hand_qty": 20 + index % 500, "reserved_qty": index % 12, "effective_at": now}
    if domain == "entregas":
        return {"delivery_id": f"DEL-{run_id}-{index:09d}", "order_id": f"ORD-{run_id}-{index:09d}", "store_id": store, "region_id": f"REG-{index % 4 + 1:02d}", "promised_at": now, "delivered_at": now, "delivery_cost": round(4.5 + (index % 180) / 10, 2)}
    if domain == "benchmark_competidores":
        return {"benchmark_id": f"BEN-{run_id}-{index:09d}", "competitor_id": f"COMP-{index % 5 + 1:02d}", "sku_id": sku, **common, "observed_at": now, "competitor_price": round(5 + (index % 900) / 10, 2), "availability": "IN_STOCK" if index % 7 else "OUT_OF_STOCK"}
    if domain == "eventos_locales":
        return {"local_event_id": f"LOC-{run_id}-{index:09d}", "store_id": store, "event_type": ("FERIA_LOCAL", "FESTIVO", "CAMPAÑA")[index % 3], "start_at": now, "end_at": now, "impact_score": round((index % 100) / 100, 2), "source_uri": common["source_uri"]}
    if domain == "redes_sociales":
        return {"post_id": f"POST-{run_id}-{index:09d}", "platform": ("instagram", "tiktok", "x")[index % 3], "published_at": now, "sku_id": sku, "sentiment_score": round(((index % 200) - 100) / 100, 2), "engagement_count": index % 10000, "text_hash": hashlib.sha256(f"{run_id}:{index}".encode()).hexdigest(), "source_uri": f"generated://{run_id}/{domain}/{index}"}
    raise ValueError(f"Dominio no soportado: {domain}")


def _synthetic_event(producer_key: str, index: int, run_id: str, event_index: int | None = None) -> dict:
    profile = CONFIG["streaming"]["producers"][producer_key]
    kind = profile["payload_kind"]
    now = _iso_now()
    sku = f"SKU-{index % 500 + 1:04d}"
    store = f"STORE-{index % 8 + 1:03d}"
    warehouse = f"WH-{index % 4 + 1:03d}"
    if kind == "order":
        payload = {"order_id": f"ORD-{run_id}-{index:09d}", "order_line_id": f"LINE-{index:03d}", "customer_id": f"CUS-{index % 9000000 + 1:07d}", "store_id": store, "warehouse_id": warehouse, "product_id": sku, "quantity": index % 5 + 1}
    elif kind == "inventory":
        payload = {"snapshot_id": f"INV-{run_id}-{index:09d}", "warehouse_id": warehouse, "store_id": store, "sku_id": sku, "on_hand_qty": 20 + index % 500, "reserved_qty": index % 12, "effective_at": now}
    elif kind == "delivery":
        payload = {"delivery_id": f"DEL-{run_id}-{index:09d}", "order_id": f"ORD-{run_id}-{index:09d}", "store_id": store, "region_id": "REG-01", "promised_at": now, "delivered_at": now, "delivery_cost": 8.75}
    else:
        payload = {"asset_id": f"ASSET-{producer_key[-6:]}", "sensor_id": f"SENSOR-{index % 40 + 1:03d}", "warehouse_id": warehouse, "store_id": store, "metric_name": "temperature_c" if producer_key == "id-68f797120ee647dc9272b2367d134137" else "sensor_value", "metric_value": round(2 + (index % 80) / 10, 1), "unit": "celsius" if producer_key == "id-68f797120ee647dc9272b2367d134137" else "unit", "occurred_at": now}
    if kind == "telemetry":
        payload.pop("store_id", None) if not payload.get("store_id") else None
    event_index = event_index or index
    return {"schema_version": "1.1.0", "simulation_id": run_id, "scenario_id": run_id, "producer_id": profile["producer_id"], "event_type": profile["event_type"], "event_id": f"evt-{run_id}-{event_index:09d}", "occurred_at": now, "emitted_at": now, "trace_id": f"trace-{run_id}-{event_index:09d}", "payload": payload}


@app.get("/")
def index():
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/api/config")
def get_config():
    return {
        "project_id": PROJECT_ID or None, "region": REGION, "topic": TOPIC_NAME or None,
        "batch_domains": CONFIG["batch_domains"], "streaming": CONFIG["streaming"],
        "producers": _producer_rows(), "max_upload_bytes": MAX_UPLOAD_BYTES,
        "max_request_upload_bytes": MAX_REQUEST_UPLOAD_BYTES,
        "workflow": WORKFLOW_NAME or None,
    }


@app.get("/api/health")
def health():
    try:
        _require_config()
        pub = _client("publisher")
        pub.get_topic(request={"topic": pub.topic_path(PROJECT_ID, TOPIC_NAME)})
        landing_ok = _client("storage").bucket(LANDING_BUCKET).exists()
        bq = _client("bigquery")
        missing_tables = []
        for domain, rule in CONFIG["batch_domains"].items():
            table = f"{PROJECT_ID}.{BRONZE_DATASET}.{rule['bronze_table']}"
            try:
                bq.get_table(table)
            except NotFound:
                missing_tables.append(table)
        if missing_tables:
            raise RuntimeError("Faltan tablas Bronze: " + ", ".join(missing_tables))
        if not landing_ok:
            raise RuntimeError(f"No se encontró el bucket {LANDING_BUCKET}")
        return {"status": "connected", "project_id": PROJECT_ID, "region": REGION,
                "entrypoints": {"streaming": f"Pub/Sub:{TOPIC_NAME}",
                                "batch": f"GCS:{LANDING_BUCKET} → BigQuery:{BRONZE_DATASET}"}}
    except Exception as exc:
        LOGGER.warning("GCP readiness check failed: %s", exc)
        return {"status": "unavailable", "project_id": PROJECT_ID or None, "region": REGION,
                "message": "No se pudo verificar Pub/Sub, Landing y Bronze con las credenciales del servicio."}


def _validate_order_event(raw: dict) -> dict:
    try:
        event = streaming_contract.normalize(json.dumps(raw, ensure_ascii=False))
    except (ValueError, TypeError, json.JSONDecodeError) as exc:
        raise HTTPException(422, str(exc)) from exc
    supported = CONFIG["streaming"]["supported_event_types"]
    event_type = event["event_type"]
    if event_type not in supported:
        raise HTTPException(422, f"{event_type} todavía no tiene consumidor Silver en el Dataflow desplegado")
    profile = supported[event_type]
    if event["producer_id"] != profile["producer_id"]:
        raise HTTPException(422, f"producer_id debe ser {profile['producer_id']} para {event_type}")
    payload = event["payload"]
    missing = [field for field in profile["required_payload"] if payload.get(field) in (None, "")]
    if missing:
        raise HTTPException(422, f"Faltan campos en payload: {', '.join(missing)}")
    if "quantity" in payload:
        try:
            payload["quantity"] = int(payload["quantity"])
        except (TypeError, ValueError) as exc:
            raise HTTPException(422, "payload.quantity debe ser entero") from exc
        if payload["quantity"] < 1:
            raise HTTPException(422, "payload.quantity debe ser mayor que cero")
    if event["event_id"].startswith("evt-reemplazar"):
        event["event_id"] = f"evt-{uuid4().hex}"
    if event["trace_id"].startswith("trace-reemplazar"):
        event["trace_id"] = f"trace-{uuid4().hex}"
    return event


@app.post("/api/streaming/publish")
def publish_streaming(request: StreamingRequest):
    _require_config()
    event = _validate_order_event(request.event)
    publisher = _client("publisher")
    topic_path = publisher.topic_path(PROJECT_ID, TOPIC_NAME)
    try:
        message_id = publisher.publish(
            topic_path, streaming_contract.canonical(event).encode("utf-8").rstrip(b"\n"),
            producer_id=event["producer_id"], event_type=event["event_type"],
            scenario_id=event["scenario_id"], trace_id=event["trace_id"],
        ).result(timeout=30)
    except Exception as exc:
        LOGGER.exception("Pub/Sub publication failed")
        raise HTTPException(502, "Pub/Sub no confirmó la publicación") from exc
    return {"status": "PUBLISHED", "message_id": message_id, "topic": TOPIC_NAME,
            "event_id": event["event_id"],
            "next": "Pub/Sub entrega el evento al Dataflow, que lo materializa en Silver. Gold se actualiza por sus procesos de consumo configurados."}


def _validate_payload(domain: str, payload: dict, line: int) -> dict:
    rule = CONFIG["batch_domains"][domain]
    missing = [key for key in rule["required"] if payload.get(key) in (None, "")]
    if missing:
        raise HTTPException(422, f"Línea {line}: faltan campos {', '.join(missing)}")
    for field, kind in rule.get("types", {}).items():
        if field not in payload or payload[field] is None:
            continue
        try:
            payload[field] = int(payload[field]) if kind == "integer" else float(payload[field])
        except (TypeError, ValueError) as exc:
            raise HTTPException(422, f"Línea {line}: {field} debe ser {kind}") from exc
    if domain == "inventario" and (payload["on_hand_qty"] < 0 or payload["reserved_qty"] < 0):
        raise HTTPException(422, f"Línea {line}: cantidades de inventario no pueden ser negativas")
    return payload


def _effective_at(payload: dict, fields: list[str], now: str) -> str:
    for field in fields:
        value = payload.get(field)
        if value:
            return str(value)
    return now


def _raw_schema(domain: str) -> list[bigquery.SchemaField]:
    table_name = f"{domain}_raw"
    schema = BATCH_SCHEMA.get("bronze", {}).get(table_name)
    if not schema:
        raise HTTPException(503, f"No hay esquema de carga Bronze configurado para {table_name}")
    return [bigquery.SchemaField(name, field_type) for name, field_type, *_ in schema]


def _merge_sql(target: str, stage: str) -> str:
    return f"""MERGE `{target}` T
USING `{stage}` S
ON T.batch_id=S.batch_id AND T.file_id=S.file_id AND T.source_row_number=S.source_row_number
WHEN NOT MATCHED THEN INSERT
(batch_id,file_id,source_file_uri,source_system,source_row_number,ingested_at,effective_at,record_hash,payload_json,is_valid,error_reason)
VALUES
(S.batch_id,S.file_id,S.source_file_uri,S.source_system,S.source_row_number,S.ingested_at,S.effective_at,S.record_hash,S.payload_json,S.is_valid,S.error_reason)"""


def _load_to_bronze(domain: str, uri: str, batch_id: str) -> int:
    bq = _client("bigquery")
    rule = CONFIG["batch_domains"][domain]
    target = f"{PROJECT_ID}.{BRONZE_DATASET}.{rule['bronze_table']}"
    stage = f"{PROJECT_ID}.{BRONZE_DATASET}.{domain}_stage_{batch_id.replace('-', '_')}"
    try:
        bq.get_table(target)
    except NotFound as exc:
        raise HTTPException(503, f"No existe la tabla de entrada {target}; complete primero el runbook de GCP") from exc
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        schema=_raw_schema(domain), write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
    )
    try:
        load_job = bq.load_table_from_uri(uri, stage, job_config=job_config, location=REGION)
        load_job.result(timeout=300)
        count = int(load_job.output_rows or 0)
        bq.query(_merge_sql(target, stage), location=REGION).result(timeout=300)
        return count
    except HTTPException:
        raise
    except Exception as exc:
        LOGGER.exception("Batch load failed for %s", domain)
        raise HTTPException(502, f"No se pudo confirmar la carga Bronze de {domain}: {exc}") from exc
    finally:
        try:
            bq.delete_table(stage, not_found_ok=True)
        except Exception:
            LOGGER.warning("Could not clean BigQuery staging table %s", stage, exc_info=True)


def _start_batch_workflow(batch_id: str) -> str | None:
    if not WORKFLOW_NAME:
        return None
    client = _client("workflows")
    parent = f"projects/{PROJECT_ID}/locations/{REGION}/workflows/{WORKFLOW_NAME}"
    execution = {"argument": json.dumps({"run_id": batch_id, "dataset": f"{PREFIX.replace('-', '_')}_gold"})}
    try:
        return client.create_execution(request={"parent": parent, "execution": execution}).name
    except Exception:
        LOGGER.exception("Workflow start failed for batch %s", batch_id)
        return None


def _run_snapshot(run_id: str) -> dict:
    with _runs_lock:
        run = _runs.get(run_id)
        if not run:
            raise HTTPException(404, "Ejecución no encontrada")
        return {k: v for k, v in run.items() if k not in {"stop_event", "thread"}}


def _set_run(run_id: str, **values) -> None:
    with _runs_lock:
        if run_id in _runs:
            _runs[run_id].update(values)


def _run_streaming(run_id: str) -> None:
    with _runs_lock:
        run = _runs[run_id]
        stop = run["stop_event"]
        producers = run["producers"]
        duration = run["duration_seconds"]
        rate = run["rate_per_second"]
    publisher = _client("publisher")
    topic_path = publisher.topic_path(PROJECT_ID, TOPIC_NAME)
    end_at = time.monotonic() + duration
    sequence = 0
    published = 0
    failed = 0
    started = time.monotonic()
    try:
        pending_futures = []
        while not stop.is_set() and time.monotonic() < end_at:
            tick = time.monotonic()
            for _ in range(rate):
                sequence += 1
                producer_index = (sequence - 1) % len(producers)
                producer_key = producers[producer_index]
                entity_index = (sequence - 1) // len(producers) + 1
                event = _synthetic_event(producer_key, entity_index, run_id, sequence)
                pending_futures.append(publisher.publish(
                    topic_path, streaming_contract.canonical(event).encode("utf-8").rstrip(b"\n"),
                    producer_id=event["producer_id"], event_type=event["event_type"],
                    scenario_id=run_id, trace_id=event["trace_id"],
                ))
            done, pending_futures = wait(pending_futures, timeout=max(0.01, 1.0 - (time.monotonic() - tick)))
            pending_futures = list(pending_futures)
            for future in done:
                try:
                    future.result()
                    published += 1
                except Exception:
                    failed += 1
            _set_run(run_id, accepted=published, failed=failed,
                     elapsed_seconds=round(time.monotonic() - started, 1), generated=sequence)
            stop.wait(max(0, 1.0 - (time.monotonic() - tick)))
        while pending_futures:
            done, pending_futures = wait(pending_futures, timeout=30)
            pending_futures = list(pending_futures)
            for future in done:
                try:
                    future.result()
                    published += 1
                except Exception:
                    failed += 1
        _set_run(run_id, status="STOPPED" if stop.is_set() else "COMPLETED",
                 accepted=published, failed=failed, generated=sequence,
                 elapsed_seconds=round(time.monotonic() - started, 1), finished_at=_iso_now())
    except Exception as exc:
        LOGGER.exception("Streaming run failed: %s", run_id)
        _set_run(run_id, status="FAILED", error=str(exc), accepted=published,
                 failed=failed, generated=sequence, finished_at=_iso_now())


def _run_batch(run_id: str) -> None:
    with _runs_lock:
        run = _runs[run_id]
        stop = run["stop_event"]
        producer_domains = run["producer_domains"]
        duration = run["duration_seconds"]
        rows_per_file = run["batch_rows_per_file"]
        interval = run["interval_seconds"]
    bucket = _client("storage").bucket(LANDING_BUCKET)
    started = time.monotonic()
    end_at = started + duration
    sequence = 0
    total_rows = 0
    files_created = 0
    cycle_number = 0
    stage = "preparar acceso a Landing"
    try:
        while not stop.is_set() and time.monotonic() < end_at:
            tick = time.monotonic()
            cycle_number += 1
            for producer_key, domain in producer_domains.items():
                file_id = f"{domain}-{cycle_number:06d}-{uuid4().hex[:10]}"
                uri = f"gs://{LANDING_BUCKET}/generated/{run_id}/{domain}/{file_id}.jsonl"
                now = _iso_now()
                envelopes = []
                for row_no in range(1, rows_per_file + 1):
                    sequence += 1
                    record_index = (cycle_number - 1) * rows_per_file + row_no
                    payload = _synthetic_payload(domain, record_index, run_id)
                    raw_payload = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
                    envelopes.append(json.dumps({
                        "batch_id": run_id, "file_id": file_id, "source_file_uri": uri,
                        "source_system": CONFIG["batch_domains"][domain]["producer"],
                        "source_row_number": row_no, "ingested_at": now,
                        "effective_at": _effective_at(payload, CONFIG["batch_domains"][domain]["effective_fields"], now),
                        "record_hash": hashlib.sha256(f"{run_id}:{file_id}:{row_no}:{raw_payload}".encode()).hexdigest(),
                        "payload_json": payload, "is_valid": True, "error_reason": None,
                    }, ensure_ascii=False, separators=(",", ":")))
                blob = bucket.blob(f"generated/{run_id}/{domain}/{file_id}.jsonl")
                stage = f"subir archivo del dominio {domain} a Landing"
                blob.upload_from_string("\n".join(envelopes) + "\n", content_type="application/x-ndjson")
                stage = f"cargar dominio {domain} de Landing a Bronze"
                loaded = _load_to_bronze(domain, uri, run_id)
                total_rows += loaded
                files_created += 1
                _set_run(run_id, rows_loaded=total_rows, files_created=files_created,
                         generated=sequence, elapsed_seconds=round(time.monotonic() - started, 1),
                         last_file=uri)
            stop.wait(min(max(0, tick + interval - time.monotonic()), max(0, end_at - time.monotonic())))
        stage = "iniciar el Workflow de procesamiento batch"
        workflow = _start_batch_workflow(run_id)
        processing_note = ("Workflow iniciado para curar Silver y materializar salidas Gold."
                           if workflow else "Archivos Landing y filas Bronze cargados; no se confirmó el inicio del Workflow.")
        _set_run(run_id, status="STOPPED" if stop.is_set() else "COMPLETED",
                 rows_loaded=total_rows, files_created=files_created,
                 elapsed_seconds=round(time.monotonic() - started, 1),
                 workflow_execution=workflow, processing_note=processing_note, finished_at=_iso_now())
    except Exception as exc:
        LOGGER.exception("Batch run failed at %s: %s", stage, run_id)
        if isinstance(exc, HTTPException):
            cause = f"{exc.detail} (HTTP {exc.status_code})"
        else:
            cause = f"{type(exc).__name__}: {exc}"
        _set_run(run_id, status="FAILED", failure_stage=stage,
                 error=f"Falló al {stage}: {cause}", rows_loaded=total_rows,
                 files_created=files_created, finished_at=_iso_now())


@app.post("/api/runs")
def start_run(request: RunRequest):
    _require_config()
    if request.mode not in {"streaming", "batch"}:
        raise HTTPException(422, "Elige Streaming o Batch")
    if not request.producers or len(set(request.producers)) != len(request.producers):
        raise HTTPException(422, "Selecciona al menos un productor, sin duplicados")
    if not 1 <= request.duration_seconds <= 3600:
        raise HTTPException(422, "Duración permitida: 1 a 3600 segundos")
    with _runs_lock:
        if any(run["status"] == "RUNNING" for run in _runs.values()):
            raise HTTPException(409, "Ya existe una ejecución activa. Deténla o espera a que termine.")
    if request.mode == "streaming":
        profiles = CONFIG["streaming"]["producers"]
        unknown = set(request.producers) - set(profiles)
        if unknown:
            raise HTTPException(422, f"Productor Streaming no soportado: {', '.join(sorted(unknown))}")
        if not 1 <= request.rate_per_second <= 10000:
            raise HTTPException(422, "Tasa total permitida: 1 a 10.000 eventos/s")
        if request.rate_per_second * request.duration_seconds > 10_000_000:
            raise HTTPException(422, "La ejecución supera el límite de 10 millones de eventos; reduce la tasa o duración")
        producer_domains = {}
    else:
        producer_rows = {row["archimate_id"]: row for row in _producer_rows()}
        domains_by_producer = {v["producer"]: k for k, v in CONFIG["batch_domains"].items()}
        invalid = [key for key in request.producers if key not in producer_rows or producer_rows[key]["producer"] not in domains_by_producer]
        if invalid:
            raise HTTPException(422, f"Productor Batch no soportado: {', '.join(invalid)}")
        if not 1 <= request.batch_rows_per_file <= MAX_ROWS_PER_FILE:
            raise HTTPException(422, f"Filas por archivo: 1 a {MAX_ROWS_PER_FILE:,}")
        if not 10 <= request.interval_seconds <= 3600:
            raise HTTPException(422, "Frecuencia Batch permitida: 10 a 3600 segundos")
        projected_files = ((request.duration_seconds - 1) // request.interval_seconds) + 1
        if projected_files * request.batch_rows_per_file * len(request.producers) > 10_000_000:
            raise HTTPException(422, "La ejecución supera el límite de 10 millones de filas; reduce filas, productores o duración")
        producer_domains = {key: domains_by_producer[producer_rows[key]["producer"]] for key in request.producers}
        profiles = {}
    run_id = f"run-{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}-{uuid4().hex[:6]}"
    thread_target = _run_streaming if request.mode == "streaming" else _run_batch
    with _runs_lock:
        _runs[run_id] = {"run_id": run_id, "mode": request.mode, "producers": request.producers,
                         "producer_domains": producer_domains, "duration_seconds": request.duration_seconds,
                         "rate_per_second": request.rate_per_second, "batch_rows_per_file": request.batch_rows_per_file,
                         "interval_seconds": request.interval_seconds, "status": "RUNNING", "generated": 0,
                         "accepted": 0, "failed": 0, "rows_loaded": 0, "files_created": 0,
                         "started_at": _iso_now(), "stop_event": threading.Event()}
        thread = threading.Thread(target=thread_target, args=(run_id,), daemon=True, name=f"lumina-{run_id}")
        _runs[run_id]["thread"] = thread
        thread.start()
    return _run_snapshot(run_id)


@app.get("/api/runs")
def list_runs():
    with _runs_lock:
        ids = list(_runs.keys())[-25:]
    return {"runs": [_run_snapshot(run_id) for run_id in reversed(ids)]}


@app.get("/api/runs/{run_id}")
def get_run(run_id: str):
    return _run_snapshot(run_id)


@app.post("/api/runs/{run_id}/stop")
def stop_run(run_id: str):
    with _runs_lock:
        run = _runs.get(run_id)
        if not run:
            raise HTTPException(404, "Ejecución no encontrada")
        if run["status"] == "RUNNING":
            run["stop_event"].set()
        return {k: v for k, v in run.items() if k not in {"stop_event", "thread"}}


@app.post("/api/batch/ingest")
async def ingest_batch(
    batch_id: Annotated[str, Form()],
    domains: Annotated[list[str], Form()],
    files: Annotated[list[UploadFile], File()],
):
    _require_config()
    if not RUN_ID_RE.fullmatch(batch_id):
        raise HTTPException(422, "batch_id solo admite letras, números, guion y guion bajo (3–64 caracteres)")
    if len(files) != len(domains) or not files:
        raise HTTPException(422, "Selecciona al menos un archivo e indica su dominio")
    request_size = sum(upload.size or 0 for upload in files)
    if request_size > MAX_REQUEST_UPLOAD_BYTES:
        raise HTTPException(413, "La carga total supera 20 MiB por solicitud; divide el lote en varias cargas")
    bucket = _client("storage").bucket(LANDING_BUCKET)

    uploaded: list[dict] = []
    totals: dict[str, int] = {}
    now = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    for domain, upload in zip(domains, files):
        if domain not in CONFIG["batch_domains"]:
            raise HTTPException(422, f"Dominio Batch no soportado: {domain}")
        raw = await upload.read(MAX_UPLOAD_BYTES + 1)
        if len(raw) > MAX_UPLOAD_BYTES:
            raise HTTPException(413, f"{upload.filename}: supera el límite de 25 MiB; divide el lote en archivos menores")
        if not raw:
            raise HTTPException(422, f"{upload.filename}: archivo vacío")
        try:
            text = raw.decode("utf-8-sig")
        except UnicodeDecodeError as exc:
            raise HTTPException(422, f"{upload.filename}: debe estar codificado en UTF-8") from exc
        file_id = f"{domain}-{hashlib.sha256(raw).hexdigest()[:24]}"
        uri = f"gs://{LANDING_BUCKET}/batch/{batch_id}/{domain}/{file_id}.jsonl"
        lines: list[str] = []
        for line_no, raw_line in enumerate(text.splitlines(), start=1):
            if not raw_line.strip():
                continue
            try:
                payload = json.loads(raw_line)
            except json.JSONDecodeError as exc:
                raise HTTPException(422, f"{upload.filename}, línea {line_no}: JSON inválido") from exc
            if not isinstance(payload, dict):
                raise HTTPException(422, f"{upload.filename}, línea {line_no}: cada línea debe ser un objeto JSON")
            payload = _validate_payload(domain, payload, line_no)
            row_number = len(lines) + 1
            envelope = {
                "batch_id": batch_id, "file_id": file_id, "source_file_uri": uri,
                "source_system": CONFIG["batch_domains"][domain]["producer"],
                "source_row_number": row_number, "ingested_at": now,
                "effective_at": _effective_at(payload, CONFIG["batch_domains"][domain]["effective_fields"], now),
                "record_hash": hashlib.sha256(f"{domain}:{batch_id}:{row_number}:{raw_line}".encode()).hexdigest(),
                "payload_json": payload, "is_valid": True, "error_reason": None,
            }
            lines.append(json.dumps(envelope, ensure_ascii=False, separators=(",", ":")))
            if len(lines) > MAX_ROWS_PER_FILE:
                raise HTTPException(413, f"{upload.filename}: supera {MAX_ROWS_PER_FILE:,} filas; divide el lote")
        if not lines:
            raise HTTPException(422, f"{upload.filename}: no contiene registros JSONL")
        blob = bucket.blob(f"batch/{batch_id}/{domain}/{file_id}.jsonl")
        try:
            blob.upload_from_string("\n".join(lines) + "\n", content_type="application/x-ndjson")
        except Exception as exc:
            LOGGER.exception("Landing upload failed for %s", domain)
            raise HTTPException(502, f"No se pudo subir {domain} a Landing") from exc
        row_count = _load_to_bronze(domain, uri, batch_id)
        totals[domain] = row_count
        uploaded.append({"domain": domain, "producer": CONFIG["batch_domains"][domain]["producer"], "uri": uri, "rows": row_count})

    workflow_execution = _start_batch_workflow(batch_id) if "pedidos" in domains else None
    pending_domains = [d for d in domains if d != "pedidos"]
    if workflow_execution and pending_domains:
        note = "Workflow batch iniciado para pedidos (CU03/operational_mart); los otros dominios están en Bronze y esperan su orquestación."
    elif workflow_execution:
        note = "Workflow batch iniciado; consulta la ejecución para confirmar la materialización CU03/operational_mart."
    else:
        note = "Datos guardados en Landing y Bronze; no se confirmó una ejecución de Workflow batch."
    return {"status": "BRONZE_INGESTED", "batch_id": batch_id, "files": uploaded,
            "rows": totals, "workflow_execution": workflow_execution, "processing_note": note}


@app.get("/api/streaming/template")
def streaming_template():
    event = json.loads(json.dumps(EVENT_TEMPLATE))
    event["event_id"] = "evt-reemplazar-001"
    event["simulation_id"] = "sim-reemplazar"
    event["scenario_id"] = "lote-operador"
    event["trace_id"] = "trace-reemplazar-001"
    now = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    event["occurred_at"] = event["emitted_at"] = now
    return event
