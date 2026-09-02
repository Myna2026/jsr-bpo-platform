// Edge Function: Bruno, der Haustechniker (Helpdesk am Ort). Zwei Modi:
//  - fragen (Standard): analysiert die aktuelle Lage (Bereich + Browser-Fehler + Rechte des Nutzers + bekanntes
//    Wissen) und antwortet als Anleitung / Rechte-Hinweis / Fehler-Erklärung / „echter Fehler" (mit Übergabe-Angebot).
//  - action:'handoff': sammelt die Lage und übergibt ans Management — Meldung im System (system_findings) + Slack.
// Er repariert nichts. Zugang: eingeloggter Nutzer mit HR-Portal. Deploy: supabase functions deploy helpdesk --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods":"POST, OPTIONS" };
const json = (b:unknown, s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});

const MODEL = "claude-sonnet-5";
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") || "";
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SLACK = Deno.env.get("SLACK_BOT_TOKEN") || "";
const DEFAULT_TO = "info@mynaai.de";

const NAV: string[][] = [
  ["cockpit","Cockpit","Kennzahlen-Überblick"],["daily_tasks","Tagesaufgaben","was heute zu tun ist"],
  ["employees","Mitarbeiter","Mitarbeiter anlegen/bearbeiten, Vertrag, Status, Kündigung"],
  ["absences","Abwesenheiten","Krank/Urlaub eintragen"],["urlaubantraege","Urlaubsanträge","Anträge entscheiden"],
  ["payroll","Löhne","Lohnlauf, Boni, Abrechnungen"],["performance","Performance","KPIs eintragen"],
  ["callqa","Call-Qualität","Call-Bewertungen"],["kanban","Recruiting","Bewerber-Pipeline, per Drag&Drop bewegen"],
  ["cvs","CVs & Bewerber","Bewerber-Liste, nächste Phase"],["funnel","Bewerber-Trichter","Recruiting-Auswertung"],
  ["dubletten","Dubletten","doppelte Bewerber"],["onboarding","Onboarding","Einarbeitung, Hardware"],
  ["training_plans","Schulungsplanung","Schulungen, Teilnehmer"],["projects","Projekte","Projekt-Übersicht"],
  ["shiftplan","Schichtplanung","Wochen-Schichtplan"],["checkin","Check-in","Ist-Anwesenheit"],
  ["dataimport","Datenimport","Dateien hochladen"],["uploads","Uploads","was fällig ist"],
  ["nlquery","Datenabfrage","Zahlen-Fragen an die DB"],["praesentation","Präsentationen","Kundenbericht"],
  ["errorlog","Fehler-Log","gesammelte Frontend-Fehler (Management)"],
];
const NAV_KEYS = new Set(NAV.map((n)=>n[0]));

const ARCHITEKTUR = `AUFBAU (Kurz): Portale HR/Mitarbeiter/Client. Supabase (Postgres, Auth, RLS, Storage, Functions).
ROLLEN → Portale: kunde→client; mitarbeiter→mitarbeiter; teamlead/qm/trainer/asp/projektleiter/hr/finance/management→hr.
Rechte über RLS (is_management/is_hr/is_finance/is_admin=mgmt|hr/is_planner). Feingranular über permission_areas: je
Bereich {visible, mode:none/read/edit, projects:own/all, columns}. Wer etwas nicht darf, dem fehlt meist das Recht im
Bereich, oder die Rolle. Projektleiter sehen nur ihr Projekt. HR sieht keine Management-Gehälter.
RECRUITING: Bewerber wandern per Drag&Drop durch Phasen (Bereich 'kanban' → Rechte-Bereich 'bewerber'). Wer nicht
verschieben kann: Rechte-Bereich 'bewerber' braucht mode 'edit'; eine CV→Mitarbeiter-Grenze wird bewusst geblockt.`;

const TOOL = {
  name: "hilfe",
  description: "Brunos Einordnung und Antwort. Bodenständig, kurz, in Alltagssprache.",
  input_schema: { type:"object", properties:{
    kind: { type:"string", enum:["anleitung","rechte","fehler_erklaert","echter_fehler","rueckfrage"],
      description:"anleitung=wie geht das; rechte=liegt an fehlendem Recht; fehler_erklaert=Fehlermeldung erklärt; echter_fehler=unklar, gehört gemeldet; rueckfrage=ich brauche die genaue Meldung" },
    answer: { type:"string", description:"kurze Antwort in Brunos Stimme, Deutsch, per Du" },
    steps: { type:"array", items:{type:"string"}, description:"kurze Schritte, je ein Satz (bei anleitung)" },
    jump: { type:["string","null"], description:"view-key aus NAVIGATION zum Hinspringen, oder null" },
    missing_right: { type:["string","null"], description:"bei kind=rechte: welches Recht/welche Rolle fehlt, in Alltagssprache" },
    handoff_suggested: { type:"boolean", description:"true, wenn es ein echter Fehler ist und ans Management sollte" },
  }, required:["kind","answer"] },
};

