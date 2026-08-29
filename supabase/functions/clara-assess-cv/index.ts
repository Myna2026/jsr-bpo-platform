// Clara liest die Freitexte eines Bewerbers (Sprache, Inhalt, Auffälligkeiten) und gibt eine EINSCHÄTZUNG.
// Ausdrücklich eine VERMUTUNG aus dem Text, KEINE exakte Messung (die Regeln sind exakt, das hier nicht).
// Ergebnis wird in cvs.extra.clara_review gespeichert und erscheint als zweite Ebene im Warum-Popover.
// Nur bei neuen Bewerbern (Auto-Lauf beim Anlegen) oder auf Knopfdruck — nicht rückwirkend über alle.
// Deploy: supabase functions deploy clara-assess-cv --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods":"POST, OPTIONS" };
const json = (b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});
const MODEL = "claude-sonnet-5";
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") || "";
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const sb = createClient(SB_URL, SERVICE);

const TOOL = { name:"einschaetzung", description:"Claras Textlesung des Bewerbers (Vermutung).", input_schema:{ type:"object", properties:{
  sprache:{type:"string", description:"kurzer Eindruck zu Ausdruck/Sprachniveau aus den Texten"},
  inhalt:{type:"string", description:"was der Inhalt über Eignung/Motivation vermuten lässt"},
  auffaelligkeiten:{type:"string", description:"Widersprüche, Warnzeichen oder Besonderes; leer wenn nichts"},
  fazit:{type:"string", description:"ein Satz Gesamteindruck"} }, required:["sprache","inhalt","auffaelligkeiten","fazit"] } };

Deno.serve(async (req)=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
  if(!ANTHROPIC_KEY) return json({error:"ANTHROPIC_API_KEY fehlt"},503);

  // Angemeldeter HR-Nutzer (Knopf) — der Auto-Lauf schickt dieselbe Session mit.
  const authz = req.headers.get("Authorization") || "";
  const userClient = createClient(SB_URL, ANON, { global:{ headers:{ Authorization:authz } } });
  const { data:me } = await userClient.auth.getUser();
  if(!me || !me.user) return json({ error:"nicht angemeldet" }, 401);

  let body:any={}; try{ body=await req.json(); }catch(_e){}
  const cvId = String(body.cv_id||"").trim();
  if(!cvId) return json({ error:"cv_id fehlt" }, 400);

  const { data:cv } = await sb.from("cvs").select("first_name,last_name,dream,hobbies,travel_wish,notes,work_history,languages_str,extra").eq("id",cvId).maybeSingle();
  if(!cv) return json({ error:"Bewerber nicht gefunden" }, 404);
  const ex = (cv.extra && typeof cv.extra==="object" && !Array.isArray(cv.extra)) ? cv.extra : {};

  // Freitexte einsammeln (nur was da ist).
  const parts:string[] = [];
  const add=(label:string,v:any)=>{ const s=(typeof v==="string"?v:(v?JSON.stringify(v):"")).trim(); if(s && s.length>=3) parts.push(label+": "+s); };
  add("Schriftprobe (Antwort auf Kunden-Mail)", ex.writing_sample);
  add("Hörprobe-Transkript", ex.audio_transcript);
  add("Traum/Ziel", cv.dream);
  add("Hobbys", cv.hobbies);
  add("Reisewunsch", cv.travel_wish);
  add("Werdegang", cv.work_history);
  add("Sprachen (Selbstauskunft)", cv.languages_str);
  add("Notizen", cv.notes);
  const blob = parts.join("\n");
  if(blob.length < 20) return json({ ok:true, skipped:true, note:"zu wenig Freitext für eine Einschätzung" });

  let persona=""; try{ const { data } = await sb.from("ai_agents").select("persona").eq("key","clara").maybeSingle(); persona=(data&&data.persona)||""; }catch(_e){}
  const system = "Du bist Clara aus dem Recruiting.\n"+(persona?(persona+"\n\n"):"")+
    "Lies die Freitexte eines Bewerbers und gib eine kurze Einschätzung in drei Punkten: Sprache (Ausdruck, "+
    "Niveau-Eindruck), Inhalt (was es über Eignung/Motivation vermuten lässt), Auffälligkeiten (Widersprüche, "+
    "Warnzeichen, Besonderes; leer lassen wenn nichts). Dann ein Satz Fazit. WICHTIG: Das ist eine VERMUTUNG aus "+
    "dem Text, KEINE exakte Messung, formuliere entsprechend vorsichtig. Deutsch, kurze Sätze, kein Konjunktiv-Schwall, "+
    "keine erfundenen Fakten, nur was im Text steht.";
  const user = "Bewerber: "+((cv.first_name||"")+" "+(cv.last_name||"")).trim()+"\n\nFREITEXTE:\n"+blob;

  let review:any;
  try{
    const r = await fetch("https://api.anthropic.com/v1/messages",{ method:"POST",
      headers:{ "x-api-key":ANTHROPIC_KEY, "anthropic-version":"2023-06-01", "content-type":"application/json" },
      body: JSON.stringify({ model:MODEL, max_tokens:500, system, tools:[TOOL], tool_choice:{type:"tool",name:"einschaetzung"}, messages:[{role:"user",content:user}] }) });
    const d = await r.json();
    if(!r.ok) return json({ error:(d?.error?.message)||("HTTP "+r.status) }, 502);
    const tu = (d.content||[]).find((c:any)=>c.type==="tool_use");
    if(!tu) return json({ error:"keine Einschätzung erhalten" }, 502);
    review = { sprache:String(tu.input?.sprache||""), inhalt:String(tu.input?.inhalt||""),
      auffaelligkeiten:String(tu.input?.auffaelligkeiten||""), fazit:String(tu.input?.fazit||""),
      confidence:"vermutung", model:MODEL, at:new Date().toISOString() };
  }catch(e){ return json({ error:"KI nicht erreichbar: "+((e as Error).message||"") }, 502); }

  // Persistieren nach extra.clara_review (bestehendes extra bewahren).
  const nextExtra = { ...ex, clara_review: review };
  const { error:upErr } = await sb.from("cvs").update({ extra: nextExtra }).eq("id", cvId);
  if(upErr) return json({ error:"Speichern fehlgeschlagen: "+upErr.message }, 500);

  return json({ ok:true, review });
});
