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
  // ── Agenten laufen mit: Clara (zählbare Aktionen). Weitere folgen, sobald ihre Aktionen protokolliert werden.
  try{
    const nd = new Date(date+"T00:00:00Z"); nd.setUTCDate(nd.getUTCDate()+1); const next = nd.toISOString().slice(0,10);
    const cvC = await sb.from("cvs").select("id",{count:"exact",head:true}).eq("source","meta").gte("created_at",date).lt("created_at",next);
    const mlC = await sb.from("applicant_messages").select("id",{count:"exact",head:true}).eq("origin","auto").eq("status","sent").gte("sent_at",date).lt("sent_at",next);
    const sorted = cvC.count||0, mails = mlC.count||0;
    if(sorted>0 || mails>0){
      const bits:string[]=[]; if(sorted>0) bits.push(`${sorted} Bewerbung${sorted===1?"":"en"} vorsortiert`); if(mails>0) bits.push(`${mails} Anreicherungs-Mail${mails===1?"":"s"} verschickt`);
      await sb.from("agent_digests").upsert({ day:date, agent_key:"clara", name:"Clara", summary:"Clara hat "+bits.join(" und ")+".", metrics:{sorted,mails} }, {onConflict:"day,agent_key"});
    }
  }catch(_e){ /* Agenten-Zeile optional */ }

  // ── Max/Paul/Anna aus agent_actions (zählbare Aktionen des Tages) ──
  try{
    const nd2 = new Date(date+"T00:00:00Z"); nd2.setUTCDate(nd2.getUTCDate()+1); const next2 = nd2.toISOString().slice(0,10);
    const { data:acts } = await sb.from("agent_actions").select("agent_key,kind").gte("at",date).lt("at",next2);
    const cnt:Record<string,Record<string,number>> = {};
    (acts||[]).forEach((x:any)=>{ (cnt[x.agent_key]=cnt[x.agent_key]||{}); cnt[x.agent_key][x.kind]=(cnt[x.agent_key][x.kind]||0)+1; });
    const g=(k:string)=>cnt[k]||{};
    const lines:{key:string,name:string,summary:string,metrics:any}[]=[];
    const mx=g("max"); const rem=(mx.reminder_slack||0)+(mx.reminder_cliq||0);
    if(rem>0) lines.push({key:"max",name:"Max",summary:`Max hat ${rem} Erinnerung${rem===1?"":"en"} verschickt.`,metrics:mx});
    const pl=g("paul"); const sums=(pl.summary||0)+(pl.analysis||0), pol=pl.polish||0; const pb:string[]=[];
    if(sums>0) pb.push(`${sums} Zusammenfassung${sums===1?"":"en"} und Analyse${sums===1?"":"n"} erstellt`);
    if(pol>0) pb.push(`${pol} Text${pol===1?"":"e"} gesäubert`);
    if(pb.length) lines.push({key:"paul",name:"Paul",summary:"Paul hat "+pb.join(" und ")+".",metrics:pl});
    const an=g("anna"); const q=(an.assistant||0)+(an.nlquery||0);
    if(q>0) lines.push({key:"anna",name:"Anna",summary:`Anna hat ${q} Frage${q===1?"":"n"} beantwortet.`,metrics:an});
    for(const l of lines){ await sb.from("agent_digests").upsert({ day:date, agent_key:l.key, name:l.name, summary:l.summary, metrics:l.metrics },{onConflict:"day,agent_key"}); }
  }catch(_e){ /* Agenten-Zeilen optional */ }

  // ── Lena: Datenpflege-Auffälligkeiten (Snapshot) + gemeldete Chat-Verstöße (an dem Tag). Sie MELDET. ──
  try{
    const { data:lf } = await sb.rpc("lena_scan");
    const n = (lf||[]).length;
    const nd = new Date(date+"T00:00:00Z"); nd.setUTCDate(nd.getUTCDate()+1); const next = nd.toISOString().slice(0,10);
    const { count:cf } = await sb.from("chat_flags").select("id",{count:"exact",head:true}).gte("created_at",date).lt("created_at",next);
    const flags = cf||0;
    if(n>0 || flags>0){
      const byCat:Record<string,number> = {}; (lf||[]).forEach((f:any)=>{ byCat[f.category]=(byCat[f.category]||0)+1; });
      const NAMES:Record<string,string> = { vertrag_ohne_daten:"Verträge ohne Daten", ausweis_fehlt:"Ausweis fehlt", bank_fehlt:"Bankdaten fehlen", urlaubsantrag_liegt:"liegende Urlaubsanträge", abwesenheit_unplausibel:"unplausible Abwesenheiten", portalzugang_fehlt:"fehlende Portalzugänge" };
      const parts:string[]=[];
      if(n>0){ const top = Object.entries(byCat).sort((a,b)=>b[1]-a[1]).slice(0,3).map(([k,v])=>v+"× "+(NAMES[k]||k)).join(", "); parts.push(`${n} Auffälligkeit${n===1?"":"en"} in der Datenpflege (${top})`); }
      if(flags>0){ parts.push(`${flags} Chat-Verstoß${flags===1?"":"e"}`); }
      await sb.from("agent_digests").upsert({ day:date, agent_key:"lena", name:"Lena", summary:"Lena meldet "+parts.join(" und ")+".", metrics:{...byCat, chat_flags:flags} }, {onConflict:"day,agent_key"});
    }
  }catch(_e){ /* Lena-Zeile optional */ }

  return json({ ok:true, date, users:active.length, done, failed });
});