function ctxText(c:any):string{
  if(!c) return "(keine Angaben)";
  const p=c.perm;
  const permS = p ? `Bereich '${p.area}': sichtbar=${p.visible}, Modus=${p.mode||'-'}, Projekte=${p.projects||'-'}` : "(kein bereichsbezogenes Recht bekannt)";
  const errs = Array.isArray(c.recent_errors)&&c.recent_errors.length ? c.recent_errors.map((e:any)=>`- [${e.kind}] ${e.message} (Bereich ${e.area||'?'})`).join("\n") : "(keine Browser-Fehler erfasst)";
  return [
    "Bereich, in dem der Nutzer gerade ist: "+(c.area_label||c.area||"?")+" (view-key: "+(c.area||"?")+")",
    "Rolle(n) des Nutzers: "+((c.role_keys||[]).join(", ")||"?"),
    "Recht in diesem Bereich: "+permS,
    "Sichtbare Fehlermeldung (Toast): "+(c.toast||"(keine)"),
    "Zuletzt erfasste Browser-Fehler:\n"+errs,
  ].join("\n");
}

async function knowledge(admin:any):Promise<string>{
  let manual:any[]=[], kb:any[]=[];
  try{ const {data}=await admin.from("app_config").select("value").eq("key","jsr_system_manual_v1").maybeSingle(); manual=(data&&data.value)||[]; }catch(_e){}
  try{ const {data}=await admin.from("app_config").select("value").eq("key","jsr_kb_v1").maybeSingle(); kb=(data&&data.value&&data.value.articles)||[]; }catch(_e){}
  const mt=(manual||[]).map((d:any)=>"### "+(d.title||"")+"\n"+((d.sections||[]).map((s:any)=>"- "+(s.h||"")+": "+(s.body||"")).join("\n"))).join("\n\n");
  const kt=(kb||[]).map((a:any)=>"### "+(a.title||"")+"\n"+(a.content||"")).join("\n\n");
  return ("HANDBUCH:\n"+(mt||"(leer)")+"\n\nWISSENSBASIS:\n"+(kt||"(leer)")).slice(0,14000);
}

async function recipient(admin:any):Promise<string>{
  try{ const {data}=await admin.from("app_config").select("value").eq("key","jsr_maya_watch_recipient").maybeSingle();
    const v=data?.value; if(typeof v==="string"&&v.includes("@")) return v; if(v&&typeof v==="object"&&typeof (v as any).email==="string") return (v as any).email; }catch(_e){}
  return DEFAULT_TO;
}

async function slackAsBruno(email:string, text:string):Promise<string>{
  if(!SLACK) return "no-slack-token";
  const lu=await (await fetch("https://slack.com/api/users.lookupByEmail?email="+encodeURIComponent(email),{headers:{Authorization:"Bearer "+SLACK}})).json();
  if(!lu.ok) return "no-slack-user:"+(lu.error||"?");
  const o=await (await fetch("https://slack.com/api/conversations.open",{method:"POST",headers:{Authorization:"Bearer "+SLACK,"Content-Type":"application/json"},body:JSON.stringify({users:lu.user.id})})).json();
  if(!o.ok) return "open-fail:"+(o.error||"?");
  const m=await (await fetch("https://slack.com/api/chat.postMessage",{method:"POST",headers:{Authorization:"Bearer "+SLACK,"Content-Type":"application/json"},
    body:JSON.stringify({channel:o.channel.id, text, username:"Bruno · Helpdesk"})})).json();
  return m.ok?"sent":("post:"+(m.error||"?"));
}

