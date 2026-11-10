import json, os
from pathlib import Path
root = Path(os.environ['ROOT']); run = os.environ['DEMO_RUN_ID']
out = root / 'state' / run / 'batch-fixtures'; out.mkdir(parents=True, exist_ok=True)
payloads = {'pedidos': {'order_id': f'ORD-{run}', 'order_line_id': f'LINE-{run}', 'customer_id': 'CUS-001', 'store_id': 'STORE-001', 'sku_id': 'SKU-001', 'quantity': 12}, 'inventario': {'warehouse_id': 'WH-001', 'store_id': 'STORE-001', 'sku_id': 'SKU-001', 'on_hand_qty': 8, 'reserved_qty': 4}, 'entregas': {'delivery_id': f'DEL-{run}', 'order_id': f'ORD-{run}', 'store_id': 'STORE-001', 'region_id': 'REG-001', 'delivery_cost': 18.5}, 'telemetria': {'asset_id': 'ASSET-001', 'sensor_id': 'SENSOR-001', 'warehouse_id': 'WH-001', 'metric_name': 'temperature', 'metric_value': 9.8, 'unit': 'C'}}
for domain, payload in payloads.items():
    row = {'batch_id': run, 'file_id': f'{domain}-{run}', 'source_file_uri': f'gs://landing/batch/{run}/{domain}.jsonl', 'source_system': 'synthetic', 'source_row_number': 1, 'ingested_at': '2026-11-04T00:00:00Z', 'effective_at': '2026-11-04T00:00:00Z', 'record_hash': f'{domain}-{run}-001', 'payload_json': payload, 'is_valid': True, 'error_reason': None}
    (out / f'{domain}.jsonl').write_text(json.dumps(row, separators=(',', ':')) + '\n')
print(out)
