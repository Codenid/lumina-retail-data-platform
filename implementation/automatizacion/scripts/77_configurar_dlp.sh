#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 77 — plantilla DLP y prueba sintética regional'
STATE="$ROOT/state/$DEMO_RUN_ID"
CONTRACT="$ROOT/automatizacion/configuracion/contratos/security_controls.json"
RENDERED_CONTRACT="$STATE/security_controls.rendered.json"
render_template "$CONTRACT" "$RENDERED_CONTRACT"
CONTRACT="$RENDERED_CONTRACT"
[[ -s "$STATE/security_secret_ok.txt" ]] || { echo 'SCRIPT 77: 0 — dependencia: SCRIPT 76'; exit 1; }
TOKEN="$(gcloud auth print-access-token)"
[[ -n "$TOKEN" ]] || { echo 'SCRIPT 77: 0 — no se obtuvo token de acceso'; exit 1; }
export TOKEN PROJECT_ID REGION
python3 - "$CONTRACT" "$STATE/security_dlp_template.json" "$STATE/security_dlp_result.json" <<'PY'
import json,os,sys,urllib.error,urllib.parse,urllib.request
contract_path,template_file,result_file=sys.argv[1:]
c=json.load(open(contract_path,encoding='utf-8'))['dlp']
project=os.environ['PROJECT_ID']; region=os.environ['REGION']; token=os.environ['TOKEN']
base=f'https://dlp.googleapis.com/v2/projects/{project}/locations/{region}'
name=f'{base}/inspectTemplates/{c["template_id"]}'

def request(method,url,body=None,allow_404=False):
    data=None if body is None else json.dumps(body,separators=(',',':')).encode()
    req=urllib.request.Request(url,data=data,method=method,headers={
        'Authorization':'Bearer '+token,'x-goog-user-project':project,'Content-Type':'application/json'})
    try:
        with urllib.request.urlopen(req,timeout=60) as response:
            return response.status,json.loads(response.read() or b'{}')
    except urllib.error.HTTPError as exc:
        detail=exc.read().decode('utf-8','replace')
        if allow_404 and exc.code==404: return 404,{}
        raise RuntimeError(f'{method} {url} devolvió HTTP {exc.code}: {detail}') from exc

_,template=request('GET',name,allow_404=True)
wanted={
  'displayName':c['display_name'],
  'description':'Detectores mínimos para pruebas sintéticas RetailSmart; no incluye quotes',
  'inspectConfig':{
    'infoTypes':[{'name':x} for x in c['info_types']],
    'minLikelihood':c['minimum_likelihood'],
    'includeQuote':c['include_quote'],
    'limits':{'maxFindingsPerRequest':100}
  }
}
if not template:
    url=base+'/inspectTemplates'
    _,template=request('POST',url,{'inspectTemplate':wanted,'templateId':c['template_id']})

actual=template.get('inspectConfig',{})
actual_types={x.get('name') for x in actual.get('infoTypes',[])}
if actual_types!=set(c['info_types']): raise SystemExit(f'infoTypes divergentes: {sorted(actual_types)}')
if actual.get('minLikelihood')!=c['minimum_likelihood']: raise SystemExit(f'minLikelihood divergente: {actual.get("minLikelihood")}')
if actual.get('includeQuote',False) is not False: raise SystemExit('la plantilla existente incluye quote; no se modifica')
with open(template_file,'w',encoding='utf-8') as stream: json.dump(template,stream,ensure_ascii=False,indent=2)

sample='Contacto sintético: ana.demo@example.com, +1 415-555-2671, tarjeta de prueba 4111111111111111.'
_,result=request('POST',base+'/content:inspect',{'inspectTemplateName':template.get('name'),'item':{'value':sample}})
findings=result.get('result',{}).get('findings',[])
types={f.get('infoType',{}).get('name') for f in findings}
required={'EMAIL_ADDRESS','CREDIT_CARD_NUMBER'}
if not required.issubset(types): raise SystemExit(f'detectores obligatorios ausentes: {sorted(required-types)}; observados={sorted(types)}')
if any('quote' in f for f in findings): raise SystemExit('la respuesta contiene quote pese al contrato')
safe={'result':{'findings':[{'infoType':f.get('infoType'),'likelihood':f.get('likelihood'),'location':f.get('location')} for f in findings]}}
with open(result_file,'w',encoding='utf-8') as stream: json.dump(safe,stream,ensure_ascii=False,indent=2)
print(f'Plantilla DLP verificada; tipos detectados={sorted(types)}; contenido no persistido')
PY
printf 'template=%s\nlocation=%s\nsynthetic_inspection=verified\n' \
  "$(contract_value "$CONTRACT" dlp.template_id)" "$REGION" > "$STATE/security_dlp_ok.txt"
echo 'SCRIPT 77: 1 — plantilla DLP y detección sintética verificadas sin guardar quotes'
