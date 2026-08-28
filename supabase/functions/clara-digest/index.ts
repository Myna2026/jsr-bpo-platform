// Claras Morgen-Zusammenfassung fürs Recruiting-Team. Nach dem Import (nach 02:00 UTC), morgens ~07:00 Berlin.
// INTERN an eigene Leute → keine Vorlagenpflicht, Clara formuliert frei (Leitplanke „kein Freitext nach außen"
// gilt hier NICHT). Kennzahlen aus clara_morning_stats + Claras Beobachtungen (Schnitt 3/4-Stimme). Slack + Mail
// parallel aus Claras eigenem Postfach. Empfänger aus app_config jsr_clara_digest_recipients_v1 (leicht erweiterbar).
// Deploy: supabase functions deploy clara-digest --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const json = (b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{"Content-Type":"application/json"}});
const MODEL = "claude-sonnet-5";
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") || "";
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SLACK = Deno.env.get("SLACK_BOT_TOKEN") || "";
const Z_HOST = Deno.env.get("ZOHO_SMTP_HOST") || "smtppro.zoho.eu";
const Z_PORT = Number(Deno.env.get("ZOHO_SMTP_PORT") || "465");
const sb = createClient(SB_URL, SERVICE);

import { isWeekendBerlin } from "../_shared/schedule.ts";
const berlinHour = ()=> Number(new Intl.DateTimeFormat("en-GB",{timeZone:"Europe/Berlin",hour:"2-digit",hour12:false}).format(new Date()));
const berlinDate = ()=>{ const b=new Date(new Date().toLocaleString("en-US",{timeZone:"Europe/Berlin"})); return b.toISOString().slice(0,10); };

