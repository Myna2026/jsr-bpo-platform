// Echte Agenten-Kommunikation: Frage -> Antwort aus EIGENEN Daten -> Schluss.
// Löst den erfundenen Thread von agent-synthesis ab. Drei Züge, jeder ein eigener Aufruf mit echten Daten:
//   1) Frage: aus den heutigen agent_observations die stärksten ECHTEN Lücken finden (bis max_per_day),
//      die das Gebiet eines ANDEREN Kollegen füllen könnte -> {fragt, gefragt, frage}.
//   2) Antwort: der Gefragte baut EINE SELECT-Abfrage über NUR seine Domänentabellen (agent_query_exec,
//      read-only) und antwortet aus den echten Zeilen, oder sagt ehrlich "weiß nicht".
//   3) Schluss: der Fragende zieht daraus einen Schluss - oder lässt ihn aus, wenn die Antwort nichts hergibt.
// Speichert je Austausch eine agent_handoffs-Zeile mit thread[{kind:question|answer|conclusion}].
// Cron: 1x/Tag nach agent-observe. Deploy: supabase functions deploy agent-dialogue --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods":"POST, OPTIONS" };
const json = (b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});
const MODEL = "claude-sonnet-5";
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") || "";
const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
function berlinToday(){ const b=new Date(new Date().toLocaleString("en-US",{timeZone:"Europe/Berlin"})); return b.toISOString().slice(0,10); }
function addDays(d:string,n:number){ const x=new Date(d+"T00:00:00Z"); x.setUTCDate(x.getUTCDate()+n); return x.toISOString().slice(0,10); }

const AGENTS = ["clara","max","anna","paul","maya","lena"];
const NAMES:Record<string,string> = { clara:"Clara", max:"Max", anna:"Anna", paul:"Paul", maya:"Maya", lena:"Lena" };
// Kurzbeschreibung je Gebiet (für den Frage-Zug: wer kann was beantworten).
const DOMAIN_DESC:Record<string,string> = {
  clara:"Recruiting: Bewerbungen (cvs), Werbe-Kampagnen (windsor_marketing), Meta-Leads (windsor_leads)",
  max:"Datenvollständigkeit/Uploads: welche Datei/Forecast/Schichtplan je Projekt vorliegt oder fehlt (data_imports, report_forecast, shift_assignments)",
  anna:"Wissen: Handbuch und offene Wissensfragen (app_config, assistant_gaps)",
  paul:"Analyse: gelieferte Stunden (weekly_hours), Calls (weekly_calls), KPIs (kpi_entries), Call-Qualität, Personalbedarf",
  maya:"Systemnutzung: Anmeldungen und Datenpflege-Aktivität je Zugang (activity_log, app_users)",
  lena:"Mitarbeiterstamm: Bankdaten, Ausweis, Vertrag, Status (employees)",
};
// Kuratierte Spalten-Hinweise je Tabelle (nur die nützlichen). Das ist auch die Allowlist für den Antwort-Zug:
// dem Agenten werden GENAU diese Tabellen als seine Daten gezeigt.
const COLS:Record<string,string> = {
  cvs:"id, first_name, last_name, status, project_id, source, primary_skill, language_level, created_at, cv_date",
  windsor_marketing:"date, campaign, account_name, spend, impressions, clicks, reach",
  windsor_leads:"id, campaign, ad_name, created_time, status_review, imported, imported_cv_id, email",
  data_imports:"id, project_id, source_type, kw, year, status, matched_count, unmatched_count, uploaded_by_name, created_at",
  report_forecast:"id, project_id, skill, year, kw, fc_hours, planned_hours, updated_at",
  shift_assignments:"project_id, skill, employee_id, work_date, shift_id, net_hours, gross_hours, updated_at",
  assistant_gaps:"id, question, asked_by, resolved, created_at",
  app_config:"key, value (jsonb; Handbuch unter key='jsr_system_manual_v1', Wissensbasis unter key='jsr_kb_v1')",
  weekly_hours:"id, project_id, employee_id, kw, year, skill, hours, pause_hours, sales_calls, created_at",
  weekly_calls:"id, project_id, employee_id, kw, year, answered, outbound, no_answer, avg_handle_sec, avg_talk_sec, created_at",
  kpi_config:"id, project_id, skill, name, type, unit, thresholds, level, is_primary",
  kpi_entries:"id, emp_id, kw, year, kpi_id, value, source, ts",
  kpi_project_entries:"id, project_id, skill, kw, year, kpi_id, value, month, source, ts",
  activity_log:"id, user_id, user_name, action, entity, entity_label, created_at",
  app_users:"user_id, role_keys, full_name, staff_number, active, employee_id, created_at",
  employees:"id, first_name, last_name, staff_number, project_id, skill, status, position, bank (jsonb name/iban/bic), contract (jsonb signed_at/start/end), id_number, hire_date, termination_date, salary_currency",
  projects:"id, name, client, status, location",
};
const DOMAIN_TABLES:Record<string,string[]> = {
  clara:["cvs","windsor_marketing","windsor_leads"],
  max:["data_imports","report_forecast","shift_assignments","projects"],
  anna:["assistant_gaps","app_config"],
  paul:["weekly_hours","weekly_calls","kpi_config","kpi_entries","kpi_project_entries","shift_assignments","report_forecast","projects"],
  maya:["activity_log","app_users"],
  lena:["employees","projects"],
};

