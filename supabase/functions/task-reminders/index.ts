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

// WICHTIG: kompaktes Spiegelbild von ROLE_TASKS aus frontend/hr.html — bei Katalog-Aenderungen HIER mitziehen.
// auto (Kalender-Pflichttermine) werden fuer Erinnerungen ausgelassen (monatlich, kein taeglicher Anstoss).
const ROLE_TASKS = [
  { key:'mgr_checkin', owner:['management','teamlead','projektleiter'], title:'Check-in: Anwesenheit bestätigen' },
  { key:'mgr_cv_abgleich', owner:'management', title:'CV-Abgleich HR' },
  { key:'mgr_cv_funnel', owner:'management', title:'CV-Funnel prüfen' },
  { key:'mgr_kunden', owner:'management', title:'Kundentelefonate & Wochen-Updates' },
  { key:'mgr_kpi', owner:'management', title:'KPI-Pflege je Skill', cadence:'weekly' },
  { key:'mgr_rechnung', owner:'management', title:'Rechnungserstellung', window:[1], auto:true },
  { key:'mgr_lohn', owner:'management', title:'Lohnlauf & Überweisung', window:[1], auto:true },
  { key:'hr_cv_select', owner:'hr', title:'Eingehende CVs selektieren' },
  { key:'hr_cv_phase', owner:'hr', title:'CVs in die richtige Phase' },
  { key:'hr_kommunikation', owner:'hr', title:'Bewerber-Kommunikation' },
  { key:'hr_interview', owner:'hr', title:'Vorstellungsgespräche' },
  { key:'hr_stammdaten', owner:'hr', title:'Stammdatenpflege', cadence:'weekly' },
  { key:'hr_vertraege', owner:'hr', title:'Arbeitsverträge', cadence:'weekly' },
  { key:'hr_hardware', owner:'hr', title:'Hardware-Koordination', cadence:'weekly' },
  { key:'hr_onboarding', owner:'hr', title:'Onboarding-Pflege' },
  { key:'hr_feedback', owner:'hr', title:'Mitarbeitergespräche' },
  { key:'hr_bonus', owner:'hr', title:'Bonuspflege', window:[1,2] },
  { key:'fin_re_in', owner:'finance', title:'Rechnungseingang' },
  { key:'fin_re_out', owner:'finance', title:'Rechnungsausgang' },
  { key:'fin_buchungen', owner:'finance', title:'Buchungen Buchhaltung' },
  { key:'fin_lohn', owner:'finance', title:'Gehaltsabrechnung & Löhne', window:[1], auto:true },
  { key:'fin_bwa', owner:'finance', title:'Monatsabschluss BWA', window:[1,2] },
  { key:'lead_shift', owner:['projektleiter','teamlead'], title:'Schichtplan aktuell halten' },
  { key:'lead_absence', owner:['projektleiter','teamlead'], title:'Abwesenheiten & Krankmeldungen' },
  { key:'lead_vacreq', owner:['projektleiter','teamlead'], title:'Urlaubsanträge entscheiden' },
  { key:'pl_kpi', owner:'projektleiter', title:'Kennzahlen des Projekts pflegen', cadence:'weekly' },
  { key:'pl_perf', owner:'projektleiter', title:'Team-Performance prüfen', cadence:'weekly' },
  { key:'pl_bericht', owner:'projektleiter', title:'Wochenbericht vorbereiten', cadence:'weekly' },
];
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

Deno.serve(async (req)=>{
  const force = new URL(req.url).searchParams.get('force')==='1';   // manueller Test ausserhalb der Slots
  const only  = new URL(req.url).searchParams.get('only') || '';    // gezielter Test: nur diese uid ODER E-Mail
  const berlinHour = Number(new Intl.DateTimeFormat('en-GB',{timeZone:'Europe/Berlin',hour:'2-digit',hour12:false}).format(new Date()));
  if(![9,12,16].includes(berlinHour) && !force) return json({skipped:'off-hours', berlinHour});

  const sb = createClient(SUPA_URL, SERVICE);
  const now=new Date(); const today=isoLocal(now);
  const mon=new Date(now); mon.setDate(now.getDate()-((now.getDay()+6)%7)); const monday=isoLocal(mon);
  const monthWeek=Math.ceil(now.getDate()/7);

  const [uRes, aRes, dRes, pRes, cRes, prRes] = await Promise.all([
    sb.from('app_users').select('user_id,full_name,role_keys,active,mgmt_external'),
    sb.from('task_assignments').select('*'),
    sb.from('daily_tasks_done').select('task_key,date,assignee_user,project_id').in('date',[today,monday]),
    sb.from('notify_prefs').select('user_id,channel'),
    sb.from('app_config').select('value').eq('key','jsr_notify_channel_default').maybeSingle(),
    sb.from('projects').select('id,name'),
  ]);
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

  const greet = berlinHour<10 ? 'Guten Morgen!' : berlinHour<13 ? 'Mittags-Erinnerung:' : 'Letzte Erinnerung für heute:';
  const results:any[]=[];
  for(const u of (uRes.data||[])){
    if(u.active===false) continue;
    if(only && u.user_id!==only && (emailBy[u.user_id]||'').toLowerCase()!==only.toLowerCase()) continue;
    const roles=taskRolesOf(u); if(!roles.length) continue;
    const inst=effInstances(u.role_keys||[], (aRes.data||[]).filter((a:any)=>a.user_id===u.user_id)).filter(t=>!t.auto && winActive(t));
    const open=inst.filter(t=>!isDone(u.user_id,t));
    if(!open.length) continue;                                   // alles erledigt -> keine Nachricht
    const channel = prefBy[u.user_id] || defChannel;
    if(channel==='none') { results.push({u:u.full_name,skip:'channel-none'}); continue; }
    const lines=open.map(t=>'• '+t.title+(t.project_id?(' · '+(projName[t.project_id]||t.project_id)):'')+(t.cadence==='weekly'?' (diese Woche)':''));
    const text=greet+' Du hast '+open.length+' offene Aufgabe'+(open.length===1?'':'n')+':\n'+lines.join('\n')+'\n\nErledigen im HR-Portal: '+PORTAL;
    const outcome = channel==='cliq' ? await cliqDM(emailBy[u.user_id], text) : await slackDM(emailBy[u.user_id], text);
    results.push({u:u.full_name, channel, open:open.length, outcome});
  }
  return json({berlinHour, sent:results.filter(r=>r.outcome==='sent').length, results});
});
