// Maya System-Watch, Scan + Sofort-Slack. Läuft täglich: erkennt DB-Auffälligkeiten (maya_system_scan),
// meldet NEUE BLOCKIERENDE Funde sofort per Slack-DM an den Eigentümer — sichtbar als Maya (Name + Gesicht,
// chat:write.customize). Nur an ihn, einmal je Fund. Cosmetic-Funde wandern nur in die Di/Fr-Mail.
// Deploy: supabase functions deploy maya-system-scan --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods":"POST, OPTIONS" };
const json = (b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});
const SLACK = Deno.env.get("SLACK_BOT_TOKEN") || "";
const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const MAYA_ICON = "https://tive360.de/assets/agents/maya.png";
const DEFAULT_TO = "info@mynaai.de";

async function recipient():Promise<string>{
  try{ const { data } = await sb.from("app_config").select("value").eq("key","jsr_maya_watch_recipient").maybeSingle();
    const v = data?.value; if(typeof v==="string" && v.includes("@")) return v; if(v && typeof v==="object" && typeof (v as any).email==="string") return (v as any).email; }catch(_e){}
  return DEFAULT_TO;
}

// Slack-DM sichtbar als Maya (Name + Gesicht). Braucht chat:write.customize; sonst meldet Slack missing_scope.
async function slackAsMaya(email:string, text:string):Promise<string>{
  if(!SLACK) return "no-slack-token";
  const lu = await (await fetch("https://slack.com/api/users.lookupByEmail?email="+encodeURIComponent(email),{headers:{Authorization:"Bearer "+SLACK}})).json();
  if(!lu.ok) return "no-slack-user:"+(lu.error||"?");
  const o = await (await fetch("https://slack.com/api/conversations.open",{method:"POST",headers:{Authorization:"Bearer "+SLACK,"Content-Type":"application/json"},body:JSON.stringify({users:lu.user.id})})).json();
  if(!o.ok) return "open-fail:"+(o.error||"?");
  const m = await (await fetch("https://slack.com/api/chat.postMessage",{method:"POST",headers:{Authorization:"Bearer "+SLACK,"Content-Type":"application/json"},
    body:JSON.stringify({channel:o.channel.id, text, username:"Maya", icon_url:MAYA_ICON})})).json();
  return m.ok ? "sent" : ("post:"+(m.error||"?"));
}

function findingText(f:any):string{
  const e = f.evidence||{};
  return "*Maya · Systemhinweis*\n"+f.title+
    (e.was?("\n• Was: "+e.was):"")+
    (e.seit?("\n• Seit: "+e.seit):"")+
    (e.haengt_dran?("\n• Hängt dran: "+e.haengt_dran):"");
}

Deno.serve(async (req)=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
  let body:any={}; try{ body=await req.json(); }catch(_e){}
  const to = await recipient();

  // Test-Modus: eine Beispiel-Maya-Nachricht, um Identität + chat:write.customize zu prüfen.
  if(body.test===true){ const r = await slackAsMaya(to, "*Maya · Test*\nWenn du das mit meinem Gesicht und Namen siehst, ist chat:write.customize aktiv."); return json({ ok:true, test:true, to, slack:r }); }

  const { data:scan, error } = await sb.rpc("maya_system_scan");
  if(error) return json({ error:"Scan fehlgeschlagen: "+error.message }, 500);
  const newBlocking = (scan?.new_blocking as any[]) || [];

  const sent:string[] = []; const failed:any[] = [];
  for(const f of newBlocking){
    const r = await slackAsMaya(to, findingText(f));
    if(r==="sent"){ sent.push(f.fkey); }
    else failed.push({ fkey:f.fkey, slack:r });
  }
  if(sent.length){ await sb.from("system_findings").update({ notified_at:new Date().toISOString() }).in("fkey", sent); }

  return json({ ok:true, scanned:scan?.scanned||0, new_blocking:newBlocking.length, slack_sent:sent.length, failed });
});
