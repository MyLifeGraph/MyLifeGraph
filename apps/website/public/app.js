import {german,demoCopy,tourCopy,signals,chartPoints} from './content.js';
import {appearances,normalizeAppearance,appearanceIcon} from './appearance.js';

const copyNodes=[...document.querySelectorAll('[data-copy]')];
const ariaNodes=[...document.querySelectorAll('[data-aria]')];
const english=new Map(copyNodes.map(el=>[el.dataset.copy,el.innerHTML]));
const englishAria=new Map(ariaNodes.map(el=>[el.dataset.aria,el.getAttribute('aria-label')]));
const panel=document.querySelector('#demo-panel');
const tabs=[...document.querySelectorAll('[data-tab]')];
let language='en';
try{if(localStorage.getItem('mylifegraph.website.language')==='de')language='de';}catch{}
let active='today', completed=new Set([1]), metric='sleep',day=2,answer=null;
let morning=true,evening=false,insightView='overview',plannerView='week';
let appearance='liquid-glass';
try{appearance=normalizeAppearance(localStorage.getItem('mylifegraph.website.appearance'));}catch{}
const themeToggle=document.querySelector('#appearance-toggle');
const themeMenu=document.querySelector('#appearance-menu');
function closeAppearance(returnFocus=false){themeMenu.hidden=true;themeToggle.setAttribute('aria-expanded','false');if(returnFocus)themeToggle.focus();}
function applyAppearance(){
  document.documentElement.dataset.theme=appearance;
  themeToggle.innerHTML=appearanceIcon(appearance);
  themeToggle.setAttribute('aria-label',`${tourCopy[language].appearance}: ${appearances.find(t=>t.id===appearance).label}`);
  themeToggle.title=themeToggle.getAttribute('aria-label');
  themeMenu.innerHTML=appearances.map(t=>`<button type="button" data-appearance="${t.id}" aria-pressed="${t.id===appearance}">${appearanceIcon(t.id)}<span>${t.label}</span><span class="theme-check" aria-hidden="true">${t.id===appearance?'✓':''}</span></button>`).join('');
  document.querySelector('meta[name=theme-color]').content=appearance==='light'?'#f6f6f1':appearance==='space'?'#070814':appearance==='dark'?'#08110f':'#0d131c';
}
themeToggle.addEventListener('click',()=>{const opening=themeMenu.hidden;themeMenu.hidden=!opening;themeToggle.setAttribute('aria-expanded',String(opening));});
themeMenu.addEventListener('click',event=>{const option=event.target.closest('[data-appearance]');if(!option)return;appearance=normalizeAppearance(option.dataset.appearance);try{localStorage.setItem('mylifegraph.website.appearance',appearance);}catch{}applyAppearance();closeAppearance(true);});
document.addEventListener('pointerdown',event=>{if(!event.target.closest('.appearance'))closeAppearance();});
document.addEventListener('focusin',event=>{if(!event.target.closest('.appearance'))closeAppearance();});
document.querySelector('.appearance').addEventListener('keydown',event=>{
  if(event.key==='Escape'){event.preventDefault();closeAppearance(true);return;}
  if(!['ArrowDown','ArrowUp','Home','End'].includes(event.key))return;
  event.preventDefault();themeMenu.hidden=false;themeToggle.setAttribute('aria-expanded','true');
  const choices=[...themeMenu.querySelectorAll('button')],index=choices.indexOf(document.activeElement);
  const next=event.key==='Home'?0:event.key==='End'?choices.length-1:event.key==='ArrowDown'?(index+1)%choices.length:(index<0?choices.length-1:(index+choices.length-1)%choices.length);
  choices[next].focus();
});
const escapeText=text=>String(text).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const message=text=>{document.querySelector('#announcement').textContent=text;};