async function callClaude(body:any){
  const r = await fetch("https://api.anthropic.com/v1/messages",{ method:"POST",
    headers:{ "x-api-key":ANTHROPIC_KEY, "anthropic-version":"2023-06-01", "content-type":"application/json" },
    body: JSON.stringify(body) });
  const d = await r.json();
  if(!r.ok) throw new Error((d?.error?.message)||("HTTP "+r.status));
  return d;
}

// Kompaktes Schema (Tabelle: spalten) für die Domänentabellen eines Agenten, aus den kuratierten Hinweisen.
function schemaText(tables:string[]):string{
  return tables.map(t=>COLS[t]?(t+" ("+COLS[t]+")"):null).filter(Boolean).join("\n");
}

// Zug 2: der Gefragte antwortet aus SEINEN Daten (echte SELECTs) oder ehrlich "weiß nicht".
async function answerFromData(asked:string, question:string){
  const schema = schemaText(DOMAIN_TABLES[asked]||[]);
  const sys = "Du bist "+NAMES[asked]+". Dein Gebiet: "+DOMAIN_DESC[asked]+".\n"+
    "Du hast NUR Zugriff auf deine eigenen Tabellen:\n"+schema+"\n\n"+
    "Ein Kollege fragt dich etwas. Sieh in DEINEN Daten nach: baue EINE PostgreSQL-SELECT-Abfrage über deine "+
    "Tabellen und rufe run_query damit auf (du darfst es 1-2x versuchen). Antworte dann mit dem Werkzeug antwort "+
    "in erster Person, kurz, mit der echten Zahl/Erkenntnis aus dem Ergebnis (nenne Projekt/Zeitraum konkret). "+
    "Deutsch, kurze Sätze, kein Konjunktiv. Kann dein Gebiet die Frage NICHT beantworten (leeres/unpassendes "+
    "Ergebnis oder liegt außerhalb deines Gebiets), rufe antwort mit weiss_nicht=true. Erfinde nie eine Zahl.";
  const tools = [
    { name:"run_query", description:"Eine einzelne SELECT-Abfrage über deine Tabellen ausführen.", input_schema:{ type:"object", properties:{ sql:{type:"string"} }, required:["sql"] } },
    { name:"antwort", description:"Deine Antwort an den Kollegen.", input_schema:{ type:"object", properties:{
      text:{type:"string", description:"kurze Antwort in erster Person mit echter Zahl; bei weiss_nicht: ehrlicher Satz was fehlt"},
      weiss_nicht:{type:"boolean"} }, required:["text","weiss_nicht"] } },
  ];
  const messages:any[] = [{ role:"user", content:"Frage von einem Kollegen: "+question }];
  for(let round=0; round<4; round++){
    const d = await callClaude({ model:MODEL, max_tokens:700, system:sys, tools, tool_choice:{type:"any"}, messages });
    const tu = (d.content||[]).find((c:any)=>c.type==="tool_use");
    if(!tu) return { text:"", weiss_nicht:true, queried:false };
    messages.push({ role:"assistant", content:d.content });
    if(tu.name==="antwort") return { text:String(tu.input?.text||""), weiss_nicht:!!tu.input?.weiss_nicht, queried:round>0 };
    if(tu.name==="run_query"){
      let payload="";
      try{ const { data, error } = await sb.rpc("agent_query_exec",{ p_sql:String(tu.input?.sql||"") });
        payload = error ? ("Fehler: "+error.message) : JSON.stringify(data).slice(0,3000); }
      catch(e){ payload = "Fehler: "+((e as Error).message||""); }
      messages.push({ role:"user", content:[{ type:"tool_result", tool_use_id:tu.id, content:payload }] });
      continue;
    }
    return { text:"", weiss_nicht:true, queried:false };
  }
  return { text:"", weiss_nicht:true, queried:true };
}

