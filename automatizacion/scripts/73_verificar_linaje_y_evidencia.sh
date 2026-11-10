#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 73 — verificar linaje BigQuery y cerrar evidencia de gobierno'
STATE="$ROOT/state/$DEMO_RUN_ID"
[[ -s "$STATE/governance_preflight.txt" && -s "$STATE/governance_api_ok.txt" && -s "$STATE/governance_metadata_ok.txt" ]] || {
  echo 'SCRIPT 73: 0 — dependencias: SCRIPTS 70, 71 y 72'; exit 1;
}

CONTRACT="$ROOT/automatizacion/configuracion/contratos/governance_catalog.json"
LINEAGE_OUT="$STATE/governance_lineage"
mkdir -p "$LINEAGE_OUT"
TOKEN="$(gcloud auth print-access-token)"
[[ -n "$TOKEN" ]] || { echo 'SCRIPT 73: 0 — no se obtuvo token de acceso'; exit 1; }
export TOKEN PROJECT_ID REGION PREFIX

if python3 - "$CONTRACT" "$LINEAGE_OUT" "$STATE/governance_metadata_ok.txt" <<'PY'
import json,os,subprocess,sys,time,urllib.error,urllib.parse,urllib.request
contract_path,out_dir,metadata_marker=sys.argv[1:]
c=json.load(open(contract_path,encoding='utf-8'))
project=os.environ['PROJECT_ID']; region=os.environ['REGION']; token=os.environ['TOKEN']
dataset=c['datasets']['gold']['id'].replace('{{PREFIX}}', os.environ['PREFIX']); pairs=c['lineage']['pairs']
api=f'https://datalineage.googleapis.com/v1/projects/{project}/locations/{region}:searchLinks'
os.makedirs(out_dir,exist_ok=True)

def call_search(target):
    body=json.dumps({'target':{'fullyQualifiedName':f'bigquery:{project}.{dataset}.{target}'},'pageSize':100}).encode()
    req=urllib.request.Request(api,data=body,method='POST',headers={
        'Authorization':'Bearer '+token,'x-goog-user-project':project,
        'Content-Type':'application/json; charset=utf-8'})
    try:
        with urllib.request.urlopen(req,timeout=60) as response:
            return json.loads(response.read() or b'{}')
    except urllib.error.HTTPError as exc:
        detail=exc.read().decode('utf-8','replace')
        raise RuntimeError(f'SearchLinks para {target} devolvió HTTP {exc.code}: {detail}') from exc

def contains_expected_source(response,source):
    expected=f'bigquery:{project}.{dataset}.{source}'
    return any((link.get('source') or {}).get('fullyQualifiedName')==expected for link in response.get('links',[]))

def query_norm(value):
    return ' '.join(value.replace('`','').split()).lower()

# Solo se vuelve a ejecutar el DDL de vistas cuya definición coincide con el
# contrato. CREATE OR REPLACE VIEW no toca las tablas ni los datos de Gold.
before={}
for pair in pairs:
    target=pair['target']
    table_info=os.path.join(out_dir,target+'.view.json')
    result=subprocess.run(['bq',f'--project_id={project}','show','--format=prettyjson',f'{project}:{dataset}.{target}'],
                          check=True,capture_output=True,text=True)
    with open(table_info,'w',encoding='utf-8') as stream: stream.write(result.stdout)
    info=json.loads(result.stdout)
    if info.get('type')!='VIEW': raise SystemExit(f'{target} ya no es una vista; se conserva sin modificar')
    expected=c['lineage']['view_sql'].format(project=project,dataset=dataset,source=pair['source'])
    actual=(info.get('view') or {}).get('query','')
    if query_norm(actual)!=query_norm(expected):
        raise SystemExit(f'{target} tiene SQL divergente; se conserva sin reemplazar. actual={actual!r}; esperado={expected!r}')
    current=call_search(target)
    before[target]=current
    if not contains_expected_source(current,pair['source']):
        sql=f'CREATE OR REPLACE VIEW `{project}.{dataset}.{target}` AS SELECT * FROM `{project}.{dataset}.{pair["source"]}`'
        job_file=os.path.join(out_dir,target+'.refresh_job.json')
        created=subprocess.run(['bq',f'--project_id={project}',f'--location={region}','query','--use_legacy_sql=false','--format=prettyjson',sql],
                               check=True,capture_output=True,text=True)
        with open(job_file,'w',encoding='utf-8') as stream: stream.write(created.stdout)
        print(f'Linaje: DDL idempotente ejecutado para {target}; SQL de la vista coincidía con el contrato')
    else:
        print(f'Linaje existente reutilizado: {pair["source"]} → {target}')

verified={}
for attempt in range(20):
    missing=[]
    for pair in pairs:
        response=call_search(pair['target'])
        path=os.path.join(out_dir,pair['target']+'.json')
        with open(path,'w',encoding='utf-8') as stream: json.dump(response,stream,ensure_ascii=False,indent=2)
        if contains_expected_source(response,pair['source']):
            verified[pair['target']]=pair['source']
        else:
            missing.append(pair['target'])
    if not missing: break
    if attempt<19:
        print(f'Linaje pendiente de propagación para {len(missing)} vista(s); intento de consulta {attempt+1}/20')
        time.sleep(15)