// ── Mail (Claras Postfach, freier Text) ──
function b64utf8(s:string){ const b=new TextEncoder().encode(s); let bin=""; const CH=0x8000; for(let i=0;i<b.length;i+=CH) bin+=String.fromCharCode(...b.subarray(i,i+CH)); return btoa(bin); }
function encWord(s:string){ return /[^\x00-\x7F]/.test(s) ? "=?UTF-8?B?"+b64utf8(s)+"?=" : s; }
function smtpPass(key:string){ const cap=key.charAt(0).toUpperCase()+key.slice(1).toLowerCase(); for(const v of [key.toUpperCase(),key,key.toLowerCase(),cap]){ const x=Deno.env.get("ZOHO_SMTP_PASS_"+v); if(x) return x; } return ""; }
function encPart(ct:string, s:string){ return "Content-Type: "+ct+"; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n\r\n"+b64utf8(s).replace(/(.{76})/g,"$1\r\n")+"\r\n"; }
function buildMultipart(fromName:string, fromEmail:string, to:string, subject:string, text:string, html:string){
  const bnd="b_"+crypto.randomUUID().replace(/-/g,"");
  const headers=["From: "+encWord(fromName)+" <"+fromEmail+">","To: "+to,"Subject: "+encWord(subject),"MIME-Version: 1.0",'Content-Type: multipart/alternative; boundary="'+bnd+'"',"Date: "+new Date().toUTCString(),"Message-ID: <"+crypto.randomUUID()+"@25hrs.net>"].join("\r\n");
  return headers+"\r\n\r\n--"+bnd+"\r\n"+encPart("text/plain",text)+"--"+bnd+"\r\n"+encPart("text/html",html)+"--"+bnd+"--\r\n.\r\n";
}
async function smtpSend(fromName:string, fromEmail:string, pass:string, to:string, subject:string, text:string, html:string){
  const enc=new TextEncoder(), dec=new TextDecoder(); let conn:Deno.TlsConn|null=null;
  try{
    conn=await Deno.connectTls({hostname:Z_HOST,port:Z_PORT}); const rbuf=new Uint8Array(8192);
    const read=async()=>{ let acc=""; for(;;){ const n=await conn!.read(rbuf); if(n===null) break; acc+=dec.decode(rbuf.subarray(0,n)); const l=acc.split(/\r?\n/).filter(x=>x.length); if(l.length&&/^\d{3} /.test(l[l.length-1])) break; } return acc; };
    const cmd=async(line:string,exp:string,lbl:string)=>{ await conn!.write(enc.encode(line+"\r\n")); const r=await read(); if(!r.trimStart().startsWith(exp)) throw new Error(lbl+": "+r.trim().slice(0,150)); };
    await read(); await cmd("EHLO 25hrs.net","250","EHLO"); await cmd("AUTH LOGIN","334","AUTH");
    await cmd(btoa(fromEmail),"334","USER"); await cmd(btoa(pass),"235","PASS");
    await cmd("MAIL FROM:<"+fromEmail+">","250","MAIL"); await cmd("RCPT TO:<"+to+">","250","RCPT"); await cmd("DATA","354","DATA");
    await conn.write(enc.encode(buildMultipart(fromName,fromEmail,to,subject,text,html))); const done=await read();
    if(!done.trimStart().startsWith("250")) throw new Error("DATA: "+done.trim().slice(0,150));
    try{ await conn.write(enc.encode("QUIT\r\n")); }catch(_e){}
    return {ok:true};
  }catch(e){ return {ok:false,error:"SMTP: "+((e as Error).message||String(e))}; }
  finally{ if(conn){ try{ conn.close(); }catch(_e){} } }
}
// ── Slack ──
async function slackDM(email:string, text:string){ if(!SLACK||!email) return "no-slack";
  const lu=await (await fetch("https://slack.com/api/users.lookupByEmail?email="+encodeURIComponent(email),{headers:{Authorization:"Bearer "+SLACK}})).json();
  if(!lu.ok) return "lookup:"+lu.error; const uid=lu.user.id;
  const o=await (await fetch("https://slack.com/api/conversations.open",{method:"POST",headers:{Authorization:"Bearer "+SLACK,"Content-Type":"application/json"},body:JSON.stringify({users:uid})})).json();
  if(!o.ok) return "open:"+o.error;
  const m=await (await fetch("https://slack.com/api/chat.postMessage",{method:"POST",headers:{Authorization:"Bearer "+SLACK,"Content-Type":"application/json"},body:JSON.stringify({channel:o.channel.id,text})})).json();
  return m.ok?"sent":"post:"+m.error;
}