// Zug 3: der Fragende zieht den Schluss - oder lässt ihn aus.
async function conclude(asker:string, askedName:string, obsTitle:string, question:string, answer:string){
  const sys = "Du bist "+NAMES[asker]+". Du hattest beobachtet: \""+obsTitle+"\". Du hast "+askedName+" gefragt: \""+question+
    "\". Antwort: \""+answer+"\". Ziehe daraus EINEN kurzen Schluss in erster Person (beginne mit \"Zusammen heißt das\"), "+
    "NUR wenn die Antwort wirklich etwas hergibt. Gibt sie nichts her, rufe schluss mit kein_schluss=true. Deutsch, ein Satz, kein Konjunktiv.";
  const tools = [{ name:"schluss", description:"Der Schluss oder Verzicht darauf.", input_schema:{ type:"object", properties:{
    text:{type:"string"}, kein_schluss:{type:"boolean"} }, required:["text","kein_schluss"] } }];
  const d = await callClaude({ model:MODEL, max_tokens:300, system:sys, tools, tool_choice:{type:"tool",name:"schluss"},
    messages:[{ role:"user", content:"Ziehe den Schluss oder lass ihn aus." }] });
  const tu = (d.content||[]).find((c:any)=>c.type==="tool_use");
  if(!tu) return { text:"", kein:true };
  return { text:String(tu.input?.text||""), kein:!!tu.input?.kein_schluss };
}

function slug(s:string){ return String(s||"").toLowerCase().replace(/[^a-z0-9äöü]+/g,"_").replace(/^_+|_+$/g,"").slice(0,40)||"frage"; }