function header(title,subtitle,pill){return `<div class="panel-header"><div><h2>${title}</h2><p>${subtitle}</p></div><span class="pill">${pill}</span></div>`;}
function render(){
  const c=demoCopy[language];
  const t=tourCopy[language];
  tabs.forEach(tab=>{const selected=tab.dataset.tab===active;tab.setAttribute('aria-selected',String(selected));tab.tabIndex=selected?0:-1;});
  panel.setAttribute('aria-labelledby',`tab-${active}`);
  panel.dataset.view=active;
  if(active==='today'){
    panel.innerHTML=header(c.todayTitle,c.todaySub,c.streak)+`<div class="demo-grid"><section class="demo-card"><div class="card-head"><h3>${c.checkin}</h3><span>${c.sample}</span></div><div class="metrics"><div><b>7<small>/10</small></b><span>${c.energy}</span></div><div><b>8<small>h</small></b><span>${c.sleep}</span></div></div><svg class="mini-chart" viewBox="0 0 300 74" aria-hidden="true"><path class="chart-grid" d="M0 65H300M0 30H300"/><path class="chart-line" d="M0 58Q25 60 50 41T100 45T150 25T200 30T250 16T300 19"/></svg></section><section class="demo-card"><div class="card-head"><h3>${c.tasks}</h3><span>${completed.size}/3</span></div><p>${c.tasksHint}</p><div class="task-list">${c.taskNames.map((title,i)=>`<button class="task" type="button" data-task="${i}" aria-pressed="${completed.has(i)}"><span class="task-check" aria-hidden="true">${completed.has(i)?'✓':''}</span><span class="task-label">${title}</span></button>`).join('')}</div></section></div><div class="agenda"><time>09:30</time><div><strong>${c.agenda}</strong><small>${c.agendaSub}</small></div></div>`;
  }else if(active==='insights'){
    const s=signals[metric];
    panel.innerHTML=header(c.insightsTitle,c.insightsSub,c.period)+`<div class="segmented">${['sleep','energy'].map(m=>`<button type="button" data-metric="${m}" aria-pressed="${m===metric}">${c[`${m}Metric`]}</button>`).join('')}</div><section class="demo-card"><div class="card-head"><h3>${c[`${metric}Title`]}</h3></div><p>${c[`${metric}Unit`]}</p><div class="chart-wrap"><svg viewBox="0 0 520 175" role="img" aria-label="${c.chartAria}"><title>${c[`${metric}Title`]}</title><desc>${c.recent}: ${s.recent.join(', ')}. ${c.previous}: ${s.previous.join(', ')}.</desc><path class="chart-grid" d="M20 25H500M20 87H500M20 150H500"/><polyline class="chart-previous" points="${chartPoints(s.previous,s.min,s.max)}"/><polyline class="chart-line" points="${chartPoints(s.recent,s.min,s.max)}"/></svg></div><div class="chart-legend"><span>— ${c.recent}</span><span>┄ ${c.previous}</span></div></section><p class="chart-note">${c.chartNote}</p>`;
  }else if(active==='planner'){
    panel.innerHTML=header(c.plannerTitle,c.plannerSub,c.planPill)+`<div class="days">${c.days.map((d,i)=>`<button class="day" type="button" data-day="${i}" aria-pressed="${i===day}" aria-label="${d}">${d}<strong>${14+i}</strong></button>`).join('')}</div><div class="plan-events">${c.events[day].length?c.events[day].map(([time,title,note])=>`<div class="plan-event"><time>${time}</time><div><strong>${title}</strong><small>${note}</small></div></div>`).join(''):`<section class="demo-card"><h3>${c.freeTitle}</h3><p>${c.freeCopy}</p></section>`}</div>`;
  }else{
    panel.innerHTML=header(c.coachTitle,c.coachSub,c.scripted)+`<div class="chat-message">${c.greeting}</div>${answer===null?'':`<div class="chat-message user">${c.prompts[answer]}</div><div class="chat-message">${c.answers[answer]}</div>`}<div class="chat-prompts">${c.prompts.map((prompt,i)=>`<button type="button" data-answer="${i}" aria-pressed="${i===answer}">${prompt}</button>`).join('')}</div><p class="chat-hint">${c.coachHint}</p>`;
  }
  // Reuse the working synthetic controls, within the real product's hierarchy.
  const heading=panel.querySelector('.panel-header');
  heading.querySelector('h2').textContent=t[active];
  heading.querySelector('p').textContent=active==='today'?t.date:c.sample;
  heading.querySelector('.pill').remove();
  heading.insertAdjacentHTML('beforeend',`<details class="demo-info"><summary aria-label="${t.info}">ⓘ</summary><p>${t.infoText}</p></details>`);
  if(active==='today'){
    const tasks=panel.querySelector('.demo-grid .demo-card:last-child');
    tasks.querySelector('h3').textContent=t.tasks;
    const taskHtml=tasks.outerHTML,agendaHtml=panel.querySelector('.agenda').outerHTML;
    panel.querySelector('.demo-grid').remove();panel.querySelector('.agenda').remove();
    panel.insertAdjacentHTML('beforeend',`<div class="today-tour"><section class="demo-card capture-card"><div class="card-head"><h3>♧ ${t.streak}</h3><span>${t.days}</span></div><p>${c.checkin} · Sep 16</p><div class="capture-metrics"><div><span>ϟ ${c.energy}</span><strong>7/10</strong></div><div><span>☾ ${c.sleep}</span><strong>8h</strong></div><div><span>◉ ${t.quality}</span><strong>8/10</strong></div></div><div class="capture-buttons">${[['morning',morning,'☀'],['evening',evening,'☾']].map(([kind,saved,icon])=>`<button type="button" data-capture="${kind}" aria-pressed="${saved}"><span aria-hidden="true">${icon}</span><strong>${t[kind]}</strong><small>${saved?'✓ '+t.saved:t.todo}</small></button>`).join('')}</div></section><section class="schedule-card"><h3>${t.schedule}</h3>${agendaHtml}</section><section class="demo-card progress-card"><div class="card-head"><h3>${t.progress}</h3><span>${completed.size}/3</span></div><progress value="${completed.size}" max="3" aria-label="${t.progress}"></progress></section>${taskHtml}</div>`);
  }else if(active==='insights'){
    const original=[...panel.children].slice(1).map(el=>el.outerHTML).join('');
    [...panel.children].slice(1).forEach(el=>el.remove());
    panel.insertAdjacentHTML('beforeend',`<div class="view-toggle">${['overview','advanced'].map(view=>`<button type="button" data-insight-view="${view}" aria-pressed="${view===insightView}">${t[view]}</button>`).join('')}</div>${insightView==='advanced'?`<div class="tour-subheading">${t.past} · ${c.period}</div>${original}`:`<section class="demo-card insight-summary"><div class="card-head"><h3>${t.pattern}</h3><span>${t.patternState}</span></div><p>${t.patternText}</p></section><section class="demo-card insight-summary"><div class="card-head"><h3>${t.sleepRec}</h3><span>${c.sample}</span></div><div class="sleep-windows">${[[t.sleepStart,'23:00–23:30'],[t.wake,'07:00–07:30'],[t.duration,'7.5–8 h']].map(([label,value])=>`<div><span>${label}</span><strong>${value}</strong></div>`).join('')}</div></section><p class="chart-note">${c.chartNote}</p>`}`);
  }else if(active==='planner'){
    const calendar=panel.querySelector('.days').outerHTML+panel.querySelector('.plan-events').outerHTML;
    panel.querySelector('.days').remove();panel.querySelector('.plan-events').remove();
    const planning=`<section class="demo-card"><h3>◷ ${t.attention}</h3><p>${t.attentionText}</p></section><section class="demo-card"><h3>▱ ${t.ongoing}</h3><p>${t.remaining}</p></section><section class="demo-card"><h3>↻ ${t.habits}</h3><p>${t.habitText}</p></section>`;
    panel.insertAdjacentHTML('beforeend',`<div class="view-toggle planner-toggle"><button type="button" data-planner-view="week" aria-pressed="${plannerView==='week'}">▦ ${t.thisWeek}</button><button type="button" data-planner-view="planning" aria-pressed="${plannerView==='planning'}">☷ ${t.planning}</button></div><div class="planner-tour" data-planner-view="${plannerView}"><section class="calendar-tour demo-card"><div class="card-head"><h3>${t.nextDays}</h3><div class="day-arrows"><button type="button" data-step="-1" aria-label="${t.back}">‹</button><button type="button" data-step="1" aria-label="${t.next}">›</button></div></div>${calendar}</section><aside class="planning-tour">${planning}</aside></div>`);
  }else{
    const items=[...panel.querySelectorAll('.chat-message')].map(el=>el.outerHTML).join('');
    const prompts=panel.querySelector('.chat-prompts').outerHTML;
    [...panel.children].slice(1).forEach(el=>el.remove());
    panel.insertAdjacentHTML('beforeend',`<section class="coach-frame"><div class="coach-timeline">${items}</div><div class="coach-composer"><p>${t.choosePrompt}</p>${prompts}<div class="composer-model"><span>◈ ${t.standard}</span><small>${c.scripted}</small></div></div></section><p class="chat-hint">${c.coachHint}</p>`);
  }
}