Deno.serve(async (req)=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
  if(req.method!=="POST") return json({error:"POST erwartet"},405);
  const auth=req.headers.get("Authorization")||"";
  if(!auth) return json({error:"Nicht angemeldet."},401);
  const sb=createClient(SB_URL,ANON,{global:{headers:{Authorization:auth}}});
  const { data:udata }=await sb.auth.getUser();
  const uid=udata?.user?.id;
  if(!uid) return json({error:"Sitzung ungültig."},401);
  const { data:au }=await sb.from("app_users").select("role_keys,full_name").eq("user_id",uid).single();
  const roles:string[]=(au?.role_keys as string[])||[];
  if(!roles.length) return json({error:"Kein Zugang."},403);
  const { data:rdefs }=await sb.from("roles_definitions").select("portals").in("role_key",roles);
  const hasHr=(rdefs||[]).some((r:any)=>(r.portals||[]).includes("hr"));
  if(!hasHr) return json({error:"Nur fürs HR-Portal freigegeben."},403);

  let body:any={}; try{ body=await req.json(); }catch{}
  const context=body?.context||{};
  const admin=createClient(SB_URL,SERVICE);

  // ── Modus 2: Übergabe ans Management ──────────────────────────────────────
  if(body?.action==="handoff"){
    const who=(au?.full_name)||udata?.user?.email||uid;
    const wo=context.area_label||context.area||"?";
    const was=String(body?.question||context.summary||"").slice(0,600);
    const meldung=context.toast||(Array.isArray(context.recent_errors)&&context.recent_errors[0]?context.recent_errors[0].message:"")||"(keine Meldung)";
    const p=context.perm;
    const rechte=p?`${p.area}: sichtbar=${p.visible}, Modus=${p.mode||'-'}, Projekte=${p.projects||'-'}`:"(unbekannt)";
    const title=("Helpdesk: "+(was||"Problem")).slice(0,140);
    const evidence={ was, wer:who+" ("+roles.join(", ")+")", wo, meldung, rechte, browser:String(context.user_agent||"").slice(0,300), seite:String(context.url||"").slice(0,300) };
    let fkey="helpdesk:"+crypto.randomUUID();
    try{ await admin.from("system_findings").insert({ fkey, category:"helpdesk", severity:"blocking", title, evidence, notified_at:new Date().toISOString() }); }catch(_e){}
    const to=await recipient(admin);
    const text="*Bruno · Helpdesk-Meldung*\n"+title+
      "\n• Wer: "+evidence.wer+"\n• Wo: "+wo+"\n• Was: "+(was||"-")+"\n• Meldung: "+meldung+"\n• Rechte: "+rechte+"\n• Browser: "+evidence.browser;
    let slack="skip"; try{ slack=await slackAsBruno(to,text); }catch(_e){ slack="error"; }
    try{ await admin.from("agent_actions").insert({ agent_key:"bruno", kind:"handoff" }); }catch(_e){}
    return json({ ok:true, slack });
  }

  // ── Modus 1: Fragen / Analyse ─────────────────────────────────────────────
  if(!ANTHROPIC_KEY) return json({error:"Der KI-Schlüssel ist noch nicht hinterlegt."},503);
  const question=String(body?.question||"").trim();
  if(!question) return json({error:"Keine Frage übergeben."},400);
  const know=await knowledge(admin);

  const system =
    "Du bist Bruno, der Haustechniker im System. Bodenständig, ruhig, verlässlich. Du hilfst dort, wo jemand nicht "+
    "weiterkommt. Du reparierst NICHTS und änderst keine Daten. Kurze Sätze, einfache Wörter, per Du, kein "+
    "Konjunktivgeflecht, keine Redewendungen (Deutsch als Zweitsprache). Keine Emotionen, keine erfundenen Fakten.\n\n"+
    "SO GEHST DU VOR:\n"+
    "- Schau zuerst auf die AKTUELLE LAGE (Bereich, Rechte, Fehlermeldung).\n"+
    "- Fragt jemand WIE etwas geht → kind='anleitung', kurze Schritte, wenn sinnvoll ein jump-Ziel.\n"+
    "- Deutet die LAGE auf ein fehlendes RECHT (Modus 'read' oder 'none' oder sichtbar=false, wo 'edit' nötig wäre) → "+
    "kind='rechte', erklär in missing_right was fehlt. Stimmen die Rechte, sag das und frag nach der genauen Meldung (kind='rueckfrage').\n"+
    "- Gibt es eine erklärbare Fehlermeldung → kind='fehler_erklaert', sag was sie bedeutet und was zu tun ist.\n"+
    "- Ist es ein echter Fehler, den weder Rechte noch bekanntes Wissen erklären → kind='echter_fehler', "+
    "handoff_suggested=true, biete an, es an das Management zu übergeben. Erfinde keine Ursache.\n"+
    "- jump nur als echter view-key aus der NAVIGATION, sonst null.\n\n"+
    ARCHITEKTUR+"\n\nNAVIGATION (view-key = wo man was macht):\n"+NAV.map((n)=>"- "+n[0]+" = "+n[1]+": "+n[2]).join("\n")+"\n\n"+
    "AKTUELLE LAGE:\n"+ctxText(context)+"\n\n"+know;

  let tool:any;
  try{
    const resp=await fetch("https://api.anthropic.com/v1/messages",{ method:"POST",
      headers:{ "x-api-key":ANTHROPIC_KEY, "anthropic-version":"2023-06-01", "content-type":"application/json" },
      body: JSON.stringify({ model:MODEL, max_tokens:900, system, tools:[TOOL], tool_choice:{type:"tool",name:"hilfe"}, messages:[{role:"user",content:question}] }) });
    const data=await resp.json();
    if(!resp.ok) return json({error:"KI-Fehler: "+(data?.error?.message||resp.status)},502);
    tool=(data.content||[]).find((c:any)=>c.type==="tool_use");
    if(!tool) return json({error:"Keine verwertbare Antwort."},502);
  }catch(e){ return json({error:"Die KI ist gerade nicht erreichbar: "+(e as Error).message},502); }

  const out=tool.input||{};
  const jump=(typeof out.jump==="string"&&NAV_KEYS.has(out.jump))?out.jump:null;
  if(out.kind==="echter_fehler"){ try{ const q=question.slice(0,500); if(q) await admin.from("assistant_gaps").insert({ question:q, asked_by:uid }); }catch(_e){} }
  try{ await admin.from("agent_actions").insert({ agent_key:"bruno", kind:"helpdesk" }); }catch(_e){}
  return json({ kind:out.kind||"rueckfrage", answer:out.answer||"", steps:Array.isArray(out.steps)?out.steps:[], jump,
    missing_right:(typeof out.missing_right==="string"?out.missing_right:null), handoff_suggested:!!out.handoff_suggested });
});
