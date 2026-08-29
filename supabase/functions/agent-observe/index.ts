// AI-Kollegen, Schnitt 4: ungefragtes Bemerken. Einmal am Tag (Cron) prüft JEDER Kollege sein Gebiet und
// meldet NUR echte Abweichungen (Vortag/Vorwoche oder gespeicherter Vortags-Stand). Jede Prüfung schreibt
// agent_checks (zuletzt geprüft) — Schweigen bedeutet dann „geprüft, alles in Ordnung", nicht „war nicht da".
// Sätze in der Kollegen-Stimme (persona aus Register, Hausregeln wie in usage-digest). Global gerechnet;
// der nutzerbezogene Filter kommt in Schnitt 5. Deploy: supabase functions deploy agent-observe --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods":"POST, OPTIONS" };
const json = (b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});

const MODEL = "claude-sonnet-5";
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") || "";
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const sb = createClient(SB_URL, SERVICE);

// ── Kollegen-Stimme (identisch zu usage-digest; später ins _shared) ──
const PERSONAE: Record<string,string> = {};
async function personaOf(key:string): Promise<string> {
  if(PERSONAE[key]!==undefined) return PERSONAE[key];
  const { data } = await sb.from("ai_agents").select("persona").eq("key",key).maybeSingle();
  PERSONAE[key] = (data&&data.persona) || ""; return PERSONAE[key];
}
const TOOL = { name:"satz", description:"Ein Satz.", input_schema:{ type:"object", properties:{ summary:{type:"string"} }, required:["summary"] } };
const HOUSE = "Hausregeln: Deutsch als Zweitsprache — kurze Sätze, kein Konjunktiv, keine Redewendungen. "+
  "Keine Emotionen, kein Lob, kein Tadel. Erfinde nichts: nutze NUR die gegebenen Zahlen. "+
  "Nenne den Vergleich zur Vorperiode, wenn er gegeben ist. Mach die Sicherheit hörbar, wenn gegeben "+
  "(exakt / Obergrenze / Vermutung). Wenn etwas fehlt, sag klar was fehlt und dass die Zahl dann leer ist, nicht falsch. "+
  "Wenn ein Thema zu einem anderen Kollegen gehört, verweise kurz auf ihn. Höchstens zwei kurze Sätze. Keine Zusagen. "+
  "Schreib in der dritten Person mit dem Namen. Wenn du jemanden ansprichst, duze immer (per Du), niemals Sie.";
async function colleagueLine(name:string, persona:string, brief:any): Promise<string> {
  const facts = (brief.facts||[]).map((f:any)=> `${f.label}: ${f.current}${(f.prior!==undefined&&f.prior!==null)?` (Vorperiode ${f.prior})`:""}`).join("; ");
  const parts = [`Kollege: ${name}`, `Fakten: ${facts}`];
  if(brief.confidence) parts.push(`Sicherheit: ${brief.confidence}`);
  if(brief.missing) parts.push(`Fehlt: ${brief.missing}`);
  if(brief.frame) parts.push(`Rahmen: ${brief.frame}`);
  const system = (persona? persona+"\n\n":"") + HOUSE;
  const r = await fetch("https://api.anthropic.com/v1/messages",{ method:"POST",
    headers:{ "x-api-key":ANTHROPIC_KEY, "anthropic-version":"2023-06-01", "content-type":"application/json" },
    body: JSON.stringify({ model:MODEL, max_tokens:200, system, tools:[TOOL], tool_choice:{type:"tool",name:"satz"}, messages:[{role:"user",content:parts.join("\n")}] }) });
  const d = await r.json();
  if(!r.ok) throw new Error((d?.error?.message)||("HTTP "+r.status));
  const tu = (d.content||[]).find((c:any)=>c.type==="tool_use");
  return (tu && tu.input && tu.input.summary) || "";
}

