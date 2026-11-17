#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 84 — cargar escenario demo para los cuatro consumidores'
[[ -s "$ROOT/state/$DEMO_RUN_ID/batch_productivo_preflight.txt" ]] || { echo 'SCRIPT 84: 0 — ejecuta primero SCRIPT 54'; exit 1; }
BATCH_RUN_ID="$(cat "$ROOT/state/$DEMO_RUN_ID/batch_productivo_id.txt")"
OUT="$ROOT/state/$DEMO_RUN_ID/demo-load/$BATCH_RUN_ID"
mkdir -p "$OUT"
export OUT BATCH_RUN_ID LANDING
python3 - <<'PY'
import json, os
from datetime import datetime, timedelta, timezone
from pathlib import Path
out=Path(os.environ['OUT']); run=os.environ['BATCH_RUN_ID']; start=datetime(2026,11,1,tzinfo=timezone.utc)
def row(domain,n,payload,when):
    stamp=when.isoformat().replace('+00:00','Z')
    return {'batch_id':run,'file_id':f'{domain}-{run}','source_file_uri':f'gs://{os.environ["LANDING"]}/batch/{run}/{domain}.jsonl','source_system':'demo-fixture','source_row_number':n,'ingested_at':stamp,'effective_at':stamp,'record_hash':f'{domain}-{run}-{n:03d}','payload_json':payload,'is_valid':True,'error_reason':None}
rows={
 'pedidos':[row('pedidos',1,{'order_id':f'ORD-{run}','order_line_id':f'LINE-{run}','customer_id':'CUS-001','store_id':'STORE-001','warehouse_id':'WH-001','sku_id':'SKU-001','quantity':12},start)],
 'inventario':[],
 'entregas':[row('entregas',1,{'delivery_id':f'DEL-{run}','order_id':f'ORD-{run}','store_id':'STORE-001','region_id':'REG-001','promised_at':(start+timedelta(days=3)).isoformat().replace('+00:00','Z'),'delivered_at':(start+timedelta(days=2)).isoformat().replace('+00:00','Z'),'delivery_cost':18.5},start)],
 'benchmark_competidores':[row('benchmark_competidores',1,{'benchmark_id':f'BENCH-{run}','competitor_id':'COMP-001','sku_id':'SKU-001','store_id':'STORE-001','observed_at':start.isoformat().replace('+00:00','Z'),'competitor_price':19.5,'availability':'IN_STOCK'},start)],
 'eventos_locales':[row('eventos_locales',1,{'local_event_id':f'LOCAL-{run}','store_id':'STORE-001','event_type':'FERIA_LOCAL','start_at':start.isoformat().replace('+00:00','Z'),'end_at':(start+timedelta(days=1)).isoformat().replace('+00:00','Z'),'impact_score':0.7},start)],
 'redes_sociales':[row('redes_sociales',1,{'post_id':f'POST-{run}','platform':'social-demo','published_at':start.isoformat().replace('+00:00','Z'),'sku_id':'SKU-001','sentiment_score':0.8,'engagement_count':42,'text_hash':f'HASH-{run}'},start)]}
for n,qty in enumerate((42,36,30,24,18,12,8,5),1):
    rows['inventario'].append(row('inventario',n,{'snapshot_id':f'{run}:INV-{n:02d}','warehouse_id':'WH-001','store_id':'STORE-001','sku_id':'SKU-001','on_hand_qty':qty,'reserved_qty':2 if qty>4 else 3},start+timedelta(days=n-1)))
for domain,records in rows.items():
    (out/f'{domain}.jsonl').write_text(''.join(json.dumps(x,separators=(',',':'))+'\n' for x in records),encoding='utf-8')
(out/'manifest.json').write_text(json.dumps({k:len(v) for k,v in rows.items()},indent=2)+'\n')
PY
for domain in pedidos inventario entregas benchmark_competidores eventos_locales redes_sociales; do
  target="gs://$LANDING/batch/$BATCH_RUN_ID/$domain.jsonl"
  gcloud storage cp "$OUT/$domain.jsonl" "$target" >/dev/null
  gcloud storage objects describe "$target" --format='value(name,size)' | grep -q "$domain.jsonl" || { echo "SCRIPT 84: 0 — objeto no verificado: $domain"; exit 1; }
done
printf 'batch_id=%s\nlanding=gs://%s/batch/%s\n' "$BATCH_RUN_ID" "$LANDING" "$BATCH_RUN_ID" > "$ROOT/state/$DEMO_RUN_ID/demo_load_ok.txt"
echo "SCRIPT 84: 1 — escenario cargado en Landing; inventario=8 snapshots; manifest=$OUT/manifest.json"
