#!/usr/bin/env python3
"""Genera carga operativa reproducible para la plataforma retail.

El generador escribe sobres JSONL particionados por dominio. Los nombres y
valores representan sistemas productivos de retail; no se incluyen etiquetas
de demo/prueba en los registros.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import random
from datetime import datetime, timedelta, timezone
from pathlib import Path


DOMAINS = {
    "pedidos": "OMS",
    "inventario": "ERP_COMERCIAL",
    "entregas": "LOGISTICA",
    "benchmark_competidores": "PRICING",
    "eventos_locales": "MARKETING",
    "redes_sociales": "MARKETING",
}


def stable_int(value: str, modulo: int) -> int:
    return int(hashlib.sha256(value.encode()).hexdigest()[:12], 16) % modulo


def envelope(domain: str, run_id: str, number: int, payload: dict, when: datetime) -> dict:
    stamp = when.isoformat().replace("+00:00", "Z")
    return {
        "batch_id": run_id,
        "file_id": f"{domain}-{run_id}",
        "source_file_uri": f"landing://operacion/{run_id}/{domain}.jsonl",
        "source_system": DOMAINS[domain],
        "source_row_number": number,
        "ingested_at": stamp,
        "effective_at": stamp,
        "record_hash": hashlib.sha256(f"{domain}:{run_id}:{number}".encode()).hexdigest(),
        "payload_json": payload,
        "is_valid": True,
        "error_reason": None,
    }


def writer(root: Path, domain: str, shard: int):
    path = root / domain / f"{domain}-{shard:06d}.jsonl"
    path.parent.mkdir(parents=True, exist_ok=True)
    return path.open("w", encoding="utf-8"), path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--run-id", required=True)
    # Escala demo coherente con una cadena regional, sin inflar la operación.
    ap.add_argument("--orders", type=int, default=28_000)
    ap.add_argument("--stores", type=int, default=32)
    ap.add_argument("--catalog-skus", type=int, default=3_200)
    ap.add_argument("--inventory-per-store", type=int, default=120)
    ap.add_argument("--shard-rows", type=int, default=100_000)
    ap.add_argument("--days", type=int, default=30)
    args = ap.parse_args()
    if min(args.orders, args.stores, args.catalog_skus, args.inventory_per_store) <= 0:
        ap.error("los volúmenes deben ser positivos")

    rng = random.Random(20261116)
    start = datetime(2026, 10, 18, tzinfo=timezone.utc)
    counts = {domain: 0 for domain in DOMAINS}
    handles: dict[str, tuple] = {}
    shard_by_domain = {domain: 0 for domain in DOMAINS}

    def emit(domain: str, payload: dict, when: datetime) -> None:
        n = counts[domain] + 1
        if domain not in handles or (n - 1) % args.shard_rows == 0:
            if domain in handles:
                handles[domain][0].close()
            handles[domain] = writer(args.output, domain, shard_by_domain[domain])
            shard_by_domain[domain] += 1
        handles[domain][0].write(json.dumps(envelope(domain, args.run_id, n, payload, when), separators=(",", ":")) + "\n")
        counts[domain] = n

    # Pedidos y entregas modelan una demanda mensual de 900k clientes/pedidos.
    for i in range(args.orders):
        day = start + timedelta(days=stable_int(f"day:{i}", args.days), hours=stable_int(f"hour:{i}", 16))
        store = 1 + stable_int(f"store:{i}", args.stores)
        sku = 1 + stable_int(f"sku:{i}", args.catalog_skus)
        order_id = f"ORD-{start.strftime('%Y%m')}-{i + 1:09d}"
        store_id = f"STORE-{store:03d}"
        sku_id = f"SKU-{sku:05d}"
        quantity = 1 + stable_int(f"qty:{i}", 6)
        emit("pedidos", {"order_id": order_id, "order_line_id": f"{order_id}-01", "customer_id": f"CUS-{i + 1:09d}", "store_id": store_id, "warehouse_id": f"WH-{1 + (store - 1) // 8:03d}", "sku_id": sku_id, "quantity": quantity}, day)
        promised = day + timedelta(hours=24 + stable_int(f"promise:{i}", 48))
        delivered = promised + timedelta(hours=-4 + stable_int(f"delivery:{i}", 12))
        emit("entregas", {"delivery_id": f"DEL-{start.strftime('%Y%m')}-{i + 1:09d}", "order_id": order_id, "store_id": store_id, "region_id": f"REG-{1 + (store - 1) // 12:02d}", "promised_at": promised.isoformat().replace("+00:00", "Z"), "delivered_at": delivered.isoformat().replace("+00:00", "Z"), "delivery_cost": round(8 + rng.random() * 22, 2)}, day)

    for store in range(1, args.stores + 1):
        for local in range(args.inventory_per_store):
            sku = 1 + ((store * args.inventory_per_store + local) % args.catalog_skus)
            on_hand = 8 + stable_int(f"inventory:{store}:{sku}", 240)
            reserved = stable_int(f"reserved:{store}:{sku}", min(on_hand, 25))
            day = start + timedelta(days=args.days - 1)
            emit("inventario", {"snapshot_id": f"SNAP-{start.strftime('%Y%m%d')}-{store:03d}-{sku:05d}", "warehouse_id": f"WH-{1 + (store - 1) // 8:03d}", "store_id": f"STORE-{store:03d}", "sku_id": f"SKU-{sku:05d}", "on_hand_qty": on_hand, "reserved_qty": reserved}, day)

    for store in range(1, args.stores + 1):
        emit("benchmark_competidores", {"benchmark_id": f"BENCH-{start.strftime('%Y%m')}-{store:03d}", "competitor_id": f"COMP-{1 + store % 4:03d}", "sku_id": f"SKU-{1 + store:05d}", "store_id": f"STORE-{store:03d}", "observed_at": start.isoformat().replace("+00:00", "Z"), "competitor_price": round(5 + rng.random() * 90, 2), "availability": "IN_STOCK" if store % 5 else "LOW_STOCK"}, start)
        emit("eventos_locales", {"local_event_id": f"EVENT-{start.strftime('%Y%m')}-{store:03d}", "store_id": f"STORE-{store:03d}", "event_type": "PROMOCION_LOCAL" if store % 3 else "FERIA_LOCAL", "start_at": start.isoformat().replace("+00:00", "Z"), "end_at": (start + timedelta(days=1)).isoformat().replace("+00:00", "Z"), "impact_score": round(0.35 + rng.random() * 0.6, 3)}, start)
        emit("redes_sociales", {"post_id": f"POST-{start.strftime('%Y%m')}-{store:03d}", "platform": "SOCIAL_COMERCIAL", "published_at": start.isoformat().replace("+00:00", "Z"), "sku_id": f"SKU-{1 + store:05d}", "sentiment_score": round(-0.2 + rng.random() * 1.1, 3), "engagement_count": 50 + stable_int(f"engagement:{store}", 8000), "text_hash": hashlib.sha256(f"post:{store}".encode()).hexdigest()}, start)

    for handle, _ in handles.values():
        handle.close()
    manifest = {"run_id": args.run_id, "orders": args.orders, "stores": args.stores, "catalog_skus": args.catalog_skus, "inventory_per_store": args.inventory_per_store, "records": counts, "source_systems": DOMAINS}
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
