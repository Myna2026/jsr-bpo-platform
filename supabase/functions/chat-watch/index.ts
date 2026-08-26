// Lenas Chat-Wächter. Prüft NUR Nachrichten von überwachten Absendern (chat_is_monitored) und NUR auf
// Beleidigungen/Beschimpfungen/Mobbing/Betrugsversuche. Kostensparend: ein STICHWORT-VORFILTER läuft billig
// über jede neue Nachricht; die KI (Claude) beurteilt nur die Verdachtsfälle. Treffer -> chat_flags
// (nur Management+HR sichtbar). Lena meldet, sie sanktioniert nicht. Cursor in app_config; per Cron aufgerufen.
// Deploy: supabase functions deploy chat-watch
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods":"POST, OPTIONS" };
const json = (b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});

const MODEL = "claude-sonnet-5";
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") || "";
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const sb = createClient(SB_URL, SERVICE);
const CURSOR_KEY = "jsr_chat_watch_cursor_v1";

// Grober Vorfilter (klein halten, tunebar): löst NUR die KI-Prüfung aus, entscheidet nichts.
const KEYWORDS = [
  // Beleidigung/Beschimpfung (de)
  "idiot","idioten","dumm","dümmer","blöd","blödmann","arschloch","arsch","hurensohn","fotze","schlampe",
  "wichser","spast","behindert","versager","trottel","depp","fresse","halt die","verpiss","fick","scheiss","scheiß","dreck",
  // Drohung/Mobbing
  "drohe","umbringen","fertig machen","fertigmachen","mobbing","mobben","niemand mag dich","du gehörst","schikan",
  // Betrug
  "betrug","betrügen","abzocke","überweis","paypal","bitcoin","gutschein","passwort","zugangsdaten","gewinn","dringend geld",
  // (sq) häufige Beleidigungen
  "budall","kar","pidh","qij","mut","idiot",
];
const kwLower = KEYWORDS.map((k)=>k.toLowerCase());
function keywordHit(text:string): boolean {
  const t = (text||"").toLowerCase();
  return kwLower.some((k)=> t.indexOf(k) >= 0);
}

const TOOL = { name:"beurteilung", description:"Verstoß-Beurteilung einer Nachricht.", input_schema:{ type:"object", properties:{
  category:{ type:"string", enum:["beleidigung","beschimpfung","mobbing","betrug","kein"], description:"Art des Verstoßes oder 'kein'" } }, required:["category"] } };

async function classify(text:string): Promise<string> {
  const system = "Du bist ein sachlicher Prüfer für Verstöße in einem internen Team-Chat. Beurteile EINE Nachricht. "+
    "Melde NUR: beleidigung, beschimpfung, mobbing, betrug (Betrugsversuch). Alles andere ist 'kein' — auch derbe, "+
    "aber nicht gegen eine Person gerichtete Sprache, Ironie unter Kollegen, oder harmlose Flüche. Im Zweifel 'kein'. "+
    "Antworte nur mit der Kategorie.";
  const r = await fetch("https://api.anthropic.com/v1/messages",{ method:"POST",
    headers:{ "x-api-key":ANTHROPIC_KEY, "anthropic-version":"2023-06-01", "content-type":"application/json" },
    body: JSON.stringify({ model:MODEL, max_tokens:100, system, tools:[TOOL], tool_choice:{type:"tool",name:"beurteilung"}, messages:[{role:"user",content:"Nachricht:\n"+text}] }) });
  const d = await r.json();
  if(!r.ok) throw new Error((d?.error?.message)||("HTTP "+r.status));
  const tu = (d.content||[]).find((c:any)=>c.type==="tool_use");
  return (tu && tu.input && tu.input.category) || "kein";
}

Deno.serve(async (req)=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
  if(!ANTHROPIC_KEY) return json({error:"ANTHROPIC_API_KEY fehlt"},503);

  // Cursor (erster Lauf: ab jetzt, keine Rückwirkung auf Altnachrichten).
  const { data:cur } = await sb.from("app_config").select("value").eq("key",CURSOR_KEY).maybeSingle();
  const cursor = (cur && cur.value && cur.value.ts) || new Date().toISOString();

  const { data:msgs } = await sb.from("dm_messages").select("id,thread_id,from_emp_id,text_original,sent_at")
    .gt("sent_at", cursor).order("sent_at",{ascending:true}).limit(500);
  const rows = msgs || [];
  let checked=0, flagged=0, newCursor=cursor;

  // Vorfilter + Überwachungs-Check, dann KI nur für Verdachtsfälle.
  const monCache: Record<string,boolean> = {};
  const nameCache: Record<string,string> = {};
  for(const m of rows){
    newCursor = m.sent_at;
    if(!keywordHit(m.text_original)) continue;                 // billiger Vorfilter
    const emp = String(m.from_emp_id);
    if(monCache[emp] === undefined){ const { data } = await sb.rpc("chat_is_monitored", { p_emp: m.from_emp_id }); monCache[emp] = !!data; }
    if(!monCache[emp]) continue;                               // Absender nicht überwacht -> keine Prüfung
    checked++;
    try{
      const cat = await classify(m.text_original);
      if(cat && cat !== "kein"){
        if(nameCache[emp] === undefined){ const { data:e } = await sb.from("employees").select("first_name,last_name").eq("id", m.from_emp_id).maybeSingle();
          nameCache[emp] = e ? (((e.first_name||"")+" "+(e.last_name||"")).trim()||"Mitarbeiter") : "Mitarbeiter"; }
        await sb.from("chat_flags").upsert({ message_id:m.id, thread_id:m.thread_id, from_emp_id:m.from_emp_id,
          from_name:nameCache[emp], category:cat, excerpt:String(m.text_original).slice(0,300), sent_at:m.sent_at }, { onConflict:"message_id" });
        flagged++;
      }
    }catch(_e){ /* KI-Fehler: Nachricht überspringen, Cursor läuft weiter */ }
  }

  await sb.from("app_config").upsert({ key:CURSOR_KEY, value:{ ts:newCursor }, updated_at:new Date().toISOString() });
  return json({ ok:true, scanned:rows.length, checked, flagged });
});
