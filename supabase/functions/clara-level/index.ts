// Clara bewertet eine Sprachprobe (Schriftprobe = Antwort auf Kunden-Mail, oder Hörprobe-Transkript) auf
// CEFR-Niveau A2-C2. Ersetzt den früheren Direktaufruf aus dem Browser (localStorage-Key) — eine KI-Quelle
// im Bewerberbereich (Clara). Das Ergebnis ist eine Einschätzung, nicht die finale HR-Bewertung.
// Deploy: supabase functions deploy clara-level --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods":"POST, OPTIONS" };
const json = (b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});
const MODEL = "claude-sonnet-5";
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") || "";
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const sb = createClient(SB_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

const TOOL = { name:"niveau", description:"CEFR-Einschätzung der Sprachprobe.", input_schema:{ type:"object", properties:{
  level:{type:"string", enum:["A2","B1","B2","C1","C2"]},
  confidence:{type:"string", description:"hoch | mittel | niedrig"},
  strengths:{type:"string", description:"kurze Stärken, max 1 Satz"},
  weaknesses:{type:"string", description:"kurze Schwächen, max 1 Satz, leer wenn keine"},
  reasoning:{type:"string", description:"1-2 Sätze, warum dieses Niveau"} }, required:["level","confidence","reasoning"] } };

Deno.serve(async (req)=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
  if(!ANTHROPIC_KEY) return json({error:"ANTHROPIC_API_KEY fehlt"},503);

  const authz = req.headers.get("Authorization") || "";
  const userClient = createClient(SB_URL, ANON, { global:{ headers:{ Authorization:authz } } });
  const { data:me } = await userClient.auth.getUser();
  if(!me || !me.user) return json({ error:"nicht angemeldet" }, 401);

  let body:any={}; try{ body=await req.json(); }catch(_e){}
  const type = body.type==="audio" ? "audio" : "writing";
  const text = String(body.text||"").trim();
  if(text.length < 20) return json({ error:"Bitte zuerst eine Probe eingeben (min. 20 Zeichen)." }, 400);

  let persona=""; try{ const { data } = await sb.from("ai_agents").select("persona").eq("key","clara").maybeSingle(); persona=(data&&data.persona)||""; }catch(_e){}

  const task = type==="writing"
    ? "Aufgabe des Bewerbers war: eine kurze Antwort-Mail auf eine Kunden-E-Mail schreiben (Problem: doppelte "+
      "Buchungsabbuchung). Bewerte die schriftliche Sprachkompetenz.\n\nBewerber-Antwort:\n\""+text+"\""
    : "Vorlesetext war: \"Guten Tag, mein Name ist [Name]. Ich freue mich, heute bei TIVE 360 vorzusprechen. Im "+
      "Kundenkontakt ist mir eine freundliche und klare Kommunikation besonders wichtig, denn zufriedene Kunden "+
      "sind das Ziel jedes guten Gesprächs.\" Bewerte die mündliche Sprachkompetenz aus dem Transkript.\n\n"+
      "Transkript (vom HR-Team nach Anhören eingetippt):\n\""+text+"\"";

  const system = "Du bist Clara aus dem Recruiting und Sprachexpertin für Deutsch.\n"+(persona?(persona+"\n\n"):"")+
    "Bewerte die Sprachprobe eines Bewerbers für eine deutschsprachige Kundendienst-Stelle auf CEFR-Niveau. "+
    "Niveaus: A2 (sehr einfach, viele Fehler), B1 (verständlich, aber Fehler), B2 (gut & professionell), "+
    "C1 (sehr gut, kaum Fehler), C2 (muttersprachlich). Für Kundenservice ist B2 das Minimum. Sei streng, aber fair. "+
    "Antworte über das Werkzeug niveau. Deutsch, kurze Sätze, keine erfundenen Fakten.";

  try{
    const r = await fetch("https://api.anthropic.com/v1/messages",{ method:"POST",
      headers:{ "x-api-key":ANTHROPIC_KEY, "anthropic-version":"2023-06-01", "content-type":"application/json" },
      body: JSON.stringify({ model:MODEL, max_tokens:400, system, tools:[TOOL], tool_choice:{type:"tool",name:"niveau"}, messages:[{role:"user",content:task}] }) });
    const d = await r.json();
    if(!r.ok) return json({ error:(d?.error?.message)||("HTTP "+r.status) }, 502);
    const tu = (d.content||[]).find((c:any)=>c.type==="tool_use");
    if(!tu) return json({ error:"keine Einschätzung erhalten" }, 502);
    const lvl = String(tu.input?.level||"");
    if(!["A2","B1","B2","C1","C2"].includes(lvl)) return json({ error:"ungültiges Niveau" }, 502);
    return json({ ok:true, result:{ level:lvl, confidence:String(tu.input?.confidence||""),
      strengths:String(tu.input?.strengths||""), weaknesses:String(tu.input?.weaknesses||""), reasoning:String(tu.input?.reasoning||"") } });
  }catch(e){ return json({ error:"KI nicht erreichbar: "+((e as Error).message||"") }, 502); }
});
