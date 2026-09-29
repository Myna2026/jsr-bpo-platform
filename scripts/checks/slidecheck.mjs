#!/usr/bin/env node
/* Folien-Überlaufprüfung.
 *
 * Warum: Die Folien haben ein festes Format (16:9) und `overflow:hidden`. Läuft der Inhalt über,
 * wird er STILL abgeschnitten — zweimal ist uns genau das passiert (CSAT, Mail). Seit dem 29.09.
 * misst der Renderer selbst, wie viele Zeilen passen; diese Prüfung hält fest, dass es auch so
 * bleibt. Sie rendert den Foliensatz mit einem erfundenen, absichtlich vollen Datensatz und meldet
 * jede Folie, deren Inhalt über den Rand ragt.
 *
 * Die grosse Hintergrundziffer ragt absichtlich hinaus (pointer-events:none) und zaehlt nicht mit.
 * Exit 0 = alles drin · 1 = Überlauf gefunden · 2 = konnte nicht laufen (kein Block).
 */
import { chromium } from './smoketest/node_modules/playwright/index.mjs';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..', '..');
const LIB  = join(ROOT, 'frontend', 'shared', 'presentation-slides.js');

// Voller Datensatz: mehr Zeilen, als je auf eine Folie passen — so schlägt die Prüfung an,
// wenn die Messung ausfällt oder jemand wieder eine feste Zeilenzahl einbaut.
const N = 22;
const namen = Array.from({length:N}, (_,i)=>'Testperson mit langem Namen '+(i+1));
const weeks = [35,36,37,38,39].map(k=>({kw:k, key:'2026-'+k}));
const team = () => ({
  fte:'14', members:[],
  stunden: weeks.map(w=>({kw:String(w.kw), plan:'420', rueck:'400', geliefert:'380', erkl:'Ein längerer Erklärtext zur Differenz'})),
  calls:{ vorwoche:Object.fromEntries(namen.map((n,i)=>[ 'id'+i, {answered:String(120+i), handled:String(130+i), outbound:'4', avg_talk:'10:15', avg_acw:'3:53', avg_handle:'14:31', avg_hold:'1:24'} ])),
          monat:Object.fromEntries(namen.map((n,i)=>[ 'id'+i, {answered:String(220+i), handled:'240', outbound:'5', avg_talk:'10:32', avg_acw:'4:06', avg_handle:'14:44', avg_hold:'1:25'} ])) },
  csat:{ weeks, rows:namen.map((n,i)=>({id:'id'+i, name:n, cells:Object.fromEntries(weeks.map(w=>[w.key,{v:3.8,n:40}])), avg:3.8})) },
  callaht:{ weeks, agents:namen.map((n,i)=>({id:'id'+i, name:n, byWeek:Object.fromEntries(weeks.map(w=>[w.key,{aht:620}])), tot:{aht:620}, newbie:i%3===0})) },
  mail:{ vorwoche:{kw:39, rows:namen.map((n,i)=>({id:'id'+i,name:n,std:20.5,mails:180,meh:8.8,newbie:i%4===0})), total:{std:300,mails:2600,meh:8.7}},
         monat:{label:'September 2026', weekKws:[36,37,38,39], rows:namen.map((n,i)=>({id:'id'+i,name:n,std:40.5,mails:360,meh:8.9,newbie:i%4===0})), total:{std:600,mails:5200,meh:8.7}} },
  mailtrend:{ weeks, agents:namen.map((n,i)=>({id:'id'+i, name:n, byWeek:Object.fromEntries(weeks.map(w=>[w.key,{meh:9.1}])), tot:{meh:9.1}, newbie:i%4===0})) },
  fteList:{ total:14, rows:namen.map((n,i)=>({id:'id'+i,name:n,fte:0.9})) },
  fehlzeiten:{ weeks:weeks.map(w=>({kw:w.kw,key:w.key})), krank:Object.fromEntries(weeks.map(w=>[w.key,3])), comment:{} },
  cr:{ weeks, reportKey:'2026-39', team:Object.fromEntries(weeks.map(w=>[w.key,{open:40,osl:150,calls:300,cr:52.1,crSrc:'computed'}])),
       agents:namen.map((n,i)=>({id:'id'+i,name:n,byWeek:Object.fromEntries(weeks.map(w=>[w.key,{open:8,osl:20,calls:60,cr:46.6}])),tot:{open:40,osl:100,calls:300,cr:46.6}})),
       mtd:{label:'September 2026', weekKws:[36,37,38,39], agents:namen.map((n,i)=>({id:'id'+i,name:n,open:8,osl:20,calls:60,cr:46.6})), team:{open:40,osl:100,calls:300,cr:46.6}} },
  massnahmen:'Eine Maßnahme je Zeile\n'.repeat(12),
});

