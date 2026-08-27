// Maya, Systemüberwachung: EIN nüchterner Satz je aktivem Nutzer pro Tag — was hat die Person im System
// bewegt. Betont ECHTE Datenänderungen; abgehakte Aufgaben ohne Datenänderung werden neutral benannt.
// Läuft täglich per Cron für den Vortag (mode 'run'), kann aber auch für ein beliebiges Datum aufgerufen werden.
// Sachlich, keine Wertung, keine kumpelhafte Sprache (Maya beobachtet die Nutzung; ein freundlicher Ton
// würde sie zum Aufpasser machen). Kennzahlen aus usage_day_metrics, Sätze in usage_digests.
// Deploy: supabase functions deploy usage-digest
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods":"POST, OPTIONS" };
const json = (b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});

const MODEL = "claude-sonnet-5";
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") || "";
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const sb = createClient(SB_URL, SERVICE);

const AREA: Record<string,string> = { cv:"Bewerber", employee:"Mitarbeiter", shift_assignment:"Schichtplan", absence:"Abwesenheiten", kpi:"Kennzahlen", project:"Projekte", payroll_input:"Löhne", meeting_note:"Besprechungen", feedback:"Feedbackgespräche", presentation:"Präsentationen" };

function yesterdayBerlin(): string {
  const now = new Date();
  const berlin = new Date(now.toLocaleString("en-US",{timeZone:"Europe/Berlin"}));
  berlin.setDate(berlin.getDate()-1);
  return berlin.toISOString().slice(0,10);
}

function profileText(r:any): string {
  const parts:string[]=[];
  if(r.sessions>0) parts.push(`${r.sessions} Sitzung(en), rund ${r.active_minutes} Min. anwesend`);
  else if(r.logins>0) parts.push(`${r.logins} Anmeldung(en)`);
  const be = r.writes_by_entity||{};
  const wl = Object.keys(be).map(k=>`${AREA[k]||k}: ${be[k]}`).join(", ");
  parts.push(r.writes>0 ? `${r.writes} Datenänderung(en)${wl?" ("+wl+")":""}` : "keine Datenänderungen");
  if(Array.isArray(r.areas) && r.areas.length) parts.push("besuchte Bereiche: "+r.areas.map((a:string)=>AREA[a]||a).join(", "));
  if(r.tasks_done>0) parts.push(`${r.tasks_done} Tagesaufgabe(n) abgehakt${r.tasks_empty>0?`, davon ${r.tasks_empty} ohne begleitende Datenänderung`:""}`);
  return parts.join("; ");
}

const TOOL = { name:"satz", description:"Ein nüchterner Satz.", input_schema:{ type:"object", properties:{ summary:{type:"string", description:"genau EIN Satz, sachlich, deutsch"} }, required:["summary"] } };

async function summarize(name:string, prof:string): Promise<string> {
  const system = "Du bist Maya, die Systemüberwachung. Du fasst nüchtern zusammen, was eine Person an einem Tag im System bewegt hat. "+
    "Regeln: GENAU EIN Satz. Sachlich, keine Wertung, keine kumpelhafte Sprache, keine Lob-/Tadel-Wörter (kein 'fleißig', 'faul', 'gut', 'wenig'). "+
    "Zeig was IST, bewerte nicht. Betone echte Datenänderungen. Wenn Aufgaben abgehakt wurden ohne begleitende Datenänderung, benenne das neutral und klar. "+
    "Nutze NUR die gegebenen Kennzahlen, erfinde nichts. Schreib in der dritten Person mit dem Namen. "+
    "Schreib zeitneutral (z. B. 'hat ... vorgenommen'), NICHT 'heute'/'am heutigen Tag' — der Bezugstag ist durch den Kontext gegeben.";
  const user = `Person: ${name}\nKennzahlen des Tages: ${prof}`;
  const r = await fetch("https://api.anthropic.com/v1/messages",{ method:"POST",
    headers:{ "x-api-key":ANTHROPIC_KEY, "anthropic-version":"2023-06-01", "content-type":"application/json" },
    body: JSON.stringify({ model:MODEL, max_tokens:300, system, tools:[TOOL], tool_choice:{type:"tool",name:"satz"}, messages:[{role:"user",content:user}] }) });
  const d = await r.json();
  if(!r.ok) throw new Error((d?.error?.message)||("HTTP "+r.status));
  const tu = (d.content||[]).find((c:any)=>c.type==="tool_use");
  return (tu && tu.input && tu.input.summary) || "";
}

