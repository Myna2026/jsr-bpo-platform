// task-reminders (Schnitt 5a): DM je Person mit ihren OFFENEN Tagesaufgaben. Dispatcher waehlt den Kanal
// (Slack direkt / Zoho Cliq via Make) je Person mit globalem Standard. Cron feuert zu mehreren UTC-Stunden,
// die Function sendet nur, wenn es in Europe/Berlin 09/12/16 Uhr ist (Ortszeit-Pruefung -> DST-sicher).
// Wer alles erledigt hat oder keinen Kanal-Account hat, bekommt nichts. Nur DMs.
// (Faellige/ueberfaellige UPLOADS kommen in 5b.)
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPA_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const SLACK     = Deno.env.get('SLACK_BOT_TOKEN') || '';
const MAKE_CLIQ = Deno.env.get('MAKE_CLIQ_WEBHOOK') || '';   // Zoho Cliq via Make (5b/spaeter aktiv)
const PORTAL = 'https://hr.tive360.de';

// Aufgaben-Katalog kommt aus der DB (task_catalog) — EINE Wahrheit, kein hr.html-Spiegel mehr. Pro Request
// geladen (siehe handler). auto (Kalender-Pflichttermine) werden fuer Erinnerungen ausgelassen.
let ROLE_TASKS: any[] = [];
const owners = (t: any) => Array.isArray(t.owner) ? t.owner : [t.owner];
const taskRolesOf = (u: any) => { const rk=u.role_keys||[]; const ext=!!u.mgmt_external;
  return ['management','hr','finance','teamlead','projektleiter'].filter(r=>rk.includes(r)&&!(r==='management'&&ext)); };
function effInstances(roles: string[], rows: any[]){
  const rs=roles||[], ar=rows||[];
  const removed=new Set(ar.filter(a=>a.active===false).map(a=>a.task_key+'|'+(a.project_id||'')));
  const out:any[]=[], seen=new Set();
  const push=(t:any,pid:string|null)=>{ const ik=t.key+'|'+(pid||''); if(removed.has(ik)||seen.has(ik)) return; seen.add(ik); out.push({...t, project_id:pid||null, ik}); };
  ROLE_TASKS.filter(t=>owners(t).some((o:string)=>rs.includes(o))).forEach(t=>push(t,null));
  ar.filter(a=>a.active!==false).forEach(a=>{ const t=ROLE_TASKS.find(x=>x.key===a.task_key); if(t) push(t, a.project_id||null); });
  return out;
}
const isoLocal=(d:Date)=>d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');
const json=(o:any,s=200)=>new Response(JSON.stringify(o),{status:s,headers:{'Content-Type':'application/json'}});

async function slackLookup(email:string){ const r=await fetch('https://slack.com/api/users.lookupByEmail?email='+encodeURIComponent(email),{headers:{Authorization:'Bearer '+SLACK}}); const j=await r.json(); return j.ok?j.user.id:null; }
async function slackDM(email:string|undefined, text:string){ if(!SLACK) return 'no-slack-token'; if(!email) return 'no-email';
  const uid=await slackLookup(email); if(!uid) return 'no-slack-user';
  const o=await (await fetch('https://slack.com/api/conversations.open',{method:'POST',headers:{Authorization:'Bearer '+SLACK,'Content-Type':'application/json'},body:JSON.stringify({users:uid})})).json();
  if(!o.ok) return 'open:'+o.error;
  const m=await (await fetch('https://slack.com/api/chat.postMessage',{method:'POST',headers:{Authorization:'Bearer '+SLACK,'Content-Type':'application/json'},body:JSON.stringify({channel:o.channel.id,text})})).json();
  return m.ok?'sent':'post:'+m.error;
}
async function cliqDM(email:string|undefined, text:string){ if(!MAKE_CLIQ) return 'no-make-webhook'; if(!email) return 'no-email';
  const r=await fetch(MAKE_CLIQ,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email,text})}); return r.ok?'sent':'make:'+r.status; }

