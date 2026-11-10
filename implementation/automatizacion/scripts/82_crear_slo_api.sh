#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
heading 'Paso 82 — servicio Cloud Monitoring y SLO de disponibilidad'
STATE="$ROOT/state/$DEMO_RUN_ID"; CONTRACT="$ROOT/automatizacion/configuracion/contratos/observability_controls.json"
[[ -s "$STATE/observability_metric.json" ]] || { echo 'SCRIPT 82: 0 — dependencia: SCRIPT 81'; exit 1; }
TOKEN="$(gcloud auth print-access-token)"; [[ -n "$TOKEN" ]] || { echo 'SCRIPT 82: 0 — no se obtuvo token de acceso'; exit 1; }; export TOKEN PROJECT_ID REGION PREFIX
python3 - "$CONTRACT" "$STATE/observability_service.json" "$STATE/observability_slo.json" <<'PY'
import json,os,sys,urllib.error,urllib.parse,urllib.request
contract_path,service_file,slo_file=sys.argv[1:]
c=json.load(open(contract_path,encoding='utf-8'))['service_monitoring']; project=os.environ['PROJECT_ID']; region=os.environ['REGION']; prefix=os.environ['PREFIX']; token=os.environ['TOKEN']; render=lambda v:v.replace('{{PROJECT_ID}}',project).replace('{{REGION}}',region).replace('{{PREFIX}}',prefix); service_id=render(c['service_id']); slo_id=render(c['slo_id']); base=f'https://monitoring.googleapis.com/v3/projects/{project}'
def request(method,url,body=None,allow_404=False):
    data=None if body is None else json.dumps(body,separators=(',',':')).encode(); req=urllib.request.Request(url,data=data,method=method,headers={'Authorization':'Bearer '+token,'x-goog-user-project':project,'Content-Type':'application/json'})
    try:
        with urllib.request.urlopen(req,timeout=60) as response: return json.loads(response.read() or b'{}')
    except urllib.error.HTTPError as exc:
        detail=exc.read().decode('utf-8','replace')
        if allow_404 and exc.code==404: return {}
        raise RuntimeError(f'{method} {url} devolvió HTTP {exc.code}: {detail}') from exc
service=request('GET',base+'/services/'+urllib.parse.quote(service_id,safe=''),allow_404=True)
wanted={'displayName':'Lumina Lab Insights API','basicService':{'serviceType':'CLOUD_RUN','serviceLabels':{'service_name':render(c['service_name']),'location':region}}}
if not service: service=request('POST',base+'/services?'+urllib.parse.urlencode({'service_id':service_id}),wanted)
actual=service.get('basicService',{}); labels=actual.get('serviceLabels',{})
if actual.get('serviceType')!='CLOUD_RUN' or labels.get('service_name')!=render(c['service_name']) or labels.get('location')!=region: raise SystemExit(f'service divergente: {actual}')
json.dump(service,open(service_file,'w',encoding='utf-8'),ensure_ascii=False,indent=2)
service_path=service.get('name') or f'projects/{project}/services/{service_id}'
slo_url='https://monitoring.googleapis.com/v3/'+service_path+'/serviceLevelObjectives/'+urllib.parse.quote(slo_id,safe=''); slo=request('GET',slo_url,allow_404=True)
wanted_slo={'displayName':'99% API availability in rolling 24 hours','serviceLevelIndicator':{'basicSli':{'availability':{}}},'goal':c['goal'],'rollingPeriod':c['rolling_period']}
if not slo: slo=request('POST','https://monitoring.googleapis.com/v3/'+service_path+'/serviceLevelObjectives?'+urllib.parse.urlencode({'service_level_objective_id':slo_id}),wanted_slo)
if slo.get('goal')!=c['goal'] or slo.get('rollingPeriod')!=c['rolling_period']: raise SystemExit('SLO divergente; se conserva sin modificar')
json.dump(slo,open(slo_file,'w',encoding='utf-8'),ensure_ascii=False,indent=2)
print(f'Servicio y SLO verificados: {service_path}')
PY
echo "service_id=$(contract_value "$CONTRACT" service_monitoring.service_id)" > "$STATE/observability_slo_ok.txt"
echo "slo_id=$(contract_value "$CONTRACT" service_monitoring.slo_id)" >> "$STATE/observability_slo_ok.txt"
echo 'SCRIPT 82: 1 — servicio Cloud Monitoring y SLO de disponibilidad verificados'
