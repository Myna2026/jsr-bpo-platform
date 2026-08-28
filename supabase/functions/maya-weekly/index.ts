// Mayas Wochenmeldung (freitags 09:00 Berlin, Cron 07:00 UTC ~ Sommerzeit).
//  - An jede interne Person einzeln: ihre eigene Nutzung der letzten 7 Tage, mit Vergleich zur Vorwoche.
//    Kennzahl-Kacheln, Wochenverlauf als Balken, Mayas Beobachtung mit Bild, Knopf ins System.
//  - An die Geschäftsleitung (Rajner, Shkurte, Thorsten + info@mynaai.de): Zusammenfassung über alle,
//    Aktivität je Person als Balken vergleichbar.
//  - Kanäle: Mail (maya@25hrs.net über Zoho) UND Slack-DM. Nüchtern, kein Lob, kein Tadel.
//  Tive Master, Kunden-Zugänge und Testkonten bleiben außen vor.
// Modi: {mode:'send'} regulär · {mode:'preview', preview_to:'...'} Muster-Einzelfassung + Gesamt an EINE Adresse.
// Optik aus der geteilten Grundlage _shared/agent_mail.ts. Deploy: supabase functions deploy maya-weekly --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { agentBrand, tiles, barChart, hBars, observation, button, shell, delta, PORTAL_URL } from "../_shared/agent_mail.ts";
import { scheduleDue, getSchedule } from "../_shared/schedule.ts";

const SB_URL  = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const Z_HOST  = Deno.env.get("ZOHO_SMTP_HOST") || "smtppro.zoho.eu";
const Z_PORT  = Number(Deno.env.get("ZOHO_SMTP_PORT") || "465");
const SLACK   = Deno.env.get("SLACK_BOT_TOKEN") || "";
const OWNER_MAIL = "info@mynaai.de";   // "mich"
const cors = { "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods":"POST, OPTIONS" };
const json = (b:unknown, s=200)=> new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});
const sb = createClient(SB_URL, SERVICE);

// ── Zoho-SMTP ──
function b64utf8(s:string):string{ const b=new TextEncoder().encode(s); let bin=""; const CH=0x8000; for(let i=0;i<b.length;i+=CH) bin+=String.fromCharCode(...b.subarray(i,i+CH)); return btoa(bin); }
function encWord(s:string):string{ return /[^\x00-\x7F]/.test(s) ? "=?UTF-8?B?"+b64utf8(s)+"?=" : s; }
function smtpPass(key:string):string{ const cap=key.charAt(0).toUpperCase()+key.slice(1).toLowerCase(); for(const v of [key.toUpperCase(),key,key.toLowerCase(),cap]){ const val=Deno.env.get("ZOHO_SMTP_PASS_"+v); if(val) return val; } return ""; }
function buildMessage(sender:any,to:string,subject:string,html:string):string{
  const b64=b64utf8(html).replace(/(.{76})/g,"$1\r\n");
  const headers=["From: "+encWord(sender.fromName)+" <"+sender.email+">","To: "+to,"Subject: "+encWord(subject),"MIME-Version: 1.0","Content-Type: text/html; charset=utf-8","Content-Transfer-Encoding: base64","Date: "+new Date().toUTCString(),"Message-ID: <"+crypto.randomUUID()+"@25hrs.net>"].join("\r\n");
  return headers+"\r\n\r\n"+b64+"\r\n.\r\n";
}
async function smtpSend(sender:any,to:string,subject:string,html:string):Promise<{ok:boolean;error?:string}>{
  const pass=smtpPass(sender.key); if(!pass) return {ok:false,error:"Secret ZOHO_SMTP_PASS_"+sender.key.toUpperCase()+" fehlt"};
  const enc=new TextEncoder(), dec=new TextDecoder(); let conn:Deno.TlsConn|null=null;
  try{
    conn=await Deno.connectTls({hostname:Z_HOST,port:Z_PORT}); const rbuf=new Uint8Array(8192);
    const read=async():Promise<string>=>{ let acc=""; for(;;){ const n=await conn!.read(rbuf); if(n===null) break; acc+=dec.decode(rbuf.subarray(0,n)); const lines=acc.split(/\r?\n/).filter(l=>l.length); if(lines.length&&/^\d{3} /.test(lines[lines.length-1])) break; } return acc; };
    const cmd=async(line:string,expect:string,label:string)=>{ await conn!.write(enc.encode(line+"\r\n")); const r=await read(); if(!r.trimStart().startsWith(expect)) throw new Error(label+": "+r.trim().slice(0,200)); };
    await read(); await cmd("EHLO 25hrs.net","250","EHLO"); await cmd("AUTH LOGIN","334","AUTH");
    await cmd(btoa(sender.email),"334","USER"); await cmd(btoa(pass),"235","PASS");
    await cmd("MAIL FROM:<"+sender.email+">","250","MAIL FROM"); await cmd("RCPT TO:<"+to+">","250","RCPT TO"); await cmd("DATA","354","DATA");
    await conn.write(enc.encode(buildMessage(sender,to,subject,html))); const done=await read();
    if(!done.trimStart().startsWith("250")) throw new Error("nach DATA: "+done.trim().slice(0,200));
    try{ await conn.write(enc.encode("QUIT\r\n")); }catch(_e){}
    return {ok:true};
  }catch(e){ return {ok:false,error:"SMTP: "+((e as Error).message||String(e))}; }
  finally{ if(conn){ try{ conn.close(); }catch(_e){} } }
}
async function slackDM(email:string|undefined, text:string):Promise<string>{
  if(!SLACK) return "no-slack-token"; if(!email) return "no-email";
  const lu=await (await fetch("https://slack.com/api/users.lookupByEmail?email="+encodeURIComponent(email),{headers:{Authorization:"Bearer "+SLACK}})).json();
  if(!lu.ok) return "no-slack-user";
  const o=await (await fetch("https://slack.com/api/conversations.open",{method:"POST",headers:{Authorization:"Bearer "+SLACK,"Content-Type":"application/json"},body:JSON.stringify({users:lu.user.id})})).json();
  if(!o.ok) return "open-fail";
  const m=await (await fetch("https://slack.com/api/chat.postMessage",{method:"POST",headers:{Authorization:"Bearer "+SLACK,"Content-Type":"application/json"},body:JSON.stringify({channel:o.channel.id,text})})).json();
  return m.ok?"sent":("post:"+(m.error||"?"));
}

