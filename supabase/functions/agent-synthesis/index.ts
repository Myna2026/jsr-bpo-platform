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
    topic:{type:"string", description:"kurzer Slug, stabil (dedupe je Tag), z.B. rueckgang_ohne_forecast"},
    contributors:{ type:"array", description:"ZWEI VERSCHIEDENE Kollegen (nie zweimal derselbe Kollege), in Reihenfolge des Gesprächs",
      items:{ type:"object", properties:{
        agent:{type:"string", enum:AGENTS}, ref:{type:"integer", description:"Nummer (ref) des Befunds aus der Liste"},
        say:{type:"string", description:"optional: wie dieser Kollege seinen Befund im Kanal sagt (erste Person, kurz, mit der Zahl)"} }, required:["agent","ref"] } },
    by_agent:{type:"string", enum:AGENTS, description:"wer die Schlussfolgerung zieht"},
    insight:{type:"string", description:"die Schlussfolgerung als letzter Satz ('Zusammen heißt das ...')"},
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
  // Entdubletten: nur der NEUESTE Befund je (Agent, okey) — sonst taucht derselbe Befund über zwei Tage
  // mehrfach auf und wird fälschlich als „Verbindung" mit sich selbst gepaart.
  const seenK = new Set<string>(); const list = (obs||[]).filter((o:any)=>{ const k=o.agent_key+"|"+o.okey; if(seenK.has(k)) return false; seenK.add(k); return true; });
  const agentsPresent = new Set(list.map((o:any)=>o.agent_key));
  if(agentsPresent.size < 2) return json({ ok:true, day, note:"weniger als zwei Kollegen mit Befunden — nichts zu verbinden", handoffs:[] });

  // Kurze ref-Nummern statt UUIDs — die KI kopiert lange IDs unzuverlässig; über ref mappen wir sicher zurück.
  const compact = list.map((o:any,i:number)=>({ ref:i+1, agent:o.agent_key, okey:o.okey, severity:o.severity, satz:o.title,
    fakten:(o.facts||[]).map((f:any)=>f.label+": "+f.current+(f.prior!=null?(" (vorher "+f.prior+")"):"")) }));

  const system = "Sechs digitale Kollegen melden Befunde (Clara Bewerber, Max Aufgaben/Daten, Anna Wissen, Paul "+
    "Analyse, Maya Systemnutzung, Lena Mitarbeiterdaten), jeder mit einer Nummer ref. Finde EINEN echten Zusammenhang "+
    "zwischen ZWEI VERSCHIEDENEN Kollegen, bei dem der eine Befund den anderen erst deutbar oder bedenklich macht. "+
    "Gutes Beispiel, das du nehmen sollst: Paul meldet einen Stunden-Einbruch UND Max meldet fehlenden Forecast -> "+
    "zusammen weiß man nicht, ob der Einbruch geplant war. Für jeden beteiligten Kollegen: agent, ref und 'say' — wie "+
    "er seinen Befund im Kanal sagt (erste Person, kurz, mit der Zahl). Dann by_agent und insight: die "+
    "Schlussfolgerung als letzter Satz ('Zusammen heißt das ...'). Erfinde nichts, nutze nur die gegebenen Zahlen. "+
    "NICHT nehmen: bloße Umformulierungen oder Sammel-Aussagen ('an mehreren Stellen fehlt Datenpflege'), und nie "+
    "zweimal derselbe Kollege. Kein echter Zusammenhang -> leere Liste.";
  const user = "BEFUNDE HEUTE (jeder mit ref):\n"+JSON.stringify(compact);

  let tool:any;
  try{
    const r = await fetch("https://api.anthropic.com/v1/messages",{ method:"POST",
      headers:{ "x-api-key":ANTHROPIC_KEY, "anthropic-version":"2023-06-01", "content-type":"application/json" },
      body: JSON.stringify({ model:MODEL, max_tokens:1300, system, tools:[TOOL], tool_choice:{type:"tool",name:"handoffs"}, messages:[{role:"user",content:user}] }) });
    const d = await r.json();
    if(!r.ok) return json({ error:(d?.error?.message)||("HTTP "+r.status) }, 502);
    tool = (d.content||[]).find((c:any)=>c.type==="tool_use");
  }catch(e){ return json({ error:"KI nicht erreichbar: "+((e as Error).message||"") }, 502); }

  const raw = Array.isArray(tool&&tool.input&&tool.input.handoffs) ? tool.input.handoffs : [];
  const byRef = (r:any)=>{ const i=Number(r)-1; return (i>=0 && i<list.length) ? list[i] : null; };
  // Beiträge bekommen morgens ansteigende Zeitstempel (Beobachtung ~07:30 Berlin, Schluss etwas später).
  const base = Date.parse(day+"T07:30:00+02:00");
  // Fallback-Satz, wenn die KI kein 'say' liefert: den Befund-Titel entschlacken ("Paul meldet: …", "exakt …").
  const clean = (t:string)=> String(t||"").replace(/^\s*[A-Za-zÄÖÜäöü]+\s+meldet:?\s*/,"").replace(/,?\s*exakt[^.]*\.?/i,".").replace(/\s{2,}/g," ").trim();
  const out:any[] = [];
  for(const h of raw){
    const cs = (h.contributors||[]).map((c:any)=>({ obs:byRef(c.ref), say:c.say })).filter((c:any)=>c.obs);
    // je Agent nur EIN Beitrag (nie zwei Befunde desselben Kollegen), mindestens ZWEI verschiedene Kollegen.
    const perAgent = new Map<string,any>(); for(const c of cs){ const k=c.obs.agent_key; if(!perAgent.has(k)) perAgent.set(k,c); }
    if(perAgent.size < 2) continue;
    const ordered = [...perAgent.values()];
    const contributors = ordered.map((c:any)=>({ agent:c.obs.agent_key, observation_id:c.obs.id,
      fact: (c.obs.facts&&c.obs.facts[0]&&c.obs.facts[0].label) || c.obs.title }));
    // Der Verlauf: jeder Befund als Beitrag (wie der Kollege es sagt), dann die Schlussfolgerung als letzter.
    const thread = ordered.map((c:any,i:number)=>({ agent:c.obs.agent_key,
      text:String((c.say&&String(c.say).trim())||clean(c.obs.title)).slice(0,300), observation_id:c.obs.id, at:new Date(base + i*90000).toISOString() }));
    const byA = h.by_agent||ordered[ordered.length-1].obs.agent_key;
    thread.push({ agent:byA, text:String(h.insight||"").slice(0,400), observation_id:null, at:new Date(base + thread.length*90000).toISOString() });
    if(!String(h.insight||"").trim()) continue;
    out.push({ day, topic:String(h.topic||"handoff").slice(0,60), by_agent:byA, contributors, thread,
      insight:h.insight, severity:["info","warn","high"].includes(h.severity)?h.severity:"info" });
  }
  // „Lieber eine gute pro Tag als mehrere belanglose": nur die stärkste behalten (die KI führt sie zuerst).
  const top = out.slice(0, 1);
  if(dry) return json({ ok:true, day, dry:true, considered:list.length, handoffs:top });
  let stored=0;
  for(const h of top){ const { error } = await sb.from("agent_handoffs").upsert(h,{onConflict:"day,topic"}); if(!error) stored++; }
  return json({ ok:true, day, considered:list.length, stored, handoffs:top });
});
