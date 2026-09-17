/* ═══ Coach-Oberfläche (geteilt: Mitarbeiter-Portal = echte Einheiten, HR-Portal = Probelauf). Vanilla, kein Framework.
   Braucht: window.sb (Supabase-Client), Host-Element (_coCtx.hostId), optional kbAvatarHtml/kbInjectCss aus dem Portal.
   Eingebunden per <script src="shared/coach-ui.js?v=__BUILD_ID__">. ═══ */
// ══ Coach (Conny coacht): Einheit starten, Fragen beantworten, Auflösung mit Quelle, Ergebnis, Verlauf. ══
// Fragen kommen fertig aus der Fragenbank (coach-session start), bewertet wird serverseitig (answer/finish).
// Kein Modus-Wirrwarr: drei Einstiege (Tageseinheit / Thema / Vor dem Gespräch) + Dauer, Schwierigkeit, Frageart.
var _coAvail=null,_coAg=null,_coSess=null,_coQ=[],_coIdx=0,_coT0=0,_coBusy=false,_coHist=null,_coOrder=null,_coMatch=null,_coAssign=null;
// Kontext je Portal: {pid, agent, preview, hostId, avatarHtml(ag,size), fallbackAgent(pid)}. MA-Portal: echte Einheiten; HR: Probelauf (preview, nichts gespeichert).
var _coCtx={pid:null,agent:null,preview:false,hostId:'vCoach',avatarHtml:null,fallbackAgent:null};
function coSetCtx(c){ for(var k in c) _coCtx[k]=c[k]; }
function coAvatar(ag,size){ try{ if(_coCtx.avatarHtml) return _coCtx.avatarHtml(ag,size); if(typeof kbAvatarHtml==='function') return kbAvatarHtml(ag,size); }catch(e){} return '<div style="width:100%;height:100%;border-radius:50%;background:'+(ag&&ag.color||'#0F5661')+';color:#fff;display:flex;align-items:center;justify-content:center;font-weight:800">'+String((ag&&ag.name)||'C').charAt(0)+'</div>'; }
function coInjectCss(){ if(document.getElementById('cocss'))return; var st=document.createElement('style'); st.id='cocss'; st.textContent=[
'.co{--acc:#0F5661;background:#fff;border:1px solid color-mix(in srgb, var(--acc) 22%, #e2e8f0);border-radius:20px;padding:22px;box-shadow:0 8px 26px rgba(15,23,42,.06)}',
'.co-hd{display:flex;gap:16px;align-items:center;margin-bottom:16px}',
'.co-lbl{font-size:11.5px;font-weight:800;text-transform:uppercase;letter-spacing:.06em;color:color-mix(in srgb, var(--acc) 70%, #334155);margin:16px 0 8px}',
'.co-modes{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:10px}',
'.co-mode{border:2px solid #e2e8f0;border-radius:14px;padding:14px;cursor:pointer;background:#fff;text-align:left;font-family:inherit}',
'.co-mode.on{border-color:var(--acc);background:color-mix(in srgb, var(--acc) 7%, #fff)}',
'.co-mode b{display:block;font-size:15px;color:#0f172a} .co-mode span{font-size:12.5px;color:#64748b}',
'.co-row{display:flex;gap:8px;flex-wrap:wrap;align-items:center}',
'.co-chip{border:1.5px solid #e2e8f0;border-radius:999px;padding:7px 14px;font-size:13px;font-weight:600;background:#fff;cursor:pointer;font-family:inherit;color:#334155;min-height:40px}',
'.co-chip.on{border-color:var(--acc);background:var(--acc);color:#fff}',
'.co-sel{padding:9px 12px;border:1.5px solid #e2e8f0;border-radius:10px;font-size:14px;font-family:inherit;background:#fff;min-height:42px;max-width:100%}',
'.co-go{margin-top:18px;width:100%;padding:15px;border:none;border-radius:14px;background:var(--acc);color:#fff;font-size:17px;font-weight:800;cursor:pointer;font-family:inherit}',
'.co-go:disabled{opacity:.5}',
'.co-prog{display:flex;gap:4px;margin-bottom:14px} .co-prog i{flex:1;height:6px;border-radius:3px;background:#e2e8f0} .co-prog i.ok{background:#059669} .co-prog i.half{background:#d97706} .co-prog i.no{background:#dc2626} .co-prog i.cur{background:var(--acc)}',
'.co-meta{font-size:12px;color:#64748b;font-weight:600;margin-bottom:6px} .co-meta b{color:var(--acc)}',
'.co-q{font-size:19px;font-weight:700;color:#0f172a;line-height:1.35;margin:0 0 16px;white-space:pre-wrap}',
'.co-opt{display:block;width:100%;text-align:left;border:2px solid #e2e8f0;border-radius:12px;padding:13px 14px;margin-bottom:8px;background:#fff;font-size:15px;font-family:inherit;color:#0f172a;cursor:pointer;line-height:1.4}',
'.co-opt.on{border-color:var(--acc);background:color-mix(in srgb, var(--acc) 8%, #fff)} .co-opt.right{border-color:#059669;background:#ecfdf5} .co-opt.wrong{border-color:#dc2626;background:#fef2f2}',
'.co-opt .k{display:inline-block;width:26px;height:26px;border-radius:50%;background:#f1f5f9;color:#334155;font-weight:800;text-align:center;line-height:26px;margin-right:10px;font-size:13px}',
'.co-in{width:100%;box-sizing:border-box;padding:13px 14px;border:2px solid #e2e8f0;border-radius:12px;font-size:16px;font-family:inherit;min-height:48px} .co-in:focus{outline:none;border-color:var(--acc)}',
'.co-ta{min-height:110px;resize:vertical}',
'.co-pair{display:grid;grid-template-columns:1fr 1fr;gap:8px;align-items:center;margin-bottom:8px} .co-pair .l{font-weight:700;font-size:14px}',
'.co-ord{display:flex;align-items:center;gap:8px;border:2px solid #e2e8f0;border-radius:12px;padding:10px 12px;margin-bottom:6px;background:#fff;font-size:14px} .co-ord .n{width:26px;height:26px;border-radius:50%;background:var(--acc);color:#fff;font-weight:800;text-align:center;line-height:26px;flex:0 0 auto} .co-ord .t{flex:1} .co-ord button{border:1px solid #e2e8f0;background:#fff;border-radius:8px;width:36px;height:36px;cursor:pointer;font-size:16px}',
'.co-act{display:flex;gap:8px;margin-top:16px;flex-wrap:wrap} .co-btn{padding:12px 18px;border-radius:12px;border:none;background:var(--acc);color:#fff;font-weight:800;font-size:15px;cursor:pointer;font-family:inherit;min-height:46px} .co-btn.sec{background:#fff;color:#334155;border:1.5px solid #e2e8f0} .co-btn:disabled{opacity:.5}',
'.co-fb{margin-top:14px;padding:14px 16px;border-radius:14px;border:1px solid} .co-fb.ok{background:#ecfdf5;border-color:#a7f3d0} .co-fb.half{background:#fffbeb;border-color:#fde68a} .co-fb.no{background:#fef2f2;border-color:#fecaca}',
'.co-fb .h{font-size:15px;font-weight:800;margin-bottom:4px} .co-fb .x{font-size:14px;color:#0f172a;line-height:1.5;white-space:pre-wrap} .co-fb .s{font-size:11.5px;color:#64748b;margin-top:8px} .co-fb .flag{margin-top:8px;border:none;background:transparent;color:#64748b;font-size:12px;cursor:pointer;text-decoration:underline;font-family:inherit}',
'.co-rub{margin-top:8px;font-size:13px} .co-rub li{margin:2px 0} .co-rub .y{color:#059669} .co-rub .m{color:#b45309}',
'.co-res{text-align:center;padding:10px 0} .co-res .big{font-size:52px;font-weight:800;color:var(--acc);line-height:1;font-variant-numeric:tabular-nums} .co-res .sub{font-size:15px;color:#334155;margin-top:6px}',
'.co-tr{display:flex;flex-direction:column;gap:8px;margin-top:14px} .co-tl{display:grid;grid-template-columns:1fr 120px 52px;gap:10px;align-items:center;font-size:13px} .co-bar{height:8px;border-radius:4px;background:#eef2f4;overflow:hidden} .co-bar i{display:block;height:100%}',
'.co-hist{margin-top:18px} .co-hrow{display:flex;gap:10px;align-items:center;padding:8px 0;border-top:1px solid #eef2f7;font-size:13px} .co-hrow .p{font-family:ui-monospace,monospace;font-weight:700;width:60px} .co-hrow .d{color:#64748b;width:110px} .co-hrow .m{flex:1;color:#334155}',
'.co-asg{display:flex;flex-direction:column;gap:8px} .co-asgrow{display:flex;gap:12px;align-items:center;border:2px solid #fecaca;background:#fff7f7;border-radius:12px;padding:12px 14px} .co-asgrow.late{border-color:#dc2626} .co-asgmeta{font-size:12px;color:#64748b;margin-top:2px} .co-asgnote{font-size:12.5px;color:#334155;margin-top:4px}',
'@media (max-width:640px){.co{padding:16px;border-radius:14px} .co-q{font-size:17px} .co-pair{grid-template-columns:1fr} .co-tl{grid-template-columns:1fr 90px 44px}}'
].join('\n'); document.head.appendChild(st); }
function coEsc(s){ return String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
// Fehler lesbar machen: supabase-js meldet bei 4xx/5xx nur „non-2xx status code“; die eigentliche Meldung steht im Antwort-Body.
function coCall(body){ if(_coCtx.preview){ body=Object.assign({},body,{preview:true,project_id:_coCtx.pid}); }
  return sb.functions.invoke('coach-session',{body:body}).then(function(res){
    if(res.error){ var ctx=res.error.context; var st=ctx&&ctx.status;
      if(ctx&&typeof ctx.json==='function'){ return ctx.clone().json().then(function(j){ var m=(j&&(j.error||j.message))||res.error.message; console.error('[coach] '+(st||'')+' '+m, body); throw new Error(m+(st?' ('+st+')':'')); },function(){ console.error('[coach] '+(st||''), res.error); throw new Error(res.error.message+(st?' ('+st+')':'')); }); }
      console.error('[coach]', res.error); throw res.error; }
    if(res.data&&res.data.error) throw new Error(res.data.error); return res.data; }); }
function renderCoach(){
  coInjectCss(); if(typeof kbInjectCss==='function') kbInjectCss();
  var host=document.getElementById(_coCtx.hostId||'vCoach'); if(!host)return;
  var pid=_coCtx.pid;
  host.innerHTML='<div style="padding:20px;color:#8b93a8;font-size:14px">Lädt…</div>';
  var availP=_coCtx.preview ? sb.from('coach_questions').select('topic,zielgebiet').eq('project_id',pid).eq('status','active').limit(5000).then(function(r){ var rows=r.data||[]; var t={},z={}; rows.forEach(function(x){ t[x.topic]=1; if(x.zielgebiet) z[x.zielgebiet]=1; }); return {data:{questions:rows.length,topics:Object.keys(t).sort(),zielgebiete:Object.keys(z).sort(),today:0,assignments:[]}}; }) : sb.rpc('coach_available');
  Promise.all([availP, sb.from('partner_agents').select('*').eq('project_id',pid).maybeSingle()]).then(function(r){
    _coAvail=(r[0]&&r[0].data)||{}; _coAg=(r[1]&&r[1].data)||(_coCtx.fallbackAgent?_coCtx.fallbackAgent(pid):(typeof kbFallbackAgent==='function'?kbFallbackAgent(pid):{name:'Coach',color:'#0F5661'}));
    if(!_coAvail.questions){ host.innerHTML='<div class="co"><div class="kbc-empty">Für dein Projekt liegt noch kein Übungsstoff vor. Sobald Wissen im Wissensspeicher liegt, erscheint der Coach hier.</div></div>'; return; }
    coStartScreen(host);
  }).catch(function(e){ host.innerHTML='<div class="co"><div class="kbc-err">Coach nicht erreichbar: '+coEsc(e.message||e)+'</div></div>'; });
}
var _coSet={mode:'daily',topic:'',zielgebiet:'',minutes:5,difficulty:'mix',kinds:'auto'};
function coStartScreen(host){
  var ag=_coAg, a=_coAvail, s=_coSet; var name=coEsc(ag.name||'Coach');
  var greet=_coCtx.preview?'Probelauf: dieselbe Einheit, die die Mitarbeiter bekommen. Nichts wird gespeichert.':(a.today>0?('Du hast heute schon '+a.today+' Einheit'+(a.today>1?'en':'')+' gemacht. Noch eine?'):'Heute noch nicht geübt. Fünf Minuten reichen.');
  var asg=(a.assignments||[]);
  var asgHtml=asg.length?'<div class="co-lbl" style="color:#b91c1c">Pflichteinheiten · '+asg.length+' offen</div><div class="co-asg">'+asg.map(function(x){ var due=x.due_date?new Date(x.due_date+'T00:00:00').toLocaleDateString('de-DE'):null; return '<div class="co-asgrow'+(x.overdue?' late':'')+'"><div style="flex:1;min-width:0"><b>'+coEsc(x.topic||(x.zielgebiet?'Vor dem Gespräch: '+x.zielgebiet:'Mix aus allem'))+'</b><div class="co-asgmeta">'+x.minutes+' Min · '+({mix:'gemischt',leicht:'leicht',mittel:'mittel',schwer:'schwer'}[x.difficulty]||x.difficulty)+(due?' · bis '+due+(x.overdue?' (überfällig)':''):'')+(x.assigned_by_name?' · von '+coEsc(x.assigned_by_name):'')+'</div>'+(x.note?'<div class="co-asgnote">„'+coEsc(x.note)+'“</div>':'')+'</div><button class="co-btn co-asgo" data-id="'+x.id+'">Jetzt machen</button></div>'; }).join('')+'</div>':'';
  var topics=(a.topics||[]), zgs=(a.zielgebiete||[]);
  host.innerHTML='<div class="co" style="--acc:'+(ag.color||'#0F5661')+'">'
    +'<div class="co-hd"><div class="kbc-orb" style="width:64px;height:64px">'+coAvatar(ag,64)+'</div><div><div class="kbc-ttl">'+name+' coacht</div><div class="kbc-sub">'+coEsc(greet)+' Ich frage aus unseren Unterlagen, du antwortest, ich sage dir sofort, was stimmt.</div></div></div>'
    +asgHtml
    +'<div class="co-lbl">'+(asg.length?'Oder frei üben':'Womit anfangen?')+'</div><div class="co-modes">'
    +'<button class="co-mode'+(s.mode==='daily'?' on':'')+'" data-m="daily"><b>Tageseinheit</b><span>Mix aus allem, deine schwachen Themen zuerst</span></button>'
    +'<button class="co-mode'+(s.mode==='topic'?' on':'')+'" data-m="topic"><b>Thema üben</b><span>Gesprächsführung, Stornierung, Peakwork …</span></button>'
    +'<button class="co-mode'+(s.mode==='sprint'?' on':'')+'" data-m="sprint"><b>Vor dem Gespräch</b><span>Ein Zielgebiet, zwei Minuten, das Wichtigste</span></button></div>'
    +'<div id="coTopic" style="display:'+(s.mode==='topic'?'block':'none')+'"><div class="co-lbl">Thema</div><select class="co-sel" id="coTopicSel"><option value="">Zufall</option>'+topics.map(function(t){ return '<option value="'+coEsc(t)+'"'+(s.topic===t?' selected':'')+'>'+coEsc(t)+'</option>'; }).join('')+'</select></div>'
    +'<div id="coZg" style="display:'+(s.mode==='sprint'?'block':'none')+'"><div class="co-lbl">Zielgebiet</div><select class="co-sel" id="coZgSel"><option value="">Zufällig</option>'+zgs.map(function(t){ return '<option value="'+coEsc(t)+'"'+(s.zielgebiet===t?' selected':'')+'>'+coEsc(t)+'</option>'; }).join('')+'</select></div>'
    +'<div class="co-lbl">Dauer</div><div class="co-row" id="coMin">'+[2,5,10,15].map(function(m){ return '<button class="co-chip'+(s.minutes===m?' on':'')+'" data-v="'+m+'">'+m+' Min</button>'; }).join('')+'</div>'
    +'<div class="co-lbl">Schwierigkeit</div><div class="co-row" id="coDiff">'+[['mix','Gemischt'],['leicht','Leicht'],['mittel','Mittel'],['schwer','Schwer']].map(function(d){ return '<button class="co-chip'+(s.difficulty===d[0]?' on':'')+'" data-v="'+d[0]+'">'+d[1]+'</button>'; }).join('')+'</div>'
    +'<div class="co-lbl">Wie gefragt wird</div><div class="co-row" id="coKind">'+[['auto','Passend zum Stoff'],['mc','Auswahl'],['gap','Eintippen'],['free','Situationen (Freitext)']].map(function(d){ return '<button class="co-chip'+(s.kinds===d[0]?' on':'')+'" data-v="'+d[0]+'">'+d[1]+'</button>'; }).join('')+'</div>'
    +'<button class="co-go" id="coGo">Einheit starten</button>'
    +'<div class="co-hist" id="coHist"></div></div>';
  host.querySelectorAll('.co-mode').forEach(function(b){ b.addEventListener('click',function(){ s.mode=b.getAttribute('data-m'); if(s.mode==='sprint'&&s.minutes>5)s.minutes=2; coStartScreen(host); }); });
  var chip=function(id,key){ host.querySelectorAll('#'+id+' .co-chip').forEach(function(b){ b.addEventListener('click',function(){ var v=b.getAttribute('data-v'); s[key]=(key==='minutes')?Number(v):v; coStartScreen(host); }); }); };
  chip('coMin','minutes'); chip('coDiff','difficulty'); chip('coKind','kinds');
  var ts=document.getElementById('coTopicSel'); if(ts) ts.addEventListener('change',function(){ s.topic=ts.value; });
  var zs=document.getElementById('coZgSel'); if(zs) zs.addEventListener('change',function(){ s.zielgebiet=zs.value; });
  document.getElementById('coGo').addEventListener('click',function(){ coStart(host); });
  host.querySelectorAll('.co-asgo').forEach(function(b){ b.addEventListener('click',function(){ coStart(host,b.getAttribute('data-id')); }); });
  if(!_coCtx.preview) coLoadHist();
}
function coLoadHist(){ var el=document.getElementById('coHist'); if(!el)return;
  coCall({action:'history'}).then(function(h){ _coHist=h; var ss=h.sessions||[]; if(!ss.length){ el.innerHTML=''; return; }
    var topics=h.topics||{}; var keys=Object.keys(topics).filter(function(k){return topics[k].max>0;}).sort(function(a,b){ return topics[a].points/topics[a].max-topics[b].points/topics[b].max; });
    var html='<div class="co-lbl">Deine letzten 30 Tage</div>';
    if(keys.length){ html+='<div class="co-tr">'+keys.slice(0,8).map(function(k){ var p=topics[k].points/topics[k].max; var col=p>=.8?'#059669':p>=.6?'#d97706':'#dc2626'; return '<div class="co-tl"><div>'+coEsc(k)+'</div><div class="co-bar"><i style="width:'+Math.round(p*100)+'%;background:'+col+'"></i></div><div style="text-align:right;font-family:ui-monospace,monospace;font-weight:700;color:'+col+'">'+Math.round(p*100)+'%</div></div>'; }).join('')+'</div>'; }
    html+='<div class="co-lbl">Letzte Einheiten</div>'+ss.slice(0,8).map(function(x){ var d=new Date(x.finished_at||x.started_at); var mode={daily:'Tageseinheit',topic:'Thema: '+((x.settings||{}).topic||'Zufall'),sprint:'Vor dem Gespräch'+((x.settings||{}).zielgebiet?': '+(x.settings||{}).zielgebiet:'')}[(x.settings||{}).mode]||'Einheit'; var sc=Math.round((x.score||0)*100); return '<div class="co-hrow"><span class="p" style="color:'+(sc>=80?'#059669':sc>=60?'#d97706':'#dc2626')+'">'+sc+'%</span><span class="d">'+d.toLocaleDateString('de-DE')+'</span><span class="m">'+coEsc(mode)+' · '+(x.max_points||0)+' Fragen</span></div>'; }).join('');
    el.innerHTML=html; }).catch(function(){ el.innerHTML=''; });
}
function coStart(host,assignmentId){ var s=_coSet; var go=document.getElementById('coGo'); if(go){ go.disabled=true; go.textContent='Stelle Einheit zusammen…'; }
  var kinds=s.kinds==='auto'?null:(s.kinds==='mc'?['mc','match']:s.kinds==='gap'?['gap','order']:['free']);
  var body=assignmentId?{action:'start',assignment_id:assignmentId}:{action:'start',settings:{mode:s.mode,topic:s.mode==='topic'?s.topic:null,zielgebiet:s.mode==='sprint'?s.zielgebiet:null,minutes:s.minutes,difficulty:s.difficulty,kinds:kinds}};
  coCall(body)
    .then(function(r){ _coSess=r.session_id; _coQ=r.questions||[]; _coIdx=0; _coRes=[]; _coAssign=r.assignment||null; coRenderQ(host); })
    .catch(function(e){ if(go){ go.disabled=false; go.textContent='Einheit starten'; } alert('Konnte keine Einheit starten: '+(e.message||e)); });
}
function coProg(results){ return '<div class="co-prog">'+_coQ.map(function(q,i){ var r=results[i]; var c=i===_coIdx?'cur':(r==null?'':(r>=1?'ok':r>0?'half':'no')); return '<i class="'+c+'"></i>'; }).join('')+'</div>'; }
var _coRes=[];
function coRenderQ(host){
  var q=_coQ[_coIdx]; var ag=_coAg; if(!q){ coFinish(host); return; }
  _coT0=Date.now(); _coOrder=null; _coMatch={};
  var kindLbl={mc:'Auswahl',gap:'Eintippen',match:'Zuordnen',order:'Reihenfolge',free:'Situation'}[q.kind]||'';
  var body='';
  if(q.kind==='mc'){ body=(q.options||[]).map(function(o){ return '<button class="co-opt" data-k="'+coEsc(o.key)+'"><span class="k">'+coEsc(o.key)+'</span>'+coEsc(o.text)+'</button>'; }).join(''); }
  else if(q.kind==='gap'){ body='<input class="co-in" id="coGap" placeholder="Deine Antwort" autocomplete="off">'; }
  else if(q.kind==='free'){ body='<textarea class="co-in co-ta" id="coFree" placeholder="Was sagst oder tust du? In deinen Worten."></textarea>'; }
  else if(q.kind==='match'){ var L=(q.options||{}).left||[], R=(q.options||{}).right||[]; body=L.map(function(l,i){ return '<div class="co-pair"><div class="l">'+coEsc(l)+'</div><select class="co-sel co-msel" data-l="'+coEsc(l)+'"><option value="">…</option>'+R.map(function(r){ return '<option value="'+coEsc(r)+'">'+coEsc(r)+'</option>'; }).join('')+'</select></div>'; }).join(''); }
  else if(q.kind==='order'){ _coOrder=(q.options||[]).slice(); body='<div id="coOrd"></div>'; }
  host.innerHTML='<div class="co" style="--acc:'+(ag.color||'#0F5661')+'">'+coProg(_coRes)
    +(_coAssign?'<div class="co-meta" style="color:#b91c1c">Pflichteinheit'+(_coAssign.by?' von '+coEsc(_coAssign.by):'')+(_coAssign.note?': „'+coEsc(_coAssign.note)+'“':'')+'</div>':'')
    +'<div class="co-meta">Frage '+(_coIdx+1)+' von '+_coQ.length+' · <b>'+coEsc(q.topic)+'</b>'+(q.zielgebiet?' · '+coEsc(q.zielgebiet):'')+' · '+kindLbl+'</div>'
    +'<div class="co-q">'+coEsc(q.prompt)+'</div>'+body
    +'<div class="co-act"><button class="co-btn" id="coSubmit">Antworten</button><button class="co-btn sec" id="coSkip">Weiß ich nicht</button></div>'
    +'<div id="coFb"></div></div>';
  if(q.kind==='mc'){ host.querySelectorAll('.co-opt').forEach(function(b){ b.addEventListener('click',function(){ host.querySelectorAll('.co-opt').forEach(function(x){x.classList.remove('on');}); b.classList.add('on'); }); }); }
  if(q.kind==='order'){ coDrawOrder(); }
  var inp=document.getElementById('coGap')||document.getElementById('coFree'); if(inp){ inp.focus(); if(q.kind==='gap') inp.addEventListener('keydown',function(e){ if(e.key==='Enter') coSubmit(host,false); }); }
  document.getElementById('coSubmit').addEventListener('click',function(){ coSubmit(host,false); });
  document.getElementById('coSkip').addEventListener('click',function(){ coSubmit(host,true); });
}
function coDrawOrder(){ var el=document.getElementById('coOrd'); if(!el)return; el.innerHTML=_coOrder.map(function(t,i){ return '<div class="co-ord"><span class="n">'+(i+1)+'</span><span class="t">'+coEsc(t)+'</span><button data-i="'+i+'" data-d="-1"'+(i===0?' disabled':'')+'>↑</button><button data-i="'+i+'" data-d="1"'+(i===_coOrder.length-1?' disabled':'')+'>↓</button></div>'; }).join('');
  el.querySelectorAll('button').forEach(function(b){ b.addEventListener('click',function(){ var i=Number(b.getAttribute('data-i')), d=Number(b.getAttribute('data-d')); var j=i+d; if(j<0||j>=_coOrder.length)return; var t=_coOrder[i]; _coOrder[i]=_coOrder[j]; _coOrder[j]=t; coDrawOrder(); }); }); }
function coSubmit(host,skip){ if(_coBusy)return; var q=_coQ[_coIdx]; var ans={};
  if(!skip){
    if(q.kind==='mc'){ var on=host.querySelector('.co-opt.on'); if(!on){ return; } ans={key:on.getAttribute('data-k')}; }
    else if(q.kind==='gap'){ ans={text:(document.getElementById('coGap')||{}).value||''}; if(!ans.text.trim())return; }
    else if(q.kind==='free'){ ans={text:(document.getElementById('coFree')||{}).value||''}; if(!ans.text.trim())return; }
    else if(q.kind==='match'){ var pairs={}; host.querySelectorAll('.co-msel').forEach(function(s){ pairs[s.getAttribute('data-l')]=s.value; }); ans={pairs:pairs}; }
    else if(q.kind==='order'){ ans={sequence:_coOrder.slice()}; }
  }
  _coBusy=true; var btn=document.getElementById('coSubmit'); if(btn){ btn.disabled=true; btn.textContent=q.kind==='free'?(_coAg.name||'Coach')+' liest…':'…'; }
  var secs=Math.round((Date.now()-_coT0)/1000);
  coCall({action:'answer',session_id:_coSess,question_id:q.id,answer:ans,seconds:secs}).then(function(r){
    _coBusy=false; _coRes[_coIdx]=r.points; coShowFb(host,q,r,ans);
  }).catch(function(e){ _coBusy=false; if(btn){ btn.disabled=false; btn.textContent='Antworten'; } alert('Antwort konnte nicht bewertet werden: '+(e.message||e)); });
}
function coShowFb(host,q,r,ans){
  var p=Number(r.points||0); var cls=p>=1?'ok':p>0?'half':'no'; var head=p>=1?'Richtig':p>0?'Teilweise richtig':'Nicht ganz';
  var sol='';
  if(q.kind==='mc'){ var key=(r.solution||{}).key; host.querySelectorAll('.co-opt').forEach(function(b){ var k=b.getAttribute('data-k'); if(k===key)b.classList.add('right'); else if(ans.key===k)b.classList.add('wrong'); b.disabled=true; }); }
  else if(q.kind==='gap'){ sol='Richtig: '+((r.solution||{}).accept||[])[0]; }
  else if(q.kind==='match'){ var pr=(r.solution||{}).pairs||{}; sol=Object.keys(pr).map(function(k){ return k+' → '+pr[k]; }).join('\n'); }
  else if(q.kind==='order'){ sol=((r.solution||{}).sequence||[]).map(function(s,i){ return (i+1)+'. '+s; }).join('\n'); }
  var rub=''; if(q.kind==='free'&&r.rubric){ rub='<ul class="co-rub">'+(r.rubric.hits||[]).map(function(h){ return '<li class="y">✓ '+coEsc(h)+'</li>'; }).join('')+(r.rubric.missing||[]).map(function(m){ return '<li class="m">→ fehlte: '+coEsc(m)+'</li>'; }).join('')+'</ul>'; }
  var fb=document.getElementById('coFb'); fb.innerHTML='<div class="co-fb '+cls+'"><div class="h">'+head+(q.kind!=='mc'&&q.kind!=='free'?' · '+Math.round(p*100)+' %':'')+'</div>'
    +(r.feedback&&r.feedback!=='Richtig.'?'<div class="x">'+coEsc(r.feedback)+'</div>':'')+rub
    +(sol?'<div class="x" style="margin-top:6px">'+coEsc(sol)+'</div>':'')
    +(r.explanation&&q.kind!=='mc'?'<div class="x" style="margin-top:6px;color:#334155">'+coEsc(r.explanation)+'</div>':'')
    +(r.source?'<div class="s">Quelle: '+coEsc(r.source)+'</div>':'')
    +(_coCtx.preview?'':'<button class="flag" id="coFlag">Frage unklar oder falsch? Melden</button>')+'</div>';
  if(document.getElementById('coFlag')) document.getElementById('coFlag').addEventListener('click',function(){ var note=prompt('Was ist unklar oder falsch an dieser Frage?'); if(note===null)return; sb.rpc('coach_flag',{p_answer:r.answer_id,p_note:note}).then(function(){ var b=document.getElementById('coFlag'); if(b)b.textContent='Gemeldet, danke.'; }); });
  var act=host.querySelector('.co-act'); act.innerHTML='<button class="co-btn" id="coNext">'+(_coIdx+1<_coQ.length?'Weiter':'Ergebnis')+'</button>';
  document.getElementById('coNext').addEventListener('click',function(){ _coIdx++; coRenderQ(host); }); document.getElementById('coNext').focus();
}
function coFinish(host){ var ag=_coAg; host.innerHTML='<div class="co" style="--acc:'+(ag.color||'#0F5661')+'"><div style="padding:20px;color:#64748b">Werte aus…</div></div>';
  coCall(_coCtx.preview?{action:'finish',results:_coQ.map(function(q,i){ return {topic:q.topic,points:_coRes[i]||0}; })}:{action:'finish',session_id:_coSess}).then(function(r){ var sc=Math.round((r.score||0)*100); var tp=r.topics||{}; var keys=Object.keys(tp);
    var msg= (_coAssign?'Pflichteinheit erledigt. ':'')+(sc>=90?'Stark. Das sitzt.': sc>=70?'Gut. Ein paar Stellen üben wir nochmal.': sc>=50?'Solide Basis, da ist noch Luft.':'Kein Drama. Genau dafür ist der Coach da.');
    host.innerHTML='<div class="co" style="--acc:'+(ag.color||'#0F5661')+'"><div class="co-hd"><div class="kbc-orb" style="width:56px;height:56px">'+coAvatar(ag,56)+'</div><div><div class="kbc-ttl">'+coEsc(ag.name||'Coach')+'</div><div class="kbc-sub">'+coEsc(msg)+'</div></div></div>'
      +'<div class="co-res"><div class="big">'+Math.round(r.points*10)/10+' / '+r.max+'</div><div class="sub">'+sc+' % richtig'+(r.strong?' · stark bei '+coEsc(r.strong):'')+'</div></div>'
      +(keys.length?'<div class="co-tr">'+keys.map(function(k){ var p=tp[k].points/tp[k].max; var col=p>=.8?'#059669':p>=.5?'#d97706':'#dc2626'; return '<div class="co-tl"><div>'+coEsc(k)+'</div><div class="co-bar"><i style="width:'+Math.round(p*100)+'%;background:'+col+'"></i></div><div style="text-align:right;font-family:ui-monospace,monospace;font-weight:700;color:'+col+'">'+Math.round(p*100)+'%</div></div>'; }).join('')+'</div>':'')
      +(r.recommend?'<div class="co-fb half" style="margin-top:16px"><div class="h">Das üben wir als Nächstes</div><div class="x">'+coEsc(r.recommend)+'</div></div>':'')
      +'<div class="co-act">'+(r.recommend?'<button class="co-btn" id="coAgain">'+coEsc(r.recommend)+' üben</button>':'')+'<button class="co-btn sec" id="coHome">Zur Übersicht</button></div></div>';
    var ag2=document.getElementById('coAgain'); if(ag2) ag2.addEventListener('click',function(){ _coSet.mode='topic'; _coSet.topic=r.recommend; _coRes=[]; coStart(host); });
    document.getElementById('coHome').addEventListener('click',function(){ _coRes=[]; renderCoach(); });
  }).catch(function(e){ host.innerHTML='<div class="co"><div class="kbc-err">'+coEsc(e.message||e)+'</div></div>'; });
}
// Menüpunkt nur zeigen, wenn es für das Projekt Übungsstoff gibt; Marker „heute noch nicht geübt“.
function coBootNav(){ sb.rpc('coach_available').then(function(r){ var a=(r&&r.data)||{}; var btn=document.querySelector('[data-view="Coach"]'); if(!btn)return; if(!a.questions){ btn.style.display='none'; return; } btn.style.display=''; var dot=document.getElementById('coNavDot'); if(dot){ var open=(a.assignments||[]).length; dot.style.display=(open>0||!a.today)?'inline-block':'none'; dot.style.background=open>0?'#dc2626':'#F5B301'; dot.title=open>0?(open+' Pflichteinheit'+(open>1?'en':'')+' offen'):'heute noch nicht geübt'; } }).catch(function(){}); }