function renderPreview(){
  // A non-interactive snapshot of the same responsive demo, not a second app.
  const snapshot=document.querySelector('#demo-dialog .demo-frame').cloneNode(true);
  snapshot.querySelectorAll('[id],[autofocus],[aria-controls],[aria-labelledby]').forEach(el=>{
    for(const attr of ['id','autofocus','aria-controls','aria-labelledby'])el.removeAttribute(attr);
  });
  snapshot.querySelector('.demo-dialog-actions').remove();
  document.querySelector('#demo-preview').replaceChildren(snapshot);
}

function translate(){
  message('');
  document.documentElement.lang=language;
  copyNodes.forEach(el=>{
    const key=el.dataset.copy;
    // Both dictionaries are bundled, trusted copy. Never render visitor content.
    el.innerHTML=language==='de'?escapeText(german[key]).replaceAll('\n','<br>'):english.get(key);
  });
  ariaNodes.forEach(el=>el.setAttribute('aria-label',language==='de'?german[el.dataset.aria]:englishAria.get(el.dataset.aria)));
  document.title=language==='de'?'MyLifeGraph — Dein Studium. Dein Rhythmus.':'MyLifeGraph — Your studies. Your rhythm.';
  document.querySelector('meta[name=description]').content=language==='de'?'Studienplanung, Fokus und Wohlbefinden verbinden. Entdecke MyLifeGraph in einer interaktiven Demo ohne Konto.':'Bring your study plans, focus and wellbeing together. Explore MyLifeGraph with an interactive, account-free demo.';
  const switcher=document.querySelector('#language');
  switcher.innerHTML=language==='de'?'DE <span aria-hidden="true">/ EN</span>':'EN <span aria-hidden="true">/ DE</span>';
  switcher.setAttribute('aria-label',language==='de'?'Switch to English':'Auf Deutsch wechseln');
  applyAppearance();
  render();
  renderPreview();
}
document.querySelector('#language').addEventListener('click',()=>{language=language==='en'?'de':'en';try{localStorage.setItem('mylifegraph.website.language',language);}catch{}translate();});
tabs.forEach(tab=>tab.addEventListener('click',()=>{active=tab.dataset.tab;render();}));
document.querySelector('#demo-tabs').addEventListener('keydown',event=>{
  const index=tabs.indexOf(document.activeElement);if(index<0)return;
  let next;if(event.key==='ArrowRight')next=(index+1)%tabs.length;else if(event.key==='ArrowLeft')next=(index+tabs.length-1)%tabs.length;else if(event.key==='Home')next=0;else if(event.key==='End')next=tabs.length-1;else return;
  event.preventDefault();tabs[next].focus();tabs[next].click();
});
panel.addEventListener('click',event=>{
  const button=event.target.closest('button');if(!button)return;
  let restore;
  if(button.hasAttribute('data-task')){const n=Number(button.dataset.task);completed.has(n)?completed.delete(n):completed.add(n);message(demoCopy[language][completed.has(n)?'done':'undone']);restore=`[data-task="${n}"]`;}
  else if(button.dataset.metric){metric=button.dataset.metric;restore=`[data-metric="${metric}"]`;}
  else if(button.hasAttribute('data-day')){day=Number(button.dataset.day);restore=`[data-day="${day}"]`;}
  else if(button.hasAttribute('data-answer')){answer=Number(button.dataset.answer);message(demoCopy[language].answers[answer]);restore=`[data-answer="${answer}"]`;}
  else if(button.dataset.capture){if(button.dataset.capture==='morning')morning=!morning;else evening=!evening;restore=`[data-capture="${button.dataset.capture}"]`;}
  else if(button.dataset.insightView){insightView=button.dataset.insightView;restore=`[data-insight-view="${insightView}"]`;}
  else if(button.dataset.plannerView){plannerView=button.dataset.plannerView;restore=`button[data-planner-view="${plannerView}"]`;}
  else if(button.dataset.step){day=(day+Number(button.dataset.step)+7)%7;restore=`[data-step="${button.dataset.step}"]`;}
  else return;
  render();panel.querySelector(restore)?.focus({preventScroll:true});
});
document.querySelector('#reset').addEventListener('click',()=>{active='today';completed=new Set([1]);metric='sleep';day=2;answer=null;morning=true;evening=false;insightView='overview';plannerView='week';render();message(demoCopy[language].resetDone);});
translate();