// ── Helfer ──
function berlinToday():string{ const b=new Date(new Date().toLocaleString("en-US",{timeZone:"Europe/Berlin"})); return b.toISOString().slice(0,10); }
function addDays(d:string,n:number){ const x=new Date(d+"T00:00:00Z"); x.setUTCDate(x.getUTCDate()+n); return x.toISOString().slice(0,10); }
function deDate(d:string){ const [y,m,da]=d.split("-"); return da+"."+m+"."+y; }
function wdLabel(iso:string){ const dt=new Date(iso+"T12:00:00Z"); return ["So","Mo","Di","Mi","Do","Fr","Sa"][dt.getUTCDay()]; }
function daysBetween(fromD:string,toD:string){ const a:string[]=[]; let d=fromD; for(let i=0;i<14;i++){ a.push(d); if(d===toD) break; d=addDays(d,1); } return a; }
function fmtMins(mins:number){ const h=Math.floor(mins/60), m=Math.round(mins%60); return h>0 ? (h+" h"+(m>0?" "+m+" min":"")) : (m+" min"); }
function tage(n:number){ return n===1 ? "1 Tag" : n+" Tage"; }
function anTagen(n:number){ return n===1 ? "an 1 Tag" : "an "+n+" Tagen"; }
function entityLabel(k:string){ const M:Record<string,string>={employees:"Mitarbeiter",cvs:"Bewerber",shift_assignments:"Schichtplan",kpi_entries:"Kennzahlen",absences:"Abwesenheiten",shift_checkins:"Check-ins",meeting_notes:"Besprechungen",app_users:"Zugänge",presentations:"Präsentationen"}; return M[k]||k; }

// Funktions-Gruppen: der Vergleich ist NUR innerhalb einer Funktion sinnvoll (ein Teamleiter erzeugt
// wenig Änderungen, aber führt; eine HR-Kraft pflegt viel). Priorität von oben.
const FUNCS = [
  { key:"management",     label:"Management",     roles:["management"],    lead:true  },
  { key:"projektleitung", label:"Projektleitung", roles:["projektleiter"], lead:true  },
  { key:"teamleitung",    label:"Teamleitung",    roles:["teamlead"],      lead:true  },
  { key:"hr",             label:"HR",             roles:["hr"],            lead:false },
  { key:"mitarbeiter",    label:"Mitarbeiter",    roles:["mitarbeiter"],   lead:false },
];
function funcOf(roleKeys:string[]){ for(const f of FUNCS){ if((roleKeys||[]).some(r=>f.roles.includes(r))) return f; } return FUNCS[FUNCS.length-1]; }

