#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 72 — documentar activos Bronze/Silver/Gold en Knowledge Catalog'
STATE="$ROOT/state/$DEMO_RUN_ID"
[[ -s "$STATE/governance_preflight.txt" && -s "$STATE/governance_api_ok.txt" ]] || {
  echo 'SCRIPT 72: 0 — dependencias: SCRIPTS 70 y 71'; exit 1;
}
TOKEN="$(gcloud auth print-access-token)"
[[ -n "$TOKEN" ]] || { echo 'SCRIPT 72: 0 — no se obtuvo token de acceso'; exit 1; }
export TOKEN PROJECT_ID REGION
python3 - "$ROOT/automatizacion/configuracion/contratos/governance_catalog.json" "$STATE/governance_assets.json" "$STATE/governance_catalog" "$STATE/governance_metadata_ok.txt" <<'PY'
import html,json,os,sys,time,urllib.error,urllib.parse,urllib.request
contract_path,inventory_path,out_dir,marker=sys.argv[1:]
contract=json.load(open(contract_path,encoding='utf-8'))
assets=json.load(open(inventory_path,encoding='utf-8'))
project=os.environ['PROJECT_ID']; region=os.environ['REGION']; token=os.environ['TOKEN']
aspect=contract['catalog']['overview_aspect']
api='https://dataplex.googleapis.com/v1'
os.makedirs(out_dir,exist_ok=True)

def request(method,url,body=None):
    data=None if body is None else json.dumps(body,separators=(',',':')).encode()
    req=urllib.request.Request(url,data=data,method=method,headers={
        'Authorization':'Bearer '+token,
        'x-goog-user-project':project,
        'Content-Type':'application/json; charset=utf-8'})
    try:
        with urllib.request.urlopen(req,timeout=45) as response:
            raw=response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        detail=exc.read().decode('utf-8','replace')
        raise RuntimeError(f'{method} {url} devolvió HTTP {exc.code}: {detail}') from exc

def entry_name(a):
    return (f"projects/{project}/locations/{region}/entryGroups/@bigquery/entries/"
            f"bigquery.googleapis.com/projects/{project}/datasets/{a['dataset']}/tables/{a['asset']}")

def expected_content(a):
    base=contract['asset_overview'][a['layer']]
    domain=a['asset'].replace('_',' ')
    if a['asset'].startswith('reporting_'):
        domain='Vista de reporting Gold; aplicación consumidora externa opcional, fuera del alcance de esta plataforma'
    elif a['asset'].startswith('cu01_'):
        domain='CU01 riesgo de quiebre de despacho'
    elif a['asset'].startswith('cu02_'):
        domain='CU02 plan de reposición'
    elif a['asset'].startswith('cu03_'):
        domain='CU03 KPIs operativos'
    elif a['asset'].startswith('cu04_'):
        domain='CU04 alertas de mantenimiento'
    elif a['asset']=='operational_mart':
        domain='integración de resultados batch y streaming'
    elif a['asset']=='eventos_raw_pubsub':
        domain='eventos recibidos por la suscripción Pub/Sub con destino BigQuery'
    return '<p>'+html.escape(base.format(asset=a['asset'],domain=domain))+'</p>'

# Primera fase de solo lectura: valida todas las entradas y detecta metadata ajena
# antes de escribir el primer aspecto.
plan=[]
for index,a in enumerate(assets,1):
    name=entry_name(a)
    query=urllib.parse.urlencode({'view':'FULL'})
    current=request('GET',api+'/'+name+'?'+query)
    if current.get('name')!=name:
        raise SystemExit(f"entrada de catálogo divergente para {a['dataset']}.{a['asset']}: {current.get('name')!r}")
    wanted=expected_content(a)
    saved=(current.get('aspects') or {}).get(aspect,{}).get('data',{}).get('content')
    if saved not in (None,wanted):
        raise SystemExit(f"metadata overview preexistente distinta en {a['dataset']}.{a['asset']}; se conserva sin sobrescribir")
    plan.append((a,name,wanted,saved is None))
    file=os.path.join(out_dir,a['layer']+'__'+a['asset']+'.json')
    with open(file,'w',encoding='utf-8') as stream: json.dump(current,stream,ensure_ascii=False,indent=2)

changed=0
for index,(a,name,wanted,needs_update) in enumerate(plan,1):
    if needs_update:
        body={'entry':{'name':name,'aspects':{aspect:{'data':{'content':wanted}}}},
              'updateMask':'aspects','deleteMissingAspects':False,'aspectKeys':[aspect]}
        response=request('POST',api+f'/projects/{project}/locations/{region}:modifyEntry',body)
        observed=(response.get('aspects') or {}).get(aspect,{}).get('data',{}).get('content')
        if observed!=wanted:
            check=request('GET',api+'/'+name+'?'+urllib.parse.urlencode({'view':'FULL'}))
            observed=(check.get('aspects') or {}).get(aspect,{}).get('data',{}).get('content')
            if observed!=wanted:
                raise SystemExit(f"no se verificó overview después de escribir {a['dataset']}.{a['asset']}")
        changed+=1
        result=response
    else:
        result=request('GET',api+'/'+name+'?'+urllib.parse.urlencode({'view':'FULL'}))
    file=os.path.join(out_dir,a['layer']+'__'+a['asset']+'.json')
    with open(file,'w',encoding='utf-8') as stream: json.dump(result,stream,ensure_ascii=False,indent=2)
    if index%10==0 or index==len(plan): print(f'Metadatos verificados: {index}/{len(plan)}')
    time.sleep(0.08)

with open(marker,'w',encoding='utf-8') as stream:
    stream.write(f'assets={len(plan)}\noverviews_added={changed}\naspect={aspect}\n')
print(f'SCRIPT 72: 1 — {len(plan)} activos de catálogo verificados; {changed} aspectos overview añadidos; otros aspectos conservados')
PY
