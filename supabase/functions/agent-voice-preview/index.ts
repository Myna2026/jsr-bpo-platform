// Charakter-Vorschau: zeigt, wie ein Agent mit geänderten Verhaltenseinstellungen an einem ECHTEN Befund klingt.
// Nur Management (Anpassen ist Management-Sache). Erfindet nichts — nutzt die Zahlen eines realen agent_observations.
// Deploy: supabase functions deploy agent-voice-preview --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods":"POST, OPTIONS" };
const json = (b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});
const MODEL = "claude-sonnet-5";
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") || "";
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const sb = createClient(SB_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const NAMES:Record<string,string> = { clara:"Clara", max:"Max", anna:"Anna", paul:"Paul", maya:"Maya", lena:"Lena" };

function composePersona(c:string,f:string,l:string){
  return [ (c||"").trim(),
    (f||"").trim() ? ("Worauf ich achte, was ich melde, ab welcher Schwelle: "+(f||"").trim()) : "",
    (l||"").trim() ? ("Sprachregeln: "+(l||"").trim()) : "" ].filter(Boolean).join("\n\n");
}

Deno.serve(async (req)=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
  if(!ANTHROPIC_KEY) return json({error:"ANTHROPIC_API_KEY fehlt"},503);

  const authz = req.headers.get("Authorization") || "";
  const userClient = createClient(SB_URL, ANON, { global:{ headers:{ Authorization:authz } } });
  const { data:me } = await userClient.auth.getUser();
  if(!me || !me.user) return json({ error:"nicht angemeldet" }, 401);
  // Anpassen/Vorschau ist Management-Sache.
  const { data:au } = await sb.from("app_users").select("role_keys").eq("user_id", me.user.id).maybeSingle();
  if(!(au && Array.isArray(au.role_keys) && au.role_keys.includes("management"))) return json({ error:"nur Management" }, 403);

  let body:any={}; try{ body=await req.json(); }catch(_e){}
  const key = String(body.agent_key||"").trim();
  if(!NAMES[key]) return json({ error:"unbekannter Agent" }, 400);

  // Einen ECHTEN Befund als Grundlage (neuester mit Fakten), sonst ein neutraler Beispiel-Befund.
  const { data:obs } = await sb.from("agent_observations").select("title,facts,confidence").eq("agent_key",key)
    .not("facts","is",null).order("day",{ascending:false}).limit(1);
  const o = (obs&&obs[0]) || null;
  const facts = (o&&o.facts) || [{label:"Beispiel-Kennzahl", current:42, prior:61}];
  const before = (o&&o.title) || "";
  const factLines = facts.map((f:any)=>f.label+": "+f.current+(f.prior!=null?(" (vorher "+f.prior+")"):"")).join("\n");

  const persona = composePersona(String(body.char_text||""), String(body.focus_text||""), String(body.language_text||""));
  const system = "Du bist "+NAMES[key]+", digitale Kollegin/Kollege bei 25HRS.\n"+(persona?(persona+"\n\n"):"")+
    "Formuliere aus den gegebenen Zahlen EINEN kurzen Befund in erster Person, genau in deinem Ton und deinen "+
    "Sprachregeln. Nur die gegebenen Zahlen, nichts erfinden. Ein bis zwei Sätze.";
  const user = "ZAHLEN:\n"+factLines;

  try{
    const r = await fetch("https://api.anthropic.com/v1/messages",{ method:"POST",
      headers:{ "x-api-key":ANTHROPIC_KEY, "anthropic-version":"2023-06-01", "content-type":"application/json" },
      body: JSON.stringify({ model:MODEL, max_tokens:200, system, messages:[{role:"user",content:user}] }) });
    const d = await r.json();
    if(!r.ok) return json({ error:(d?.error?.message)||("HTTP "+r.status) }, 502);
    const after = ((d.content||[]).find((c:any)=>c.type==="text")?.text || "").trim();
    return json({ ok:true, before, after, basis:factLines, had_real:!!o });
  }catch(e){ return json({ error:"KI nicht erreichbar: "+((e as Error).message||"") }, 502); }
});