with open(os.path.join(out_dir,'verified.tsv'),'w',encoding='utf-8') as stream:
    for pair in pairs:
        target=pair['target']; source=pair['source']
        stream.write(f'{source}\t{target}\t{"VERIFICADO" if verified.get(target)==source else "PENDIENTE"}\n')
with open(os.path.join(out_dir,'summary.txt'),'w',encoding='utf-8') as stream:
    stream.write(f'pairs={len(pairs)}\nverified={len(verified)}\n')
if len(verified)!=len(pairs):
    print(f'SCRIPT 73: 0 — linaje automático verificado en {len(verified)}/{len(pairs)} pares; Knowledge Catalog puede tardar hasta 24 horas en reflejarlo')
    raise SystemExit(1)
with open(os.path.join(os.path.dirname(out_dir),'governance_lineage_ok.txt'),'w',encoding='utf-8') as stream:
    stream.write(f'pairs={len(pairs)}\nverified={len(verified)}\nmode=automatic_bigquery\n')
print(f'SCRIPT 73: 1 — cuatro pares de linaje BigQuery verificados')
PY
then
  LINEAGE_RC=0
else
  LINEAGE_RC=$?
fi

PREFLIGHT="$STATE/governance_preflight.txt"
METADATA="$STATE/governance_metadata_ok.txt"
LINEAGE_SUMMARY="$LINEAGE_OUT/summary.txt"
LINEAGE_VERIFIED=0
[[ -s "$LINEAGE_SUMMARY" ]] && LINEAGE_VERIFIED="$(sed -n 's/^verified=//p' "$LINEAGE_SUMMARY")"
SCRIPT73=0
[[ "$LINEAGE_RC" == 0 && "$LINEAGE_VERIFIED" == 4 ]] && SCRIPT73=1
if [[ "$SCRIPT73" == 1 ]]; then GROUP_RESULT='COMPLETADO'; else GROUP_RESULT='PARCIAL'; fi

REPORT="$ROOT/state/$DEMO_RUN_ID/EVIDENCIA_GOBIERNO_LINAJE.md"
{
  echo '# Resultado del grupo 70–73 — Gobierno y Knowledge Catalog'; echo
  printf 'Proyecto: `%s`\nRegión: `%s`\nResultado: **%s**\n\n' "$PROJECT_ID" "$REGION" "$GROUP_RESULT"
  echo '| Script | Estado | Resultado |'; echo '|---|---:|---|'
  echo '| 70 | 1 | Permisos, tres datasets, inventario y entradas automáticas verificados |'
  echo '| 71 | 1 | Dataplex y Data Lineage habilitados; agente Dataplex y rol roles/dataplex.serviceAgent verificados |'
  COUNT="$(sed -n 's/^assets=//p' "$METADATA")"
  echo "| 72 | 1 | Aspect overview aplicado/verificado en $COUNT activos; metadata previa divergente se preserva |"
  echo "| 73 | $SCRIPT73 | Linaje BigQuery verificado: $LINEAGE_VERIFIED/4 pares source→vista |"; echo
  echo '## Catálogo'; echo
  echo 'Preflight previo a habilitar APIs:'; cat "$PREFLIGHT"
  echo 'Estado posterior del API:'; cat "$STATE/governance_api_ok.txt"
  cat "$METADATA"; echo
  echo '## Linaje'; echo; [[ -s "$LINEAGE_OUT/verified.tsv" ]] && sed 's/^/- /' "$LINEAGE_OUT/verified.tsv"; echo
  echo '## Alcance y costo'; echo
  echo '- Se catalogaron activos BigQuery Bronze, Silver y Gold existentes; no se creó Lake, bucket, dataset ni tabla de negocio.'
  echo '- Las descripciones se guardan en el aspecto system overview y los aspectos técnicos/schema existentes se conservan.'
  echo '- Data Lineage queda habilitado para capturar transformaciones BigQuery futuras.'
  echo '- La captura automática puede generar cargos variables por procesamiento de linaje; la consulta de vínculos no se cobra por consulta.'; echo
  echo 'No se añadieron roles IAM al usuario ejecutor; se aplicó roles/dataplex.serviceAgent solo al agente de servicio de Dataplex.'
  echo 'Evidencia detallada: `state/demo001/governance_catalog/` y `state/demo001/governance_lineage/`.'
} > "$REPORT"

if [[ "$SCRIPT73" == 1 ]]; then
  printf '70=1\n71=1\n72=1\n73=1\nresultado=COMPLETADO\n' > "$STATE/governance_group_ok.txt"
  echo "Grupo 70–73 COMPLETADO: evidencia guardada en state/$DEMO_RUN_ID/EVIDENCIA_GOBIERNO_LINAJE.md"
else
  printf '70=1\n71=1\n72=1\n73=0\nresultado=PARCIAL\n' > "$STATE/governance_group_ok.txt"
  echo 'Grupo 70–73 PARCIAL: linaje todavía no verificado; evidencia y causa guardadas en el informe'
fi

if [[ "$SCRIPT73" != 1 ]]; then exit 1; fi
