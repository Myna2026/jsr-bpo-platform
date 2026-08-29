// Vorhaben 4, Schnitt 2: die Übergabe. Liest die Befunde aller Agenten (agent_observations der letzten Tage)
// und findet Zusammenhänge ZWISCHEN Kollegen (mindestens zwei verschiedene), die zusammen etwas zeigen, das
// keiner allein sieht. Speichert sie als agent_handoffs (mit Verweis auf die Ursprungs-Befunde). Erfindet nichts.
// Cron: 1×/Tag nach agent-observe. Deploy: supabase functions deploy agent-synthesis --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods":"POST, OPTIONS" };
const json = (b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});
const MODEL = "claude-sonnet-5";
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") || "";
const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
function berlinToday(){ const b=new Date(new Date().toLocaleString("en-US",{timeZone:"Europe/Berlin"})); return b.toISOString().slice(0,10); }
function addDays(d:string,n:number){ const x=new Date(d+"T00:00:00Z"); x.setUTCDate(x.getUTCDate()+n); return x.toISOString().slice(0,10); }

const AGENTS = ["clara","max","anna","paul","maya","lena"];
const TOOL = { name:"handoffs", description:"Gemeinsame Erkenntnisse aus den Befunden mehrerer Kollegen.", input_schema:{ type:"object", properties:{
  handoffs:{ type:"array", items:{ type:"object", properties:{
    topic:{type:"string", description:"kurzer Slug, stabil (dedupe je Tag), z.B. marketing_ohne_ertrag"},
    contributors:{ type:"array", items:{ type:"object", properties:{
      agent:{type:"string", enum:AGENTS}, ref:{type:"integer", description:"die Nummer (ref) des Befunds aus der Liste"} }, required:["agent","ref"] },
      description:"mindestens ZWEI verschiedene Kollegen" },
    by_agent:{type:"string", enum:AGENTS, description:"wer die Verbindung zieht"},
    insight:{type:"string", description:"die gemeinsame Erkenntnis, ein Satz, Deutsch, mit den Zahlen"},
    severity:{type:"string", enum:["info","warn","high"]}
  }, required:["topic","contributors","by_agent","insight","severity"] } } }, required:["handoffs"] } };