// EINE Wahrheit für Anwesenheit: präsent an einem Tag = IRGENDEIN Signal — Login, View (areas), Änderung,
// erledigte Aufgabe ODER Heartbeat-Sitzung. NICHT nur Änderungen (sonst steht eine Führungskraft, die
// nur nachsieht, fälschlich auf 0). Anmeldungen aus activity_log (login), Zeit/Minuten aus user_sessions.
type Agg = { uid:string; name:string; funcKey:string; logins:number; sessions:number; mins:number; days:Set<string>; writes:number; ent:Record<string,number>; done:number; empty:number; perDay:Record<string,number> };
function newAgg(uid:string,name:string,funcKey:string):Agg{ return {uid,name,funcKey,logins:0,sessions:0,mins:0,days:new Set(),writes:0,ent:{},done:0,empty:0,perDay:{}}; }
function isActive(a:Agg){ return a.days.size>0 || a.writes>0 || a.logins>0; }
function foldMetrics(rows:any[], into:Record<string,Agg>){
  rows.forEach((m:any)=>{ const a=into[m.user_id]; if(!a) return;
    a.logins+=(m.logins||0); a.sessions+=(m.sessions||0); a.mins+=(m.active_minutes||0); a.writes+=(m.writes||0); a.done+=(m.tasks_done||0); a.empty+=(m.tasks_empty||0);
    a.perDay[m.day]=(a.perDay[m.day]||0)+(m.writes||0);
    const present=(m.writes||0)>0||(m.logins||0)>0||(m.sessions||0)>0||(m.tasks_done||0)>0||(Array.isArray(m.areas)&&m.areas.length>0);
    if(present) a.days.add(m.day);
    const wbe=m.writes_by_entity||{}; Object.keys(wbe).forEach(k=>{ a.ent[k]=(a.ent[k]||0)+Number(wbe[k]||0); }); });
}

// Slack-Text. Anmeldungen werden NICHT gezeigt: der Login-Eintrag entsteht nur bei NEUER Sitzung, nicht bei
// Wiederkehr -> die Zahl wäre sichtbar falsch (0 trotz Präsenz). Verlässlich sind die aktiven Tage. Zeit nur
// mit Sitzungsdaten (Heartbeat).
function personText(a:Agg, fromD:string, toD:string, minutesOn:boolean){
  const period="vom "+deDate(fromD)+" bis "+deDate(toD);
  if(!isActive(a)) return "Deine Woche "+period+": keine Aktivität im System.";
  const top=Object.entries(a.ent).sort((x,y)=>y[1]-x[1]).slice(0,3).map(([k])=>entityLabel(k));
  const pres = minutesOn ? (fmtMins(a.mins)+" im System, ") : "";
  return "Deine Woche "+period+": "+pres+"aktiv "+anTagen(a.days.size)+", "+a.writes+" Einträge bearbeitet"+(top.length?" ("+top.join(", ")+")":"")+", "+a.done+" Aufgaben erledigt"+(a.empty>0?", davon "+a.empty+" ohne erkennbare Änderung":"")+".";
}

// Mayas Beobachtung, nüchtern: Vergleich zur Vorwoche, kein Wertungswort.
// Leere Häkchen (abgehakt ohne Datenänderung) werden nüchtern benannt, ohne Wertung.
function personObs(a:Agg, p:Agg|undefined, minutesOn:boolean){
  if(!isActive(a)) return "Diese Woche keine Aktivität im System. In der Vorwoche "+anTagen((p&&p.days.size)||0)+" aktiv.";
  const pres = minutesOn ? (fmtMins(a.mins)+" im System, ") : "";
  const s1=pres+"aktiv "+anTagen(a.days.size)+(p?" (Vorwoche "+p.days.size+")":"")+". "+a.writes+" Einträge bearbeitet"+(p?" (Vorwoche "+p.writes+")":"")+".";
  let s2="";
  if(p){ const d=(a.writes+a.days.size)-(p.writes+p.days.size); s2=d===0?" Etwa gleich wie in der Vorwoche.":(d>0?" Mehr Bewegung als in der Vorwoche.":" Weniger Bewegung als in der Vorwoche."); }
  const s3 = a.done>0 ? (" "+a.done+" Aufgaben erledigt"+(a.empty>0?", davon "+a.empty+" ohne erkennbare Änderung":"")+".") : "";
  return s1+s2+s3;
}