const ctx = {
  deck:{ titel:{untertitel:'Prüfung',datum:'29.09.2026',ansprech:'—'}, teams:{sales:team(), support:team()} },
  accent:'#0A4A8F', font:"'Inter',sans-serif", projName:'Prüfprojekt', period:{no:39,year:2026},
  skills:[{key:'support',label:'Support'},{key:'sales',label:'Sales'}], dummy:false,
  callScores:{ support:{best:[],worst:[],count:0}, sales:{best:[],worst:[],count:0} },
  callReviews:false, measuresFor:()=>[], membersOf:()=>namen.map((n,i)=>({id:'id'+i,name:n})), hidden:[],
};

const page_html = `<!doctype html><meta charset="utf-8"><div id="root"></div>
<script src="https://unpkg.com/react@18/umd/react.production.min.js"></script>
<script src="https://unpkg.com/react-dom@18/umd/react-dom.production.min.js"></script>
<script>${readFileSync(LIB,'utf8')}</script>
<script>
  window.__CTX__ = ${JSON.stringify(ctx)};
  window.__CTX__.measuresFor=function(){return [];};
  window.__CTX__.membersOf=function(){return window.__CTX__._members||[];};
  window.__CTX__._members=${JSON.stringify(namen.map((n,i)=>({id:'id'+i,name:n})))};
  var root=ReactDOM.createRoot(document.getElementById('root'));
  function draw(){ root.render(React.createElement('div',{style:{width:1200}},
    window.PRES.deckSlides(window.__CTX__).map(function(el,i){ return React.createElement(React.Fragment,{key:'k'+window.__N__+'_'+i},el); }))); }
  window.__N__=0;
  if(window.PRES.onFit) window.PRES.onFit(function(){ if(window.__N__++>6) return; draw(); });
  draw();
</script>`;

const b = await chromium.launch({ channel:'chrome', headless:true }).catch(()=>null);
if(!b){ console.log('slidecheck: kein Chrome gefunden -> uebersprungen.'); process.exit(2); }
const p = await (await b.newContext({viewport:{width:1400,height:900}})).newPage();
const errs=[]; p.on('pageerror',e=>errs.push(String(e)));
await p.setContent(page_html, {waitUntil:'networkidle'});
await p.waitForTimeout(1500);
const res = await p.evaluate(()=>{
  const slides = Array.from(document.querySelectorAll('.pres-slide'));
  return slides.map((sl,i)=>{
    const r = sl.getBoundingClientRect(); let over=0, who='';
    sl.querySelectorAll('*').forEach(c=>{
      if(getComputedStyle(c).pointerEvents==='none') return;      // Hintergrundziffer
      const cr=c.getBoundingClientRect(); if(cr.height<3) return;
      const d=cr.bottom-r.bottom; if(d>over){ over=d; who=(c.textContent||'').trim().slice(0,44); }
    });
    return { i, over:Math.round(over), who, titel:(sl.innerText||'').split('\n').slice(0,3).join(' · ').slice(0,56) };
  });
});
await b.close();
if(errs.length){ console.log('slidecheck: Fehler beim Rendern: '+errs[0].slice(0,140)); process.exit(1); }
const bad = res.filter(r=>r.over>2);
console.log('slidecheck: '+res.length+' Folien mit vollem Datensatz gerendert, '+bad.length+' mit Ueberlauf.');
bad.forEach(r=>console.log('   Folie '+r.i+': '+r.over+' px ueber den Rand — "'+r.who+'"  ['+r.titel+']'));
console.log(bad.length? 'RESULT: FAIL' : 'RESULT: PASS');
process.exit(bad.length?1:0);
