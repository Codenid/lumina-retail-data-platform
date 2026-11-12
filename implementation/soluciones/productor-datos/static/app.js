const $=s=>document.querySelector(s);
const modeButtons=[...document.querySelectorAll('[data-mode]')];
let config=null,mode='streaming',activeRun=null,pollTimer=null;
const selectedByMode={streaming:null,batch:null};
const fmt=n=>new Intl.NumberFormat('es-PE').format(Number(n||0));
const escapeHtml=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function showError(message){const panel=$('#run-panel');panel.hidden=false;$('#run-heading').textContent='No se pudo iniciar';$('#run-status').textContent='ERROR';$('#run-status').className='status-pill failed';$('#run-detail').textContent=message}
async function api(path,options={}){const r=await fetch(path,options);let data={};try{data=await r.json()}catch{}if(!r.ok)throw new Error(data.detail||data.message||`HTTP ${r.status}`);return data}
function selectedProducers(){return [...document.querySelectorAll('.producer-check:checked')].map(x=>x.value)}
function producerProfiles(){
  const rows=config.producers;
  if(mode==='streaming'){
    const map=config.streaming.producers;
    return rows.filter(row=>row.mode==='streaming'&&map[row.archimate_id]).map(row=>({key:row.archimate_id,name:row.producer,target:map[row.archimate_id].target,event:map[row.archimate_id].event_type,kind:map[row.archimate_id].payload_kind}));
  }
  const domains=config.batch_domains;
  return rows.filter(row=>row.mode==='batch').map(row=>{const item=Object.entries(domains).find(([,v])=>v.producer===row.producer);return item?{key:row.archimate_id,name:row.producer,target:item[1].bronze_table,domain:item[0]}:null}).filter(Boolean);
}
function renderProducers(){
  const profiles=producerProfiles();
  const selected=selectedByMode[mode];
  $('#producer-list').innerHTML=profiles.map(p=>`<label class="producer-card"><input class="producer-check" type="checkbox" value="${escapeHtml(p.key)}" ${selected===null||selected.includes(p.key)?'checked':''}><span class="checkmark"></span><span class="producer-copy"><b>${escapeHtml(p.name)}</b><small>${mode==='streaming'?`${escapeHtml(p.event)} · Silver ${escapeHtml(p.target)}`:`${escapeHtml(p.domain)} · ${escapeHtml(p.target)}`}</small></span><span class="producer-type">${mode==='streaming'?'EVENTO':'ARCHIVO'}</span></label>`).join('');
  document.querySelectorAll('.producer-check').forEach(el=>el.addEventListener('change',()=>{selectedByMode[mode]=selectedProducers();updateEstimate()}));
  $('#toggle-all').textContent='Quitar selección';
  const n=profiles.length;$('#stream-count').textContent=`${n} productores`;$('#batch-count').textContent=`${n} productores`;
  updateEstimate();
}
function setMode(next){
  if(config)selectedByMode[mode]=selectedProducers();
  mode=next;modeButtons.forEach(b=>b.classList.toggle('active',b.dataset.mode===mode));
  $('#stream-settings').hidden=mode!=='streaming';$('#batch-settings').hidden=mode!=='batch';
  renderProducers();
}
function estimate(){
  const count=selectedProducers().length;
  if(mode==='streaming')return Number($('#stream-rate').value||0)*Number($('#duration-minutes').value||0)*60;
  const duration=Number($('#batch-duration').value||0)*60,interval=Number($('#batch-interval').value||60),ticks=Math.ceil(duration/interval);
  return ticks*Number($('#batch-rows').value||0)*count;
}
function updateEstimate(){
  const total=estimate();$('#estimate-total').textContent=fmt(total);
  $('#estimate-caption').textContent=mode==='streaming'?'eventos totales · tasa distribuida entre productores':`filas · ${Math.ceil((Number($('#batch-duration').value||0)*60)/Number($('#batch-interval').value||60))} archivo(s) por productor`;
  const over=total>10000000||total<=0;$('#estimate-total').classList.toggle('over-limit',over);
  $('#start-run').disabled=over||selectedProducers().length===0||Boolean(activeRun);
}
function profileButtonEvents(){
  document.querySelectorAll('#rate-presets [data-rate]').forEach(button=>button.addEventListener('click',()=>{document.querySelectorAll('#rate-presets button').forEach(b=>b.classList.remove('selected'));button.classList.add('selected');$('#stream-rate').value=button.dataset.rate;updateEstimate()}));
  document.querySelectorAll('#batch-presets [data-rows]').forEach(button=>button.addEventListener('click',()=>{document.querySelectorAll('#batch-presets button').forEach(b=>b.classList.remove('selected'));button.classList.add('selected');$('#batch-rows').value=button.dataset.rows;updateEstimate()}));
}
function renderRun(run){
  const panel=$('#run-panel');panel.hidden=false;$('#run-heading').textContent=`${run.mode==='streaming'?'Streaming':'Batch'} · ${run.run_id}`;
  $('#run-status').textContent=run.status;$('#run-status').className=`status-pill ${run.status==='RUNNING'?'running':run.status==='FAILED'?'failed':'done'}`;
  $('#run-generated').textContent=fmt(run.generated||run.rows_loaded);$('#run-accepted').textContent=fmt(run.mode==='streaming'?run.accepted:run.rows_loaded);
  $('#run-files').textContent=fmt(run.files_created);$('#run-failed').textContent=fmt(run.failed);
  const total=run.mode==='streaming'?run.rate_per_second*run.duration_seconds:Math.ceil(run.duration_seconds/run.interval_seconds)*run.batch_rows_per_file*run.producers.length;
  const done=run.mode==='streaming'?run.generated:run.rows_loaded;$('#run-progress').style.width=`${Math.min(100,total?done/total*100:0)}%`;
  $('#run-detail').textContent=run.error|| (run.mode==='streaming'?`${run.rate_per_second} eventos/s objetivo · ${run.elapsed_seconds||0}s · confirmados por Pub/Sub en ${config.topic}; Dataflow procesa en segundo plano`:`${run.files_created} archivo(s) en Landing · ${run.processing_note|| (run.workflow_execution?'Workflow iniciado: '+run.workflow_execution:'carga en curso')}`);
  $('#stop-run').hidden=run.status!=='RUNNING';
  $('#start-run').disabled=run.status==='RUNNING';
}
function renderHistory(runs){
  if(!runs.length){$('#run-history').innerHTML='<span class="empty-history">Aún no se han iniciado cargas.</span>';return}
  $('#run-history').innerHTML=runs.slice(0,8).map(r=>`<div class="history-row"><span class="history-dot ${r.status==='FAILED'?'failed':r.status==='RUNNING'?'running':''}"></span><b>${r.mode==='streaming'?'Streaming':'Batch'}</b><code>${escapeHtml(r.run_id)}</code><span>${fmt(r.mode==='streaming'?r.accepted:r.rows_loaded)} registros</span><em>${escapeHtml(r.status)}</em></div>`).join('');
}
async function refresh(){
  const data=await api('/api/runs');renderHistory(data.runs);
  if(activeRun){const run=await api(`/api/runs/${activeRun}`);renderRun(run);if(run.status!=='RUNNING'){activeRun=null;clearInterval(pollTimer);pollTimer=null;updateEstimate()}}
}
async function startRun(){
  const producers=selectedProducers();if(!producers.length)return;
  const duration=Number($('#duration-minutes').value||1)*60;
  const body={mode,producers,duration_seconds:duration};
  if(mode==='streaming')body.rate_per_second=Number($('#stream-rate').value||1);
  else{body.batch_rows_per_file=Number($('#batch-rows').value||1);body.interval_seconds=Number($('#batch-interval').value||60)}
  const button=$('#start-run');button.disabled=true;button.textContent='Iniciando…';
  try{const run=await api('/api/runs',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});activeRun=run.run_id;renderRun(run);pollTimer=setInterval(()=>refresh().catch(e=>$('#run-detail').textContent=e.message),1200)}
  catch(error){showError(error.message)}
  finally{button.textContent='Iniciar ejecución →';updateEstimate()}
}
async function stopRun(){if(!activeRun)return;$('#stop-run').disabled=true;try{await api(`/api/runs/${activeRun}/stop`,{method:'POST'});await refresh()}catch(e){$('#run-detail').textContent=e.message}finally{$('#stop-run').disabled=false}}
async function init(){
  try{
    config=await api('/api/config');$('#project-name').textContent=config.project_id||'Proyecto no configurado';$('#region-name').textContent=config.region;$('#topic-name').textContent=config.topic||'sin tópico';
    renderProducers();profileButtonEvents();
    const health=await api('/api/health');const ok=health.status==='connected';$('#connection-label').textContent=ok?'GCP conectado':'GCP sin validar';$('#connection-dot').classList.toggle('ready',ok);$('#connection-dot').classList.toggle('error',!ok);$('#health-detail').textContent=ok?'Entradas disponibles: Pub/Sub, Landing y Bronze':health.message;
    await refresh();
  }catch(error){$('#connection-label').textContent='Configuración requerida';$('#connection-dot').classList.add('error');$('#health-detail').textContent=error.message}
}
modeButtons.forEach(button=>button.addEventListener('click',()=>setMode(button.dataset.mode)));
$('#toggle-all').addEventListener('click',()=>{const boxes=[...document.querySelectorAll('.producer-check')],all=boxes.every(x=>x.checked);boxes.forEach(x=>x.checked=!all);selectedByMode[mode]=selectedProducers();$('#toggle-all').textContent=all?'Seleccionar todos':'Quitar selección';updateEstimate()});
['stream-rate','duration-minutes','batch-rows','batch-interval','batch-duration'].forEach(id=>$('#'+id).addEventListener('input',updateEstimate));
$('#start-run').addEventListener('click',startRun);$('#stop-run').addEventListener('click',stopRun);
init();
