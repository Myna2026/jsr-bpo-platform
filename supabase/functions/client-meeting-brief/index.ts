// Vorhaben 2, Schnitt 2: Paul bereitet den Kundentermin vor. Nimmt die deterministischen Fakten
// (RPC client_meeting_prep, mit dem User-JWT -> Berechtigung greift) und formt daraus VIER Blöcke:
//   gut (was lief gut), fragen (wahrscheinliche Kundenfragen), schwach (die schwache Stelle),
//   antwort (Antwortvorschlag) — jeweils an den Zahlen belegt, in Pauls Stimme, erfindet nichts.
// Speichert das Briefing (client_meeting_briefs) und gibt facts+sections zurück.
// Deploy: supabase functions deploy client-meeting-brief --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods":"POST, OPTIONS" };
const json = (b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});
const MODEL = "claude-sonnet-5";
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") || "";
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const sb = createClient(SB_URL, SERVICE);

const TOOL = { name:"briefing", description:"Die vier Blöcke fürs Kundengespräch.", input_schema:{ type:"object", properties:{
  gut:     { type:"array", items:{type:"string"}, description:"Was lief gut — kurze Punkte, jeder mit der Zahl belegt" },
  fragen:  { type:"array", items:{type:"string"}, description:"Wahrscheinliche Kundenfragen — je Punkt eine Frage, aus schwachen/fallenden Kennzahlen abgeleitet" },
  schwach: { type:"array", items:{type:"string"}, description:"Die schwache(n) Stelle(n) — offen benannt, mit Zahl" },
  antwort: { type:"array", items:{type:"string"}, description:"Antwortvorschlag — wie man auf die Fragen/Schwäche reagiert, konkret" }
}, required:["gut","fragen","schwach","antwort"] } };

Deno.serve(async (req)=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
  if(!ANTHROPIC_KEY) return json({error:"ANTHROPIC_API_KEY fehlt"},503);
  const authz = req.headers.get("Authorization") || "";
  const userClient = createClient(SB_URL, ANON, { global:{ headers:{ Authorization:authz } } });
  const { data:me } = await userClient.auth.getUser();
  if(!me || !me.user) return json({ error:"nicht angemeldet" }, 401);

  let body:any={}; try{ body=await req.json(); }catch(_e){}
  const project = String(body.project||"").trim();
  if(!project) return json({ error:"Kein Projekt." }, 400);

  // Fakten mit dem User-JWT holen -> das Berechtigungs-Tor der RPC greift (Management ODER Planer im Projekt).
  const { data:facts, error:fe } = await userClient.rpc("client_meeting_prep", { p_project: project });
  if(fe) return json({ error:"Fakten: "+fe.message }, 502);
  if(facts && facts.error) return json({ error: facts.error }, 403);

  const { data:paul } = await sb.from("ai_agents").select("name,persona").eq("key","paul").maybeSingle();
  const persona = (paul&&paul.persona) || "Du bist Paul, Analyse. Du fasst Zahlen sachlich zusammen.";

  const system = persona + "\n\nDu bereitest ein Kundengespräch vor (Steuerungscall mit dem Auftraggeber). Aus den "+
    "gegebenen ZAHLEN formst du vier Blöcke: was lief gut, welche Fragen der Kunde wahrscheinlich stellt, wo die "+
    "schwache Stelle ist, und ein Antwortvorschlag. Regeln: Deutsch, kurze Sätze, kein Konjunktiv, keine Redewendungen, "+
    "keine Emotionen. Belege JEDEN Punkt mit der konkreten Zahl aus den Daten (Kennzahl, Wert, KW, Skill). Erfinde NICHTS "+
    "— nur die gegebenen Zahlen. Trend erkennst du aus latest vs. prev je Kennzahl. Die wahrscheinlichen Kundenfragen "+
    "leitest du aus den schwachen oder fallenden Kennzahlen ab. Nenne Sales und Support getrennt, wo es zählt. "+
    "Du bist eine Maschine, kein Mensch, beurteile niemanden persönlich.";
  const user = "PROJEKT: "+(facts.project_name||project)+" (Stand KW "+(facts.generated_yw||"?")+")\n\nZAHLEN (JSON):\n"+JSON.stringify(facts);

  let tool:any;
  try{
    const r = await fetch("https://api.anthropic.com/v1/messages",{ method:"POST",
      headers:{ "x-api-key":ANTHROPIC_KEY, "anthropic-version":"2023-06-01", "content-type":"application/json" },
      body: JSON.stringify({ model:MODEL, max_tokens:1400, system, tools:[TOOL], tool_choice:{type:"tool",name:"briefing"}, messages:[{role:"user",content:user}] }) });
    const d = await r.json();
    if(!r.ok) return json({ error:(d?.error?.message)||("HTTP "+r.status) }, 502);
    tool = (d.content||[]).find((c:any)=>c.type==="tool_use");
  }catch(e){ return json({ error:"KI nicht erreichbar: "+((e as Error).message||"") }, 502); }
  const sections = (tool&&tool.input) || { gut:[], fragen:[], schwach:[], antwort:[] };

  let id=null; try{ const { data:ins } = await sb.from("client_meeting_briefs").insert({ project_id:project, generated_by:me.user.id, facts, sections }).select("id").maybeSingle(); id=ins&&ins.id||null; }catch(_e){}
  return json({ ok:true, id, project_name: facts.project_name||project, generated_yw: facts.generated_yw, facts, sections });
});
