// Navegación en dos decisiones: modo de carga y caso de uso.
let selectedMode='batch';
let hasChosenCase=false;

const baseRenderCase=renderCase;
renderCase=function(){
  const c=getCase();
  const preferred=c.paths.findIndex(p=>selectedMode==='streaming'?p.id===`stream-${c.id}`:!p.id.startsWith('stream-')&&p.id!=='live');
  pathIndex=preferred>=0?preferred:0;
  baseRenderCase();
  document.querySelectorAll('.mode-tab').forEach(b=>b.classList.toggle('active',b.dataset.mode===selectedMode));
  document.querySelectorAll('.case-tab').forEach(b=>b.classList.toggle('active',hasChosenCase&&+b.dataset.case===caseIndex));
  ['case-summary','path-selector','workbench','route-map'].forEach(id=>document.getElementById(id).classList.toggle('hidden-until-choice',!hasChosenCase));
  document.querySelectorAll('.path-tab').forEach((button,i)=>{
    const p=c.paths[i];
    button.classList.toggle('hidden-until-choice',selectedMode==='streaming'?!(p.id.startsWith('stream-')||p.id==='live'):(p.id.startsWith('stream-')||p.id==='live'));
  });
  document.getElementById('path-selector').classList.add('hidden-until-choice');
  document.getElementById('path-description').textContent=getPath().description;
};

document.addEventListener('click',e=>{
  const mode=e.target.closest('[data-mode]');
  if(mode){selectedMode=mode.dataset.mode;pathIndex=0;stepIndex=0;renderCase();return}
  const useCase=e.target.closest('[data-case]');
  if(useCase){caseIndex=Number(useCase.dataset.case);hasChosenCase=true;stepIndex=0;sampleKey=Object.keys(getCase().samples)[0];renderCase()}
});

// Starts at the simple chooser; the first case remains preselected for a short path to exploration.
caseIndex=0;
selectedMode='batch';
renderCase();