// ── Datums-/Wochen-Helfer ──
function berlinToday(): string { const now=new Date(); const b=new Date(now.toLocaleString("en-US",{timeZone:"Europe/Berlin"})); return b.toISOString().slice(0,10); }
function addDays(d:string,n:number){ const x=new Date(d+"T00:00:00Z"); x.setUTCDate(x.getUTCDate()+n); return x.toISOString().slice(0,10); }
function isoWeek(dstr:string): {year:number, week:number} {
  const d=new Date(dstr+"T00:00:00Z"); const day=(d.getUTCDay()+6)%7; d.setUTCDate(d.getUTCDate()-day+3);
  const firstTh=new Date(Date.UTC(d.getUTCFullYear(),0,4));
  const week=1+Math.round(((d.getTime()-firstTh.getTime())/86400000 - 3 + ((firstTh.getUTCDay()+6)%7))/7);
  return { year:d.getUTCFullYear(), week };
}
async function cnt(tbl:string,col:string,from:string,to:string,f?:(x:any)=>any): Promise<number> {
  let q:any = sb.from(tbl).select("id",{count:"exact",head:true}); if(f) q=f(q); q=q.gte(col,from).lt(col,to);
  const r = await q; return r.count||0;
}

Deno.serve(async (req)=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
  if(!ANTHROPIC_KEY) return json({error:"ANTHROPIC_API_KEY fehlt"},503);
  let body:any={}; try{ body=await req.json(); }catch(_e){}
  const date = (typeof body.date==="string" && /^\d{4}-\d{2}-\d{2}$/.test(body.date)) ? body.date : berlinToday();
  const p = addDays(date,-1), n1 = addDays(date,1), d7 = addDays(date,-7), d28 = addDays(date,-28);

  // je Agent: { findings:[{okey,severity,facts,confidence,missing?,metrics?}], snapshot? }
  const checks: Record<string, {findings:any[], snapshot?:any}> = { clara:{findings:[]}, max:{findings:[]}, anna:{findings:[]}, paul:{findings:[]}, maya:{findings:[]}, lena:{findings:[]} };

  // Clara: Posteingangs-Volumen heute vs. 7-Tage-Schnitt
  try{
    const today = await cnt("cvs","created_at",date,n1);
    const last7 = await cnt("cvs","created_at",d7,date); const avg = last7/7;
    if(today>=3 && avg>=3 && Math.abs((today-avg)/avg)>=0.4)
      checks.clara.findings.push({okey:"clara_inbox_volume", severity:"info", confidence:"exakt",
        facts:[{label:"Bewerbungen heute im Posteingang", current:today, prior:Math.round(avg)}], metrics:{today,avg7:Math.round(avg)}});
  }catch(_e){}

  // Clara-Rückschau (Schnitt 9): trägt die Sortierung nach Sprachlevel? Ehrlich — nur bei genug Entschiedenen,
  // Erfahrung fehlt fast überall (kann sie nicht einbeziehen). Fehler eingestehen macht glaubwürdiger.
  try{
    const { data:chkC } = await sb.from("agent_checks").select("metrics").eq("agent_key","clara").maybeSingle();
    const prevC = (chkC&&chkC.metrics)||{};
    const HIRED = ["contract","training_planned","training","active"];
    const { data:dec } = await sb.from("cvs").select("status,language_level").not("language_level","is",null)
      .in("status",[...HIRED,"rejected_by_us","rejected_by_employee","rejected_by_client","blacklist"]);
    const top=(dec||[]).filter((c:any)=> ["C1","C2"].includes(c.language_level) || /mutter/i.test(c.language_level||""));
    const topN=top.length, topHired=top.filter((c:any)=>HIRED.includes(c.status)).length;
    if(topN>=10 && (topHired/topN)<=0.2 && (prevC.rank_topN!==topN || prevC.rank_topHired!==topHired)){
      checks.clara.findings.push({ okey:"clara_rank_review", severity:"info", confidence:"vermutung",
        facts:[{label:"nach Sprachlevel hoch eingestufte Bewerber (C1/C2/Muttersprache), entschieden", current:topN},{label:"davon eingestellt", current:topHired}],
        missing:"Erfahrungsjahre fehlen bei fast allen, darum kann ich sie nicht einbeziehen",
        frame:"Rückschau: gestehe selbstkritisch ein, dass dein Rang nach Sprachlevel schwach trennt. Sag 'möglicherweise', dass du das Sprachlevel zu stark gewichtest.",
        metrics:{rank_topN:topN, rank_topHired:topHired} });
    }
    checks.clara.snapshot = { ...(prevC||{}), rank_topN:topN, rank_topHired:topHired };
  }catch(_e){}

  // Clara: Kampagne läuft und kostet Geld, aber es kommen keine Bewerbungen? Muss auffallen. (dedupe über Signatur)
  try{
    const { data:chkC2 } = await sb.from("agent_checks").select("metrics").eq("agent_key","clara").maybeSingle();
    const prevC2 = (chkC2&&chkC2.metrics)||{};
    const from4 = addDays(date,-4);
    const { data:mk } = await sb.from("windsor_marketing").select("date,spend").gte("date",from4).lt("date",date);
    const spendByDay:Record<string,number>={}; (mk||[]).forEach((r:any)=>{ const d=String(r.date).slice(0,10); spendByDay[d]=(spendByDay[d]||0)+(Number(r.spend)||0); });
    const { data:cvd } = await sb.from("cvs").select("created_at").gte("created_at",from4).lt("created_at",date);
    const appsByDay:Record<string,number>={}; (cvd||[]).forEach((r:any)=>{ const d=String(r.created_at).slice(0,10); appsByDay[d]=(appsByDay[d]||0)+1; });
    const silent = Object.keys(spendByDay).filter(d=> spendByDay[d]>=20 && (appsByDay[d]||0)===0).sort();
    const wasted = Math.round(silent.reduce((s,d)=>s+spendByDay[d],0));
    const sig = silent.join(",");
    if(silent.length>=1 && sig !== (prevC2.silent_sig||"")){
      checks.clara.findings.push({okey:"clara_campaign_silent", severity:"high", confidence:"exakt",
        facts:[{label:"Tage mit Kampagnen-Ausgaben, aber ohne eine einzige Bewerbung", current:silent.length},{label:"in diesen Tagen ausgegeben (Euro)", current:wasted}],
        frame:"Alarm: die Kampagne lief und kostete Geld, aber es kam nichts an. Sag klar, dass das auffällt und geprüft werden muss. Die Zahlen sind exakt, die Ursache eine Vermutung.",
        metrics:{silent_days:silent, wasted}});
    }
    checks.clara.snapshot = { ...(checks.clara.snapshot||prevC2||{}), silent_sig: sig };
  }catch(_e){}

  // Max: leer abgehakte Aufgaben heute vs. Vortag
  try{
    const emToday = await cnt("daily_tasks_done","done_at",date,n1,(x)=>x.eq("session_writes",0));
    const emPrev  = await cnt("daily_tasks_done","done_at",p,date,(x)=>x.eq("session_writes",0));
    if(emToday>=3 && emToday>emPrev)
      checks.max.findings.push({okey:"max_empty_checks", severity:"warn", confidence:"exakt",
        facts:[{label:"Aufgaben leer abgehakt (ohne Datenänderung)", current:emToday, prior:emPrev}], metrics:{emToday,emPrev}});
  }catch(_e){}

  // Anna: neue offene Wissenslücken heute
  try{
    const gapsToday = await cnt("assistant_gaps","created_at",date,n1,(x)=>x.eq("resolved",false));
    if(gapsToday>=2)
      checks.anna.findings.push({okey:"anna_gaps", severity:"info", confidence:"exakt",
        facts:[{label:"neue Fragen ohne Antwort im Wissen", current:gapsToday}], metrics:{gapsToday}});
  }catch(_e){}

  // Paul: gelieferte Stunden PRO PROJEKT diese Woche vs. Vorwoche. Projekt (und Skill, wenn eindeutig) als
  // FELD mitführen, damit der Gefragte im Dialog gezielt nach diesem Projekt suchen kann statt zu raten.
  try{
    const w=isoWeek(date), wp=isoWeek(d7);
    const load=async (yr:number,kw:number)=>{ const {data}=await sb.from("weekly_hours").select("project_id,skill,hours").eq("year",yr).eq("kw",kw); return data||[]; };
    const rowsThis=await load(w.year,w.week), rowsPrev=await load(wp.year,wp.week);
    const { data:projs } = await sb.from("projects").select("id,name");
    const pmap:Record<string,string>={}; (projs||[]).forEach((p:any)=>{ pmap[p.id]=p.name; });
    const aggBy=(rows:any[])=>{ const m:Record<string,{h:number,skills:Set<string>}>={};
      for(const r of rows){ const pid=r.project_id; if(!pid) continue; (m[pid] ||= {h:0,skills:new Set()}); m[pid].h+=Number(r.hours)||0; if(r.skill) m[pid].skills.add(r.skill); } return m; };
    const aThis=aggBy(rowsThis), aPrev=aggBy(rowsPrev);
    // Union beider Wochen — ein Projekt, das auf 0 einbricht, ist der GRÖSSTE Einbruch und darf nicht durchfallen.
    const pids = new Set([...Object.keys(aThis), ...Object.keys(aPrev)]);
    const movers = [...pids].map((pid)=>{ const hThis=aThis[pid]?.h||0, hPrev=aPrev[pid]?.h||0;
        return { pid, hThis, hPrev, delta:hThis-hPrev, rel: hPrev>0?Math.abs((hThis-hPrev)/hPrev):(hThis>0?1:0),
                 skills:[...((aThis[pid]?.skills)||(aPrev[pid]?.skills)||new Set())] }; })
      .filter((m)=> m.hPrev>0 && m.rel>=0.15)   // etabliertes Projekt mit deutlicher Veränderung (auch Einbruch auf 0)
      .sort((a,b)=>Math.abs(b.delta)-Math.abs(a.delta)).slice(0,3);   // nur die stärksten Bewegungen, kein Rauschen
    for(const m of movers){ const pname=pmap[m.pid]||m.pid; const skill = m.skills.length===1?m.skills[0]:null;
      checks.paul.findings.push({ okey:"paul_hours_week_"+m.pid, severity: m.hThis<m.hPrev?"warn":"info", confidence:"exakt",
        project_id:m.pid, skill,
        facts:[{label:"gelieferte Stunden diese Woche (KW "+w.week+", "+pname+(skill?", "+skill:"")+")", current:Math.round(m.hThis), prior:Math.round(m.hPrev)}],
        metrics:{hThis:Math.round(m.hThis),hPrev:Math.round(m.hPrev),project:m.pid,skill,kw:w.week}});
    }
  }catch(_e){}

  // Maya: Zugänge mit plötzlichem Abbruch (vorher regelmäßig, letzte 7 Tage nichts)
  try{
    const { data:al } = await sb.from("activity_log").select("user_id,created_at").gte("created_at",d28).lt("created_at",n1);
    const prevDays:Record<string,Set<string>>={}, lastDays:Record<string,Set<string>>={};
    (al||[]).forEach((r:any)=>{ const day=String(r.created_at).slice(0,10); const u=r.user_id; if(!u) return;
      if(day>=d7){ (lastDays[u]=lastDays[u]||new Set()).add(day); } else { (prevDays[u]=prevDays[u]||new Set()).add(day); } });
    let drop=0; Object.keys(prevDays).forEach(u=>{ if(prevDays[u].size>=8 && !(lastDays[u]&&lastDays[u].size)) drop++; });
    if(drop>0)
      checks.maya.findings.push({okey:"maya_drop", severity:"info", confidence:"exakt",
        facts:[{label:"Zugänge seit einer Woche ohne Aktivität, vorher regelmäßig", current:drop}], metrics:{drop}});
  }catch(_e){}

  // Lena: Datenpflege-Lücken, die Geld blockieren (Bank/Ausweis), + Delta zum letzten Stand
  try{
    const { data:lf } = await sb.rpc("lena_scan");
    const byCat:Record<string,number>={}; (lf||[]).forEach((f:any)=>{ byCat[f.category]=(byCat[f.category]||0)+1; });
    const { data:chk } = await sb.from("agent_checks").select("metrics").eq("agent_key","lena").maybeSingle();
    const prev = (chk&&chk.metrics)||{};
    if((byCat.bank_fehlt||0)>0)
      checks.lena.findings.push({okey:"lena_bank_fehlt", severity:"high", confidence:"exakt",
        facts:[{label:"Mitarbeiter ohne Bankdaten, das blockiert die Lohnzahlung", current:byCat.bank_fehlt, prior:(prev.bank_fehlt!==undefined?prev.bank_fehlt:null)}], metrics:{bank_fehlt:byCat.bank_fehlt}});
    if((byCat.ausweis_fehlt||0)>0)
      checks.lena.findings.push({okey:"lena_ausweis_fehlt", severity:"warn", confidence:"exakt",
        facts:[{label:"Mitarbeiter ohne Ausweis-Nummer", current:byCat.ausweis_fehlt, prior:(prev.ausweis_fehlt!==undefined?prev.ausweis_fehlt:null)}], metrics:{ausweis_fehlt:byCat.ausweis_fehlt}});
    checks.lena.snapshot = byCat;
  }catch(_e){}

  // Vorhaben 3, Schnitt 3: Paul meldet sichere Personal-Lücken (nur wo vorhersagbar), Max meldet fehlende
  // Vorschau-Daten je Projekt — mit der Folge „ohne diese Daten keine Vorausschau" (macht Druck, sie zu schließen).
  try{
    const { data:projRows } = await sb.from("employees").select("project_id").in("status",["active","training"]);
    const projIds = [...new Set((projRows||[]).map((r:any)=>r.project_id).filter(Boolean))];
    for(const pid of projIds){
      const { data:sf } = await sb.rpc("staffing_forecast_core",{ p_project: pid });
      if(!sf) continue;
      const pname = sf.project_name || pid; const weeks = sf.weeks || [];
      const gaps = weeks.filter((w:any)=>w.status==="ok" && Number(w.gap_people)>=2).sort((a:any,b:any)=>(a.year*100+a.kw)-(b.year*100+b.kw));
      if(gaps.length){ const g=gaps[0];
        checks.paul.findings.push({okey:"paul_staffing_gap_"+pid, severity:"high", confidence:"exakt",
          project_id:pid, skill:g.skill,
          facts:[{label:"fehlende Leute in KW "+g.kw+" ("+pname+", "+g.skill+")", current:g.gap_people}], metrics:{kw:g.kw, skill:g.skill, gap:g.gap_people, project:pid}});
      }
      const hasForecast = sf.has_forecast===true;
      const anyPlanned = weeks.some((w:any)=>w.planned_h!=null);
      const anyComplete = weeks.some((w:any)=>w.status==="ok" || w.status==="skala_unklar");
      const missing:string[]=[];
      if(!hasForecast) missing.push("der Forecast");
      if(!anyPlanned)  missing.push("der Schichtplan für die kommenden Wochen");
      if(missing.length && !anyComplete){
        checks.max.findings.push({okey:"max_forecast_data_"+pid, severity:"warn", confidence:"exakt", missing:true,
          project_id:pid,
          facts:[{label:"fehlt bei "+pname+" für die Personal-Vorschau", current: missing.join(" und ")},
                 {label:"Folge", current:"ohne diese Daten keine Vorausschau für dieses Projekt"}],
          metrics:{project:pid, missing}});
      }
    }
  }catch(_e){}

  // Schreiben: Befunde als Beobachtungen (Kollegen-Satz) + Einblendungen je Zielnutzer + Heartbeat je Agent.
  const NAMES:Record<string,string> = { clara:"Clara", max:"Max", anna:"Anna", paul:"Paul", maya:"Maya", lena:"Lena" };
  // Wer bekommt welchen Kollegen zu sehen (Rollen); Kontext = wo die Einblendung passt (am richtigen Ort).
  const ROLE_TARGETS:Record<string,string[]> = { clara:["management","hr"], max:["management","hr"], anna:["management","hr"], paul:["management"], maya:["management"], lena:["management","hr"] };
  const AGENT_CONTEXT:Record<string,string[]> = { clara:["kanban","funnel","cvs","dubletten","bewerberlinks"], max:["daily_tasks","uploads","dataimport","vorschau"], anna:["nlquery","wissen_system","knowledge"], paul:["auswertung","praesentation","meetingnotes","vorschau","fcist"], maya:["useractivity"], lena:["datacheck","absences","urlaubantraege","employees"] };
  const { data:usersRaw } = await sb.from("app_users").select("user_id,role_keys,active");
  const users = (usersRaw||[]).filter((u:any)=>u.active!==false && u.user_id);
  const targetsFor=(k:string)=>{ const roles=ROLE_TARGETS[k]||["management"]; return users.filter((u:any)=>(u.role_keys||[]).some((r:string)=>roles.includes(r))).map((u:any)=>u.user_id); };
  let totalFound=0, insCount=0;
  for(const key of Object.keys(checks)){
    const c=checks[key]; const persona=await personaOf(key);
    for(const f of c.findings){
      let title=""; try{ title=await colleagueLine(NAMES[key], persona, {facts:f.facts, confidence:f.confidence, missing:f.missing}); }catch(_e){}
      if(!title) title = f.facts.map((x:any)=>`${x.label}: ${x.current}`).join("; ");
      const { data:obsRow } = await sb.from("agent_observations").upsert({ day:date, okey:f.okey, agent_key:key, severity:f.severity, title, metrics:f.metrics||null, confidence:f.confidence||null, facts:f.facts||null, project_id:f.project_id||null, skill:f.skill||null },{onConflict:"day,okey"}).select("id").maybeSingle();
      const tgts=targetsFor(key); const ctx=AGENT_CONTEXT[key]||null;
      if(tgts.length){
        // facts + confidence denormalisiert mit auf die Einblendung -> der „Warum"-Knopf zeigt die Werte, ohne
        // dass die Zielperson die admin-geschützte agent_observations-Zeile lesen muss.
        const rows = tgts.map((uid:string)=>({ agent_key:key, user_id:uid, observation_id:(obsRow&&obsRow.id)||null, okey:f.okey, day:date, title, severity:f.severity, context:ctx, facts:f.facts||null, confidence:f.confidence||null }));
        const { error } = await sb.from("agent_insights").upsert(rows, {onConflict:"user_id,day,okey", ignoreDuplicates:true});
        if(!error) insCount += rows.length;
      }
    }
    totalFound += c.findings.length;
    await sb.from("agent_checks").upsert({ agent_key:key, last_checked_at:new Date().toISOString(), last_day:date, found_count:c.findings.length, metrics:(c.snapshot!==undefined?c.snapshot:undefined), updated_at:new Date().toISOString() },{onConflict:"agent_key"});
  }

  return json({ ok:true, date, found:totalFound, insights:insCount, per:Object.fromEntries(Object.entries(checks).map(([k,v])=>[k,v.findings.length])) });
});