function personInner(brand:any, a:Agg, p:Agg|undefined, fromD:string, toD:string, minutesOn:boolean){
  const days=daysBetween(fromD,toD);
  const pt:any[]=[{ big:a.days.size, label:"aktive Tage", sub: p?delta(a.days.size,p.days.size):"" }];
  if(minutesOn) pt.push({ big:fmtMins(a.mins), label:"Zeit im System", sub:"" });
  pt.push({ big:a.writes, label:"Änderungen", sub: p?delta(a.writes,p.writes):"" });
  if(pt.length<4) pt.push({ big:a.done, label:"Aufgaben erledigt", sub: a.empty>0 ? ("davon "+a.empty+" ohne Änderung") : (p?delta(a.done,p.done):"") });
  const t = tiles(pt.slice(0,4));
  const bars = barChart("Wochenverlauf · bearbeitete Einträge je Tag", days.map(d=>({label:wdLabel(d), value:a.perDay[d]||0})), brand.accent);
  return t + bars + observation(brand, personObs(a,p,minutesOn)) + button(PORTAL_URL, "Zum System →", brand.accent);
}

// Beobachtung je Funktion, nüchtern. Führung: wer war (nicht) im System (nach aktiven Tagen). Doer: Änderungen.
function perFuncObs(f:any, ppl:Agg[]){
  const idle = ppl.filter(a=>!isActive(a)).map(a=>a.name);
  if(f.lead){
    const top=ppl.slice().sort((x,y)=>y.days.size-x.days.size)[0];
    if(top && top.days.size>0) return f.label+": "+top.name+" am häufigsten im System ("+tage(top.days.size)+")"+(idle.length?", nicht drin: "+idle.join(", "):"")+".";
    if(idle.length) return f.label+": nicht im System: "+idle.join(", ")+".";
    return f.label+": alle waren im System.";
  }
  const totW=ppl.reduce((s,a)=>s+a.writes,0);
  return f.label+": "+totW+" Änderungen"+(idle.length?", ohne Aktivität: "+idle.join(", "):"")+".";
}

function overviewInner(brand:any, list:Agg[], prevTot:{writes:number,active:number,done:number}, fromD:string, toD:string, minutesOn:boolean){
  const active=list.filter(isActive);
  const totMin=list.reduce((s,a)=>s+a.mins,0), totW=list.reduce((s,a)=>s+a.writes,0), totDone=list.reduce((s,a)=>s+a.done,0), totEmpty=list.reduce((s,a)=>s+a.empty,0);
  const doneSub = totEmpty>0 ? ("davon "+totEmpty+" ohne Änderung") : delta(totDone, prevTot.done);
  const ot:any[]=[{ big:active.length+"/"+list.length, label:"Zugänge aktiv", sub: delta(active.length, prevTot.active) }];
  if(minutesOn) ot.push({ big:fmtMins(totMin), label:"Zeit im System", sub:"" });
  ot.push({ big:totW, label:"Änderungen", sub: delta(totW, prevTot.writes) });
  if(ot.length<4) ot.push({ big:totDone, label:"Aufgaben erledigt", sub: doneSub });
  const t = tiles(ot.slice(0,4));
  // Nach Funktion gruppiert — Vergleich NUR innerhalb der Gruppe. Führung nach AKTIVEN TAGEN (verlässliche
  // Präsenz: Login/View/Änderung/Aufgabe/Sitzung), HR/Mitarbeiter nach Änderungen.
  let sections="";
  const funcObs:string[]=[];
  FUNCS.forEach(f=>{ const ppl=list.filter(a=>a.funcKey===f.key); if(!ppl.length) return;
    const rows = ppl.slice().sort((x,y)=> f.lead ? ((y.days.size-x.days.size)||(y.writes-x.writes)) : ((y.writes-x.writes)||(y.days.size-x.days.size)))
      .map(a=>{ const zeit=minutesOn?fmtMins(a.mins):null;
        const parts = f.lead ? [tage(a.days.size), zeit, a.writes+" Änd"] : [a.writes+" Änd", tage(a.days.size)];
        return { label:a.name, value: f.lead ? a.days.size : a.writes, note: parts.filter(Boolean).join(" · ") }; });
    sections += hBars(f.label+" ("+ppl.length+")"+(f.lead?" · nach Anwesenheit":""), rows, brand.accent);
    funcObs.push(perFuncObs(f, ppl));
  });
  const tasksLine = totDone>0 ? (" Insgesamt "+totDone+" Aufgaben erledigt"+(totEmpty>0?", davon "+totEmpty+" ohne erkennbare Änderung":"")+".") : "";
  const noteZeit = minutesOn ? "" : " Zeit im System füllt sich ab jetzt.";
  const obs = funcObs.join(" ") + tasksLine + noteZeit;
  return t + sections + observation(brand, obs) + button(PORTAL_URL, "Zum System →", brand.accent);
}

