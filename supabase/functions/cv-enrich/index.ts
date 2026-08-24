// Bewerber-Anreicherung per Token (öffentlich, kein Login). load = Profil zum Vorbefüllen; submit = schreibt die
// Whitelist-Felder in die BESTEHENDE cvs-Zeile (kein neuer Eintrag) + optionale Hörprobe in den privaten Bucket
// cv-audio (service role) mit Langzeit-Signed-URL in cvs.audios. Token einmalig nutzbar.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPA_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const sb = createClient(SUPA_URL, SERVICE);

const cors = { 'Access-Control-Allow-Origin':'*', 'Access-Control-Allow-Headers':'content-type,apikey,authorization', 'Access-Control-Allow-Methods':'POST,OPTIONS' };
const json = (o:any, s=200)=>new Response(JSON.stringify(o), {status:s, headers:{...cors,'Content-Type':'application/json'}});

// Direkt in cvs-Spalten schreibbare Anreicherungsfelder.
const FIELDS = ['email','phone','city','birthday','education','education_level','experience_years','work_history',
  'language_level','writing_level','languages_str','available_from','homeoffice_pref'];

Deno.serve(async (req)=>{
  if(req.method==='OPTIONS') return new Response('ok',{headers:cors});
  let body:any={}; try{ body=await req.json(); }catch(_e){}
  const action=body.action, token=String(body.token||'');
  if(!token) return json({error:'Kein Token'},400);

  const {data:inv}=await sb.from('cv_enrich_invites').select('*').eq('token',token).maybeSingle();
  if(!inv) return json({error:'Link ungültig'},404);
  if(inv.expires_at && new Date(inv.expires_at) < new Date()) return json({error:'Link abgelaufen'},410);
  const {data:cv}=await sb.from('cvs').select('*').eq('id',inv.cv_id).maybeSingle();
  if(!cv) return json({error:'Profil nicht gefunden'},404);

  if(action==='load'){
    const ex=cv.extra||{};
    return json({ first_name:cv.first_name, used:!!inv.used_at, cv:{
      email:cv.email, phone:cv.phone, city:cv.city, birthday:cv.birthday,
      education:cv.education, education_level:cv.education_level,
      experience_years:cv.experience_years, work_history:cv.work_history,
      language_level:cv.language_level, writing_level:cv.writing_level, languages_str:cv.languages_str,
      available_from:cv.available_from, homeoffice_pref:cv.homeoffice_pref,
      work_hours:ex.work_hours, weekend:ex.weekend, sunday:ex.sunday, writing_sample:ex.writing_sample,
      has_audio: Array.isArray(cv.audios) && cv.audios.length>0
    }});
  }

  if(action==='submit'){
    if(inv.used_at) return json({error:'Dieser Link wurde bereits genutzt. Bitte melde dich bei uns, falls du etwas ändern möchtest.'},409);
    const f=body.fields||{};
    const upd:any={ updated_at:new Date().toISOString() };
    for(const k of FIELDS){ if(f[k]!==undefined){ let v=f[k];
      if(k==='experience_years') v=(v===''||v==null)?null:(parseInt(String(v))||null);
      if((k==='birthday'||k==='available_from') && (v===''||v==null)) v=null;
      upd[k]=v; } }
    // Ohne eigene Spalte -> in extra mergen.
    const ex:any={ ...(cv.extra||{}) };
    if(f.work_hours!==undefined) ex.work_hours=f.work_hours;
    if(f.weekend!==undefined)    ex.weekend=!!f.weekend;
    if(f.sunday!==undefined)     ex.sunday=!!f.sunday;
    if(f.writing_sample!==undefined) ex.writing_sample=String(f.writing_sample||'');
    ex.enriched_at=new Date().toISOString();
    upd.extra=ex;

    // Hörprobe (base64) -> privater Bucket + Langzeit-Signed-URL in audios[]. Fehler blockiert die Anreicherung nicht.
    if(body.audio && body.audio.data){
      try{
        const b64=String(body.audio.data).split(',').pop() || '';
        const bin=Uint8Array.from(atob(b64), c=>c.charCodeAt(0));
        const mime=String(body.audio.mime||'audio/webm');
        const ext=mime.includes('mp4')?'m4a':mime.includes('mpeg')?'mp3':mime.includes('ogg')?'ogg':'webm';
        const path=`${inv.cv_id}/selbstaufnahme_${Date.now()}.${ext}`;
        const up=await sb.storage.from('cv-audio').upload(path, bin, {contentType:mime, upsert:true});
        if(!up.error){
          const sg=await sb.storage.from('cv-audio').createSignedUrl(path, 60*60*24*365);
          const url=sg.data?.signedUrl;
          if(url){ const audios=Array.isArray(cv.audios)?cv.audios.slice():[];
            audios.push({ id:'au'+Date.now(), label:'Selbstaufnahme (Bewerber)', name:'Selbstaufnahme', url, date:new Date().toISOString().slice(0,10) });
            upd.audios=audios; }
        }
      }catch(_e){ /* Audio optional */ }
    }

    const {error}=await sb.from('cvs').update(upd).eq('id',inv.cv_id);
    if(error) return json({error:'Speichern fehlgeschlagen'},500);
    await sb.from('cv_enrich_invites').update({used_at:new Date().toISOString()}).eq('token',token);
    return json({ok:true});
  }

  return json({error:'Unbekannte Aktion'},400);
});