Deno.serve(async (req)=>{
  if(!ANTHROPIC_KEY) return json({error:"ANTHROPIC_API_KEY fehlt"},503);
  const sp = new URL(req.url).searchParams;
  const force = sp.get("force")==="1";
  const dateP = sp.get("date")||"";
  const bh = berlinHour();
  if(bh < 7 && !force) return json({skipped:"off-hours", berlinHour:bh});
  // Kein-Wochenende-Regel: nur Mo–Fr (force/dry umgehen sie für Tests).
  if(isWeekendBerlin() && !force && sp.get("dry")!=="1") return json({skipped:"weekend"});
  const day = /^\d{4}-\d{2}-\d{2}$/.test(dateP) ? dateP : berlinDate();
  // Einmal pro Tag.
  const { data:last } = await sb.from("app_config").select("value").eq("key","jsr_clara_digest_last_v1").maybeSingle();
  if(!force && last && last.value === day) return json({skipped:"already-sent", day});

  // Kennzahlen + Claras Beobachtungen des Tages.
  const { data:stats } = await sb.rpc("clara_morning_stats", { p_date: day });
  const { data:obs } = await sb.from("agent_observations").select("title").eq("agent_key","clara").eq("day",day);
  const notes = (obs||[]).map((o:any)=>o.title).join(" ");
  const { data:cl } = await sb.from("ai_agents").select("persona,name,email,mail_from_name,disclosure,accent,avatar_url").eq("key","clara").maybeSingle();
  const persona = (cl&&cl.persona) || "Du bist Clara, digitale Kollegin im Recruiting.";

  // Die KI liefert NUR Claras Beobachtung (die Zahlen stehen als Kacheln/Balken). Ein paar kurze Sätze in ihrer Stimme.
  const system = persona + "\n\nDu schreibst NUR deine Beobachtung fürs Recruiting-Team (intern, eigene Leute) — die nackten Zahlen "+
    "stehen schon als Kacheln oben, wiederhole sie NICHT. Zwei bis drei kurze Sätze: was fällt auf, mit Kontext und Sicherheit "+
    "(exakt / Vermutung). Wenn nichts auffällt, sag das ruhig. Erwähne, dass Erfahrungsjahre fast nie vorliegen, wenn es passt. "+
    "Deutsch als Zweitsprache: kurze Sätze, kein Konjunktiv, keine Redewendungen. Keine Emotionen. Nutze nur die gegebenen Zahlen, erfinde nichts. "+
    "Wenn du das Team ansprichst, duze immer (per Du), niemals Sie.";
  const user = "KENNZAHLEN (heute): "+JSON.stringify(stats)+"\n\nWAS MIR AUFGEFALLEN IST (aus meinen Prüfungen): "+(notes||"(nichts Auffälliges)");
  const TOOL = { name:"beobachtung", description:"Claras Beobachtung.", input_schema:{ type:"object", properties:{ text:{type:"string"} }, required:["text"] } };
  let obsText="";
  try{
    const r=await fetch("https://api.anthropic.com/v1/messages",{method:"POST",headers:{"x-api-key":ANTHROPIC_KEY,"anthropic-version":"2023-06-01","content-type":"application/json"},
      body:JSON.stringify({model:MODEL,max_tokens:400,system,tools:[TOOL],tool_choice:{type:"tool",name:"beobachtung"},messages:[{role:"user",content:user}]})});
    const d=await r.json(); if(!r.ok) return json({error:(d?.error?.message)||("HTTP "+r.status)},502);
    const tu=(d.content||[]).find((c:any)=>c.type==="tool_use"); obsText=(tu&&tu.input&&tu.input.text)||"";
  }catch(e){ return json({error:"KI: "+((e as Error).message||"")},502); }
  if(!obsText) obsText="Mir ist heute nichts Besonderes aufgefallen.";

  // Kennzahlen aufbereiten (deterministisch).
  const st:any = stats||{}; const nt=st.new_today||0, np=st.new_prev||0, rep=st.repeaters||0, dub=st.dubletten_pending||0;
  const neu=Math.max(0, nt-rep); const lg=st.lang||{}; const hoch=lg.hoch||0, mit=lg.mittel||0, nied=lg.niedrig||0, unb=lg.unbekannt||0;
  const langTot=hoch+mit+nied+unb; const delta=nt-np;
  const qt=st.quality||{}; const qTop=qt.top||0, qGut=qt.gut||0, qRest=qt.rest||0;
  const arrow = delta>0 ? "▲ "+delta+" mehr als gestern" : delta<0 ? "▼ "+(-delta)+" weniger als gestern" : "gleich wie gestern";
  const acc=(cl&&cl.accent)||"#7c3aed"; const photo="https://hr.tive360.de/"+((cl&&cl.avatar_url)||"assets/agents/clara.png");
  const portal="https://hr.tive360.de";
  const dateLbl = new Date(day+"T12:00:00").toLocaleDateString("de-DE",{weekday:"long",day:"2-digit",month:"long"});
  const subject = "Recruiting heute Morgen · "+dateLbl;

  const tile=(big:number,label:string,sub:string)=>'<td width="33%" valign="top" class="ctile" style="padding:0 5px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f6f4fb;border:1px solid #ece7f8;border-radius:12px;"><tr><td style="padding:14px 8px;text-align:center;">'
    +'<div style="font-size:30px;font-weight:bold;color:#4c1d95;line-height:1;font-family:Arial,Helvetica,sans-serif;">'+big+'</div>'
    +'<div style="font-size:12px;color:#6b7280;margin-top:6px;">'+label+'</div>'
    +(sub?'<div style="font-size:11px;color:'+acc+';margin-top:4px;">'+sub+'</div>':'')+'</td></tr></table></td>';
  const bands=[["hoch",hoch,acc],["mittel",mit,"#a78bfa"],["niedrig",nied,"#c4b5fd"],["unbekannt",unb,"#e5e7eb"]].filter((b:any)=>b[1]>0);
  const barCells = langTot>0 ? bands.map((b:any)=>'<td width="'+Math.round(100*b[1]/langTot)+'%" height="24" bgcolor="'+b[2]+'"></td>').join("") : '';
  const legend = bands.map((b:any)=>'<span style="white-space:nowrap;margin-right:14px;"><span style="color:'+b[2]+';font-size:15px;">■</span> <span style="color:#374151;">'+b[0]+' '+b[1]+'</span></span>').join("");
  const html = '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
    +'<style>@media only screen and (max-width:480px){.ccard{width:100%!important;max-width:100%!important;}.ctile{display:block!important;width:100%!important;padding:0 0 8px 0!important;}}</style></head>'
    +'<body style="margin:0;padding:0;background:#f4f2f8;">'
    +'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f2f8;padding:16px 0;"><tr><td align="center">'
    +'<table role="presentation" cellpadding="0" cellspacing="0" class="ccard" style="max-width:600px;width:100%;background:#ffffff;border-radius:16px;overflow:hidden;font-family:Arial,Helvetica,sans-serif;">'
    +'<tr><td style="background:'+acc+';padding:20px 22px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="width:100%;"><tr>'
      +'<td width="60" valign="middle"><img src="'+photo+'" width="48" height="48" alt="Clara" style="border-radius:24px;display:block;border:2px solid #ffffff;"></td>'
      +'<td valign="middle" style="padding-left:12px;"><div style="font-size:19px;font-weight:bold;color:#ffffff;">Clara</div>'
      +'<div style="font-size:13px;color:#efe9fb;line-height:1.4;">Recruiting heute Morgen · '+dateLbl+'</div></td></tr></table></td></tr>'
    +'<tr><td style="padding:20px 12px 6px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="table-layout:fixed;width:100%;"><tr>'
      +tile(nt,"Bewerbungen heute",arrow)+tile(neu,"davon neu","")+tile(dub,"Dubletten offen","")
      +'</tr></table></td></tr>'
    +(langTot>0 ? '<tr><td style="padding:14px 22px 2px;"><div style="font-size:12px;color:#6b7280;font-weight:bold;text-transform:uppercase;letter-spacing:.04em;margin-bottom:8px;">Sprachniveau</div>'
      +'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="table-layout:fixed;width:100%;border-radius:8px;overflow:hidden;"><tr>'+barCells+'</tr></table>'
      +'<div style="margin-top:9px;font-size:12.5px;">'+legend+'</div></td></tr>' : '')
    +'<tr><td style="padding:14px 22px 2px;"><div style="font-size:12px;color:#6b7280;font-weight:bold;text-transform:uppercase;letter-spacing:.04em;margin-bottom:9px;">Qualität der neuen</div>'
      +'<table role="presentation" cellpadding="0" cellspacing="0"><tr>'
      +'<td style="padding-right:8px;"><span style="display:inline-block;background:#d97706;color:#ffffff;font-weight:bold;font-size:14px;padding:7px 13px;border-radius:20px;">&#9733; TOP '+qTop+'</span></td>'
      +'<td style="padding-right:8px;"><span style="display:inline-block;background:#fde68a;color:#8a5a00;font-weight:bold;font-size:14px;padding:7px 13px;border-radius:20px;">&#9733; GUT '+qGut+'</span></td>'
      +'<td><span style="display:inline-block;background:#eef0f4;color:#6b7280;font-weight:bold;font-size:14px;padding:7px 13px;border-radius:20px;">Rest '+qRest+'</span></td>'
      +'</tr></table></td></tr>'
    +'<tr><td style="padding:16px 22px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f6f4fb;border-left:4px solid '+acc+';border-radius:10px;"><tr>'
      +'<td width="58" valign="top" style="padding:14px 0 14px 14px;"><img src="'+photo+'" width="40" height="40" alt="Clara" style="border-radius:20px;display:block;"></td>'
      +'<td style="padding:14px;font-size:15px;line-height:1.55;color:#1f2937;">'+obsText.replace(/</g,"&lt;").replace(/\n/g,"<br>")+'</td></tr></table></td></tr>'
    +'<tr><td align="center" style="padding:6px 22px 24px;"><a href="'+portal+'" style="display:inline-block;background:'+acc+';color:#ffffff;text-decoration:none;font-size:16px;font-weight:bold;padding:14px 30px;border-radius:10px;">Zum Recruiting →</a></td></tr>'
    +'<tr><td style="padding:0 22px 22px;font-size:11px;color:#9ca3af;line-height:1.5;">Clara, digitale Kollegin im Recruiting. '+((cl&&cl.disclosure)||"")+'</td></tr>'
    +'</table></td></tr></table></body></html>';

  const textFb = "Recruiting heute Morgen · "+dateLbl+"\n\n"
    +"Bewerbungen heute: "+nt+" (gestern "+np+", "+arrow.replace(/▲ |▼ /,"")+")\n"
    +"Davon neu: "+neu+"\nDubletten offen: "+dub+"\n\n"
    +"Sprachniveau: hoch "+hoch+", mittel "+mit+", niedrig "+nied+", unbekannt "+unb+"\n"
    +"Qualität: TOP "+qTop+", GUT "+qGut+", Rest "+qRest+"\n\n"
    +obsText+"\n\nZum Recruiting: "+portal+"\n\n— Clara, digitale Kollegin im Recruiting";
  const slackText = "*Recruiting heute Morgen · "+dateLbl+"*\n"
    +"📥 Bewerbungen heute: *"+nt+"*  ("+arrow+")\n🆕 Davon neu: *"+neu+"*    👥 Dubletten offen: *"+dub+"*\n"
    +"Sprache: hoch "+hoch+" · mittel "+mit+" · niedrig "+nied+" · unbekannt "+unb+"\n"
    +"Qualität: ⭐ TOP "+qTop+" · ★ GUT "+qGut+" · Rest "+qRest+"\n\n"+obsText+"\n_— Clara_";

  if(sp.get("dry")==="1") return json({ dry:true, day, obsText, textFb, html });

  // Empfänger (leicht erweiterbar über die Config jsr_clara_digest_recipients_v1).
  const { data:rc } = await sb.from("app_config").select("value").eq("key","jsr_clara_digest_recipients_v1").maybeSingle();
  const recips = ((rc&&rc.value)||[]).filter((x:any)=>x&&x.email&&x.active!==false);
  const fromName = (cl&&cl.mail_from_name) || "Clara · 25HRS Recruiting";
  const fromEmail = (cl&&cl.email) || "clara@25hrs.net";
  const pass = smtpPass("clara");
  const results:any[]=[];
  for(const r of recips){
    const mail = pass ? await smtpSend(fromName, fromEmail, pass, r.email, subject, textFb, html) : {ok:false,error:"ZOHO_SMTP_PASS_CLARA fehlt"};
    const slack = await slackDM(r.slack_email||r.email, slackText);
    results.push({ to:r.email, mail: mail.ok?"sent":("fail:"+mail.error), slack });
  }
  try{ await sb.from("app_config").upsert({key:"jsr_clara_digest_last_v1", value:day}); }catch(_e){}
  return json({ ok:true, day, recipients:recips.length, results });
});