Deno.serve(async (req)=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
  let body:any={}; try{ body=await req.json(); }catch(_e){}
  const mode = body.mode==="preview" ? "preview" : "send";
  // Zentrale Zeitsteuerung: der reguläre Versand feuert nur zur geplanten Zeit (Standard Fr 09:00). preview/dry/force frei.
  if(mode==="send"){ const sched=await getSchedule(sb,"maya_weekly"); if(!body.force && !scheduleDue(sched)) return json({ok:true,skipped:"not-scheduled"}); }
  // Personen, die die Wochenmeldung abbestellt haben (reminder_schedule je Person, active=false).
  const {data:_optOut}=await sb.from("reminder_schedule").select("user_id").eq("reminder_key","maya_weekly").eq("active",false).not("user_id","is",null);
  const optOff=new Set((_optOut||[]).map((r:any)=>r.user_id));
  const toD = (typeof body.to==="string"&&/^\d{4}-\d{2}-\d{2}$/.test(body.to)) ? body.to : addDays(berlinToday(),-1);
  const fromD = (typeof body.from==="string"&&/^\d{4}-\d{2}-\d{2}$/.test(body.from)) ? body.from : addDays(toD,-6);
  const pToD = addDays(fromD,-1), pFromD = addDays(pToD,-6);   // Vorwoche

  const sender = await (async()=>{ const {data}=await sb.from("ai_agents").select("key,name,email,mail_from_name").eq("key","maya").maybeSingle(); return data&&data.email?{key:data.key,name:data.name,email:data.email,fromName:data.mail_from_name||data.name}:null; })();
  if(!sender) return json({error:"Maya hat keine Absenderadresse im Register"},503);
  const brand = await agentBrand(sb,"maya","#0e7490");

  const { data:metrics, error } = await sb.rpc("usage_day_metrics",{ p_from:fromD, p_to:toD });
  if(error) return json({error:"Kennzahlen: "+error.message},502);
  const { data:pMetrics } = await sb.rpc("usage_day_metrics",{ p_from:pFromD, p_to:pToD });
  const { data:users } = await sb.from("app_users").select("user_id,full_name,role_keys,active");
  let emailBy:Record<string,string>={}; try{ const {data:al}=await sb.auth.admin.listUsers({perPage:200}); (al?.users||[]).forEach((u:any)=>{ if(u.email) emailBy[u.id]=u.email; }); }catch(_e){}

  // Nur echte interne Mitarbeiter: aktiv, mit mindestens einer internen Rolle. Schließt Kunden, rollenlose
  // (halb angelegte) und technische/Test-Zugänge aus (z. B. der namenlose rollenlose „Zugang").
  const INTERNAL_ROLES=["management","hr","teamlead","projektleiter","mitarbeiter"];
  const isInternal=(u:any)=>{ const roles=u.role_keys||[]; const nm=(u.full_name||"").toLowerCase();
    if(!u.active) return false;
    if(!roles.some((r:string)=>INTERNAL_ROLES.includes(r))) return false;
    if(nm.includes("tive master")||nm.includes("test")||nm.includes(" ag")) return false; return true; };
  const internal=(users||[]).filter(isInternal);

  const aggBy:Record<string,Agg>={}, pAggBy:Record<string,Agg>={};
  internal.forEach(u=>{ const fk=funcOf(u.role_keys).key; aggBy[u.user_id]=newAgg(u.user_id,u.full_name||"Zugang",fk); pAggBy[u.user_id]=newAgg(u.user_id,u.full_name||"Zugang",fk); });
  foldMetrics(metrics||[], aggBy); foldMetrics(pMetrics||[], pAggBy);
  const aggList=Object.values(aggBy);
  const prevActive=Object.values(pAggBy).filter(isActive).length;
  const prevTot={ writes:Object.values(pAggBy).reduce((s,a)=>s+a.writes,0), active:prevActive, done:Object.values(pAggBy).reduce((s,a)=>s+a.done,0) };
  // Anmeldungen werden nicht gezeigt (Login nur bei neuer Sitzung -> unzuverlässig). Zeit aus dem Heartbeat.
  const minutesOn = aggList.some(a=>a.mins>0);

  const mgrUids=(users||[]).filter(u=>u.active&&(u.role_keys||[]).includes("management")&&!(String(u.full_name||"").toLowerCase().match(/tive master|test/))).map(u=>u.user_id);
  const mgrMails=[...new Set(mgrUids.map(uid=>emailBy[uid]).filter(Boolean).concat([OWNER_MAIL]))];
  const sub="Nutzung "+deDate(fromD)+"–"+deDate(toD);
  const logAction=async(kind:string,meta:any)=>{ try{ await sb.from("agent_actions").insert({agent_key:"maya",kind,meta}); }catch(_e){} };
  const results:any[]=[];

  if(body.dry){
    const sample = aggList.slice().sort((x,y)=>(y.writes+y.mins)-(x.writes+x.mins))[0];
    return json({ok:true,dry:true,
      html_person: sample?shell(brand,"Deine Woche im System",sub,personInner(brand,sample,pAggBy[sample.uid],fromD,toD,minutesOn)):null,
      html_overview: shell(brand,"Nutzung über alle",sub,overviewInner(brand,aggList,prevTot,fromD,toD,minutesOn)) });
  }
  if(mode==="preview"){
    const to = (typeof body.preview_to==="string"&&body.preview_to.includes("@")) ? body.preview_to : OWNER_MAIL;
    const sample = aggList.slice().sort((x,y)=>(y.writes+y.mins)-(x.writes+x.mins))[0];
    if(sample){ const p=pAggBy[sample.uid];
      const html=shell(brand, "Deine Woche im System", sub+" · Vorschau (Muster: "+sample.name+")", personInner(brand,sample,p,fromD,toD,minutesOn));
      const r=await smtpSend(sender,to,"Vorschau · Maya Wochenmeldung (persönliche Fassung)",html); results.push({kind:"preview_person",sample:sample.name,mail:r.ok?"sent":r.error}); }
    const html2=shell(brand, "Nutzung über alle", sub+" · Vorschau", overviewInner(brand,aggList,prevTot,fromD,toD,minutesOn));
    const r2=await smtpSend(sender,to,"Vorschau · Maya Wochenmeldung (Zusammenfassung über alle)",html2); results.push({kind:"preview_overview",mail:r2.ok?"sent":r2.error});
    return json({ok:true,mode,to,window:{from:fromD,to:toD},persons:aggList.length,managers:mgrMails,results});
  }

  for(const a of aggList){ if(optOff.has(a.uid)){ results.push({person:a.name,skipped:"opt-out"}); continue; } const email=emailBy[a.uid]; const p=pAggBy[a.uid];
    const html=shell(brand, "Deine Woche im System", sub, personInner(brand,a,p,fromD,toD,minutesOn));
    const mr = email ? await smtpSend(sender,email,"Deine Woche im System · "+deDate(fromD)+"–"+deDate(toD),html) : {ok:false,error:"no-email"};
    const sr = await slackDM(email, personText(a,fromD,toD,minutesOn));
    results.push({person:a.name,mail:mr.ok?"sent":mr.error,slack:sr});
    await logAction("weekly_person",{user:a.name,mail:mr.ok,slack:sr});
  }
  for(const mail of mgrMails){ const html=shell(brand, "Nutzung über alle", sub, overviewInner(brand,aggList,prevTot,fromD,toD,minutesOn));
    const mr=await smtpSend(sender,mail,"Nutzung über alle · Woche "+deDate(fromD)+"–"+deDate(toD),html);
    const sr=await slackDM(mail, "*Maya · Nutzung über alle* ("+deDate(fromD)+"–"+deDate(toD)+")\n"+aggList.filter(isActive).length+" von "+aggList.length+" Zugängen aktiv. Details in der Mail.");
    results.push({overview_to:mail,mail:mr.ok?"sent":mr.error,slack:sr});
    await logAction("weekly_overview",{to:mail,mail:mr.ok});
  }
  return json({ok:true,mode,window:{from:fromD,to:toD},persons:aggList.length,managers:mgrMails,results});
});