Deno.serve(async (req)=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
  if(!ANTHROPIC_KEY) return json({error:"ANTHROPIC_API_KEY fehlt"},503);
  let body:any={}; try{ body=await req.json(); }catch(_e){}
  const day = (typeof body.date==="string"&&/^\d{4}-\d{2}-\d{2}$/.test(body.date)) ? body.date : berlinToday();
  const dry = body.dry===true;

  // Befunde der letzten 2 Tage (aktuell genug, damit ein gestriger Clara-Befund mit einem heutigen Max-Befund
  // verbunden werden kann), mit den lesbaren Fakten.
  const { data:obs } = await sb.from("agent_observations").select("id,agent_key,okey,severity,title,facts,day")
    .gte("day", addDays(day,-1)).lte("day", day).order("day",{ascending:false});
  const list = (obs||[]);
  const agentsPresent = new Set(list.map((o:any)=>o.agent_key));
  if(agentsPresent.size < 2) return json({ ok:true, day, note:"weniger als zwei Kollegen mit Befunden — nichts zu verbinden", handoffs:[] });

  // Kurze ref-Nummern statt UUIDs — die KI kopiert lange IDs unzuverlässig; über ref mappen wir sicher zurück.
  const compact = list.map((o:any,i:number)=>({ ref:i+1, agent:o.agent_key, okey:o.okey, severity:o.severity, satz:o.title,
    fakten:(o.facts||[]).map((f:any)=>f.label+": "+f.current+(f.prior!=null?(" (vorher "+f.prior+")"):"")) }));

  const system = "Du bist die Verbindungsstelle zwischen sechs digitalen Kollegen (Clara Bewerber, Max Aufgaben/Daten, "+
    "Anna Wissen, Paul Analyse, Maya Systemnutzung, Lena Mitarbeiterdaten). Dir liegen ihre heutigen Befunde vor. "+
    "Finde Zusammenhänge ZWISCHEN Kollegen — mindestens zwei VERSCHIEDENE Kollegen —, die zusammen etwas zeigen, das "+
    "keiner allein sieht. Beispiel: Clara meldet weniger Bewerbungen UND Max meldet fehlende Uploads -> zusammen: die "+
    "Datenlage bremst das Recruiting. Auch KOMPLEMENTÄRE Befunde zählen: meldet ein Kollege ein Ergebnis und ein "+
    "anderer eine fehlende Grundlage dafür, ist das ein echter Zusammenhang (z.B. Paul liefert Stundenzahlen, Max "+
    "meldet fehlende Forecasts -> wir messen Leistung, können sie aber für diese Projekte nicht gegen einen Plan "+
    "stellen). Weitere Muster: ein Einbruch bei einem Kollegen (z.B. weniger gelieferte Stunden) und ein Ausfall "+
    "bei einem anderen (z.B. inaktive Zugänge) deuten oft auf dieselbe Ursache; mehrere fehlende Datenpflege-Stände "+
    "bei verschiedenen Kollegen (Bank fehlt, Forecast fehlt) zeigen zusammen, dass die Datenpflege an mehreren "+
    "Stellen hakt. Sei nicht ZU streng: wenn zwei Befunde verschiedener Kollegen plausibel zusammenhängen und du es "+
    "mit den Zahlen belegen kannst, nimm die Verbindung. Regeln: NUR belegbare Zusammenhänge aus den gegebenen Befunden, erfinde "+
    "nichts. Jede Erkenntnis in einem Satz, Deutsch, kurz, mit den konkreten Zahlen. Verweise je Beitrag auf die "+
    "observation_id. Wenn es keinen echten Zusammenhang gibt, gib eine leere Liste. Höchstens drei Verbindungen.";
  const user = "BEFUNDE HEUTE (jeder mit einer Nummer ref):\n"+JSON.stringify(compact)+"\n\nVerweise je Beitrag mit ref auf den Befund.";

  let tool:any;
  try{
    const r = await fetch("https://api.anthropic.com/v1/messages",{ method:"POST",
      headers:{ "x-api-key":ANTHROPIC_KEY, "anthropic-version":"2023-06-01", "content-type":"application/json" },
      body: JSON.stringify({ model:MODEL, max_tokens:900, system, tools:[TOOL], tool_choice:{type:"tool",name:"handoffs"}, messages:[{role:"user",content:user}] }) });
    const d = await r.json();
    if(!r.ok) return json({ error:(d?.error?.message)||("HTTP "+r.status) }, 502);
    tool = (d.content||[]).find((c:any)=>c.type==="tool_use");
  }catch(e){ return json({ error:"KI nicht erreichbar: "+((e as Error).message||"") }, 502); }

  const raw = (tool&&tool.input&&tool.input.handoffs) || [];
  const byRef = (r:any)=>{ const i=Number(r)-1; return (i>=0 && i<list.length) ? list[i] : null; };
  const out:any[] = [];
  for(const h of raw){
    const obsList = (h.contributors||[]).map((c:any)=>byRef(c.ref)).filter(Boolean);
    const distinct = new Set(obsList.map((o:any)=>o.agent_key));   // echter Agent aus dem Befund, nicht die KI-Angabe
    if(distinct.size < 2) continue;   // echte Übergabe braucht mindestens zwei Kollegen
    const seen=new Set(); const contributors = obsList.filter((o:any)=>{ if(seen.has(o.id)) return false; seen.add(o.id); return true; })
      .map((o:any)=>({ agent:o.agent_key, observation_id:o.id, fact:o.title }));
    out.push({ day, topic:String(h.topic||"handoff").slice(0,60), by_agent:h.by_agent||"maya",
      contributors, insight:h.insight, severity:["info","warn","high"].includes(h.severity)?h.severity:"info" });
  }
  if(dry) return json({ ok:true, day, dry:true, considered:list.length, handoffs:out });
  let stored=0;
  for(const h of out){ const { error } = await sb.from("agent_handoffs").upsert(h,{onConflict:"day,topic"}); if(!error) stored++; }
  return json({ ok:true, day, considered:list.length, stored, handoffs:out });
});