// ── Kollegen-Stimme (Schnitt 3): aus Rohzahl + Vorperiode + Konfidenz einen Satz IM CHARAKTER des Kollegen ──
// Persona kommt aus dem Register (ai_agents.persona, im Admin änderbar). Die Hausregeln gelten für alle:
// Deutsch als Zweitsprache, keine Emotionen, nichts erfinden, Sicherheit hörbar, Grenze benennen, weiterreichen.
const PERSONAE: Record<string,string> = {};
async function personaOf(key:string): Promise<string> {
  if(PERSONAE[key]!==undefined) return PERSONAE[key];
  const { data } = await sb.from("ai_agents").select("persona").eq("key",key).maybeSingle();
  PERSONAE[key] = (data&&data.persona) || ""; return PERSONAE[key];
}
const HOUSE = "Hausregeln: Deutsch als Zweitsprache — kurze Sätze, kein Konjunktiv, keine Redewendungen. "+
  "Keine Emotionen, kein Lob, kein Tadel. Erfinde nichts: nutze NUR die gegebenen Zahlen. "+
  "Nenne den Vergleich zur Vorperiode, wenn er gegeben ist (z. B. 'letzte Woche 45'). "+
  "Mach die Sicherheit hörbar, wenn gegeben (exakt / Obergrenze / Vermutung). "+
  "Wenn etwas fehlt, sag klar was fehlt und dass die Zahl dann leer ist, nicht falsch. "+
  "Wenn ein Thema zu einem anderen Kollegen gehört, verweise kurz auf ihn. "+
  "Höchstens zwei kurze Sätze. Keine Zusagen. Schreib in der dritten Person mit dem Namen.";
async function colleagueLine(name:string, persona:string, brief:any): Promise<string> {
  const facts = (brief.facts||[]).map((f:any)=> `${f.label}: ${f.current}${(f.prior!==undefined&&f.prior!==null)?` (Vorperiode ${f.prior})`:""}`).join("; ");
  const parts = [`Kollege: ${name}`, `Fakten: ${facts}`];
  if(brief.confidence) parts.push(`Sicherheit: ${brief.confidence}`);
  if(brief.missing) parts.push(`Fehlt: ${brief.missing}`);
  if(brief.handoff) parts.push(`Gehört zu: ${brief.handoff}`);
  const system = (persona? persona+"\n\n":"") + HOUSE;
  const r = await fetch("https://api.anthropic.com/v1/messages",{ method:"POST",
    headers:{ "x-api-key":ANTHROPIC_KEY, "anthropic-version":"2023-06-01", "content-type":"application/json" },
    body: JSON.stringify({ model:MODEL, max_tokens:220, system, tools:[TOOL], tool_choice:{type:"tool",name:"satz"}, messages:[{role:"user",content:parts.join("\n")}] }) });
  const d = await r.json();
  if(!r.ok) throw new Error((d?.error?.message)||("HTTP "+r.status));
  const tu = (d.content||[]).find((c:any)=>c.type==="tool_use");
  return (tu && tu.input && tu.input.summary) || "";
}
function prevDay(d:string){ const x=new Date(d+"T00:00:00Z"); x.setUTCDate(x.getUTCDate()-1); return x.toISOString().slice(0,10); }
function nextDay(d:string){ const x=new Date(d+"T00:00:00Z"); x.setUTCDate(x.getUTCDate()+1); return x.toISOString().slice(0,10); }

