// AI-Kollegen, Schnitt 10: EIN Eingang, sechs Kollegen. Eine Frage rein — das System wählt den richtigen
// Kollegen (oder den gezielt angesprochenen) und antwortet in dessen Stimme (persona aus Register), gegründet
// NUR auf gegebenem Wissen + Live-Zahlen. Reicht das Wissen nicht, verweist der Kollege ehrlich auf den Bereich
// oder einen anderen Kollegen. Gespräche werden gespeichert (offengelegt). Deploy: supabase functions deploy ask-colleague --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods":"POST, OPTIONS" };
const json = (b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});

const MODEL = "claude-sonnet-5";
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") || "";
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const sb = createClient(SB_URL, SERVICE);

const TOOL = { name:"antwort", description:"Wer antwortet und die Antwort.", input_schema:{ type:"object", properties:{
  agent:{type:"string", enum:["clara","max","anna","paul","maya","lena"], description:"Kollege, der antwortet"},
  answer:{type:"string", description:"kurze Antwort in dessen Stimme, Deutsch"} }, required:["agent","answer"] } };

async function liveFacts(): Promise<string> {
  const c = async (t:string,f?:(x:any)=>any)=>{ try{ let q:any=sb.from(t).select("id",{count:"exact",head:true}); if(f) q=f(q); const r=await q; return r.count||0; }catch(_e){ return "?"; } };
  const today = new Date().toISOString().slice(0,10);
  const [cvs, cvNew, emp, gaps, meet] = await Promise.all([
    c("cvs"), c("cvs",(x)=>x.gte("created_at",today)), c("employees",(x)=>x.eq("status","active")),
    c("assistant_gaps",(x)=>x.eq("resolved",false)), c("meeting_notes"),
  ]);
  return `Bewerbungen gesamt: ${cvs}; heute neu: ${cvNew}; aktive Mitarbeiter: ${emp}; offene Wissenslücken: ${gaps}; Besprechungen: ${meet}.`;
}

Deno.serve(async (req)=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
  if(!ANTHROPIC_KEY) return json({error:"ANTHROPIC_API_KEY fehlt"},503);
  const authz = req.headers.get("Authorization") || "";
  const userClient = createClient(SB_URL, ANON, { global:{ headers:{ Authorization:authz } } });
  const { data:me } = await userClient.auth.getUser();
  if(!me || !me.user) return json({ error:"nicht angemeldet" }, 401);

  let body:any={}; try{ body=await req.json(); }catch(_e){}
  const question = String(body.question||"").trim();
  if(!question) return json({ error:"Keine Frage." }, 400);
  const forced = ["clara","max","anna","paul","maya","lena"].includes(body.agent) ? body.agent : null;

  // Register (nur sichtbare für diesen Nutzer — RLS über userClient) + Wissen + Live-Zahlen.
  const { data:agents } = await userClient.from("ai_agents").select("key,name,persona,domain,tagline").eq("active",true);
  const list = (agents||[]);
  if(!list.length) return json({ error:"Keine Kollegen verfügbar." }, 403);
  let manual:any[]=[], kb:any[]=[];
  try{ const { data } = await sb.from("app_config").select("value").eq("key","jsr_system_manual_v1").maybeSingle(); manual=(data&&data.value)||[]; }catch(_e){}
  try{ const { data } = await sb.from("app_config").select("value").eq("key","jsr_kb_v1").maybeSingle(); kb=(data&&data.value&&data.value.articles)||[]; }catch(_e){}
  const knowledge = ((manual||[]).map((d:any)=>"### "+(d.title||"")+"\n"+((d.sections||[]).map((s:any)=>"- "+(s.h||"")+": "+(s.body||"")).join("\n"))).join("\n\n")
    + "\n\n" + (kb||[]).map((a:any)=>"### "+(a.title||"")+"\n"+(a.body||a.content||"")).join("\n\n")).slice(0, 14000);
  const facts = await liveFacts();

  const roster = list.map((a:any)=>`- ${a.key} (${a.name}${a.domain?", "+a.domain:""}): ${a.tagline||""}`).join("\n");
  const personas = list.map((a:any)=>`## ${a.name} [${a.key}]\n${a.persona||""}`).join("\n\n");
  const system = "Du bist der gemeinsame Eingang zu sechs digitalen Kollegen. Wähle den Kollegen, dessen Gebiet zur Frage passt, "+
    (forced?("aber der Nutzer hat GEZIELT '"+forced+"' angesprochen — antworte als dieser Kollege. "):"") +
    "und antworte AUS DESSEN Sicht, in seiner Stimme.\n\nKOLLEGEN:\n"+roster+"\n\nSTIMMEN:\n"+personas+"\n\n"+
    "Hausregeln: Deutsch als Zweitsprache — kurze Sätze, kein Konjunktiv, keine Redewendungen. Keine Emotionen. "+
    "Erfinde NICHTS: nutze nur das gegebene Wissen und die Live-Zahlen. Reicht es nicht, sag ehrlich, dass du es so nicht weißt, "+
    "und verweise auf den passenden Bereich oder einen anderen Kollegen. Keine Zusagen. Höchstens fünf Sätze. "+
    "Duze den Nutzer immer (per Du), niemals Sie. "+
    "Du bist eine Maschine, kein Mensch — beurteile niemanden.";
  const user = "FRAGE: "+question+"\n\nLIVE-ZAHLEN: "+facts+"\n\nWISSEN:\n"+(knowledge||"(leer)");

  let tool:any;
  try{
    const r = await fetch("https://api.anthropic.com/v1/messages",{ method:"POST",
      headers:{ "x-api-key":ANTHROPIC_KEY, "anthropic-version":"2023-06-01", "content-type":"application/json" },
      body: JSON.stringify({ model:MODEL, max_tokens:700, system, tools:[TOOL], tool_choice:{type:"tool",name:"antwort"}, messages:[{role:"user",content:user}] }) });
    const d = await r.json();
    if(!r.ok) return json({ error:(d?.error?.message)||("HTTP "+r.status) }, 502);
    tool = (d.content||[]).find((c:any)=>c.type==="tool_use");
  }catch(e){ return json({ error:"KI nicht erreichbar: "+((e as Error).message||"") }, 502); }
  const outAgent = (tool&&tool.input&&tool.input.agent) || forced || "anna";
  const answer = (tool&&tool.input&&tool.input.answer) || "Das weiß ich so nicht.";
  const who = list.find((a:any)=>a.key===outAgent) || {key:outAgent, name:outAgent};

  try{ await sb.from("agent_conversations").insert({ user_id:me.user.id, agent_key:outAgent, question, answer }); }catch(_e){}
  return json({ ok:true, agent:outAgent, name:who.name, answer });
});
