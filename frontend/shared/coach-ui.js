/* ═══ Coach-Oberfläche v2 (geteilt: Mitarbeiter-Portal = echte Einheiten, HR-Portal = Probelauf). Vanilla, kein Framework.
   Aufbau wie eine Schulung, nicht wie ein Formular: 3 Schritte (Was · Wie · Wie lange) → Startkarte (Thema, Stufe, Dauer,
   Anzahl, Arten) → Fokus-Modus (Vollbild, Uhr rückwärts, eine Frage, Tastatur A-D/Enter, Abbrechen oben rechts) →
   Auflösung, die weiterhilft (warum falsch, Merk-Satz, Musterantwort, Kernpunkte) → Ergebnis (Zeit, Themen, Streak, fällig).
   Braucht: window.sb (Supabase-Client), Host-Element (_coCtx.hostId), optional kbAvatarHtml/kbInjectCss aus dem Portal.
   Eingebunden per <script src="shared/coach-ui.js?v=__BUILD_ID__">. ═══ */
var _coAvail=null,_coAg=null,_coSess=null,_coQ=[],_coIdx=0,_coT0=0,_coBusy=false,_coOrder=null,_coAssign=null,_coFill=null,_coRes=[],_coStart=0,_coTimer=null,_coMinutes=5,_coOver=false,_coKey=null;
var _coCtx={pid:null,agent:null,preview:false,hostId:'vCoach',avatarHtml:null,fallbackAgent:null,greet:null};
var _coSet={mode:'daily',topic:'',zielgebiet:'',minutes:5,difficulty:'mix',kinds:'auto',step:1};
function coSetCtx(c){ for(var k in c) _coCtx[k]=c[k]; }
function coAvatar(ag,size){ try{ if(_coCtx.avatarHtml) return _coCtx.avatarHtml(ag,size); if(typeof kbAvatarHtml==='function') return kbAvatarHtml(ag,size); }catch(e){} return '<div style="width:100%;height:100%;border-radius:50%;background:'+(ag&&ag.color||'#0F5661')+';color:#fff;display:flex;align-items:center;justify-content:center;font-weight:800">'+String((ag&&ag.name)||'C').charAt(0)+'</div>'; }
function coEsc(s){ return String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
function coCountFor(m){ return Math.max(3,Math.min(20,Math.round(m*1.2))); }
function coInjectCss(){ if(document.getElementById('cocss'))return; var st=document.createElement('style'); st.id='cocss'; st.textContent=[
'.co{--acc:#0F5661;background:#fff;border:1px solid color-mix(in srgb, var(--acc,#0F5661) 22%, #e2e8f0);border-radius:20px;padding:22px;box-shadow:0 8px 26px rgba(15,23,42,.06);font-family:Inter,system-ui,sans-serif;color:#0f172a}',
'.co *{box-sizing:border-box} .co-hd{display:flex;gap:16px;align-items:center;margin-bottom:14px} .co-orb{flex:0 0 auto;width:60px;height:60px;border-radius:50%;overflow:hidden;background:#fff;border:3px solid color-mix(in srgb, var(--acc,#0F5661) 35%, #fff)} .co-orb svg,.co-orb img{width:100%;height:100%;display:block;object-fit:cover}',
'.co-ttl{font-size:19px;font-weight:800;line-height:1.2} .co-sub{font-size:13.5px;color:#475569;margin-top:2px;line-height:1.45}',
'.co-lbl{font-size:11.5px;font-weight:800;text-transform:uppercase;letter-spacing:.06em;color:color-mix(in srgb, var(--acc,#0F5661) 70%, #334155);margin:16px 0 8px}',
'.co-steps{display:flex;gap:6px;align-items:center;margin:4px 0 14px;font-size:12px;color:#64748b} .co-steps b{display:inline-flex;align-items:center;gap:6px;padding:4px 10px;border-radius:999px;background:#f1f5f9;font-weight:700;color:#334155} .co-steps b.on{background:var(--acc,#0F5661);color:#fff} .co-steps b.done{background:color-mix(in srgb, var(--acc,#0F5661) 14%, #fff);color:var(--acc,#0F5661)}',
'.co-modes{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:10px} .co-mode{border:2px solid #e2e8f0;border-radius:14px;padding:14px;cursor:pointer;background:#fff;text-align:left;font-family:inherit} .co-mode.on{border-color:var(--acc,#0F5661);background:color-mix(in srgb, var(--acc,#0F5661) 7%, #fff)} .co-mode b{display:block;font-size:15px;color:#0f172a} .co-mode span{font-size:12.5px;color:#64748b}',
'.co-row{display:flex;gap:8px;flex-wrap:wrap;align-items:center} .co-chip{border:1.5px solid #e2e8f0;border-radius:999px;padding:7px 14px;font-size:13px;font-weight:600;background:#fff;cursor:pointer;font-family:inherit;color:#334155;min-height:40px} .co-chip.on{border-color:var(--acc,#0F5661);background:var(--acc,#0F5661);color:#fff}',
'.co-sel{padding:9px 12px;border:1.5px solid #e2e8f0;border-radius:10px;font-size:14px;font-family:inherit;background:#fff;min-height:42px;max-width:100%}',
'.co-nav{display:flex;gap:8px;margin-top:18px;flex-wrap:wrap} .co-btn{padding:12px 18px;border-radius:12px;border:none;background:var(--acc,#0F5661);color:#fff;font-weight:800;font-size:15px;cursor:pointer;font-family:inherit;min-height:46px} .co-btn.sec{background:#fff;color:#334155;border:1.5px solid #e2e8f0} .co-btn.big{width:100%;padding:15px;font-size:17px;border-radius:14px} .co-btn:disabled{opacity:.5}',
'.co-card{border:2px solid color-mix(in srgb, var(--acc,#0F5661) 40%, #e2e8f0);border-radius:16px;padding:18px;background:color-mix(in srgb, var(--acc,#0F5661) 5%, #fff)} .co-card h3{margin:0 0 10px;font-size:20px;font-weight:800} .co-facts{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px} .co-fact{background:#fff;border:1px solid #e2e8f0;border-radius:12px;padding:10px 12px} .co-fact .k{font-size:10.5px;font-weight:800;text-transform:uppercase;letter-spacing:.05em;color:#64748b} .co-fact .v{font-size:17px;font-weight:800;margin-top:2px}',
'.co-fill{margin-top:12px;padding:9px 12px;border-radius:10px;background:#fffbeb;border:1px solid #fde68a;color:#92400e;font-size:12.5px}',
'.co-asg{display:flex;flex-direction:column;gap:8px} .co-asgrow{display:flex;gap:12px;align-items:center;border:2px solid #fecaca;background:#fff7f7;border-radius:12px;padding:12px 14px;flex-wrap:wrap} .co-asgrow.late{border-color:#dc2626} .co-asgmeta{font-size:12px;color:#64748b;margin-top:2px} .co-asgnote{font-size:12.5px;color:#334155;margin-top:4px}',
'.co-tr{display:flex;flex-direction:column;gap:8px;margin-top:14px} .co-tl{display:grid;grid-template-columns:1fr 120px 52px;gap:10px;align-items:center;font-size:13px} .co-bar{height:8px;border-radius:4px;background:#eef2f4;overflow:hidden} .co-bar i{display:block;height:100%}',
'.co-hist{margin-top:18px} .co-hrow{display:flex;gap:10px;align-items:center;padding:8px 0;border-top:1px solid #eef2f7;font-size:13px} .co-hrow .p{font-family:ui-monospace,monospace;font-weight:700;width:60px} .co-hrow .d{color:#64748b;width:110px} .co-hrow .m{flex:1;color:#334155}',
'.co-kpis{display:flex;gap:18px;flex-wrap:wrap;margin-top:6px} .co-kpi b{display:block;font-size:22px;font-family:ui-monospace,monospace} .co-kpi span{font-size:11px;text-transform:uppercase;letter-spacing:.05em;color:#64748b;font-weight:700}',
/* Fokus-Modus */
'.co-focus{position:fixed;inset:0;z-index:100000;background:#F5F6F8;overflow:auto;font-family:Inter,system-ui,sans-serif;color:#0f172a;--acc:#0F5661} .co-focus *{box-sizing:border-box}',
'.co-fbar{position:sticky;top:0;z-index:2;display:flex;align-items:center;gap:14px;padding:12px 18px;background:#fff;border-bottom:1px solid #e2e8f0}',
'.co-fbar .who{display:flex;align-items:center;gap:10px;min-width:0} .co-fbar .who .n{font-weight:800;font-size:14px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis} .co-fbar .who .s{font-size:11.5px;color:#64748b}',
'.co-clock{margin-left:auto;display:flex;align-items:center;gap:10px} .co-clock svg{display:block} .co-clock .t{font-family:ui-monospace,monospace;font-weight:800;font-size:16px;min-width:52px;text-align:right} .co-clock.over .t{color:#dc2626}',
'.co-quit{white-space:nowrap;border:1.5px solid #e2e8f0;background:#fff;color:#334155;border-radius:10px;padding:8px 12px;font-weight:700;cursor:pointer;font-family:inherit;font-size:13px} .co-quit:hover{border-color:#dc2626;color:#dc2626}',
'.co-prog{display:flex;gap:4px;padding:10px 18px 0;max-width:820px;margin:0 auto} .co-prog i{flex:1;height:6px;border-radius:3px;background:#e2e8f0} .co-prog i.ok{background:#059669} .co-prog i.half{background:#d97706} .co-prog i.no{background:#dc2626} .co-prog i.cur{background:var(--acc,#0F5661)}',
'.co-stage{max-width:820px;margin:0 auto;padding:22px 18px 60px}',
'.co-meta{font-size:12px;color:#64748b;font-weight:600;margin-bottom:8px} .co-meta b{color:var(--acc,#0F5661)} .co-meta .kind{display:inline-block;padding:1px 8px;border-radius:6px;background:#eef2f4;color:#334155;margin-left:6px}',
'.co-q{font-size:22px;font-weight:700;color:#0f172a;line-height:1.35;margin:0 0 18px;white-space:pre-wrap}',
'.co-opt{display:flex;align-items:flex-start;gap:12px;width:100%;text-align:left;border:2px solid #e2e8f0;border-radius:14px;padding:14px 16px;margin-bottom:10px;background:#fff;font-size:16px;font-family:inherit;color:#0f172a;cursor:pointer;line-height:1.45}',
'.co-opt:hover{border-color:color-mix(in srgb, var(--acc,#0F5661) 50%, #e2e8f0)} .co-opt.on{border-color:var(--acc,#0F5661);background:color-mix(in srgb, var(--acc,#0F5661) 8%, #fff)} .co-opt.right{border-color:#059669;background:#ecfdf5} .co-opt.wrong{border-color:#dc2626;background:#fef2f2}',
'.co-opt .k{flex:0 0 auto;width:30px;height:30px;border-radius:50%;background:#f1f5f9;color:#334155;font-weight:800;text-align:center;line-height:30px;font-size:13px} .co-opt.on .k{background:var(--acc,#0F5661);color:#fff} .co-opt.right .k{background:#059669;color:#fff} .co-opt.wrong .k{background:#dc2626;color:#fff} .co-opt .why{display:block;font-size:12.5px;color:#64748b;margin-top:3px}',
'.co-in{width:100%;padding:14px 16px;border:2px solid #e2e8f0;border-radius:14px;font-size:17px;font-family:inherit;min-height:52px;background:#fff} .co-in:focus{outline:none;border-color:var(--acc,#0F5661)} .co-ta{min-height:130px;resize:vertical;line-height:1.5}',
'.co-pair{display:grid;grid-template-columns:1fr 1fr;gap:10px;align-items:center;margin-bottom:10px} .co-pair .l{font-weight:700;font-size:15px}',
'.co-ord{display:flex;align-items:center;gap:10px;border:2px solid #e2e8f0;border-radius:12px;padding:12px 14px;margin-bottom:8px;background:#fff;font-size:15px} .co-ord .n{width:28px;height:28px;border-radius:50%;background:var(--acc,#0F5661);color:#fff;font-weight:800;text-align:center;line-height:28px;flex:0 0 auto} .co-ord .t{flex:1} .co-ord button{border:1px solid #e2e8f0;background:#fff;border-radius:8px;width:38px;height:38px;cursor:pointer;font-size:16px}',
'.co-act{display:flex;gap:10px;margin-top:18px;flex-wrap:wrap;align-items:center} .co-hint{font-size:12px;color:#94a3b8;margin-left:auto}',
'.co-fb{margin-top:18px;padding:16px 18px;border-radius:16px;border:1px solid} .co-fb.ok{background:#ecfdf5;border-color:#a7f3d0} .co-fb.half{background:#fffbeb;border-color:#fde68a} .co-fb.no{background:#fef2f2;border-color:#fecaca}',
'.co-fb .h{font-size:16px;font-weight:800;margin-bottom:6px} .co-fb .x{font-size:15px;color:#0f172a;line-height:1.55;white-space:pre-wrap} .co-fb .model{margin-top:10px;padding:12px 14px;border-radius:12px;background:#fff;border:1px dashed color-mix(in srgb, var(--acc,#0F5661) 45%, #cbd5e1)} .co-fb .model .l{font-size:11px;font-weight:800;text-transform:uppercase;letter-spacing:.05em;color:var(--acc,#0F5661);margin-bottom:4px} .co-fb .model .t{font-size:15px;font-style:italic;line-height:1.5}',
'.co-fb .s{font-size:11.5px;color:#64748b;margin-top:10px} .co-fb .flag{margin-top:8px;border:none;background:transparent;color:#64748b;font-size:12px;cursor:pointer;text-decoration:underline;font-family:inherit;padding:0} .co-fb .next{font-size:12px;color:#64748b;margin-top:6px}',
'.co-rub{margin:8px 0 0;padding-left:0;list-style:none;font-size:14px} .co-rub li{margin:3px 0} .co-rub .y{color:#059669} .co-rub .m{color:#b45309}',
'.co-res{text-align:center;padding:10px 0} .co-res .big{font-size:56px;font-weight:800;color:var(--acc,#0F5661);line-height:1;font-variant-numeric:tabular-nums} .co-res .sub{font-size:15px;color:#334155;margin-top:8px}',
'.co-over{position:fixed;inset:0;z-index:100001;background:rgba(15,23,42,.45);display:flex;align-items:center;justify-content:center;padding:20px} .co-over .box{background:#fff;border-radius:16px;padding:22px 24px;max-width:420px;width:100%;text-align:center} .co-over .box h3{margin:0 0 6px;font-size:18px} .co-over .box p{margin:0 0 14px;color:#475569;font-size:14px}',
'@media (max-width:640px){.co{padding:16px;border-radius:14px} .co-fbar{padding:10px 12px;gap:10px} .co-quit{padding:8px 10px} .co-q{font-size:19px} .co-pair{grid-template-columns:1fr} .co-tl{grid-template-columns:1fr 90px 44px} .co-stage{padding:16px 14px 60px} .co-fbar .who .s{display:none}}'
].join('\n'); document.head.appendChild(st); }
// Fehler lesbar machen: supabase-js meldet bei 4xx/5xx nur „non-2xx status code“; die eigentliche Meldung steht im Antwort-Body.
function coCall(body){ if(_coCtx.preview){ body=Object.assign({},body,{preview:true,project_id:_coCtx.pid}); }
  return sb.functions.invoke('coach-session',{body:body}).then(function(res){
    if(res.error){ var ctx=res.error.context; var st=ctx&&ctx.status;
      if(ctx&&typeof ctx.json==='function'){ return ctx.clone().json().then(function(j){ var m=(j&&(j.error||j.message))||res.error.message; console.error('[coach] '+(st||'')+' '+m, body); throw new Error(m); },function(){ console.error('[coach] '+(st||''), res.error); throw new Error(res.error.message+(st?' ('+st+')':'')); }); }
      console.error('[coach]', res.error); throw res.error; }
    if(res.data&&res.data.error) throw new Error(res.data.error); return res.data; }); }

// ── Verfügbarkeit: die Auswahl richtet sich nach dem Stoff ──
function coScope(rows,s){ var zg=(s.mode==='sprint'&&s.zielgebiet)?s.zielgebiet.toLowerCase():null; return rows.filter(function(r){ if(s.mode==='topic'&&s.topic) return r.t===s.topic; if(zg) return (r.z||'').toLowerCase().indexOf(zg)>=0; return true; }); }
function coAvailFor(s){ var rows=(_coAvail&&_coAvail.matrix)||[]; var sc=coScope(rows,s); var sum=function(list){ return list.reduce(function(a,r){ return a+(r.n||0); },0); };
  var topics={}; rows.forEach(function(r){ topics[r.t]=(topics[r.t]||0)+r.n; }); var zgs={}; rows.forEach(function(r){ if(r.z) zgs[r.z]=(zgs[r.z]||0)+r.n; });
  var diffs={}; sc.forEach(function(r){ diffs[r.d]=(diffs[r.d]||0)+r.n; }); var kinds={}; sc.forEach(function(r){ if(s.difficulty==='mix'||r.d===s.difficulty) kinds[r.k]=(kinds[r.k]||0)+r.n; });
  var exact=sum(sc.filter(function(r){ return (s.difficulty==='mix'||r.d===s.difficulty)&&(s.kinds==='auto'||(s.kinds==='mc'?(r.k==='mc'||r.k==='match'):s.kinds==='gap'?(r.k==='gap'||r.k==='order'):r.k==='free')); }));
  return {topics:Object.keys(topics).sort(function(a,b){ return a.localeCompare(b,'de'); }).map(function(t){ return {t:t,n:topics[t]}; }), zgs:Object.keys(zgs).sort(function(a,b){ return a.localeCompare(b,'de'); }).map(function(z){ return {z:z,n:zgs[z]}; }), diffs:diffs, kinds:kinds, inScope:sum(sc), exact:exact}; }

function renderCoach(){
  coInjectCss(); if(typeof kbInjectCss==='function') kbInjectCss();
  var host=document.getElementById(_coCtx.hostId||'vCoach'); if(!host)return;
  var pid=_coCtx.pid;
  if(!pid){ host.innerHTML='<div class="co"><div class="co-sub">Für deinen Zugang ist noch kein Projekt hinterlegt. Bitte wende dich an HR.</div></div>'; return; }
  host.innerHTML='<div class="co"><div class="co-sub">Lade den Coach…</div></div>';
  var availP=_coCtx.preview ? sb.from('coach_questions').select('topic,zielgebiet,difficulty,kind').eq('project_id',pid).eq('status','active').limit(5000).then(function(r){ return sb.from('coach_settings').select('*').eq('project_id',pid).maybeSingle().then(function(sr){ var st=(sr&&sr.data)||{}; var hid=st.hidden_topics||[], ak=st.allowed_kinds||null; var rows=(r.data||[]).filter(function(x){ return hid.indexOf(x.topic)<0&&(!ak||ak.indexOf(x.kind)>=0); }); var t={},z={},m={}; rows.forEach(function(x){ t[x.topic]=1; if(x.zielgebiet) z[x.zielgebiet]=1; var k=[x.topic,x.zielgebiet||'',x.difficulty,x.kind].join('|'); m[k]=(m[k]||0)+1; }); var matrix=Object.keys(m).map(function(k){ var p=k.split('|'); return {t:p[0],z:p[1]||null,d:p[2],k:p[3],n:m[k]}; }); return {data:{questions:rows.length,topics:Object.keys(t).sort(),zielgebiete:Object.keys(z).sort(),matrix:matrix,settings:st,today:0,assignments:[]}}; }); }) : sb.rpc('coach_available');
  Promise.all([availP, sb.from('partner_agents').select('*').eq('project_id',pid).maybeSingle()]).then(function(r){
    _coAvail=(r[0]&&r[0].data)||{}; _coAg=(r[1]&&r[1].data)||(_coCtx.fallbackAgent?_coCtx.fallbackAgent(pid):(typeof kbFallbackAgent==='function'?kbFallbackAgent(pid):{name:'Coach',color:'#0F5661'}));
    var st=_coAvail.settings||{}; if(st.default_minutes&&!_coSet._touched) _coSet.minutes=st.default_minutes; if(st.default_difficulty&&!_coSet._touched) _coSet.difficulty=st.default_difficulty;
    if(!_coAvail.questions){ host.innerHTML='<div class="co"><div class="co-sub">Für dein Projekt liegt noch kein Übungsstoff vor. Sobald Wissen im Wissensspeicher liegt, erscheint der Coach hier.</div></div>'; return; }
    coStartScreen(host);
  }).catch(function(e){ host.innerHTML='<div class="co"><div class="co-sub" style="color:#b91c1c">Coach nicht erreichbar: '+coEsc(e.message||e)+'</div></div>'; });
}
// ── Startbild: Pflichteinheiten, dann 3 Schritte, dann Startkarte ──
function coStartScreen(host){
  var ag=_coAg, a=_coAvail, s=_coSet; var name=coEsc(ag.name||'Coach');
  var av0=coAvailFor(s); if(s.difficulty!=='mix'&&!av0.diffs[s.difficulty]) s.difficulty='mix'; var av1=coAvailFor(s); var kindOk={auto:true,mc:!!(av1.kinds.mc||av1.kinds.match),gap:!!(av1.kinds.gap||av1.kinds.order),free:!!av1.kinds.free}; if(!kindOk[s.kinds]) s.kinds='auto';
  var av=coAvailFor(s); var need=coCountFor(s.minutes);
  var greet=_coCtx.greet?_coCtx.greet:_coCtx.preview?'Probelauf: genau die Einheit, die die Mitarbeiter bekommen. Nichts wird gespeichert.':(a.today>0?('Heute schon '+a.today+' Einheit'+(a.today>1?'en':'')+'. Noch eine?'):'Heute noch nicht geübt. Fünf Minuten reichen.');
  var asg=(a.assignments||[]);
  var asgHtml=asg.length?'<div class="co-lbl" style="color:#b91c1c;margin-top:4px">Pflichteinheiten · '+asg.length+' offen</div><div class="co-asg">'+asg.map(function(x){ var due=x.due_date?new Date(x.due_date+'T00:00:00').toLocaleDateString('de-DE'):null; return '<div class="co-asgrow'+(x.overdue?' late':'')+'"><div style="flex:1;min-width:0"><b>'+coEsc(x.topic||(x.zielgebiet?'Vor dem Gespräch: '+x.zielgebiet:'Mix aus allem'))+'</b><div class="co-asgmeta">'+x.minutes+' Min · '+coCountFor(x.minutes)+' Fragen · '+({mix:'gemischt',leicht:'leicht',mittel:'mittel',schwer:'schwer'}[x.difficulty]||x.difficulty)+(due?' · bis '+due+(x.overdue?' (überfällig)':''):'')+(x.assigned_by_name?' · von '+coEsc(x.assigned_by_name):'')+'</div>'+(x.note?'<div class="co-asgnote">„'+coEsc(x.note)+'“</div>':'')+'</div><button class="co-btn co-asgo" data-id="'+x.id+'">Jetzt machen</button></div>'; }).join('')+'</div>':'';
  var stepBar='<div class="co-steps">'+[[1,'Was'],[2,'Wie'],[3,'Wie lange'],[4,'Start']].map(function(x){ return '<b class="'+(s.step===x[0]?'on':(s.step>x[0]?'done':''))+'" data-step="'+x[0]+'">'+x[0]+' '+x[1]+'</b>'; }).join('')+'</div>';
  var body='';
  if(s.step===1){
    body='<div class="co-lbl">Womit üben?</div><div class="co-modes">'
      +'<button class="co-mode'+(s.mode==='daily'?' on':'')+'" data-m="daily"><b>Tageseinheit</b><span>Mix aus allem, fällige Wiederholungen zuerst</span></button>'
      +'<button class="co-mode'+(s.mode==='topic'?' on':'')+'" data-m="topic"><b>Thema üben</b><span>'+coEsc(av.topics.slice(0,3).map(function(t){return t.t.replace(/^Coaching: /,'');}).join(', '))+' …</span></button>'
      +'<button class="co-mode'+(s.mode==='sprint'?' on':'')+'" data-m="sprint"><b>Vor dem Gespräch</b><span>Ein Zielgebiet, zwei Minuten, das Wichtigste</span></button></div>'
      +(s.mode==='topic'?'<div class="co-lbl">Thema</div><select class="co-sel" id="coTopicSel"><option value="">Zufall ('+(a.questions||0)+' Fragen)</option>'+av.topics.map(function(x){ return '<option value="'+coEsc(x.t)+'"'+(s.topic===x.t?' selected':'')+'>'+coEsc(x.t)+' ('+x.n+')</option>'; }).join('')+'</select>':'')
      +(s.mode==='sprint'?'<div class="co-lbl">Zielgebiet</div><select class="co-sel" id="coZgSel"><option value="">Zufällig</option>'+av.zgs.map(function(x){ return '<option value="'+coEsc(x.z)+'"'+(s.zielgebiet===x.z?' selected':'')+'>'+coEsc(x.z)+' ('+x.n+')</option>'; }).join('')+'</select>':'')
      +'<div class="co-nav"><button class="co-btn" id="coStepNext">Weiter</button></div>';
  } else if(s.step===2){
    body='<div class="co-lbl">Schwierigkeit</div><div class="co-row" id="coDiff">'+[['mix','Gemischt'],['leicht','Leicht'],['mittel','Mittel'],['schwer','Schwer']].filter(function(d){ return d[0]==='mix'||av.diffs[d[0]]; }).map(function(d){ return '<button class="co-chip'+(s.difficulty===d[0]?' on':'')+'" data-v="'+d[0]+'">'+d[1]+(d[0]!=='mix'?' <span style="opacity:.7;font-weight:500">'+av.diffs[d[0]]+'</span>':'')+'</button>'; }).join('')+'</div>'
      +'<div class="co-sub" style="margin-top:6px">Leicht: drei nahe Antworten. Mittel: vier nahe Antworten, Eintippen. Schwer: Situationen in eigenen Worten, Reihenfolgen.</div>'
      +'<div class="co-lbl">Wie gefragt wird</div><div class="co-row" id="coKind">'+[['auto','Passend zum Stoff'],['mc','Auswahl'],['gap','Eintippen'],['free','Situationen (Freitext)']].filter(function(d){ return kindOk[d[0]]; }).map(function(d){ return '<button class="co-chip'+(s.kinds===d[0]?' on':'')+'" data-v="'+d[0]+'">'+d[1]+'</button>'; }).join('')+'</div>'
      +'<div class="co-nav"><button class="co-btn sec" id="coStepBack">Zurück</button><button class="co-btn" id="coStepNext">Weiter</button></div>';
  } else if(s.step===3){
    body='<div class="co-lbl">Dauer</div><div class="co-row" id="coMin">'+[2,5,10,15].map(function(m){ return '<button class="co-chip'+(s.minutes===m?' on':'')+'" data-v="'+m+'">'+m+' Min · '+coCountFor(m)+' Fragen</button>'; }).join('')+'</div>'
      +(av.exact<need&&((s.mode==='topic'&&s.topic)||(s.mode==='sprint'&&s.zielgebiet))?'<div class="co-fill">Dazu gibt es '+av.exact+' passende Frage'+(av.exact===1?'':'n')+'. Fehlt etwas, nimmt Conny nur wirklich Verwandtes dazu, sonst wird die Einheit kürzer.</div>':'')
      +'<div class="co-nav"><button class="co-btn sec" id="coStepBack">Zurück</button><button class="co-btn" id="coStepNext">Zur Startkarte</button></div>';
  } else {
    var was=s.mode==='topic'?(s.topic||'Zufall aus allen Themen'):s.mode==='sprint'?('Vor dem Gespräch: '+(s.zielgebiet||'zufälliges Zielgebiet')):'Tageseinheit, Mix aus allem';
    var kindsTxt={auto:'passend zum Stoff',mc:'Auswahl und Zuordnung',gap:'Eintippen und Reihenfolge',free:'Situationen in eigenen Worten'}[s.kinds];
    body='<div class="co-card"><h3>'+coEsc(was)+'</h3><div class="co-facts">'
      +'<div class="co-fact"><div class="k">Schwierigkeit</div><div class="v">'+({mix:'Gemischt',leicht:'Leicht',mittel:'Mittel',schwer:'Schwer'}[s.difficulty])+'</div></div>'
      +'<div class="co-fact"><div class="k">Dauer</div><div class="v">'+s.minutes+' Min</div></div>'
      +'<div class="co-fact"><div class="k">Fragen</div><div class="v" id="coPlanN">…</div></div>'
      +'<div class="co-fact"><div class="k">Fragearten</div><div class="v" style="font-size:14px">'+kindsTxt+'</div></div></div>'
      +'<div class="co-sub" style="margin-top:12px">Eine Frage nach der anderen, im Vollbild. Nach jeder Antwort siehst du sofort, was stimmt und warum. Die Uhr läuft mit, sie entscheidet nichts. Abbrechen geht jederzeit oben rechts.</div>'
      +'<div class="co-fill" id="coPlanNote" style="display:none"></div>'
      +'</div><div class="co-nav"><button class="co-btn sec" id="coStepBack">Ändern</button><button class="co-btn big" id="coGo" style="flex:1">Los geht’s</button></div>';
  }
  host.innerHTML='<div class="co" style="--acc:'+(ag.color||'#0F5661')+'">'
    +'<div class="co-hd"><div class="co-orb">'+coAvatar(ag,60)+'</div><div><div class="co-ttl">'+name+' coacht</div><div class="co-sub">'+coEsc(greet)+'</div></div></div>'
    +asgHtml+stepBar+body+'<div class="co-hist" id="coHist"></div></div>';
  host.querySelectorAll('.co-mode').forEach(function(b){ b.addEventListener('click',function(){ s.mode=b.getAttribute('data-m'); if(s.mode==='sprint'&&s.minutes>5)s.minutes=2; s._touched=true; coStartScreen(host); }); });
  var chip=function(id,key){ host.querySelectorAll('#'+id+' .co-chip').forEach(function(b){ b.addEventListener('click',function(){ var v=b.getAttribute('data-v'); s[key]=(key==='minutes')?Number(v):v; s._touched=true; coStartScreen(host); }); }); };
  chip('coMin','minutes'); chip('coDiff','difficulty'); chip('coKind','kinds');
  var ts=document.getElementById('coTopicSel'); if(ts) ts.addEventListener('change',function(){ s.topic=ts.value; coStartScreen(host); });
  var zs=document.getElementById('coZgSel'); if(zs) zs.addEventListener('change',function(){ s.zielgebiet=zs.value; coStartScreen(host); });
  host.querySelectorAll('.co-steps b').forEach(function(b){ b.addEventListener('click',function(){ var st=Number(b.getAttribute('data-step')); if(st<s.step){ s.step=st; coStartScreen(host); } }); });
  var nx=document.getElementById('coStepNext'); if(nx) nx.addEventListener('click',function(){ s.step=Math.min(4,s.step+1); coStartScreen(host); });
  var bk=document.getElementById('coStepBack'); if(bk) bk.addEventListener('click',function(){ s.step=Math.max(1,s.step-1); coStartScreen(host); });
  var go=document.getElementById('coGo'); if(go) go.addEventListener('click',function(){ coStart(host); });
  if(s.step===4) coLoadPlan();
  host.querySelectorAll('.co-asgo').forEach(function(b){ b.addEventListener('click',function(){ coStart(host,b.getAttribute('data-id')); }); });
  if(!_coCtx.preview) coLoadHist();
}
// Startkarte: echte Anzahl und Zusammensetzung vom Motor (dieselbe Auswahl wie beim Start), statt einer Schätzung
function coLoadPlan(){ var s=_coSet; var kinds=s.kinds==='auto'?null:(s.kinds==='mc'?['mc','match']:s.kinds==='gap'?['gap','order']:['free']);
  coCall({action:'plan',settings:{mode:s.mode,topic:s.mode==='topic'?s.topic:null,zielgebiet:s.mode==='sprint'?s.zielgebiet:null,minutes:s.minutes,difficulty:s.difficulty,kinds:kinds}}).then(function(r){ var p=r.plan||{}; var el=document.getElementById('coPlanN'); if(el) el.textContent=p.n+(p.short?' statt '+p.wanted:''); var nt=document.getElementById('coPlanNote'); if(nt&&p.note){ nt.textContent=p.note; nt.style.display=''; } })
  .catch(function(){ var el=document.getElementById('coPlanN'); if(el) el.textContent=coCountFor(s.minutes); }); }
function coLoadHist(){ var el=document.getElementById('coHist'); if(!el)return;
  coCall({action:'history'}).then(function(h){ var ss=h.sessions||[];
    var kp='<div class="co-kpis"><div class="co-kpi"><b>'+(h.streak||0)+'</b><span>Tage in Folge</span></div><div class="co-kpi"><b>'+(h.due||0)+'</b><span>fällig zur Wiederholung</span></div><div class="co-kpi"><b>'+(h.learned||0)+'</b><span>sicher gelernt</span></div></div>';
    if(!ss.length){ el.innerHTML='<div class="co-lbl">Dein Stand</div>'+kp; return; }
    var topics=h.topics||{}; var keys=Object.keys(topics).filter(function(k){return topics[k].max>0;}).sort(function(a,b){ return topics[a].points/topics[a].max-topics[b].points/topics[b].max; });
    var html='<div class="co-lbl">Dein Stand</div>'+kp;
    if(keys.length){ html+='<div class="co-lbl">Themen, letzte 30 Tage</div><div class="co-tr">'+keys.slice(0,8).map(function(k){ var p=topics[k].points/topics[k].max; var col=p>=.8?'#059669':p>=.6?'#d97706':'#dc2626'; return '<div class="co-tl"><div>'+coEsc(k)+'</div><div class="co-bar"><i style="width:'+Math.round(p*100)+'%;background:'+col+'"></i></div><div style="text-align:right;font-family:ui-monospace,monospace;font-weight:700;color:'+col+'">'+Math.round(p*100)+'%</div></div>'; }).join('')+'</div>'; }
    html+='<div class="co-lbl">Letzte Einheiten</div>'+ss.slice(0,6).map(function(x){ var d=new Date(x.finished_at||x.started_at); var mode={daily:'Tageseinheit',topic:'Thema: '+((x.settings||{}).topic||'Zufall'),sprint:'Vor dem Gespräch'+((x.settings||{}).zielgebiet?': '+(x.settings||{}).zielgebiet:'')}[(x.settings||{}).mode]||'Einheit'; var sc=Math.round((x.score||0)*100); return '<div class="co-hrow"><span class="p" style="color:'+(sc>=80?'#059669':sc>=60?'#d97706':'#dc2626')+'">'+sc+'%</span><span class="d">'+d.toLocaleDateString('de-DE')+'</span><span class="m">'+coEsc(mode)+' · '+(x.max_points||0)+' Fragen'+((x.settings||{}).assignment?' · Pflicht':'')+'</span></div>'; }).join('');
    el.innerHTML=html; }).catch(function(){ el.innerHTML=''; });
}
// ── Einheit starten: Fortschritt sichtbar, dann Fokus-Modus ──
function coStart(host,assignmentId){ var s=_coSet; var go=document.getElementById('coGo'); if(go){ go.disabled=true; }
  var st=document.createElement('div'); st.className='co-fill'; st.id='coStarting'; st.style.marginTop='12px'; st.textContent=(_coAg.name||'Coach')+' stellt deine Einheit zusammen …'; var card=host.querySelector('.co-card'); (card||host.querySelector('.co')).appendChild(st);
  var dots=0; var tick=setInterval(function(){ dots=(dots+1)%4; var el=document.getElementById('coStarting'); if(el) el.textContent=(_coAg.name||'Coach')+' stellt deine Einheit zusammen'+'.'.repeat(dots)+' (fällige Wiederholungen, Themen, Stufe)'; },400);
  var kinds=s.kinds==='auto'?null:(s.kinds==='mc'?['mc','match']:s.kinds==='gap'?['gap','order']:['free']);
  var body=assignmentId?{action:'start',assignment_id:assignmentId}:{action:'start',settings:{mode:s.mode,topic:s.mode==='topic'?s.topic:null,zielgebiet:s.mode==='sprint'?s.zielgebiet:null,minutes:s.minutes,difficulty:s.difficulty,kinds:kinds}};
  coCall(body).then(function(r){ clearInterval(tick); _coSess=r.session_id; _coQ=r.questions||[]; _coIdx=0; _coRes=[]; _coAssign=r.assignment||null; _coFill=(r.fill&&r.fill.note)||null; _coMinutes=r.minutes||s.minutes||5; _coDue=(r.fill&&r.fill.due)||0; coOpenFocus(); })
    .catch(function(e){ clearInterval(tick); var el=document.getElementById('coStarting'); if(el){ el.style.background='#fef2f2'; el.style.borderColor='#fecaca'; el.style.color='#b91c1c'; el.textContent='Konnte keine Einheit starten: '+(e.message||e); } if(go) go.disabled=false; });
}
var _coDue=0;
function coOpenFocus(){ var old=document.getElementById('coFocus'); if(old) old.remove();
  var f=document.createElement('div'); f.id='coFocus'; f.className='co-focus'; f.style.setProperty('--acc',(_coAg.color||'#0F5661'));
  f.innerHTML='<div class="co-fbar"><div class="co-orb" style="width:40px;height:40px;border-width:2px">'+coAvatar(_coAg,40)+'</div><div class="who"><div class="n" id="coFbTitle"></div><div class="s" id="coFbSub"></div></div><div class="co-clock" id="coClock"></div><button class="co-quit" id="coQuit">Abbrechen ✕</button></div><div class="co-prog" id="coProg"></div><div class="co-stage" id="coStage"></div>';
  document.body.appendChild(f); document.body.style.overflow='hidden';
  document.getElementById('coQuit').addEventListener('click',function(){ coConfirm('Einheit abbrechen?','Deine bisherigen Antworten bleiben gespeichert, die Einheit wird ohne Ergebnis beendet.','Abbrechen','Weiter üben',function(){ coCloseFocus(true); }); });
  _coStart=Date.now(); _coOver=false; if(_coTimer) clearInterval(_coTimer); _coTimer=setInterval(coTick,500); coTick();
  _coKey=function(e){ if(!document.getElementById('coFocus')) return; var q=_coQ[_coIdx]; if(!q) return; var fb=document.getElementById('coFb'); var answered=fb&&fb.children.length>0;
    if(e.key==='Enter'&&!(e.target&&e.target.tagName==='TEXTAREA')){ if(answered){ var nx=document.getElementById('coNext'); if(nx){ e.preventDefault(); nx.click(); } } else { var sb2=document.getElementById('coSubmit'); if(sb2&&q.kind!=='free'){ e.preventDefault(); sb2.click(); } } return; }
    if(q.kind==='mc'&&!answered&&/^[a-dA-D]$/.test(e.key)&&!(e.target&&/INPUT|TEXTAREA/.test(e.target.tagName))){ var k=e.key.toUpperCase(); var opt=f.querySelector('.co-opt[data-k="'+k+'"]'); if(opt){ f.querySelectorAll('.co-opt').forEach(function(x){x.classList.remove('on');}); opt.classList.add('on'); } } };
  document.addEventListener('keydown',_coKey);
  coRenderQ();
}
function coCloseFocus(abort){ if(_coTimer){ clearInterval(_coTimer); _coTimer=null; } if(_coKey){ document.removeEventListener('keydown',_coKey); _coKey=null; } var f=document.getElementById('coFocus'); if(f) f.remove(); document.body.style.overflow=''; if(!_coCtx.preview) coBootNav();
  if(abort){ if(_coSess&&!_coCtx.preview&&_coRes.some(function(x){return x!=null;})) coCall({action:'finish',session_id:_coSess}).catch(function(){}); var host=document.getElementById(_coCtx.hostId||'vCoach'); if(host){ _coSet.step=1; renderCoach(); } } }
function coTick(){ var el=document.getElementById('coClock'); if(!el) return; var show=!(_coAvail&&_coAvail.settings&&_coAvail.settings.show_timer===false); if(!show){ el.innerHTML=''; return; }
  var total=_coMinutes*60, used=Math.floor((Date.now()-_coStart)/1000), left=total-used; var frac=Math.max(0,Math.min(1,used/total)); var r=14, c=2*Math.PI*r;
  var m=Math.floor(Math.abs(left)/60), s2=Math.abs(left)%60; var txt=(left<0?'-':'')+m+':'+(s2<10?'0':'')+s2;
  el.className='co-clock'+(left<0?' over':''); el.innerHTML='<svg width="36" height="36" viewBox="0 0 36 36"><circle cx="18" cy="18" r="'+r+'" fill="none" stroke="#e2e8f0" stroke-width="4"/><circle cx="18" cy="18" r="'+r+'" fill="none" stroke="'+(left<0?'#dc2626':'var(--acc,#0F5661)')+'" stroke-width="4" stroke-linecap="round" stroke-dasharray="'+c+'" stroke-dashoffset="'+(c*frac)+'" transform="rotate(-90 18 18)"/></svg><span class="t">'+txt+'</span>';
  if(left<0&&!_coOver){ _coOver=true; coConfirm('Die Zeit ist um.','Kein Problem: Du kannst die Einheit jetzt abschließen oder die restlichen Fragen in Ruhe fertig machen.','Jetzt abschließen','Fertig machen',function(){ coFinish(); }); }
}
function coConfirm(title,text,yes,no,onYes){ var o=document.createElement('div'); o.className='co-over'; o.style.setProperty('--acc',(_coAg&&_coAg.color)||'#0F5661'); o.innerHTML='<div class="box"><h3>'+coEsc(title)+'</h3><p>'+coEsc(text)+'</p><div class="co-nav" style="justify-content:center;margin-top:0"><button class="co-btn sec" id="coNo">'+coEsc(no)+'</button><button class="co-btn" id="coYes">'+coEsc(yes)+'</button></div></div>'; document.body.appendChild(o);
  o.querySelector('#coNo').addEventListener('click',function(){ o.remove(); }); o.querySelector('#coYes').addEventListener('click',function(){ o.remove(); onYes(); }); }
function coProg(){ var el=document.getElementById('coProg'); if(!el)return; el.innerHTML=_coQ.map(function(q,i){ var r=_coRes[i]; var c=i===_coIdx?'cur':(r==null?'':(r>=1?'ok':r>0?'half':'no')); return '<i class="'+c+'"></i>'; }).join(''); }
function coRenderQ(){
  var q=_coQ[_coIdx]; var stage=document.getElementById('coStage'); if(!stage) return; if(!q){ coFinish(); return; }
  _coT0=Date.now(); _coOrder=null; coProg();
  document.getElementById('coFbTitle').textContent=(_coAssign?'Pflichteinheit'+(_coAssign.by?' von '+_coAssign.by:''):((_coAg.name||'Coach')+' coacht'))+' · Frage '+(_coIdx+1)+' von '+_coQ.length;
  document.getElementById('coFbSub').textContent=q.topic+(q.zielgebiet?' · '+q.zielgebiet:'');
  var kindLbl={mc:'Auswahl',gap:'Eintippen',match:'Zuordnen',order:'Reihenfolge',free:'Situation'}[q.kind]||'';
  var body='';
  if(q.kind==='mc'){ body=(q.options||[]).map(function(o){ return '<button class="co-opt" data-k="'+coEsc(o.key)+'"><span class="k">'+coEsc(o.key)+'</span><span style="flex:1"><span>'+coEsc(o.text)+'</span></span></button>'; }).join(''); }
  else if(q.kind==='gap'){ body='<input class="co-in" id="coGap" placeholder="Deine Antwort" autocomplete="off">'; }
  else if(q.kind==='free'){ body='<textarea class="co-in co-ta" id="coFree" placeholder="Was sagst oder tust du? In deinen Worten, wie am Telefon."></textarea>'; }
  else if(q.kind==='match'){ var L=(q.options||{}).left||[], R=(q.options||{}).right||[]; body=L.map(function(l){ return '<div class="co-pair"><div class="l">'+coEsc(l)+'</div><select class="co-sel co-msel" data-l="'+coEsc(l)+'"><option value="">…</option>'+R.map(function(r){ return '<option value="'+coEsc(r)+'">'+coEsc(r)+'</option>'; }).join('')+'</select></div>'; }).join(''); }
  else if(q.kind==='order'){ _coOrder=(q.options||[]).slice(); body='<div id="coOrd"></div>'; }
  stage.innerHTML=(_coFill&&_coIdx===0?'<div class="co-fill" style="margin:0 0 12px">'+coEsc(_coFill)+'</div>':'')
    +(_coAssign&&_coAssign.note&&_coIdx===0?'<div class="co-fill" style="margin:0 0 12px;background:#fff7f7;border-color:#fecaca;color:#b91c1c">Hinweis'+(_coAssign.by?' von '+coEsc(_coAssign.by):'')+': „'+coEsc(_coAssign.note)+'“</div>':'')
    +'<div class="co-meta"><b>'+coEsc(q.topic)+'</b>'+(q.zielgebiet?' · '+coEsc(q.zielgebiet):'')+'<span class="kind">'+kindLbl+' · '+coEsc(q.difficulty)+'</span></div>'
    +'<div class="co-q">'+coEsc(q.prompt)+'</div>'+body
    +'<div class="co-act"><button class="co-btn" id="coSubmit">Antworten</button><button class="co-btn sec" id="coSkip">Weiß ich nicht</button><span class="co-hint">'+(q.kind==='mc'?'Tasten A bis D, Enter':q.kind==='free'?'In Ruhe schreiben':'Enter zum Antworten')+'</span></div>'
    +'<div id="coFb"></div>';
  if(q.kind==='mc'){ stage.querySelectorAll('.co-opt').forEach(function(b){ b.addEventListener('click',function(){ stage.querySelectorAll('.co-opt').forEach(function(x){x.classList.remove('on');}); b.classList.add('on'); }); }); }
  if(q.kind==='order'){ coDrawOrder(); }
  var inp=document.getElementById('coGap')||document.getElementById('coFree'); if(inp) inp.focus();
  document.getElementById('coSubmit').addEventListener('click',function(){ coSubmit(false); });
  document.getElementById('coSkip').addEventListener('click',function(){ coSubmit(true); });
  window.scrollTo(0,0); var fx=document.getElementById('coFocus'); if(fx) fx.scrollTop=0;
}
function coDrawOrder(){ var el=document.getElementById('coOrd'); if(!el)return; el.innerHTML=_coOrder.map(function(t,i){ return '<div class="co-ord"><span class="n">'+(i+1)+'</span><span class="t">'+coEsc(t)+'</span><button data-i="'+i+'" data-d="-1"'+(i===0?' disabled':'')+'>↑</button><button data-i="'+i+'" data-d="1"'+(i===_coOrder.length-1?' disabled':'')+'>↓</button></div>'; }).join('');
  el.querySelectorAll('button').forEach(function(b){ b.addEventListener('click',function(){ var i=Number(b.getAttribute('data-i')), d=Number(b.getAttribute('data-d')); var j=i+d; if(j<0||j>=_coOrder.length)return; var t=_coOrder[i]; _coOrder[i]=_coOrder[j]; _coOrder[j]=t; coDrawOrder(); }); }); }
function coSubmit(skip){ if(_coBusy)return; var q=_coQ[_coIdx]; var stage=document.getElementById('coStage'); var ans={};
  if(!skip){
    if(q.kind==='mc'){ var on=stage.querySelector('.co-opt.on'); if(!on){ return; } ans={key:on.getAttribute('data-k')}; }
    else if(q.kind==='gap'){ ans={text:(document.getElementById('coGap')||{}).value||''}; if(!ans.text.trim())return; }
    else if(q.kind==='free'){ ans={text:(document.getElementById('coFree')||{}).value||''}; if(!ans.text.trim())return; }
    else if(q.kind==='match'){ var pairs={}; stage.querySelectorAll('.co-msel').forEach(function(s){ pairs[s.getAttribute('data-l')]=s.value; }); ans={pairs:pairs}; }
    else if(q.kind==='order'){ ans={sequence:_coOrder.slice()}; }
  }
  _coBusy=true; var btn=document.getElementById('coSubmit'); var sk=document.getElementById('coSkip'); if(sk) sk.disabled=true;
  if(btn){ btn.disabled=true; btn.textContent=q.kind==='free'?(_coAg.name||'Coach')+' liest deine Antwort …':'…'; }
  var t0=Date.now(); var tk=q.kind==='free'?setInterval(function(){ if(btn) btn.textContent=(_coAg.name||'Coach')+' liest deine Antwort … '+Math.round((Date.now()-t0)/1000)+' s'; },500):null;
  var secs=Math.round((Date.now()-_coT0)/1000);
  coCall({action:'answer',session_id:_coSess,question_id:q.id,answer:ans,seconds:secs}).then(function(r){
    if(tk) clearInterval(tk); _coBusy=false; _coRes[_coIdx]=r.points; coProg(); coShowFb(q,r,ans);
  }).catch(function(e){ if(tk) clearInterval(tk); _coBusy=false; if(btn){ btn.disabled=false; btn.textContent='Antworten'; } if(sk) sk.disabled=false; var fb=document.getElementById('coFb'); if(fb) fb.innerHTML='<div class="co-fb no"><div class="h">Antwort konnte nicht bewertet werden</div><div class="x">'+coEsc(e.message||e)+'</div></div>'; });
}
function coShowFb(q,r,ans){
  var stage=document.getElementById('coStage'); var p=Number(r.points||0); var cls=p>=1?'ok':p>0?'half':'no'; var head=p>=1?'Richtig':p>0?'Teilweise richtig':'Nicht ganz';
  var sol='';
  if(q.kind==='mc'){ var key=(r.solution||{}).key; stage.querySelectorAll('.co-opt').forEach(function(b){ var k=b.getAttribute('data-k'); var o=(r.options_why||[]).find(function(x){return x.key===k;}); if(k===key){ b.classList.add('right'); } else if(ans.key===k){ b.classList.add('wrong'); if(o&&o.why){ var w=String(o.why); var ci=w.indexOf(': '); if(ci>0&&w.slice(ci+2).toLowerCase().indexOf(w.slice(0,ci).toLowerCase())>=0) w=w.slice(ci+2); b.querySelector('span[style]').insertAdjacentHTML('beforeend','<span class="why">Das ist '+coEsc(w)+'.</span>'); } } b.disabled=true; }); }
  else if(q.kind==='gap'){ sol=/richtig ist/i.test(r.feedback||'')?'':'Richtig: '+((r.solution||{}).accept||[])[0]; }
  else if(q.kind==='match'){ var pr=(r.solution||{}).pairs||{}; sol=Object.keys(pr).map(function(k){ return k+' → '+pr[k]; }).join('\n'); }
  else if(q.kind==='order'){ sol=((r.solution||{}).sequence||[]).map(function(s,i){ return (i+1)+'. '+s; }).join('\n'); }
  var rub=''; if(q.kind==='free'&&r.rubric){ rub='<ul class="co-rub">'+(r.rubric.hits||[]).map(function(h){ return '<li class="y">✓ '+coEsc(h)+'</li>'; }).join('')+(r.rubric.missing||[]).map(function(m){ return '<li class="m">→ hat gefehlt: '+coEsc(m)+'</li>'; }).join('')+'</ul>'+(r.rubric.model_answer?'<div class="model"><div class="l">So klingt es gut</div><div class="t">„'+coEsc(r.rubric.model_answer)+'“</div></div>':''); }
  var nextTxt=r.progress?(p>=1?'Wiederholung in '+r.progress.next_days+' Tag'+(r.progress.next_days===1?'':'en')+'.':'Kommt morgen noch einmal dran.'):'';
  var fb=document.getElementById('coFb'); fb.innerHTML='<div class="co-fb '+cls+'"><div class="h">'+head+(q.kind!=='mc'&&q.kind!=='free'&&p>0&&p<1?' · '+Math.round(p*100)+' %':'')+'</div>'
    +(r.feedback?'<div class="x">'+coEsc(r.feedback)+'</div>':'')+rub
    +(sol?'<div class="x" style="margin-top:8px">'+coEsc(sol)+'</div>':'')
    +(r.explanation&&q.kind!=='mc'&&q.kind!=='free'&&p>=1?'<div class="x" style="margin-top:6px;color:#334155">Merk dir: '+coEsc(r.explanation)+'</div>':'')
    +(r.explanation&&q.kind==='mc'&&p>=1?'<div class="x" style="margin-top:6px;color:#334155">Merk dir: '+coEsc(r.explanation)+'</div>':'')
    +(r.source?'<div class="s">Quelle: '+coEsc(r.source)+'</div>':'')+(nextTxt?'<div class="next">'+nextTxt+'</div>':'')
    +(_coCtx.preview?'':'<button class="flag" id="coFlag">Frage unklar oder falsch? Melden</button>')+'</div>';
  if(document.getElementById('coFlag')) document.getElementById('coFlag').addEventListener('click',function(){ var note=prompt('Was ist unklar oder falsch an dieser Frage?'); if(note===null)return; sb.rpc('coach_flag',{p_answer:r.answer_id,p_note:note}).then(function(){ var b=document.getElementById('coFlag'); if(b)b.textContent='Gemeldet, danke.'; }); });
  var act=stage.querySelector('.co-act'); act.innerHTML='<button class="co-btn" id="coNext">'+(_coIdx+1<_coQ.length?'Weiter':'Zum Ergebnis')+'</button><span class="co-hint">Enter</span>';
  document.getElementById('coNext').addEventListener('click',function(){ _coIdx++; coRenderQ(); }); document.getElementById('coNext').focus();
}
function coFinish(){ var stage=document.getElementById('coStage'); if(_coTimer){ clearInterval(_coTimer); _coTimer=null; } if(stage) stage.innerHTML='<div class="co-sub" style="padding:20px">Werte aus …</div>';
  var tt=document.getElementById('coFbTitle'); if(tt) tt.textContent='Ergebnis'; var ts=document.getElementById('coFbSub'); if(ts) ts.textContent=''; var ck=document.getElementById('coClock'); if(ck) ck.innerHTML=''; var qb=document.getElementById('coQuit'); if(qb){ qb.textContent='Schließen'; var nb=qb.cloneNode(true); qb.parentNode.replaceChild(nb,qb); nb.addEventListener('click',function(){ coCloseFocus(false); _coSet.step=1; renderCoach(); }); } _coIdx=_coQ.length; coProg();
  var used=Math.round((Date.now()-_coStart)/1000);
  coCall(_coCtx.preview?{action:'finish',results:_coQ.map(function(q,i){ return {topic:q.topic,points:_coRes[i]||0}; })}:{action:'finish',session_id:_coSess}).then(function(r){ var sc=Math.round((r.score||0)*100); var tp=r.topics||{}; var keys=Object.keys(tp);
    var msg=(_coAssign?'Pflichteinheit erledigt. ':'')+(sc>=90?'Stark. Das sitzt.':sc>=70?'Gut. Ein paar Stellen üben wir nochmal.':sc>=50?'Solide Basis, da ist noch Luft.':'Kein Drama. Genau dafür ist der Coach da.');
    var mm=Math.floor(used/60), ss=used%60;
    stage.innerHTML='<div class="co-hd"><div class="co-orb" style="width:56px;height:56px">'+coAvatar(_coAg,56)+'</div><div><div class="co-ttl">'+coEsc(_coAg.name||'Coach')+'</div><div class="co-sub">'+coEsc(msg)+'</div></div></div>'
      +'<div class="co-res"><div class="big">'+Math.round(r.points*10)/10+' / '+r.max+'</div><div class="sub">'+sc+' % richtig · '+mm+':'+(ss<10?'0':'')+ss+' Min gebraucht'+(r.strong?' · stark bei '+coEsc(r.strong):'')+'</div></div>'
      +(!_coCtx.preview?'<div class="co-kpis" style="justify-content:center"><div class="co-kpi"><b>'+(r.streak||0)+'</b><span>Tage in Folge</span></div><div class="co-kpi"><b>'+(r.due||0)+'</b><span>fällig zur Wiederholung</span></div></div>':'')
      +(keys.length?'<div class="co-tr">'+keys.map(function(k){ var p=tp[k].points/tp[k].max; var col=p>=.8?'#059669':p>=.5?'#d97706':'#dc2626'; return '<div class="co-tl"><div>'+coEsc(k)+'</div><div class="co-bar"><i style="width:'+Math.round(p*100)+'%;background:'+col+'"></i></div><div style="text-align:right;font-family:ui-monospace,monospace;font-weight:700;color:'+col+'">'+Math.round(p*100)+'%</div></div>'; }).join('')+'</div>':'')
      +(r.recommend?'<div class="co-fb half" style="margin-top:16px"><div class="h">Das üben wir als Nächstes</div><div class="x">'+coEsc(r.recommend)+'</div></div>':'')
      +'<div class="co-nav">'+(r.recommend?'<button class="co-btn" id="coAgain">Gleich üben</button>':'')+'<button class="co-btn sec" id="coHome">Fertig</button></div>';
    var ag2=document.getElementById('coAgain'); if(ag2) ag2.addEventListener('click',function(){ _coSet.mode='topic'; _coSet.topic=r.recommend; _coSet.step=4; coCloseFocus(false); var host=document.getElementById(_coCtx.hostId||'vCoach'); if(host){ coStartScreen(host); coStart(host); } });
    document.getElementById('coHome').addEventListener('click',function(){ coCloseFocus(false); _coSet.step=1; renderCoach(); });
  }).catch(function(e){ if(stage) stage.innerHTML='<div class="co-fb no"><div class="h">Ergebnis konnte nicht gespeichert werden</div><div class="x">'+coEsc(e.message||e)+'</div></div><div class="co-nav"><button class="co-btn sec" onclick="coCloseFocus(false);renderCoach()">Zurück</button></div>'; });
}
// Übungsstoff vorhanden? (aus coach_available, einmal je Sitzung geladen) + Punkt am Menü: Pflicht offen (rot) / heute noch nicht geübt (gelb)
var _coHas=null;
function coHasStoff(){ return _coHas===true; }
function coResetPrefs(){ _coSet._touched=false; }
function coBootNav(){ sb.rpc('coach_available').then(function(r){ var a=(r&&r.data)||{}; _coHas=!!a.questions; if(_coHas&&!_coAvail) _coAvail=a;
    var open=(a.assignments||[]).length; var dot=document.getElementById('coNavDot'); if(dot){ dot.style.display=(_coHas&&(open>0||!a.today))?'inline-block':'none'; dot.style.background=open>0?'#dc2626':'#F5B301'; dot.title=open>0?(open+' Pflichteinheit'+(open>1?'en':'')+' offen'):'heute noch nicht geübt'; }
    var d2=document.getElementById('pwCoachDot'); if(d2){ d2.style.display=open>0?'inline-block':'none'; }
    // Ansicht schon offen, aber ohne Reiter (Boot war noch nicht durch): Reiter nachziehen
    var v=document.getElementById('vPartnerwissen'); if(_coHas&&v&&v.classList.contains('on')&&!v.querySelector('.pw-tabs')&&typeof window.renderPartnerwissen==='function') window.renderPartnerwissen();
  }).catch(function(){}); }
