#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 55 — generar seis archivos y copiarlos a Landing'
[[ -s "$ROOT/state/$DEMO_RUN_ID/batch_productivo_id.txt" ]] || { echo 'SCRIPT 55: 0 — dependencia: SCRIPT 54'; exit 1; }
BATCH_RUN_ID="$(cat "$ROOT/state/$DEMO_RUN_ID/batch_productivo_id.txt")"
export ROOT BATCH_RUN_ID PROJECT_ID LANDING
python3 - <<'PY'
import json,os
from datetime import datetime,timezone
from pathlib import Path
root=Path(os.environ['ROOT']); run=os.environ['BATCH_RUN_ID']; bucket=os.environ['LANDING']; now=datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace('+00:00','Z')
payloads={
 'pedidos': {'order_id':f'ORD-{run}','order_line_id':f'LINE-{run}','customer_id':'CUS-001','store_id':'STORE-001','warehouse_id':'WH-001','sku_id':'SKU-001','quantity':12},
 'inventario': {'warehouse_id':'WH-001','store_id':'STORE-001','sku_id':'SKU-001','on_hand_qty':8,'reserved_qty':4},
 'entregas': {'delivery_id':f'DEL-{run}','order_id':f'ORD-{run}','store_id':'STORE-001','region_id':'REG-001','promised_at':now,'delivered_at':now,'delivery_cost':18.5},
 'benchmark_competidores': {'benchmark_id':f'BENCH-{run}','competitor_id':'COMP-001','sku_id':'SKU-001','store_id':'STORE-001','observed_at':now,'competitor_price':19.5,'availability':'IN_STOCK'},
 'eventos_locales': {'local_event_id':f'LOCAL-{run}','store_id':'STORE-001','event_type':'FERIA_LOCAL','start_at':now,'end_at':now,'impact_score':0.7},
 'redes_sociales': {'post_id':f'POST-{run}','platform':'social-demo','published_at':now,'sku_id':'SKU-001','sentiment_score':0.8,'engagement_count':42,'text_hash':f'HASH-{run}'}}
out=root/'state'/os.environ['DEMO_RUN_ID']/'batch-productivo'; out.mkdir(parents=True,exist_ok=True)
for domain,payload in payloads.items():
 uri=f'gs://{bucket}/batch/{run}/{domain}.jsonl'
 envelope={'batch_id':run,'file_id':f'{domain}-{run}','source_file_uri':uri,'source_system':domain,'source_row_number':1,'ingested_at':now,'effective_at':now,'record_hash':f'{domain}-{run}-001','payload_json':payload,'is_valid':True,'error_reason':None}
 (out/f'{domain}.jsonl').write_text(json.dumps(envelope,separators=(',',':'))+'\n',encoding='utf-8')
PY
for domain in pedidos inventario entregas benchmark_competidores eventos_locales redes_sociales; do
  gcloud storage cp "$ROOT/state/$DEMO_RUN_ID/batch-productivo/$domain.jsonl" "gs://$LANDING/batch/$BATCH_RUN_ID/$domain.jsonl" >/dev/null
  gcloud storage objects describe "gs://$LANDING/batch/$BATCH_RUN_ID/$domain.jsonl" --format='value(name,size)' | grep -q "$domain.jsonl" || { echo "SCRIPT 55: 0 — objeto no verificado: $domain"; exit 1; }
done
printf 'SCRIPT 55: 1 — seis fixtures generados y verificados en Landing\n' > "$ROOT/state/$DEMO_RUN_ID/batch_productivo_fixtures_ok.txt"
echo 'SCRIPT 55: 1 — seis archivos verificados en Landing'