// ── Upload-Faelligkeit (Schnitt 5b): originalgetreuer Port von computeUploadStatus/uploadTargetDone aus
//    frontend/hr.html. Buckets overdue/today/week -> in die Erinnerung; done/upcoming/inactive -> nicht.
const UPLOAD_LABEL:Record<string,string>={rohdaten:'Rohdaten-Excel',calls:'Call-CSV',gauges:'Gauges-Excel',booking_a:'Booking-Excel (Agent)',booking_week:'Booking-Team Woche',booking_month:'Booking-Team Monat',forecast_sales:'Forecast Woche · Sales',forecast_support:'Forecast Woche · Support',longterm:'Langzeit-Kapazität'};
const CAL_MONTHS=['Januar','Februar','März','April','Mai','Juni','Juli','August','September','Oktober','November','Dezember'];
function getISOWeek(date:Date){ const d=new Date(date); d.setHours(0,0,0,0); d.setDate(d.getDate()+4-(d.getDay()||7)); const ys=new Date(d.getFullYear(),0,1); return {kw:Math.ceil(((((+d)-(+ys))/86400000)+1)/7), year:d.getFullYear()}; }
function isoWeekMonday(y:number,w:number){ const jan4=new Date(y,0,4); const dow=(jan4.getDay()||7); const wk1=new Date(jan4); wk1.setDate(jan4.getDate()-(dow-1)); const mon=new Date(wk1); mon.setDate(wk1.getDate()+(w-1)*7); return mon; }
function uploadDueDate(iso:any,wd:number){ const mon=isoWeekMonday(iso.year,iso.kw); const d=new Date(mon); d.setDate(mon.getDate()+((wd||1)-1)); d.setHours(0,0,0,0); return d; }
function uploadPrevWeek(iso:any){ const mon=isoWeekMonday(iso.year,iso.kw); const d=new Date(mon); d.setDate(mon.getDate()-7); return getISOWeek(d); }
function uploadWeeksOfMonth(Y:number,M:number){ const set=new Set<number>(); const last=new Date(Y,M,0).getDate(); for(let d=1;d<=last;d++){ const w=getISOWeek(new Date(Y,M-1,d)); if(w.year===Y) set.add(w.kw); } return Array.from(set); }
const dayDiff=(a:Date,b:Date)=>Math.floor(((+b)-(+a))/86400000);
async function uploadPresent(fn:()=>any){ try{ const {count}=await fn(); return (count||0)>0; }catch(_e){ return false; } }
async function uploadTargetDone(sb:any,key:string,projId:string,kw:number|null,year:number|null,month:number|null){
  switch(key){
    case 'rohdaten': return uploadPresent(()=>sb.from('weekly_hours').select('*',{count:'exact',head:true}).eq('project_id',projId).eq('kw',kw).eq('year',year));
    case 'calls': return uploadPresent(()=>sb.from('weekly_calls').select('*',{count:'exact',head:true}).eq('project_id',projId).eq('kw',kw).eq('year',year));
    case 'gauges': return uploadPresent(()=>sb.from('weekly_gauges').select('*',{count:'exact',head:true}).eq('project_id',projId).eq('kw',kw).eq('year',year));
    case 'booking_a': return uploadPresent(()=>sb.from('kpi_entries').select('*',{count:'exact',head:true}).eq('kw',kw).eq('year',year).eq('source','import').eq('kpi_id','kpi_hc_open_bookings'));
    case 'booking_week': return uploadPresent(()=>sb.from('kpi_project_entries').select('*',{count:'exact',head:true}).eq('project_id',projId).eq('kw',kw).eq('year',year).eq('source','import'));
    case 'booking_month': return uploadPresent(()=>sb.from('kpi_project_entries').select('*',{count:'exact',head:true}).eq('project_id',projId).eq('month',month).eq('year',year).eq('source','import'));
    case 'forecast_sales': return uploadPresent(()=>sb.from('report_forecast').select('*',{count:'exact',head:true}).eq('project_id',projId).eq('skill','sales').eq('kw',kw).eq('year',year));
    case 'forecast_support': return uploadPresent(()=>sb.from('report_forecast').select('*',{count:'exact',head:true}).eq('project_id',projId).eq('skill','support').eq('kw',kw).eq('year',year));
    case 'longterm': return uploadPresent(()=>sb.from('report_longterm').select('*',{count:'exact',head:true}).eq('project_id',projId));
    default: return false;
  }
}
async function computeUploadStatus(sb:any, cfg:any, projId:string, today:Date, lastMap:Record<string,Date>){
  if(!cfg.active) return {bucket:'inactive',rel:''};
  const grace=Number(cfg.grace_days)||0; const iso=getISOWeek(today);
  if(cfg.cadence==='daily'){
    const last=lastMap[cfg.source_type]||null;
    if(!last) return {bucket:'overdue',rel:'noch nie geladen'};
    const ld=new Date(last); ld.setHours(0,0,0,0); const gap=dayDiff(ld,today);
    if(gap<=0) return {bucket:'done',rel:''};
    if(gap<=grace) return {bucket:'today',rel:'zuletzt vor '+gap+' Tag'+(gap===1?'':'en')};
    return {bucket:'overdue',rel:gap+' Tage kein Upload'};
  }
  if(cfg.cadence==='weekly_progressive'){
    const done=await uploadTargetDone(sb,cfg.source_type,projId,iso.kw,iso.year,null); const rel='KW '+iso.kw;
    if(done) return {bucket:'done',rel:''};
    const last=lastMap[cfg.source_type]||null; let gap:number|null=null; if(last){ const ld=new Date(last); ld.setHours(0,0,0,0); gap=dayDiff(ld,today); }
    const dow=(today.getDay()+6)%7;
    if(dow<=1 || (gap!=null && gap<=grace)) return {bucket:'week',rel:rel+' offen'};
    return {bucket:'overdue',rel:rel+' fehlt'};
  }
  if(cfg.cadence==='weekly_retro'){
    const prev=uploadPrevWeek(iso); const done=await uploadTargetDone(sb,cfg.source_type,projId,prev.kw,prev.year,null); const rel='KW '+prev.kw; const due=uploadDueDate(iso,cfg.due_weekday);
    if(done) return {bucket:'done',rel:''};
    const overdueAt=new Date(due); overdueAt.setDate(due.getDate()+grace);
    if(today>overdueAt) return {bucket:'overdue',rel};
    if(today>=due) return {bucket:'today',rel};
    return {bucket:'week',rel};
  }
  if(cfg.cadence==='monthly'){
    const M=today.getMonth()+1, Y=today.getFullYear(); let done=false;
    if(cfg.source_type==='booking_month') done=await uploadTargetDone(sb,'booking_month',projId,null,Y,M);
    else if(cfg.source_type==='longterm') done=await uploadTargetDone(sb,'longterm',projId,null,Y,null);
    else if(cfg.source_type==='forecast_sales'||cfg.source_type==='forecast_support'){ const kws=uploadWeeksOfMonth(Y,M); const skill=cfg.source_type==='forecast_sales'?'sales':'support'; done=await uploadPresent(()=>sb.from('report_forecast').select('*',{count:'exact',head:true}).eq('project_id',projId).eq('skill',skill).eq('year',Y).in('kw',kws)); }
    else { const last=lastMap[cfg.source_type]; done=!!(last && last.getFullYear()===Y && last.getMonth()+1===M); }
    const lastDay=new Date(Y,M,0).getDate(); const dd=Math.min(cfg.due_day||1,lastDay); const due=new Date(Y,M-1,dd); due.setHours(0,0,0,0); const rel=(CAL_MONTHS[M-1]||('Monat '+M));
    if(done) return {bucket:'done',rel:''};
    const overdueAt=new Date(due); overdueAt.setDate(due.getDate()+grace);
    if(today>overdueAt) return {bucket:'overdue',rel};
    if(today>=due) return {bucket:'today',rel};
    if(getISOWeek(due).kw===iso.kw) return {bucket:'week',rel};
    return {bucket:'upcoming',rel};
  }
  return {bucket:'inactive',rel:''};
}