Deno.serve(async (req)=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
  if(!ANTHROPIC_KEY) return json({error:"ANTHROPIC_API_KEY fehlt"},503);
  let body:any={}; try{ body=await req.json(); }catch(_e){}
  const day = (typeof body.date==="string"&&/^\d{4}-\d{2}-\d{2}$/.test(body.date)) ? body.date : berlinToday();
  const dry = body.dry===true;

  let maxPerDay = 3;
  try{ const { data } = await sb.from("app_config").select("value").eq("key","jsr_agent_dialogue_v1").maybeSingle();
    const m = Number((data?.value as any)?.max_per_day); if(Number.isFinite(m)&&m>0) maxPerDay=Math.min(m,6); }catch(_e){}

  // Befunde der letzten 2 Tage, entdubliziert (neuester je Agent+okey).
  const { data:obs } = await sb.from("agent_observations").select("id,agent_key,okey,severity,title,facts,day")
    .gte("day", addDays(day,-1)).lte("day", day).order("day",{ascending:false});
  const seen = new Set<string>(); const list = (obs||[]).filter((o:any)=>{ const k=o.agent_key+"|"+o.okey; if(seen.has(k)) return false; seen.add(k); return true; });
  if(new Set(list.map((o:any)=>o.agent_key)).size < 2) return json({ ok:true, day, note:"weniger als zwei Kollegen mit Befunden", stored:0 });

  const compact = list.map((o:any,i:number)=>({ ref:i+1, kollege:o.agent_key, satz:o.title,
    fakten:(o.facts||[]).map((f:any)=>f.label+": "+f.current+(f.prior!=null?(" (vorher "+f.prior+")"):"")) }));

  // Zug 1: echte Lücken finden (bis maxPerDay). Fragender = Eigentümer der Beobachtung (ref).
  const roster = AGENTS.map(k=>"- "+k+" ("+NAMES[k]+"): "+DOMAIN_DESC[k]).join("\n");
  const sys1 = "Sechs digitale Kollegen melden Befunde. Ihre Gebiete:\n"+roster+"\n\n"+
    "Finde bis zu "+maxPerDay+" ECHTE Lücken: eine Beobachtung (ref), der eine Information FEHLT, die das Gebiet eines "+
    "ANDEREN Kollegen liefern könnte. Der Fragende ist der Kollege, dem die Beobachtung gehört. Der Gefragte ist ein "+
    "ANDERER (nie derselbe), dessen Gebiet die Lücke füllt. Formuliere die Frage in der Stimme des Fragenden, konkret, "+
    "mit Bezug (Projekt/Zeitraum). NUR echte Lücken, bei denen die Antwort des anderen den Befund erst deutbar macht "+
    "(Beispiel: Paul sieht Stunden-Einbruch bei Fabletics und fragt Max, ob dafür ein Forecast vorliegt und seit wann nicht). "+
    "Lieber WENIGER oder GAR KEINE als erzwungene. Keine Frage, die der Fragende selbst beantworten könnte.";
  let dialoguesRaw:any[] = [];
  try{
    const tool1 = { name:"luecken", description:"Echte Lücken als Fragen zwischen Kollegen.", input_schema:{ type:"object", properties:{
      luecken:{ type:"array", items:{ type:"object", properties:{
        ref:{type:"integer", description:"Nummer des Befunds des Fragenden"},
        gefragt:{type:"string", enum:AGENTS, description:"Kollege, der aus seinem Gebiet antworten soll"},
        frage:{type:"string", description:"die Frage in der Stimme des Fragenden"} }, required:["ref","gefragt","frage"] } } }, required:["luecken"] } };
    const d1 = await callClaude({ model:MODEL, max_tokens:900, system:sys1, tools:[tool1], tool_choice:{type:"tool",name:"luecken"},
      messages:[{ role:"user", content:"BEFUNDE (mit ref):\n"+JSON.stringify(compact) }] });
    const tu = (d1.content||[]).find((c:any)=>c.type==="tool_use");
    dialoguesRaw = Array.isArray(tu?.input?.luecken) ? tu.input.luecken : [];
  }catch(e){ return json({ error:"Frage-Zug fehlgeschlagen: "+((e as Error).message||"") }, 502); }

  const byRef = (r:any)=>{ const i=Number(r)-1; return (i>=0&&i<list.length)?list[i]:null; };
  const base = Date.parse(day+"T07:30:00+02:00");
  const out:any[] = []; const usedTopics = new Set<string>();
  let di = 0;
  for(const dlg of dialoguesRaw){
    if(out.length >= maxPerDay) break;
    const askerObs = byRef(dlg.ref); if(!askerObs) continue;
    const asker = askerObs.agent_key; const asked = dlg.gefragt; const question = String(dlg.frage||"").trim();
    if(!question || asked===asker || !AGENTS.includes(asked)) continue;

    // Zug 2: Antwort aus eigenen Daten.
    let ans; try{ ans = await answerFromData(asked, question); }catch(_e){ ans = { text:"", weiss_nicht:true, queried:false }; }
    const answerText = ans.text || "Dazu finde ich in meinen Daten nichts.";

    // Zug 3: Schluss nur, wenn die Antwort etwas hergibt.
    let concl:{text:string,kein:boolean} = { text:"", kein:true };
    if(!ans.weiss_nicht && ans.text){ try{ concl = await conclude(asker, NAMES[asked], askerObs.title, question, answerText); }catch(_e){} }

    const t0=di*3, ordered = [
      { kind:"question", agent:asker, to:asked, text:question, at:new Date(base+(t0+0)*90000).toISOString() },
      { kind:"answer", agent:asked, text:answerText, weiss_nicht:!!ans.weiss_nicht, at:new Date(base+(t0+1)*90000).toISOString() },
    ];
    const hasConcl = !concl.kein && !!concl.text;
    if(hasConcl) ordered.push({ kind:"conclusion", agent:asker, text:concl.text, at:new Date(base+(t0+2)*90000).toISOString() } as any);

    // Nur behalten, wenn ein Schluss zustande kam ODER die Antwort echt abgefragt und substanziell ist.
    // Reine "weiß nichts"-Austausche ohne Datenlage sind Rauschen und fallen raus (lieber weniger).
    const substantiell = ans.queried && answerText.length > 80;
    if(!hasConcl && !substantiell) continue;

    let topic = slug(asker+"_"+asked+"_"+question); if(usedTopics.has(topic)) topic = topic+"_"+di; usedTopics.add(topic);
    const insight = (!concl.kein && concl.text) ? concl.text : answerText;
    out.push({ day, topic, by_agent:asker,
      contributors:[ { agent:asker, observation_id:askerObs.id, fact:(askerObs.facts?.[0]?.label)||askerObs.title },
                     { agent:asked, observation_id:null, fact: ans.weiss_nicht?"weiß nicht":answerText.slice(0,80) } ],
      thread:ordered, insight, severity:["info","warn","high"].includes(askerObs.severity)?askerObs.severity:"info" });
    di++;
  }

  if(dry) return json({ ok:true, day, dry:true, considered:list.length, proposed:dialoguesRaw.length, exchanges:out });
  let stored=0;
  for(const h of out){ const { error } = await sb.from("agent_handoffs").upsert(h,{onConflict:"day,topic"}); if(!error) stored++; }
  return json({ ok:true, day, considered:list.length, proposed:dialoguesRaw.length, stored, exchanges:out });
});