Deno.serve(async (req)=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
  if(!ANTHROPIC_KEY) return json({error:"ANTHROPIC_API_KEY fehlt"},503);
  let body:any={}; try{ body=await req.json(); }catch(_e){}
  const date = (typeof body.date==="string" && /^\d{4}-\d{2}-\d{2}$/.test(body.date)) ? body.date : yesterdayBerlin();

  const { data:rows, error } = await sb.rpc("usage_day_metrics", { p_from: date, p_to: date });
  if(error) return json({error:"Kennzahlen: "+error.message},502);

  // Nur aktive Nutzer (irgendein Signal an dem Tag).
  const active = (rows||[]).filter((r:any)=> r.sessions>0 || r.logins>0 || r.writes>0 || r.tasks_done>0 || (Array.isArray(r.areas)&&r.areas.length));
  let done=0, failed=0;
  for(const r of active){
    try{
      const summary = await summarize(r.user_name||"Nutzer", profileText(r));
      const { error:ue } = await sb.from("usage_digests").upsert({ day:date, user_id:r.user_id, user_name:r.user_name,
        summary, metrics:{ sessions:r.sessions, active_minutes:r.active_minutes, logins:r.logins, writes:r.writes,
          writes_by_entity:r.writes_by_entity, areas:r.areas, tasks_done:r.tasks_done, tasks_empty:r.tasks_empty } },
        { onConflict:"day,user_id" });
      if(ue) failed++; else done++;
    }catch(_e){ failed++; }
  }
  // ── Clara: Bewerbungen vorsortiert + Anreicherungs-Mails, mit Vortagsvergleich, in Claras Stimme. ──
  try{
    const p = prevDay(date), n1 = nextDay(date);
    const cnt = async (tbl:string,col:string,from:string,to:string,f:(x:any)=>any)=>{ const r=await f(sb.from(tbl).select("id",{count:"exact",head:true})).gte(col,from).lt(col,to); return r.count||0; };
    const sorted  = await cnt("cvs","created_at",date,n1,(x)=>x.eq("source","meta"));
    const mails   = await cnt("applicant_messages","sent_at",date,n1,(x)=>x.eq("origin","auto").eq("status","sent"));
    const sortedP = await cnt("cvs","created_at",p,date,(x)=>x.eq("source","meta"));
    const mailsP  = await cnt("applicant_messages","sent_at",p,date,(x)=>x.eq("origin","auto").eq("status","sent"));
    // Recruiting-Marketing überwachen (Qualität + Kampagnen-Vergleiche). Gehört Clara: sie kennt die Bewerber
    // und beurteilt, ob eine Kampagne gute bringt. Der Ausbleib-Wächter (agent-observe) ist die Grundlage.
    let mkFind:any[]=[]; try{ const {data}=await sb.rpc("clara_marketing_scan"); mkFind=(data||[]) as any[]; }catch(_e){}
    const mkOrder:Record<string,number>={qualitaet:0,daten_fehlt:1,kampagne:2};
    mkFind.sort((a,b)=>(mkOrder[a.category]??9)-(mkOrder[b.category]??9));
    if(sorted>0 || mails>0 || mkFind.length){
      const facts:any[]=[];
      if(sorted>0) facts.push({label:"Bewerbungen vorsortiert", current:sorted, prior:sortedP});
      if(mails>0)  facts.push({label:"Anreicherungs-Mails verschickt", current:mails, prior:mailsP});
      mkFind.slice(0,4).forEach((f:any)=>facts.push({label:f.detail}));
      let summary=""; try{ summary = await colleagueLine("Clara", await personaOf("clara"), {facts, confidence:"exakt"}); }catch(_e){}
      if(!summary){ const b:string[]=[]; if(sorted>0)b.push(`${sorted} Bewerbungen vorsortiert`); if(mails>0)b.push(`${mails} Anreicherungs-Mails verschickt`); mkFind.slice(0,2).forEach((f:any)=>b.push(f.detail)); summary="Clara: "+b.join("; ")+"."; }
      await sb.from("agent_digests").upsert({ day:date, agent_key:"clara", name:"Clara", summary, metrics:{sorted,mails,sorted_prev:sortedP,mails_prev:mailsP, marketing: mkFind.slice(0,30)} }, {onConflict:"day,agent_key"});
    }
  }catch(_e){ /* Agenten-Zeile optional */ }

  // ── Max/Paul/Anna aus agent_actions, mit Vortagsvergleich, je in ihrer Stimme. ──
  try{
    const p = prevDay(date), n1 = nextDay(date);
    const { data:acts } = await sb.from("agent_actions").select("agent_key,kind,at").gte("at",p).lt("at",n1);
    const bucket=(from:string,to:string)=>{ const c:Record<string,Record<string,number>>={}; (acts||[]).forEach((x:any)=>{ const d=String(x.at).slice(0,10); if(d>=from && d<to){ (c[x.agent_key]=c[x.agent_key]||{}); c[x.agent_key][x.kind]=(c[x.agent_key][x.kind]||0)+1; } }); return c; };
    const cur=bucket(date,n1), prv=bucket(p,date); const g=(c:any,k:string)=>c[k]||{};
    const put=async (key:string,name:string,summary:string,metrics:any)=>{ await sb.from("agent_digests").upsert({day:date,agent_key:key,name,summary,metrics},{onConflict:"day,agent_key"}); };
    // Max: Erinnerungen + AKTIVE Überwachung von Uploads, Check-in UND Schichtplan, mit Kontext und Folge.
    const mx=g(cur,"max"), mxP=g(prv,"max"); const rem=(mx.reminder_slack||0)+(mx.reminder_cliq||0), remP=(mxP.reminder_slack||0)+(mxP.reminder_cliq||0);
    let mFind:any[]=[];
    try{ const {data}=await sb.rpc("max_upload_scan");                 (data||[]).forEach((f:any)=>mFind.push(f)); }catch(_e){}
    try{ const {data}=await sb.rpc("max_checkin_scan",{p_date:date});  (data||[]).forEach((f:any)=>mFind.push(f)); }catch(_e){}
    try{ const {data}=await sb.rpc("max_shift_scan",  {p_date:date});  (data||[]).forEach((f:any)=>mFind.push(f)); }catch(_e){}
    try{ const {data}=await sb.rpc("max_training_scan",{p_date:date});  (data||[]).forEach((f:any)=>mFind.push(f)); }catch(_e){}
    // Priorität: eingeplant-trotz-Abwesenheit + nicht-eingecheckt zuerst, dann Überfälliges, dann der Rest.
    const mOrder:Record<string,number>={schulung_kritisch:0,schulung_abgesprungen:1,eingeplant_abwesend:2,schulung_knapp:3,nicht_eingecheckt:4,ueberfaellig:5,unbesetzt:6,unvollstaendig:7,kein_plan:8,abweichung_forecast:9,schulung_offen:10,kein_checkout:11,unbestaetigt:12,wenig_zeilen:13,muster:14};
    mFind.sort((a,b)=>(mOrder[a.category]??99)-(mOrder[b.category]??99));
    const mByCat:Record<string,number>={}; mFind.forEach((f:any)=>{ mByCat[f.category]=(mByCat[f.category]||0)+1; });
    if(rem>0 || mFind.length){
      const facts:any[]=[];
      // Die Überwachungs-Befunde ZUERST (das ist Max' Auftrag), Erinnerungen zuletzt — sonst lässt der Satz sie weg.
      mFind.slice(0,3).forEach((f:any)=>facts.push({label:f.subject+" — "+f.detail}));
      if(rem>0) facts.push({label:"Erinnerungen verschickt", current:rem, prior:remP});
      let s=""; try{ s=await colleagueLine("Max", await personaOf("max"), {facts, confidence:"exakt"}); }catch(_e){}
      if(!s){ const parts:string[]=[]; mFind.slice(0,3).forEach((f:any)=>parts.push(f.detail)); if(rem>0)parts.push(`${rem} Erinnerungen verschickt`); s="Max: "+parts.join("; ")+"."; }
      await put("max","Max",s,{...mx,rem_prev:remP, watch:mByCat, findings: mFind.slice(0,60)});
    }
    // Paul — eigene Tätigkeit + Forecast-gegen-Ist-Überwachung (Stunden-Abweichungen je Projekt/Skill)
    const pl=g(cur,"paul"), plP=g(prv,"paul"); const sums=(pl.summary||0)+(pl.analysis||0), sumsP=(plP.summary||0)+(plP.analysis||0), pol=pl.polish||0, polP=plP.polish||0;
    let pFind:any[]=[];
    try{ const {data}=await sb.rpc("paul_forecast_scan",{p_date:date}); (data||[]).forEach((f:any)=>pFind.push(f)); }catch(_e){}
    const pOrder:Record<string,number>={fc_unterdeckung_trend:0,fc_ueberdeckung_trend:1,fc_unterdeckung:2,fc_ueberdeckung:3};
    pFind.sort((a,b)=>(pOrder[a.category]??99)-(pOrder[b.category]??99));
    const pByCat:Record<string,number>={}; pFind.forEach((f:any)=>{ pByCat[f.category]=(pByCat[f.category]||0)+1; });
    if(sums>0||pol>0||pFind.length){
      const facts:any[]=[];
      // Abweichungs-Funde ZUERST (das ist Pauls Auftrag), eigene Tätigkeit danach.
      pFind.slice(0,3).forEach((f:any)=>facts.push({label:f.subject+" — "+f.detail}));
      if(sums>0)facts.push({label:"Zusammenfassungen und Analysen erstellt", current:sums, prior:sumsP});
      if(pol>0)facts.push({label:"Texte gesäubert", current:pol, prior:polP});
      let s=""; try{ s=await colleagueLine("Paul", await personaOf("paul"), {facts, confidence:"exakt"}); }catch(_e){}
      if(!s){ const b:string[]=[]; pFind.slice(0,3).forEach((f:any)=>b.push(f.detail)); if(sums>0)b.push(`${sums} Zusammenfassungen und Analysen erstellt`); if(pol>0)b.push(`${pol} Texte gesäubert`); s="Paul: "+b.join("; ")+"."; }
      await put("paul","Paul",s,{...pl, watch:pByCat, findings:pFind.slice(0,60)});
    }
    // Anna
    const an=g(cur,"anna"), anP=g(prv,"anna"); const q=(an.assistant||0)+(an.nlquery||0), qP=(anP.assistant||0)+(anP.nlquery||0);
    if(q>0){ let s=""; try{ s=await colleagueLine("Anna", await personaOf("anna"), {facts:[{label:"Fragen beantwortet", current:q, prior:qP}], confidence:"exakt"}); }catch(_e){} if(!s) s=`Anna hat ${q} Fragen beantwortet.`; await put("anna","Anna",s,{...an}); }
  }catch(_e){ /* Agenten-Zeilen optional */ }

  // ── Lena: Datenpflege-Auffälligkeiten (Snapshot, kein Vorwert) + Chat-Verstöße (Tag vs. Vortag). Sie MELDET. ──
  try{
    const { data:lf } = await sb.rpc("lena_scan");
    const n = (lf||[]).length; const p = prevDay(date), n1 = nextDay(date);
    const cf  = (await sb.from("chat_flags").select("id",{count:"exact",head:true}).gte("created_at",date).lt("created_at",n1)).count||0;
    const cfP = (await sb.from("chat_flags").select("id",{count:"exact",head:true}).gte("created_at",p).lt("created_at",date)).count||0;
    if(n>0 || cf>0){
      const byCat:Record<string,number> = {}; (lf||[]).forEach((f:any)=>{ byCat[f.category]=(byCat[f.category]||0)+1; });
      const NAMES:Record<string,string> = { vertrag_ohne_daten:"Verträge ohne Daten", ausweis_fehlt:"Ausweis fehlt", bank_fehlt:"Bankdaten fehlen", urlaubsantrag_liegt:"liegende Urlaubsanträge", abwesenheit_unplausibel:"unplausible Abwesenheiten", portalzugang_fehlt:"fehlende Portalzugänge" };
      const top = Object.entries(byCat).sort((a,b)=>b[1]-a[1]).slice(0,3).map(([k,v])=>`${v}× ${NAMES[k]||k}`).join(", ");
      const facts:any[]=[];
      if(n>0)  facts.push({label:`Auffälligkeiten in der Datenpflege (${top})`, current:n});
      if(cf>0) facts.push({label:"Chat-Verstöße", current:cf, prior:cfP});
      let s=""; try{ s=await colleagueLine("Lena", await personaOf("lena"), {facts, confidence:"exakt"}); }catch(_e){}
      if(!s){ const parts:string[]=[]; if(n>0)parts.push(`${n} Auffälligkeiten in der Datenpflege (${top})`); if(cf>0)parts.push(`${cf} Chat-Verstöße`); s="Lena meldet "+parts.join(" und ")+"."; }
      await sb.from("agent_digests").upsert({ day:date, agent_key:"lena", name:"Lena", summary:s, metrics:{...byCat, chat_flags:cf} }, {onConflict:"day,agent_key"});
    }
  }catch(_e){ /* Lena-Zeile optional */ }

  // ── Maya: Zugriffsrechte-Auffälligkeiten (Snapshot, kein Vorwert). Sie MELDET nüchtern, ohne Wertung. ──
  try{
    const { data:af } = await sb.rpc("maya_access_scan");
    const rows = (af||[]) as any[];
    if(rows.length){
      const byCat:Record<string,number> = {}; rows.forEach((f:any)=>{ byCat[f.category]=(byCat[f.category]||0)+1; });
      const NAMES:Record<string,string> = { verwaist:"verwaiste Sperren/Freigaben", rolle:"Rechte ohne Rollen-Deckung", ungenutzt:"ungenutzte Zugänge mit weiten Rechten", widerspruch:"Widersprüche zwischen Menü und KI-Datenrechten" };
      const facts = Object.entries(byCat).sort((a,b)=>b[1]-a[1]).map(([k,v])=>({label:NAMES[k]||k, current:v}));
      let s=""; try{ s=await colleagueLine("Maya", await personaOf("maya"), {facts, confidence:"exakt"}); }catch(_e){}
      if(!s){ const parts=Object.entries(byCat).map(([k,v])=>`${v} ${NAMES[k]||k}`); s="Maya meldet "+parts.join(", ")+"."; }
      await sb.from("agent_digests").upsert({ day:date, agent_key:"maya", name:"Maya", summary:s,
        metrics:{ ...byCat, findings: rows.slice(0,60) } }, {onConflict:"day,agent_key"});
    }
  }catch(_e){ /* Maya-Rechte-Zeile optional */ }

  return json({ ok:true, date, users:active.length, done, failed });
});