Deno.serve(async (req)=>{
  const force = new URL(req.url).searchParams.get('force')==='1';   // manueller Test ausserhalb der Slots
  const only  = new URL(req.url).searchParams.get('only') || '';    // gezielter Test: nur diese uid ODER E-Mail
  const dry   = new URL(req.url).searchParams.get('dry')==='1';     // berechnen, aber NICHT senden (Verifikation)
  const berlinHour = Number(new Intl.DateTimeFormat('en-GB',{timeZone:'Europe/Berlin',hour:'2-digit',hour12:false}).format(new Date()));
  if(![9,12,16].includes(berlinHour) && !force) return json({skipped:'off-hours', berlinHour});

  const sb = createClient(SUPA_URL, SERVICE);
  const now=new Date(); const today=isoLocal(now);
  const mon=new Date(now); mon.setDate(now.getDate()-((now.getDay()+6)%7)); const monday=isoLocal(mon);
  const monthWeek=Math.ceil(now.getDate()/7);

  const [uRes, aRes, dRes, pRes, cRes, prRes, usRes, uoRes, tcRes, ocRes] = await Promise.all([
    sb.from('app_users').select('user_id,full_name,role_keys,active,mgmt_external'),
    sb.from('task_assignments').select('*'),
    sb.from('daily_tasks_done').select('task_key,date,assignee_user,project_id').in('date',[today,monday]),
    sb.from('notify_prefs').select('user_id,channel'),
    sb.from('app_config').select('value').eq('key','jsr_notify_channel_default').maybeSingle(),
    sb.from('projects').select('id,name'),
    sb.from('upload_schedule').select('*').eq('active',true),
    sb.from('upload_project_owner').select('project_id,responsible_user'),
    sb.from('task_catalog').select('key,owner,title,cadence,window_weeks,auto_key,count_key,data_gated').eq('active',true).order('seq'),
    sb.rpc('task_open_counts'),
  ]);
  // Katalog aus DB in die erwartete Form (window <- window_weeks, auto <- auto_key vorhanden). count/data_gated fuer das Gating.
  ROLE_TASKS = (tcRes.data||[]).map((r:any)=>({ key:r.key, owner:r.owner, title:r.title, cadence:r.cadence, window:r.window_weeks, auto:r.auto_key!=null, count:r.count_key, data_gated:r.data_gated }));
  if(!ROLE_TASKS.length) return json({ error:'task_catalog leer oder nicht lesbar' }, 500);
  // Geteilte Zaehler (task_open_counts) — DIESELBE Wahrheit wie das Frontend. Datengetriebene Aufgaben nur bei n>0.
  const ocMap:Record<string,number>={}; (ocRes.data||[]).forEach((r:any)=>{ ocMap[r.count_key+'|'+(r.project_id||'')]=Number(r.n)||0; });
  const gateCount=(t:any)=>{ const pk=t.count+'|'+(t.project_id||''); if(pk in ocMap) return ocMap[pk]; const gk=t.count+'|'; return (gk in ocMap)?ocMap[gk]:0; };
  const gatePass=(t:any)=>!t.data_gated || gateCount(t)>0;
  const doneSet=new Set((dRes.data||[]).map((r:any)=>r.task_key+'|'+r.date+'|'+(r.assignee_user||'')+'|'+(r.project_id||'')));
  const prefBy:Record<string,string>={}; (pRes.data||[]).forEach((r:any)=>prefBy[r.user_id]=r.channel);
  const projName:Record<string,string>={}; (prRes.data||[]).forEach((p:any)=>projName[p.id]=p.name);
  const defChannel = (cRes.data && cRes.data.value && (cRes.data.value.channel||cRes.data.value)) || 'slack';

  // E-Mails aus auth.users (Verknuepfung Slack/Cliq).
  const emailBy:Record<string,string>={};
  try{ const { data:al }=await sb.auth.admin.listUsers({ perPage:200 }); (al?.users||[]).forEach((u:any)=>{ if(u.email) emailBy[u.id]=u.email; }); }catch(_e){}

  const winActive=(t:any)=>!t.window||t.window.includes(monthWeek);
  const period=(t:any)=>t.cadence==='weekly'?monday:today;
  const isDone=(uid:string,t:any)=>doneSet.has(t.key+'|'+period(t)+'|'+uid+'|'+(t.project_id||'')) || (!t.project_id && doneSet.has(t.key+'|'+period(t)+'||'));

  // Upload-Faelligkeit vorbereiten: Zustaendigkeit je Projekt/Quelle (config.responsible_user ODER Projekt-Owner)
  // + Datenstand je Projekt (gecacht). today = Berlin-Kalendertag (fuer korrekte Faelligkeits-Vergleiche).
  const berlinNow = new Date(new Date().toLocaleString('en-US',{timeZone:'Europe/Berlin'}));
  const todayDate = new Date(berlinNow); todayDate.setHours(0,0,0,0);
  const ownerBy:Record<string,string>={}; (uoRes.data||[]).forEach((r:any)=>{ if(r.responsible_user) ownerBy[r.project_id]=r.responsible_user; });
  const cfgByUser:Record<string,any[]>={}; (usRes.data||[]).forEach((c:any)=>{ const resp=c.responsible_user||ownerBy[c.project_id]||null; if(resp) (cfgByUser[resp]=cfgByUser[resp]||[]).push(c); });
  const lastMapCache:Record<string,Record<string,Date>>={};
  async function lastMapFor(pid:string){ if(lastMapCache[pid]) return lastMapCache[pid]; const {data}=await sb.from('data_imports').select('source_type,created_at').eq('project_id',pid).order('created_at',{ascending:false}).limit(300); const m:Record<string,Date>={}; (data||[]).forEach((r:any)=>{ if(!m[r.source_type]) m[r.source_type]=new Date(r.created_at); }); lastMapCache[pid]=m; return m; }
  async function userDueUploads(uid:string){ const list=cfgByUser[uid]||[]; const out:any[]=[]; for(const c of list){ const lm=await lastMapFor(c.project_id); const st=await computeUploadStatus(sb,c,c.project_id,todayDate,lm); if(st.bucket==='overdue'||st.bucket==='today'||st.bucket==='week'){ out.push({label:UPLOAD_LABEL[c.source_type]||c.source_type, proj:projName[c.project_id]||c.project_id, rel:st.rel, overdue:st.bucket==='overdue'}); } } out.sort((a:any,b:any)=>(a.overdue?0:1)-(b.overdue?0:1)); return out; }

  const greet = berlinHour<10 ? 'Guten Morgen!' : berlinHour<13 ? 'Mittags-Erinnerung:' : 'Letzte Erinnerung für heute:';
  const results:any[]=[];
  for(const u of (uRes.data||[])){
    if(u.active===false) continue;
    if(only && u.user_id!==only && (emailBy[u.user_id]||'').toLowerCase()!==only.toLowerCase()) continue;
    const roles=taskRolesOf(u);
    const inst= roles.length ? effInstances(u.role_keys||[], (aRes.data||[]).filter((a:any)=>a.user_id===u.user_id)).filter(t=>!t.auto && winActive(t) && gatePass(t)) : [];
    const open=inst.filter(t=>!isDone(u.user_id,t));
    const dueU=await userDueUploads(u.user_id);
    if(!open.length && !dueU.length) continue;                   // nichts offen + keine Uploads -> keine Nachricht
    const channel = prefBy[u.user_id] || defChannel;
    if(channel==='none') { results.push({u:u.full_name,skip:'channel-none'}); continue; }
    const parts:string[]=[greet];
    if(open.length){ parts.push('*Offene Aufgaben ('+open.length+'):*'); open.forEach(t=>parts.push('• '+t.title+(t.project_id?(' · '+(projName[t.project_id]||t.project_id)):'')+(t.cadence==='weekly'?' (diese Woche)':''))); }
    if(dueU.length){ parts.push('*Uploads:*'); dueU.forEach((x:any)=>parts.push((x.overdue?'🚨 Überfällig: ':'• Fällig: ')+x.label+' · '+x.proj+(x.rel?(' ('+x.rel+')'):''))); }
    parts.push('\nErledigen im HR-Portal: '+PORTAL);
    const text=parts.join('\n');
    const outcome = dry ? 'dry' : (channel==='cliq' ? await cliqDM(emailBy[u.user_id], text) : await slackDM(emailBy[u.user_id], text));
    results.push({u:u.full_name, channel, open:open.length, uploads:dueU.length, outcome});
  }
  return json({berlinHour, sent:results.filter(r=>r.outcome==='sent').length, results});
});
