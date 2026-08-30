// Maya System-Watch, Digest-Mail (Di + Fr). Fasst die offenen Funde zusammen, nach Dringlichkeit sortiert:
// blockierend zuerst (was steht im Weg), dann cosmetic (nur unschön). Erledigtes fällt raus. Cosmetic wird
// EINMAL berichtet (digested_at), damit es nicht nervt; blockierend bleibt bis behoben. Nur an den Eigentümer,
// als Maya (Absender aus dem Register). Deploy: supabase functions deploy maya-system-digest --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { agentBrand, shell, block, lead } from "../_shared/agent_mail.ts";
import { agentMailSender, smtpSend } from "../_shared/agent_send.ts";

const cors = { "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods":"POST, OPTIONS" };
const json = (b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}});
const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const DEFAULT_TO = "info@mynaai.de";
const COSMETIC_AGE_DAYS = 14;   // cosmetic erst nach Persistenz in die Mail (kein Tages-Rauschen)

const esc=(s:string)=>String(s??"").replace(/[&<>]/g,(c)=>({"&":"&amp;","<":"&lt;",">":"&gt;"} as any)[c]);
function since(f:any):string{
  const e=f.evidence||{}; const d = e.seit ? new Date(String(e.seit)) : new Date(f.first_seen);
  if(isNaN(d.getTime())) return "";
  const days = Math.max(0, Math.floor((Date.now()-d.getTime())/86400000));
  const de = d.toLocaleDateString("de-DE",{day:"2-digit",month:"short"});
  return days<=1 ? ("seit "+de) : ("seit "+de+" ("+days+" Tagen)");
}
function evi(f:any):string{
  const e=f.evidence||{};
  return [ e.was?("<b>Was:</b> "+esc(e.was)):"", since(f)?("<b>Seit:</b> "+esc(since(f))):"",
           e.haengt_dran?("<b>Hängt dran:</b> "+esc(e.haengt_dran)):"" ].filter(Boolean).join("<br>");
}

async function recipient():Promise<string>{
  try{ const { data } = await sb.from("app_config").select("value").eq("key","jsr_maya_watch_recipient").maybeSingle();
    const v=data?.value; if(typeof v==="string"&&v.includes("@")) return v; if(v&&typeof v==="object"&&typeof (v as any).email==="string") return (v as any).email; }catch(_e){}
  return DEFAULT_TO;
}

Deno.serve(async (req)=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
  let body:any={}; try{ body=await req.json(); }catch(_e){}
  const dry = body.dry===true;
  const to = await recipient();

  const cutoff = new Date(Date.now()-COSMETIC_AGE_DAYS*86400000).toISOString();
  const { data:blocking } = await sb.from("system_findings").select("*").is("resolved_at",null).eq("severity","blocking").order("first_seen");
  const { data:cosmetic } = await sb.from("system_findings").select("*").is("resolved_at",null).eq("severity","cosmetic").is("digested_at",null).lte("first_seen",cutoff).order("category").order("first_seen");
  const blk = blocking||[]; const cos = cosmetic||[];

  const card=(title:string,bodyHtml:string,accent:string)=>block(
    '<div style="border-left:3px solid '+accent+';background:'+accent+'0d;border-radius:10px;padding:11px 14px;margin:0 0 10px;">'
    +'<div style="font-size:13px;font-weight:800;color:'+accent+';margin-bottom:5px;">'+esc(title)+'</div>'
    +'<div style="font-size:12.5px;color:#334155;line-height:1.55;">'+bodyHtml+'</div></div>');
  const eyebrow=(text:string,color:string)=>block('<div style="font-size:12px;font-weight:800;text-transform:uppercase;letter-spacing:.05em;color:'+color+';margin:16px 0 8px;">'+esc(text)+'</div>');

  const brand = await agentBrand(sb,"maya");
  let inner = "";
  if(!blk.length && !cos.length){
    inner = card("Nichts Neues", "Geprüft, nichts Blockierendes und nichts Ungeklärtes offen. Erledigtes ist bereits herausgefallen.", "#15803d");
  } else {
    if(blk.length){
      inner += eyebrow("Blockierend · steht etwas im Weg", "#b91c1c");
      for(const f of blk) inner += card(f.title, evi(f), "#dc2626");
    }
    // cosmetic: leere Tabellen gruppiert (sonst 20 Kacheln), Widersprüche einzeln.
    const emptyT = cos.filter((f:any)=>f.category==="empty_table");
    const others = cos.filter((f:any)=>f.category!=="empty_table");
    if(others.length || emptyT.length){
      inner += eyebrow("Nur unschön · bei Gelegenheit", "#b45309");
      for(const f of others) inner += card(f.title, evi(f), "#b45309");
      if(emptyT.length){
        const list = emptyT.map((f:any)=>"<b>"+esc((f.evidence?.was)||f.title)+"</b> "+esc(since(f))).join("<br>");
        inner += card(emptyT.length+" leere Tabelle(n), evtl. tot oder ungenutzt",
          "Diese Tabellen werden von niemandem befüllt. Bitte prüfen, ob sie noch gebraucht werden.<br><br>"+list, "#b45309");
      }
    }
  }
  inner = lead('<p style="margin:0 0 6px;font-size:14px;color:#1f2937;line-height:1.5;">Was mir im System aufgefallen ist, nach Dringlichkeit. Nur die Rechnung, keine Wertung.</p>') + inner;

  const html = shell(brand, "System-Watch", "Was steht im Weg, was ist nur unschön", inner);
  if(dry) return json({ ok:true, dry:true, to, blocking:blk.length, cosmetic:cos.length, html });

  const sender = await agentMailSender(sb,"maya");
  if(!sender) return json({ error:"Kein Maya-Absender im Register" }, 500);
  const r = await smtpSend(sender, to, "System-Watch · "+(blk.length?blk.length+" blockierend":"nichts Blockierendes"), html);
  if(r.ok && cos.length){ await sb.from("system_findings").update({ digested_at:new Date().toISOString() }).in("fkey", cos.map((f:any)=>f.fkey)); }
  return json({ ok:!!r.ok, to, blocking:blk.length, cosmetic:cos.length, mail:r.ok?"sent":r.error });
});
