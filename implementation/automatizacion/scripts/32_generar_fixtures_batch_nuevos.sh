#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 32 — generar fixtures de los tres productores nuevos'
[[ -s "$ROOT/state/$DEMO_RUN_ID/tablas_batch_ok.txt" ]] || { echo 'SCRIPT 32: 0 — falta 31'; exit 1; }
ROOT="$ROOT" python3 - <<'PY'
import json, os
from pathlib import Path
root=Path(os.environ['ROOT']); run=os.environ['DEMO_RUN_ID']; out=root/'state'/run/'batch-fixtures'; out.mkdir(exist_ok=True)
payloads={'benchmark_competidores':{'benchmark_id':f'BENCH-{run}','competitor_id':'COMP-001','sku_id':'SKU-001','store_id':'STORE-001','observed_at':'2026-11-05T00:00:00Z','competitor_price':19.5,'availability':'IN_STOCK','source_uri':'gs://landing/benchmark.jsonl'},'eventos_locales':{'local_event_id':f'LOCAL-{run}','store_id':'STORE-001','event_type':'FERIA_LOCAL','start_at':'2026-11-05T00:00:00Z','end_at':'2026-11-06T00:00:00Z','impact_score':0.7,'source_uri':'gs://landing/local.jsonl'},'redes_sociales':{'post_id':f'POST-{run}','platform':'social-demo','published_at':'2026-11-05T00:00:00Z','sku_id':'SKU-001','sentiment_score':0.8,'engagement_count':42,'text_hash':f'HASH-{run}','source_uri':'gs://landing/social.jsonl'}}
for domain,payload in payloads.items():
 row={'batch_id':run,'file_id':f'{domain}-{run}','source_file_uri':payload.pop('source_uri'),'source_system':domain,'source_row_number':1,'ingested_at':'2026-11-05T00:00:00Z','effective_at':'2026-11-05T00:00:00Z','record_hash':f'{domain}-{run}-001','payload_json':payload,'is_valid':True,'error_reason':None}
 (out/f'{domain}.jsonl').write_text(json.dumps(row,separators=(',',':'))+'\n')
PY
printf 'Fixtures nuevos verificados\n' > "$ROOT/state/$DEMO_RUN_ID/fixtures_nuevos_ok.txt"
echo 'SCRIPT 32: 1 — fixtures generados'
