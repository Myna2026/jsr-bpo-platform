/* Geteilte Folien-Render-Quelle für Kundenpräsentationen — EINE Umsetzung.
 * Genutzt von hr.html (In-App-Vorschau/Darstellung) UND praesentation.html (öffentliche Seite, PDF).
 * Plain JS (React.createElement), damit es via <script src> in beiden Seiten läuft (kein Babel nötig).
 * Rechenwerte werden gerechnet (Nenner-Guards), Namen kommen aus der Deck-Daten (im Snapshot eingefroren).
 *
 * ctx = {
 *   deck, accent, font, projName, period:{no,year},
 *   skills:[{key,label}],
 *   membersOf(teamKey) -> [{id,name}],   // aus System (App) bzw. Snapshot (öffentlich)
 *   dummy, ourLogo, customerLogo
 * }
 * window.PRES.deckSlides(ctx) -> [ReactElement,...]
 */
(function(){
  var R = window.React; if(!R) return;
  function h(){ return R.createElement.apply(R, arguments); }

  function numOr(v,d){ var n=Number(String(v).replace(',','.')); return isNaN(n)?(d==null?0:d):n; }
  function fmtNum(v,dec){ dec=dec||0; if(v===''||v==null||isNaN(Number(v))) return '—'; return Number(v).toLocaleString('de-DE',{minimumFractionDigits:dec,maximumFractionDigits:dec}); }
  function pctDiff(part,base){ var b=numOr(base,NaN); if(!b||isNaN(b)) return null; return (numOr(part,NaN)-b)/b*100; }
  function decToMmss(dec){ var v=parseFloat(dec); if(isNaN(v)) return String(dec); var neg=v<0,a=Math.abs(v),m=Math.floor(a),s=Math.round((a-m)*60); if(s===60){m+=1;s=0;} return (neg?'-':'')+m+':'+String(s).padStart(2,'0'); }
  function mmssToDec(str){ if(str==null) return NaN; var s=String(str).trim(); if(s==='') return NaN; if(s.indexOf(':')<0){ var n=parseFloat(s.replace(',','.')); return isNaN(n)?NaN:n; } var p=s.split(':'),mm=parseInt(p[0],10),ss=parseInt(p[1],10); if(isNaN(mm))mm=0; if(isNaN(ss))ss=0; return mm+ss/60; }
  function wavgTime(rows,tk,wk){ var ts=0,ws=0; (rows||[]).forEach(function(r){ var t=mmssToDec(r&&r[tk]); var w=numOr(r&&r[wk],0); if(!isNaN(t)&&w>0){ts+=t*w;ws+=w;} }); return ws?decToMmss(ts/ws):'—'; }
  function sumCol(rows,key){ var s=0; (rows||[]).forEach(function(r){ s+=numOr(r&&r[key],0); }); return s; }
  // Gespreizte Skala: bei eng beieinanderliegenden Werten NICHT bei 0 beginnen, sonst sehen alle
  // Balken gleich lang aus. Basis = min - span*pad (≥0). Exakte Werte stehen zusätzlich am Balken.
  function zoomDomain(vals,pad){ pad=(pad==null)?0.3:pad;
    var xs=(vals||[]).map(function(v){ return numOr(v,NaN); }).filter(function(v){ return !isNaN(v); });
    if(!xs.length) return {lo:0,hi:1,zoomed:false};
    var mn=Math.min.apply(null,xs), mx=Math.max.apply(null,xs), span=mx-mn;
    if(span<=0) return {lo:0,hi:mx||1,zoomed:false};
    var lo=Math.max(0, mn-span*pad);
    return {lo:lo, hi:mx, zoomed: lo>0};   // „gespreizt" nur behaupten, wenn der Boden wirklich > 0 ist
  }
  function frac(v,dom){ var d=dom.hi-dom.lo; if(d<=0) return 1; return Math.max(0,Math.min(1,(numOr(v,0)-dom.lo)/d)); }

  var CALL_COLS = {
    sales:   [{k:'no_answer',l:'No Answer',t:'count'},{k:'answered',l:'Answered',t:'count'},{k:'outbound',l:'Outbound',t:'count'},{k:'avg_talk',l:'Avg Talk',t:'time'},{k:'avg_acw',l:'Avg ACW',t:'time'},{k:'avg_handle',l:'Avg Handle',t:'time'},{k:'avg_hold',l:'Avg Hold',t:'time'}],
    support: [{k:'answered',l:'Answered',t:'count'},{k:'outbound',l:'Outbound',t:'count'},{k:'tel_hours',l:'Std. Telefonie',t:'num'},{k:'aht',l:'AHT',t:'time'},{k:'att',l:'ATT',t:'time'},{k:'hold',l:'HOLD',t:'time'},{k:'acw',l:'ACW',t:'time'}]
  };
  function callCols(t){ return CALL_COLS[t]||CALL_COLS.sales; }

  // ── Farb-/Kontrast-Ableitung (eine Projektfarbe → ganze Palette). Chip-Logik: Schrift kippt nach Helligkeit. ──
  var MONO="'JetBrains Mono','SF Mono',ui-monospace,Menlo,Consolas,monospace";
  function hx(h){ h=String(h||'').trim().replace('#',''); if(h.length===3) h=h.split('').map(function(c){return c+c;}).join(''); var n=parseInt(h||'2563eb',16); if(isNaN(n)) n=0x2563eb; return {r:(n>>16)&255,g:(n>>8)&255,b:n&255}; }
  function toHex(o){ function c(v){ v=Math.max(0,Math.min(255,Math.round(v))); return ('0'+v.toString(16)).slice(-2); } return '#'+c(o.r)+c(o.g)+c(o.b); }
  function lum(o){ function ch(v){ v/=255; return v<=0.03928? v/12.92 : Math.pow((v+0.055)/1.055,2.4); } return 0.2126*ch(o.r)+0.7152*ch(o.g)+0.0722*ch(o.b); }
  function contrast(a,b){ var L1=lum(a),L2=lum(b),hi=Math.max(L1,L2),lo=Math.min(L1,L2); return (hi+0.05)/(lo+0.05); }
  function mix(a,b,t){ return {r:a.r+(b.r-a.r)*t, g:a.g+(b.g-a.g)*t, b:a.b+(b.b-a.b)*t}; }
  var WHITE={r:255,g:255,b:255}, INKO={r:11,g:29,b:35};
  function textOn(o){ return contrast(o,WHITE)>=contrast(o,INKO)? '#ffffff' : '#0B1D23'; }   // helle vs. dunkle Schrift
  function rgba(hex,a){ var o=hx(hex); return 'rgba('+o.r+','+o.g+','+o.b+','+a+')'; }
  function darkenTo(A,target){ var o=A,g=0; while(contrast(o,WHITE)<target && g<60){ o=mix(o,INKO,0.08); g++; } return o; }
  function pal(accentHex){
    var A=hx(accentHex||'#2563eb');
    return {
      accent:accentHex||'#2563eb',
      fond:accentHex||'#2563eb',                        // Fond = Kundenfarbe, unverändert
      fondHi:toHex(mix(A,WHITE,0.12)), fondLo:toHex(mix(A,INKO,0.20)),  // Tiefe (Vignette), Ton bleibt
      fondText:textOn(A),                               // Schrift auf dem Fond (Chip-Logik)
      onLight:toHex(darkenTo(A,3.0)),                   // Markenton lesbar auf Weiß (Kanten/Balken/KPI)
      onLightTxt:toHex(darkenTo(A,4.6)),                // dito für kleine Schrift
      ink:'#0B1D23', muted:'#647880', panel:'#ffffff'
    };
  }
  function logoLockup(src, fallback, P){
    var inner = src ? h('img',{src:src,alt:'',style:{height:'3.4cqw',maxWidth:'20cqw',objectFit:'contain',display:'block'}})
                    : h('span',{style:{fontWeight:800,letterSpacing:'-.02em',fontSize:'2.2cqw',color:P.ink}}, fallback);
    return h('div',{style:{background:'#fff',borderRadius:'1.2cqw',padding:'1.3cqw 1.8cqw',boxShadow:'0 1cqw 2.4cqw -1cqw rgba(3,20,26,.4)',display:'inline-flex',alignItems:'center'}}, inner);
  }
  function panel(P, children, st){ return h('div',{style:Object.assign({background:P.panel,borderRadius:'2cqw',padding:'3.2cqw 3.6cqw',boxShadow:'0 2.4cqw 5cqw -1.6cqw rgba(3,20,26,.45)',borderLeft:'.55cqw solid '+P.onLight,flex:1,minHeight:0,display:'flex',flexDirection:'column'}, st||{})}, children); }
  function fondHead(P, eyebrow, title, right){ return h('div',{style:{display:'flex',justifyContent:'space-between',alignItems:'flex-end',gap:'2cqw',marginBottom:'2.4cqw'}},[
    h('div',{key:'l'},[
      h('div',{key:'e',style:{fontFamily:MONO,fontSize:'1.45cqw',letterSpacing:'.2em',textTransform:'uppercase',color:rgba(P.fondText,.72),fontWeight:600}},eyebrow),
      h('div',{key:'t',style:{fontSize:'3.7cqw',fontWeight:800,letterSpacing:'-.025em',color:P.fondText,lineHeight:1.02,marginTop:'.5cqw'}},title)
    ]),
    right?h('div',{key:'r',style:{fontFamily:MONO,fontSize:'1.5cqw',fontWeight:600,color:rgba(P.fondText,.8),textAlign:'right'}},right):null
  ]); }

  function emptyPanel(ctx, head, P, msg){ return Slide(ctx, [head, panel(P, h('div',{style:{flex:1,display:'flex',alignItems:'center',justifyContent:'center',textAlign:'center',color:P.muted,fontSize:'1.6cqw'}}, msg))]); }

  // Slide = Fond in Kundenfarbe (mit Tiefe) + Logo-Rahmen (weiße Lockups) + geisterhafte KW-Zahl + Inhalt.
  function Slide(ctx, children, opts){ opts=opts||{}; var P=pal(ctx.accent);
    var kw=ctx.period&&ctx.period.no; var ghostTxt=opts.ghost!=null?opts.ghost:(kw!=null?String(kw):'');
    var kids=[
      ghostTxt!==''?h('div',{key:'ghost',style:{position:'absolute',right:'-2cqw',bottom:'-9cqw',fontFamily:MONO,fontWeight:800,fontSize:'52cqw',lineHeight:1,color:rgba(P.fondText,.06),letterSpacing:'-.05em',pointerEvents:'none'}},ghostTxt):null,
      h('div',{key:'rail',style:{position:'absolute',top:'4cqw',left:'5cqw',right:'5cqw',display:'flex',justifyContent:'space-between',alignItems:'flex-start',gap:'3cqw',zIndex:2}},[
        logoLockup(ctx.ourLogo,'TIVE 360°',P), logoLockup(ctx.customerLogo,ctx.projName||'Kunde',P)
      ]),
      h('div',{key:'body',style:{position:'absolute',inset:0,padding:'5cqw',paddingTop:'13.5cqw',display:'flex',flexDirection:'column',zIndex:1}},children),
      ctx.dummy?h('div',{key:'wm',style:{position:'absolute',inset:0,display:'flex',alignItems:'center',justifyContent:'center',pointerEvents:'none',zIndex:3}},h('span',{style:{transform:'rotate(-24deg)',fontSize:'12cqw',fontWeight:900,color:'rgba(220,38,38,.14)',letterSpacing:'.1em'}},'BEISPIEL')):null,
      // Overlay auf Slide-ROOT-Ebene: deckt die ganze Fläche inkl. Logo-Leiste ab (zIndex über allem),
      // von den runden Slide-Ecken sauber geclippt. Kein durchscheinender Fond, keine Logos darüber.
      opts.overlay||null
    ];
    return h('div',{className:'pres-slide',style:{position:'relative',aspectRatio:'16 / 9',containerType:'inline-size',background:'radial-gradient(125% 135% at 14% -10%, '+P.fondHi+' 0%, '+P.fond+' 46%, '+P.fondLo+' 100%)',borderRadius:14,boxShadow:'0 8px 30px rgba(15,23,42,.14)',overflow:'hidden',marginBottom:20,fontFamily:ctx.font||'inherit'}}, kids);
  }

  function Title(ctx){ var P=pal(ctx.accent); var t=(ctx.deck&&ctx.deck.titel)||{};
    var win=h('div',{style:{background:'#fff',borderRadius:'2.4cqw',padding:'4cqw 4.4cqw 4.2cqw',maxWidth:'60cqw',boxShadow:'0 3cqw 6cqw -1.6cqw rgba(3,20,26,.5)',borderLeft:'.6cqw solid '+P.onLight}},[
      h('div',{key:'e',style:{fontFamily:MONO,fontSize:'1.5cqw',letterSpacing:'.22em',textTransform:'uppercase',color:P.onLightTxt,fontWeight:600}},'Performance-Bericht'),
      h('div',{key:'t',style:{fontSize:'5.4cqw',fontWeight:800,letterSpacing:'-.03em',lineHeight:1.02,color:P.ink,marginTop:'1.2cqw'}},'Weekly Performance Review'),
      h('div',{key:'m',style:{display:'flex',gap:'2.6cqw',alignItems:'baseline',flexWrap:'wrap',marginTop:'2.4cqw',paddingTop:'2cqw',borderTop:'1px solid #e6edef'}},[
        h('span',{key:'p',style:{fontSize:'2.5cqw',fontWeight:700,color:P.onLightTxt,letterSpacing:'-.01em'}}, ctx.projName+(t.untertitel?(' · '+t.untertitel):'')),
        h('span',{key:'per',style:{fontFamily:MONO,fontSize:'1.6cqw',color:P.muted}}, 'KW '+ctx.period.no+' / '+ctx.period.year+(t.datum?(' · '+t.datum):''))
      ])
    ]);
    return Slide(ctx, h('div',{style:{flex:1,display:'flex',alignItems:'center'}}, win));
  }

  function Stunden(ctx, tk){ var P=pal(ctx.accent); var td=(ctx.deck.teams||{})[tk]||{}; var lbl=skillLabel(ctx,tk);
    var rows=(td.stunden||[]).filter(function(r){ return r.kw!==''||r.plan!==''||r.geliefert!==''; });
    if(!rows.length) return emptyPanel(ctx, fondHead(P, lbl, 'Gelieferte Stunden', 'Plan · Rückmeldung · Geliefert'), P, 'Keine Stundendaten in diesem Zeitraum.');
    var vals=[]; rows.forEach(function(r){ ['plan','rueck','geliefert'].forEach(function(k){ if(r[k]!==''&&r[k]!=null) vals.push(numOr(r[k],0)); }); });
    var dom=zoomDomain(vals);
    var bar3=[{k:'plan',c:'#d5dde3',tc:'#94a3b8',l:'Plan'},{k:'rueck',c:rgba(P.onLight,.42),tc:P.onLight,l:'Rückmeldung'},{k:'geliefert',c:P.onLight,tc:P.onLightTxt,l:'Geliefert'}];
    var notes=rows.filter(function(r){ return r.erkl; });
    return Slide(ctx, [
      fondHead(P, lbl, 'Gelieferte Stunden', 'Plan · Rückmeldung · Geliefert'),
      panel(P, [
        // Diagramm = Hauptinhalt: Wochenspalten füllen die volle Breite (flex:1), Balken füllen die Höhe,
        // Werte stehen an jedem Balken, KW + %-Delta konsistent unter JEDER Woche.
        h('div',{key:'chart',style:{flex:1,minHeight:0,display:'flex',alignItems:'stretch',gap:'2.4cqw'}},
          rows.map(function(r,i){ var pc=pctDiff(r.geliefert,r.rueck);
            return h('div',{key:i,style:{flex:1,minWidth:0,display:'flex',flexDirection:'column'}},[
              h('div',{key:'bars',style:{flex:1,minHeight:0,display:'flex',alignItems:'flex-end',justifyContent:'center',gap:'0.9cqw'}},
                bar3.map(function(b){ var has=r[b.k]!==''&&r[b.k]!=null; var v=numOr(r[b.k],0); var pct=has?Math.max(4,frac(v,dom)*88):0;
                  return h('div',{key:b.k,style:{flex:1,minWidth:0,height:'100%',display:'flex',flexDirection:'column',justifyContent:'flex-end',alignItems:'center'}},[
                    h('div',{key:'v',style:{fontFamily:MONO,fontSize:'1.15cqw',fontWeight:700,color:b.tc,marginBottom:'.5cqw',whiteSpace:'nowrap'}}, has?fmtNum(v):''),
                    h('div',{key:'b',style:{width:'100%',height:pct+'%',background:b.c,borderRadius:'.5cqw .5cqw 0 0'}})
                  ]);
                })
              ),
              h('div',{key:'lab',style:{textAlign:'center',marginTop:'1cqw',paddingTop:'.9cqw',borderTop:'1px solid #eef2f4'}},[
                h('div',{key:'kw',style:{fontFamily:MONO,fontSize:'1.3cqw',fontWeight:700,color:P.ink}},'KW '+(r.kw||'—')),
                h('div',{key:'pc',style:{fontSize:'1.15cqw',fontWeight:700,marginTop:'.3cqw',color:pc==null?P.muted:pc<0?'#dc2626':'#059669'}}, pc==null?'—':((pc>0?'+':'')+fmtNum(pc,1)+' %'))
              ])
            ]);
          })
        ),
        h('div',{key:'foot',style:{display:'flex',justifyContent:'space-between',alignItems:'flex-start',gap:'3cqw',marginTop:'2cqw'}},[
          h('div',{key:'leg',style:{display:'flex',gap:'2cqw',fontSize:'1.2cqw',color:P.muted,flexShrink:0,alignItems:'center'}}, bar3.map(function(b){ return h('span',{key:b.k,style:{display:'inline-flex',alignItems:'center',gap:'.5cqw'}},[h('span',{style:{width:'1.1cqw',height:'1.1cqw',borderRadius:2,background:b.c}}),b.l]); }).concat(dom.zoomed?[h('span',{key:'scale',style:{fontFamily:MONO,fontSize:'1cqw',opacity:.8}},'Skala ab '+fmtNum(dom.lo))]:[])),
          notes.length?h('div',{key:'notes',style:{fontSize:'1.1cqw',color:P.muted,textAlign:'right',lineHeight:1.5,minWidth:0}}, [
            h('span',{key:'h',style:{fontFamily:MONO,fontWeight:700,letterSpacing:'.08em',textTransform:'uppercase',fontSize:'1cqw',marginRight:'.6cqw'}},'Erläuterungen:'),
            notes.map(function(r,i){ return h('span',{key:i},[ h('b',{style:{color:P.ink}},'KW '+(r.kw||'—')+' '), r.erkl, i<notes.length-1?'   ·   ':'' ]); })
          ]):null
        ])
      ])
    ]);
  }

  // FUNKTIONS-BÄNDER (Variante B): drei beschriftete Ebenen untereinander — Projektleitung / Overhead / Agenten.
  // KEINE Linien, KEINE Skalierung. Personen als vollfarbige Kacheln (Funktionsfarbe pp.color + Kontrast pp.txt,
  // in hr.html gebacken). Agenten-Raster adaptiv (Spalten nach Anzahl). Passt für 7 (Sales) wie 17 (Support).
  function FteBandsBody(bands, P){
    function tile(pp, big){
      return h('div',{key:pp.id,style:{background:pp.color,color:pp.txt,borderRadius:'.9cqw',padding:big?'.85cqw 1.05cqw':'.62cqw .8cqw',display:'flex',flexDirection:'column',gap:'.2cqw',minWidth:0,boxShadow:'0 .4cqw 1cqw -.6cqw rgba(3,20,26,.45)',flex:big?'1 1 16cqw':'0 1 auto',maxWidth:big?'30cqw':'none'}},[
        h('div',{key:'n',style:{fontSize:big?'1.55cqw':'1.25cqw',fontWeight:800,whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis',lineHeight:1.12}},pp.name),
        h('div',{key:'m',style:{display:'flex',justifyContent:'space-between',alignItems:'center',gap:'.5cqw'}},[
          h('span',{key:'r',style:{fontSize:big?'.95cqw':'.9cqw',fontWeight:700,opacity:.82,whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'}}, big?(pp.role||''):''),
          h('span',{key:'f',style:{fontFamily:MONO,fontSize:big?'1.1cqw':'1cqw',fontWeight:800,background:'rgba(255,255,255,.22)',borderRadius:'.5cqw',padding:'.05cqw .55cqw',flexShrink:0}}, fmtNum(pp.fte,2))
        ])
      ]);
    }
    function band(b){ var isAgent=b.key==='agent'; var n=b.people.length; var body;
      if(isAgent){ var cols=n<=6?3:n<=8?4:n<=15?5:n<=24?6:7;
        body=h('div',{key:'g',style:{display:'grid',gridTemplateColumns:'repeat('+cols+',minmax(0,1fr))',gap:'.7cqw'}}, b.people.map(function(pp){ return tile(pp,false); }));
      } else {
        body=h('div',{key:'g',style:{display:'flex',flexWrap:'wrap',gap:'.7cqw'}}, b.people.map(function(pp){ return tile(pp,true); }));
      }
      return h('div',{key:b.key,style:{marginBottom:'1.3cqw'}},[
        h('div',{key:'h',style:{display:'flex',alignItems:'center',gap:'.7cqw',marginBottom:'.6cqw'}},[
          h('span',{key:'l',style:{fontSize:'1.15cqw',fontWeight:800,letterSpacing:'.12em',textTransform:'uppercase',color:P.muted}}, b.label),
          h('span',{key:'c',style:{fontFamily:MONO,fontSize:'1cqw',fontWeight:700,color:P.muted,opacity:.7}}, n),
          h('span',{key:'r',style:{flex:1,height:'1px',background:'#e2e8ee'}})
        ]),
        body
      ]);
    }
    return h('div',{style:{flex:1,minHeight:0,display:'flex',flexDirection:'column',overflow:'hidden'}}, bands.map(band));
  }
  // Folie 2 — Besetzung & FTE. Daten in deck.teams[tk].fteList = {rows:[{id,name,fte}], total, bands?, org?, _src}.
  // Mit org (Organigramm-Zweig aus org_nodes): Baum in Präsentations-Optik (Kundenfarbe-Fond, weiße Karten,
  // Verbindungslinien), FTE an den Karten. Ohne org: Namensliste als Fallback.
  // Seitenzahl der FTE-Folie (Agenten-Band paginiert; pl/overhead nur Seite 0).
  // Seiten-Plan der FTE-Folie: Seite 0 trägt Total-Badge + Projektleitung + Overhead. Gibt es diese Bänder,
  // starten die AGENTEN auf Seite 1 (sonst würde Seite 0 mit Badge+PL+Overhead+Agenten unten abgeschnitten,
  // die nutzbare Panel-Höhe reicht dafür nicht). Ohne PL/Overhead beginnen die Agenten auf Seite 0.
  // Agentenseiten fassen 15 (5 Spalten × 3 Zeilen), gleichmäßig gesplittet. EINE Wahrheit für Count + Render.
  function ftePlan(fl){
    var bands=(fl&&fl.bands)||[];
    var ab=bands.filter(function(b){return b.key==='agent';})[0]; var agents=(ab&&ab.people)||[];
    var others=bands.filter(function(b){return b.key!=='agent';});
    var hasOthers=others.reduce(function(s,b){return s+((b.people&&b.people.length)||0);},0)>0;
    var aLabel=(ab&&ab.label)||'Agenten';
    var aPages=agents.length?agentPages(agents,15):[];
    var pages=[];
    if(hasOthers){
      pages.push({others:others, agents:[]});                                 // Seite 0: Führung + Overhead
      aPages.forEach(function(ap,i){ pages.push({others:[], agents:ap, cont:i>0, aLabel:aLabel}); });
    } else {
      if(!aPages.length){ pages.push({others:[], agents:[]}); }               // gar keine Personen → 1 leere Seite
      aPages.forEach(function(ap,i){ pages.push({others:[], agents:ap, cont:i>0, aLabel:aLabel}); });
    }
    return pages;
  }
  function ftePages(ctx, tk){ var fl=((ctx.deck.teams||{})[tk]||{}).fteList||{};
    if(fl.bands&&fl.bands.length){ return ftePlan(fl).length; }
    return agentPages(fl.rows||[],24).length; }
  function Fte(ctx, tk, page){ page=page||0; var P=pal(ctx.accent); var td=(ctx.deck.teams||{})[tk]||{}; var lbl=skillLabel(ctx,tk);
    var fl=td.fteList||{}; var rows=fl.rows||[]; var bands=fl.bands; var total=(fl.total!=null)?fl.total:numOr(td.fte,null);
    var hasBands=!!(bands&&bands.length&&bands.some(function(b){ return b.people&&b.people.length; }));
    var pcount=hasBands?bands.reduce(function(s,b){ return s+b.people.length; },0):rows.length;
    if(!rows.length && !hasBands){ return Slide(ctx,[fondHead(P, lbl, 'Besetzung & FTE',''), panel(P, h('div',{style:{flex:1,display:'flex',alignItems:'center',justifyContent:'center',textAlign:'center'}}, h('div',{},[
      h('div',{key:'t',style:{fontSize:'2.4cqw',fontWeight:800,color:P.ink}},'Keine Besetzung übernommen'),
      h('div',{key:'s',style:{fontSize:'1.4cqw',marginTop:'1cqw',color:P.muted}},'FTE-Standard je Mitarbeiter pflegen und übernehmen.')
    ])))]); }
    var totalBadge=h('div',{key:'top',style:{display:'flex',alignItems:'baseline',gap:'1.4cqw',marginBottom:'1.6cqw',flexShrink:0}},[
      h('span',{key:'n',style:{fontSize:'5.4cqw',fontWeight:800,color:P.onLightTxt,lineHeight:1,fontVariantNumeric:'tabular-nums'}}, total==null?'—':fmtNum(total,2)),
      h('span',{key:'l',style:{fontSize:'1.6cqw',fontWeight:700,color:P.muted}},'FTE gesamt')
    ]);
    if(hasBands){
      var plan=ftePlan(fl); var np=plan.length; var pg=plan[page]||plan[0];
      var pageBands=(pg.others||[]).concat(pg.agents.length?[{key:'agent',label:pg.aLabel+(pg.cont?' (Fortsetzung)':''),people:pg.agents}]:[]);
      var head=page===0?fondHead(P, lbl, 'Besetzung & FTE', (pcount?(pcount+' Mitarbeiter'):'')+(np>1?(' · '+np+' Seiten'):'')):null;
      return Slide(ctx, [ head, panel(P, (page===0?[totalBadge]:[]).concat([FteBandsBody(pageBands, P)])) ].filter(Boolean));
    }
    // Fallback: mehrspaltige Namensliste (Legacy ohne bands), paginiert
    var lpages=agentPages(rows,24); var lr=lpages[page]||[];
    var head2=page===0?fondHead(P, lbl, 'Besetzung & FTE', (pcount?(pcount+' Mitarbeiter'):'')+(lpages.length>1?(' · '+lpages.length+' Seiten'):'')):null;
    var cols3=lr.length>8?3:(lr.length>4?2:1); var per=Math.ceil(lr.length/cols3); var groups=[]; for(var g=0;g<cols3;g++) groups.push(lr.slice(g*per,(g+1)*per));
    return Slide(ctx, [ head2, panel(P, (page===0?[totalBadge]:[]).concat([
      h('div',{key:'grid',style:{flex:1,minHeight:0,display:'flex',gap:'3.5cqw',overflow:'hidden'}},
        groups.map(function(grp,gi){ return h('div',{key:gi,style:{flex:1,minWidth:0,display:'flex',flexDirection:'column',gap:'.5cqw'}},
          grp.map(function(r,ri){ return h('div',{key:r.id||ri,style:{display:'flex',alignItems:'center',justifyContent:'space-between',gap:'1cqw',padding:'.45cqw 0',borderBottom:'1px solid #f1f5f9'}},[
            h('span',{key:'n',style:{fontSize:'1.4cqw',fontWeight:600,color:P.ink,whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'}},r.name),
            h('span',{key:'f',style:{fontFamily:MONO,fontSize:'1.4cqw',fontWeight:700,color:P.onLightTxt,flexShrink:0}},fmtNum(r.fte,2))
          ]); })
        ); })
      )
    ])) ].filter(Boolean));
  }

  // Folie 3 — Gelieferte Stunden als 8-Spalten-Tabelle (KW · Plan · Rückmeldung · Diff R−P · Geliefert · Diff G−R · % · Erläuterung).
  function StundenTable(ctx, tk){ var P=pal(ctx.accent); var td=(ctx.deck.teams||{})[tk]||{}; var lbl=skillLabel(ctx,tk);
    var rows=(td.stunden||[]).filter(function(r){ return r.kw!==''||r.plan!==''||r.geliefert!==''||r.rueck!==''; });
    var head=fondHead(P, lbl, 'Gelieferte Stunden', 'Plan · Rückmeldung · Geliefert');
    if(!rows.length){ return Slide(ctx,[head, panel(P, h('div',{style:{flex:1,display:'flex',alignItems:'center',justifyContent:'center',color:P.muted,fontSize:'1.6cqw'}},'Keine Stundendaten in diesem Zeitraum.'))]); }
    var heads=['KW','Geplant FC','Rückmeldung','Diff R−P','Geliefert','Diff G−R','% (Rückm.)','Erläuterung'];
    var ws=['9%','13%','14%','11%','13%','11%','11%','18%'];
    function cell(txt,i,st){ return h('div',{key:i,style:Object.assign({width:ws[i],padding:'0 .6cqw',boxSizing:'border-box',textAlign:i===0?'left':i===7?'left':'right',fontFamily:i>=1&&i<=6?MONO:'inherit'},st||{})}, txt); }
    var hdr=h('div',{key:'h',style:{display:'flex',alignItems:'flex-end',paddingBottom:'.7cqw',borderBottom:'1px solid #e6edef',marginBottom:'.4cqw',fontSize:'1.15cqw',fontWeight:700,color:P.muted,textTransform:'uppercase',letterSpacing:'.04em'}}, heads.map(function(hh,i){ return cell(hh,i); }));
    var sp=0,sr=0,sg=0;
    var body=rows.map(function(r,ri){ var plan=numOr(r.plan,null),rueck=numOr(r.rueck,null),gel=numOr(r.geliefert,null);
      if(r.plan!==''&&r.plan!=null)sp+=plan; if(r.rueck!==''&&r.rueck!=null)sr+=rueck; if(r.geliefert!==''&&r.geliefert!=null)sg+=gel;
      var dRP=(r.rueck!==''&&r.plan!=='')?rueck-plan:null; var dGR=(r.geliefert!==''&&r.rueck!=='')?gel-rueck:null; var pc=pctDiff(r.geliefert,r.rueck);
      return h('div',{key:ri,style:{display:'flex',alignItems:'center',padding:'.5cqw 0',borderBottom:'1px solid #f1f5f9',fontSize:'1.35cqw',color:P.ink}},[
        cell('KW '+(r.kw||'—'),0,{fontWeight:700}),
        cell(r.plan===''||r.plan==null?'—':fmtNum(plan),1),
        cell(r.rueck===''||r.rueck==null?'—':fmtNum(rueck),2),
        cell(dRP==null?'—':(dRP>0?'+':'')+fmtNum(dRP),3,{color:dRP==null?P.muted:dRP<0?'#dc2626':'#059669',fontWeight:700}),
        cell(r.geliefert===''||r.geliefert==null?'—':fmtNum(gel),4,{fontWeight:700}),
        cell(dGR==null?'—':(dGR>0?'+':'')+fmtNum(dGR),5,{color:dGR==null?P.muted:dGR<0?'#dc2626':'#059669',fontWeight:700}),
        cell(pc==null?'—':(pc>0?'+':'')+fmtNum(pc,1)+' %',6,{color:pc==null?P.muted:pc<0?'#dc2626':'#059669',fontWeight:700}),
        cell(r.erkl||'',7,{fontFamily:'inherit',fontSize:'1.15cqw',color:P.muted,whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'})
      ]);
    });
    var tdRP=sr-sp, tdGR=sg-sr, tpc=(sr>0)?(sg-sr)/sr*100:null;
    var totalRow=h('div',{key:'t',style:{display:'flex',alignItems:'center',paddingTop:'.7cqw',marginTop:'.2cqw',borderTop:'2px solid '+P.onLight,fontSize:'1.4cqw',fontWeight:800,color:P.ink}},[
      cell('Gesamt',0),cell(fmtNum(sp),1),cell(fmtNum(sr),2),
      cell((tdRP>0?'+':'')+fmtNum(tdRP),3,{color:tdRP<0?'#dc2626':'#059669'}),
      cell(fmtNum(sg),4),cell((tdGR>0?'+':'')+fmtNum(tdGR),5,{color:tdGR<0?'#dc2626':'#059669'}),
      cell(tpc==null?'—':(tpc>0?'+':'')+fmtNum(tpc,1)+' %',6,{color:tpc==null?P.muted:tpc<0?'#dc2626':'#059669'}),cell('',7)
    ]);
    return Slide(ctx, [ head, panel(P, [
      h('div',{key:'tbl',style:{flex:1,minHeight:0,display:'flex',flexDirection:'column',overflow:'hidden'}}, [hdr].concat(body).concat([totalRow])),
      h('div',{key:'ft',style:{fontSize:'1.1cqw',color:P.muted,marginTop:'1cqw'}},'Diff R−P, Diff G−R und % werden gerechnet · Prozent bezogen auf die Rückmeldung.')
    ]) ]);
  }

  // Kleiner "gerechnet"-Hinweis: Teamwerte auf Call-/CSAT-Folien sind gerechnet (gewichtetes
  // Mittel der Agentenwerte), kein gepflegter Wert. Nur Kennzeichnung, keine zweite Speicherung.
  function calcTag(P){ return h('span',{style:{fontSize:'.9cqw',fontWeight:700,letterSpacing:'.02em',color:P.muted,border:'.12cqw solid '+P.muted,borderRadius:'.5cqw',padding:'.05cqw .6cqw',marginLeft:'.7cqw',whiteSpace:'nowrap',opacity:.8}},'gerechnet'); }
  function Calls(ctx, tk, page){ return CallsView(ctx, tk, 'vorwoche', 'Vorwoche', page); }
  function CallsMtd(ctx, tk, page){ return CallsView(ctx, tk, 'monat', 'Monat (MTD)', page); }
  function CallsView(ctx, tk, period, eyebrow, page){ page=page||0; var P=pal(ctx.accent); var td=(ctx.deck.teams||{})[tk]||{}; var lbl=skillLabel(ctx,tk); var cols=callCols(tk);
    var cur=(td.calls&&td.calls[period])||{};
    if(!Object.keys(cur).length) return emptyPanel(ctx, fondHead(P, lbl+' · '+eyebrow, 'Call-Kennzahlen'), P, 'Keine Call-Kennzahlen in diesem Zeitraum.');
    var members=callsAgents(ctx, tk, period);
    var rows=members.map(function(m){ var c=cur[m.id]||{}; return Object.assign({},c,{answered:c.answered}); });
    var ans=members.map(function(m){ return {m:m,n:numOr((cur[m.id]||{}).answered,0)}; }).sort(function(a,b){ return b.n-a.n; });
    var dom=zoomDomain(ans.map(function(a){ return a.n; }));
    var htCol=cols.filter(function(c){ return /handle|aht/i.test(c.k); })[0]; var htKey=htCol?htCol.k:'avg_handle';
    var pages=agentPages(ans, 14); var pa=pages[page]||[]; var baseRank=pages.slice(0,page).reduce(function(s,p){return s+p.length;},0);
    var head=page===0?fondHead(P, lbl+' · '+eyebrow, 'Call-Kennzahlen', (ans.length+' Agenten'+(pages.length>1?(' · '+pages.length+' Seiten'):''))):null;
    var body=panel(P, (function(){
        var twoCol=pa.length>7, half=Math.ceil(pa.length/2);
        var colGroups=twoCol?[pa.slice(0,half),pa.slice(half)]:[pa];
        var nameW=twoCol?'12cqw':'20cqw';
        function stat(val,l,col){ return h('div',{style:{display:'flex',alignItems:'baseline',gap:'.9cqw'}},[
          h('span',{key:'n',style:{fontSize:'3.4cqw',fontWeight:800,color:col,lineHeight:1,fontVariantNumeric:'tabular-nums'}},val),
          h('span',{key:'l',style:{fontSize:'1.15cqw',color:P.muted,fontWeight:700}},l) ]); }
        function rankRow(o,rank){ var w=Math.max(6,frac(o.n,dom)*100);
          return h('div',{key:o.m.id,style:{display:'flex',alignItems:'center',gap:'1.2cqw'}},[
            h('span',{key:'r',style:{width:'2.2cqw',textAlign:'right',fontFamily:MONO,fontSize:'1.1cqw',fontWeight:700,color:P.muted,flexShrink:0}},rank+'.'),
            h('span',{key:'n',style:{width:nameW,fontSize:'1.25cqw',fontWeight:600,color:P.ink,whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis',flexShrink:0}},o.m.name),
            h('div',{key:'b',style:{flex:1,height:'0.85cqw',background:'#eef2f4',borderRadius:'.5cqw',overflow:'hidden'}}, h('div',{style:{width:w+'%',height:'100%',background:P.onLight,borderRadius:'.5cqw'}})),
            h('span',{key:'v',style:{width:'5cqw',textAlign:'right',fontFamily:MONO,fontWeight:700,fontSize:'1.25cqw',color:P.ink,flexShrink:0}},fmtNum(o.n))
          ]); }
        var out=[];
        if(page===0) out.push(h('div',{key:'big',style:{display:'flex',gap:'4.5cqw',alignItems:'baseline',flexWrap:'wrap',marginBottom:'2cqw',flexShrink:0}},[
            stat(fmtNum(sumCol(rows,'answered')),'Answered gesamt',P.onLightTxt),
            stat(wavgTime(rows,htKey,'answered'),['Ø Handle',calcTag(P)],P.ink)
          ]));
        out.push(h('div',{key:'list',style:{flex:1,minHeight:0,display:'flex',gap:'4.5cqw',overflow:'hidden'}},
            pa.length===0 ? [h('div',{key:'e',style:{color:P.muted,fontSize:'1.4cqw'}},'Keine Mitarbeiter.')]
            : colGroups.map(function(colRows,ci){ return h('div',{key:ci,style:{flex:1,minWidth:0,display:'flex',flexDirection:'column',gap:'.7cqw',justifyContent:colRows.length<=5?'center':'flex-start'}},
                colRows.map(function(o,ri){ return rankRow(o, baseRank + ci*half + ri + 1); })
              ); })
          ));
        out.push(h('div',{key:'foot',style:{fontSize:'1cqw',color:P.muted,marginTop:'.6cqw',flexShrink:0}}, (page===0?'Ø Handle ist gerechnet: gewichtetes Mittel nach Answered. ':'')+(pages.length>1?('Seite '+(page+1)+'/'+pages.length):'')));
        return out;
      })());
    return Slide(ctx, [head, body].filter(Boolean));
  }

  function skillLabel(ctx, key){ var s=(ctx.skills||[]).filter(function(x){return x.key===key;})[0]; if(s) return s.label||s.key; return key==='sales'?'Sales':key==='support'?'Support':key; }

  // Call-Stichproben: beste/schwächste je Skill im Berichtszeitraum. ctx.callScores[tk] = {best:[{name,pct,
  // color,label,_detail?}], worst:[…], count, avg, thresholds}. Balken ABSOLUT 0–100 (Prozent bedeutungstragend,
  // NICHT gespreizt). Aufklappen JE MITARBEITER: nur IN-APP (Einträge tragen _detail) über ein Overlay — die Folie
  // ist 16:9/overflow:hidden, inline-Aufklappen würde clippen. Öffentliche Seite/PDF: Snapshot enthält KEIN
  // _detail (interne Kriterien/Kommentare bleiben draußen) → nur die Übersicht, kein Aufklappen. Leer → Hinweis.
  function CallScores(ctx, tk){ return h(CallScoresSlide, {ctx:ctx, tk:tk}); }
  function CallScoresSlide(props){
    var ctx=props.ctx, tk=props.tk; var P=pal(ctx.accent); var lbl=skillLabel(ctx,tk);
    var cs=(ctx.callScores&&ctx.callScores[tk])||null;
    var best=(cs&&cs.best)||[], worst=(cs&&cs.worst)||[], count=cs?cs.count:0;
    var unit=(cs&&cs.unit==='points')?'points':'percent'; var cmax=cs&&cs.max;
    var st=R.useState(null), open=st[0], setOpen=st[1];
    var avgTxt=(cs&&cs.avg!=null)?(unit==='points'?(' · Ø '+fmtNum(cs.avg,1)+' Pkt'):(' · Ø '+fmtNum(cs.avg,0)+' %')):'';
    var breachTxt=(cs&&cs.breaches>0)?(' · ⛔ '+cs.breaches+' Compliance-Verstoß'+(cs.breaches>1?'e':'')):'';
    var meta=count?((count)+' Stichprobe'+(count>1?'n':'')+avgTxt+breachTxt):'';
    var head=fondHead(P, lbl, 'Call-Qualität', meta);
    if(!count || (!best.length && !worst.length)){
      return Slide(ctx, [ head, panel(P, h('div',{style:{flex:1,display:'flex',alignItems:'center',justifyContent:'center',textAlign:'center'}},
        h('div',{},[
          h('div',{key:'t',style:{fontSize:'2.4cqw',fontWeight:800,color:P.ink}},'Keine Call-Stichproben in diesem Zeitraum'),
          h('div',{key:'s',style:{fontSize:'1.4cqw',marginTop:'1cqw',color:P.muted}},'Für '+lbl+' wurden im Berichtszeitraum keine Gespräche bewertet.')
        ]))) ]);
    }
    function row(e,i){ var w=Math.max(4,Math.min(100,numOr(e.pct,0))); var clk=!!e._detail;
      return h('div',{key:i, onClick: clk?function(){ setOpen(e); }:null, style:{display:'flex',alignItems:'center',gap:'1.1cqw',padding:'0.85cqw 0',cursor:clk?'pointer':'default',borderBottom:'1px solid #f1f5f9'}},[
        h('span',{key:'n',style:{flex:1,minWidth:0,fontSize:'1.5cqw',fontWeight:600,color:P.ink,whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'}},[ e.breach?h('span',{key:'cb',style:{color:'#dc2626',fontWeight:800,marginRight:'.4cqw'},title:'Compliance-Verstoß'},'⛔'):null, e.name ]),
        h('div',{key:'b',style:{width:'26%',height:'0.9cqw',background:'#eef2f4',borderRadius:'.5cqw',overflow:'hidden',flexShrink:0}}, h('div',{style:{width:w+'%',height:'100%',background:e.color||P.onLight,borderRadius:'.5cqw'}})),
        h('span',{key:'v',style:{width:'7cqw',textAlign:'right',fontFamily:MONO,fontWeight:800,fontSize:'1.7cqw',color:e.color||P.ink,flexShrink:0}}, unit==='points'?(e.points==null?'—':fmtNum(e.points,1)+(cmax!=null?' / '+fmtNum(cmax,0):'')):(fmtNum(e.pct,0)+'%')),
        h('span',{key:'c',style:{width:'1.4cqw',textAlign:'right',fontSize:'1.5cqw',color:'#cbd5e1',flexShrink:0}}, clk?'›':'')
      ]);
    }
    function col(list, title, tcol){ return h('div',{style:{flex:1,minWidth:0,display:'flex',flexDirection:'column'}},[
      h('div',{key:'h',style:{display:'flex',alignItems:'center',gap:'.8cqw',marginBottom:'.8cqw'}},[
        h('span',{key:'d',style:{width:'1cqw',height:'1cqw',borderRadius:'50%',background:tcol,flexShrink:0}}),
        h('span',{key:'t',style:{fontSize:'1.55cqw',fontWeight:800,color:tcol}},title),
        h('span',{key:'n',style:{fontSize:'1.2cqw',color:P.muted,fontWeight:600}},'('+list.length+')')
      ]),
      h('div',{key:'l'}, list.map(row))
    ]); }
    var cols=[];
    if(best.length) cols.push(col(best,'Stärkste Gespräche','#059669'));
    if(best.length&&worst.length) cols.push(h('div',{key:'sep',style:{width:1,alignSelf:'stretch',background:'#e5e7eb'}}));
    if(worst.length) cols.push(col(worst,'Zum Nachschärfen','#dc2626'));
    var legend=(cs&&cs.thresholds)?h('div',{key:'leg',style:{marginTop:'1.4cqw',fontSize:'1.1cqw',color:P.muted}}, 'Ampel: ab '+fmtNum(cs.thresholds.green,0)+(unit==='points'?' Pkt':' %')+' grün · ab '+fmtNum(cs.thresholds.yellow,0)+(unit==='points'?' Pkt':' %')+' gelb · darunter rot'):null;
    var body=[ head, panel(P, [ h('div',{key:'cols',style:{flex:1,minHeight:0,display:'flex',gap:'4cqw',alignItems:'flex-start'}}, cols), legend ]) ];
    return Slide(ctx, body, {overlay: open?detailOverlay(open):null});

    function detailOverlay(e){ var det=e._detail||{}; var scores=det.scores||[]; var last=null;
      return h('div',{key:'ov',style:{position:'absolute',inset:0,background:'#ffffff',zIndex:20,display:'flex',flexDirection:'column',padding:'3.4cqw 3.6cqw'}},[
        h('div',{key:'h',style:{display:'flex',alignItems:'flex-start',justifyContent:'space-between',gap:'1cqw',marginBottom:'1.2cqw'}},[
          h('div',{key:'l'},[
            h('div',{key:'n',style:{fontSize:'2.3cqw',fontWeight:800,color:P.ink}},[ e.name, '  ', h('span',{key:'p',style:{fontFamily:MONO,color:e.color}},fmtNum(e.pct,0)+'%') ]),
            h('div',{key:'s',style:{fontSize:'1.25cqw',color:P.muted,fontWeight:600,marginTop:'.3cqw'}},'Kriterien der letzten Stichprobe')
          ]),
          h('div',{key:'x',onClick:function(){ setOpen(null); },style:{cursor:'pointer',fontSize:'2cqw',color:P.muted,fontWeight:700,lineHeight:1,padding:'0 .4cqw'}},'✕')
        ]),
        h('div',{key:'sc',style:{flex:1,minHeight:0,overflowY:'auto'}}, scores.length? scores.map(function(s,i){
          var catH=(s.category||'')!==last?(s.category||''):null; last=s.category||''; var w=s.na?0:Math.max(3,Math.min(100,numOr(s.pct,0)));
          return h('div',{key:i},[
            catH?h('div',{key:'c',style:{fontSize:'1.05cqw',fontWeight:700,color:P.muted,textTransform:'uppercase',letterSpacing:'.06em',margin:'1cqw 0 .3cqw'}},catH):null,
            h('div',{key:'r',style:{display:'flex',alignItems:'center',gap:'1cqw',padding:'.35cqw 0'}},[
              h('div',{key:'p',style:{flex:1,minWidth:0}},[ h('div',{key:'pt',style:{fontSize:'1.3cqw',fontWeight:600,color:P.ink}},s.prompt), s.comment?h('div',{key:'cm',style:{fontSize:'1.1cqw',color:P.muted}},s.comment):null ]),
              h('div',{key:'b',style:{width:'16cqw',height:'0.8cqw',background:'#eef2f4',borderRadius:'.5cqw',overflow:'hidden',flexShrink:0}}, s.na?null:h('div',{style:{width:w+'%',height:'100%',background:s.color||'#94a3b8'}})),
              h('span',{key:'v',style:{width:'5cqw',textAlign:'right',fontFamily:MONO,fontWeight:700,fontSize:'1.3cqw',color:s.na?P.muted:(s.color||P.ink),flexShrink:0}}, s.na?'n/a':fmtNum(s.pct,0)+'%')
            ])
          ]);
        }) : h('div',{style:{color:P.muted,fontSize:'1.3cqw'}},'Keine Kriteriendetails.')),
        det.note?h('div',{key:'nt',style:{marginTop:'1.2cqw',paddingTop:'1cqw',borderTop:'1px solid #eef2f4',fontSize:'1.3cqw',color:P.ink}},[ h('span',{key:'lb',style:{fontWeight:700,color:P.muted}},'Notiz: '), det.note ]):null
      ]);
    }
  }

  // CSAT (Folie 13) — Kundenzufriedenheit je Mitarbeiter über das 5-Wochen-Fenster. Daten aus weekly_gauges,
  // beim Übernehmen in deck.teams[tk].csat = {weeks:[{kw,key}], rows:[{id,name,cells:{key:{v,n}},avg}], _src}
  // eingefroren (Namen im Snapshot → öffentliche Seite braucht keine employees). Ø gewichtet nach n (Anzahl).
  function Csat(ctx, tk, page){ page=page||0; var P=pal(ctx.accent); var td=(ctx.deck.teams||{})[tk]||{}; var lbl=skillLabel(ctx,tk);
    var cs=td.csat||{}; var weeks=cs.weeks||[]; var rows=cs.rows||[];
    var rangeTxt=weeks.length?('KW '+weeks[0].kw+' – KW '+weeks[weeks.length-1].kw):'';
    if(!rows.length){ return Slide(ctx,[fondHead(P, lbl+' · CSAT', 'Kundenzufriedenheit', rangeTxt), panel(P, h('div',{style:{flex:1,display:'flex',alignItems:'center',justifyContent:'center',textAlign:'center'}}, h('div',{},[
      h('div',{key:'t',style:{fontSize:'2.4cqw',fontWeight:800,color:P.ink}},'Keine CSAT-Daten in diesem Zeitraum'),
      h('div',{key:'s',style:{fontSize:'1.4cqw',marginTop:'1cqw',color:P.muted}},'Für '+lbl+' liegen keine Gauges-/CSAT-Werte vor.')
    ])))]); }
    function wavg(list){ var sv=0,sn=0; (list||[]).forEach(function(c){ if(c&&c.v!=null){ var n=(c.n||0)||1; sv+=c.v*n; sn+=n; } }); return sn?sv/sn:null; }
    var teamWeek={}; weeks.forEach(function(w){ teamWeek[w.key]=wavg(rows.map(function(r){ return r.cells[w.key]; })); });
    var teamAvg=wavg(rows.map(function(r){ return {v:r.avg,n:1}; }));
    var pages=agentPages(rows, 11); var pr=pages[page]||[]; var isLast=(page===pages.length-1);
    var head=page===0?fondHead(P, lbl+' · CSAT', 'Kundenzufriedenheit', rangeTxt+(pages.length>1?(' · '+rows.length+' MA · '+pages.length+' Seiten'):'')):null;
    var colName='30cqw';
    function valCell(c){ if(!c||c.v==null) return h('div',{style:{flex:1,textAlign:'center',fontFamily:MONO,fontSize:'1.4cqw',color:'#cbd5e1'}},'—');
      return h('div',{style:{flex:1,textAlign:'center'}},[
        h('div',{key:'v',style:{fontFamily:MONO,fontSize:'1.55cqw',fontWeight:700,color:P.ink}}, fmtNum(c.v,1)),
        (c.n!=null)?h('div',{key:'n',style:{fontSize:'.95cqw',color:P.muted}},'n='+fmtNum(c.n)):null
      ]);
    }
    var headerRow=h('div',{key:'hd',style:{display:'flex',alignItems:'flex-end',gap:'1cqw',paddingBottom:'.8cqw',borderBottom:'1px solid #e6edef',marginBottom:'.5cqw'}},
      [h('div',{key:'n',style:{width:colName,fontSize:'1.2cqw',fontWeight:700,color:P.muted,textTransform:'uppercase',letterSpacing:'.06em'}},'Mitarbeiter')]
      .concat(weeks.map(function(w){ return h('div',{key:w.key,style:{flex:1,textAlign:'center',fontFamily:MONO,fontSize:'1.2cqw',fontWeight:700,color:P.muted}},'KW '+w.kw); }))
      .concat([h('div',{key:'avg',style:{flex:1,textAlign:'center',fontSize:'1.2cqw',fontWeight:800,color:P.onLightTxt}},'Ø')]));
    var body=pr.map(function(r,i){ return h('div',{key:r.id||i,style:{display:'flex',alignItems:'center',gap:'1cqw',padding:'.4cqw 0',borderBottom:'1px solid #f1f5f9'}},
      [h('div',{key:'n',style:{width:colName,fontSize:'1.35cqw',fontWeight:600,color:P.ink,whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'}},r.name)]
      .concat(weeks.map(function(w){ return valCell(r.cells[w.key]); }))
      .concat([h('div',{key:'avg',style:{flex:1,textAlign:'center',fontFamily:MONO,fontSize:'1.6cqw',fontWeight:800,color:P.onLightTxt}}, r.avg==null?'—':fmtNum(r.avg,1))])); });
    var teamRow=h('div',{key:'team',style:{display:'flex',alignItems:'center',gap:'1cqw',paddingTop:'.7cqw',marginTop:'.2cqw',borderTop:'2px solid '+P.onLight}},
      [h('div',{key:'n',style:{width:colName,fontSize:'1.35cqw',fontWeight:800,color:P.ink,display:'flex',alignItems:'center'}},['Team Ø',calcTag(P)])]
      .concat(weeks.map(function(w){ var v=teamWeek[w.key]; return h('div',{key:w.key,style:{flex:1,textAlign:'center',fontFamily:MONO,fontSize:'1.5cqw',fontWeight:800,color:P.ink}}, v==null?'—':fmtNum(v,1)); }))
      .concat([h('div',{key:'avg',style:{flex:1,textAlign:'center',fontFamily:MONO,fontSize:'1.7cqw',fontWeight:800,color:P.onLightTxt}}, teamAvg==null?'—':fmtNum(teamAvg,1))]));
    return Slide(ctx, [ head, panel(P, [
      h('div',{key:'tbl',style:{flex:1,minHeight:0,display:'flex',flexDirection:'column',overflow:'hidden'}}, [headerRow].concat(body).concat(isLast?[teamRow]:[])),
      h('div',{key:'ft',style:{fontSize:'1.1cqw',color:P.muted,marginTop:'1cqw'}},'CSAT je Mitarbeiter und Woche · n = Anzahl Bewertungen · Team Ø gewichtet nach n'+(pages.length>1?(' · Seite '+(page+1)+'/'+pages.length):''))
    ]) ]);
  }

  // CR (Folien 6–10) — Daten in deck.teams[tk].cr = {weeks:[{kw,key}], team:{key:{open,osl,calls,cr}},
  //   agents:[{id,name,byWeek:{key:{open,osl,calls,cr}},tot:{...}}], mtd:{label,weekKws,agents,team}, _src}.
  //   CR = (Offene + OSL) ÷ Sales Calls × 100 (im Frontend gerechnet, nie getippt).
  function CrTable(ctx, tk){ var P=pal(ctx.accent); var td=(ctx.deck.teams||{})[tk]||{}; var lbl=skillLabel(ctx,tk);
    var cr=td.cr||{}; var weeks=cr.weeks||[]; var team=cr.team||{};
    var head=fondHead(P, lbl, 'Conversion Rate', 'CR = (Offene + OSL) ÷ Calls');
    if(!weeks.length) return emptyPanel(ctx,head,P,'Keine KPI-Daten in diesem Zeitraum.');
    var tot={open:0,osl:0,calls:0}; weeks.forEach(function(w){ var c=team[w.key]; if(c){tot.open+=c.open;tot.osl+=c.osl;tot.calls+=c.calls;} }); tot.cr=tot.calls>0?(tot.open+tot.osl)/tot.calls*100:null;
    var metrics=[{l:'Offene Buchungen',k:'open'},{l:'OSL-Buchungen',k:'osl'},{l:'Buchungen gesamt',k:'bk',b:1},{l:'Sales Calls',k:'calls'},{l:'CR',k:'cr',pct:1,b:1}];
    var colName='24cqw';
    function get(c,k){ if(!c) return null; return k==='bk'?c.open+c.osl:k==='cr'?c.cr:c[k]; }
    function gtot(k){ return k==='bk'?tot.open+tot.osl:k==='cr'?tot.cr:tot[k]; }
    var hdr=h('div',{key:'h',style:{display:'flex',alignItems:'flex-end',paddingBottom:'.7cqw',borderBottom:'1px solid #e6edef',fontSize:'1.15cqw',fontWeight:700,color:P.muted,textTransform:'uppercase'}},
      [h('div',{key:'n',style:{width:colName}},'')].concat(weeks.map(function(w){ return h('div',{key:w.key,style:{flex:1,textAlign:'right',fontFamily:MONO,paddingRight:'.6cqw'}},'KW '+w.kw); })).concat([h('div',{key:'g',style:{flex:1,textAlign:'right',paddingRight:'.6cqw',color:P.onLightTxt,fontWeight:800}},'Gesamt')]));
    var body=metrics.map(function(mt){ return h('div',{key:mt.k,style:{display:'flex',alignItems:'center',padding:'.55cqw 0',borderBottom:'1px solid #f1f5f9',fontWeight:mt.b?800:600}},
      [h('div',{key:'n',style:{width:colName,fontSize:'1.4cqw',color:P.ink}},mt.l)]
      .concat(weeks.map(function(w){ var v=get(team[w.key],mt.k); return h('div',{key:w.key,style:{flex:1,textAlign:'right',fontFamily:MONO,fontSize:'1.45cqw',color:mt.b?P.onLightTxt:P.ink,paddingRight:'.6cqw'}}, v==null?'—':(mt.pct?fmtNum(v,1)+' %':fmtNum(v))); }))
      .concat([h('div',{key:'g',style:{flex:1,textAlign:'right',fontFamily:MONO,fontSize:'1.5cqw',fontWeight:800,color:P.onLightTxt,paddingRight:'.6cqw'}}, (function(){ var v=gtot(mt.k); return v==null?'—':(mt.pct?fmtNum(v,1)+' %':fmtNum(v)); })())])); });
    return Slide(ctx,[head, panel(P,[ h('div',{key:'t',style:{flex:1,minHeight:0,display:'flex',flexDirection:'column',justifyContent:'center'}}, [hdr].concat(body)) ])]);
  }
  function CrChart(ctx, tk){ var P=pal(ctx.accent); var td=(ctx.deck.teams||{})[tk]||{}; var lbl=skillLabel(ctx,tk);
    var cr=td.cr||{}; var weeks=cr.weeks||[]; var team=cr.team||{};
    var head=fondHead(P, lbl, 'Conversion Rate im Verlauf', '5 Wochen');
    if(!weeks.length) return emptyPanel(ctx,head,P,'Keine KPI-Daten.');
    var dom=zoomDomain(weeks.map(function(w){ return team[w.key]?team[w.key].cr:null; }).filter(function(v){return v!=null;}));
    return Slide(ctx,[head, panel(P,[
      h('div',{key:'chart',style:{flex:1,minHeight:0,display:'flex',alignItems:'stretch',gap:'2.4cqw'}},
        weeks.map(function(w,i){ var c=team[w.key]; var v=c?c.cr:null;
          return h('div',{key:i,style:{flex:1,display:'flex',flexDirection:'column'}},[
            h('div',{key:'b',style:{flex:1,minHeight:0,display:'flex',flexDirection:'column',justifyContent:'flex-end',alignItems:'center'}},[
              h('div',{key:'v',style:{fontFamily:MONO,fontSize:'1.5cqw',fontWeight:800,color:P.onLightTxt,marginBottom:'.5cqw'}}, v==null?'—':fmtNum(v,1)+'%'),
              h('div',{key:'bar',style:{width:'55%',height:(v==null?0:Math.max(4,frac(v,dom)*88))+'%',background:P.onLight,borderRadius:'.5cqw .5cqw 0 0'}})
            ]),
            h('div',{key:'l',style:{textAlign:'center',marginTop:'1cqw',paddingTop:'.8cqw',borderTop:'1px solid #eef2f4',fontFamily:MONO,fontSize:'1.3cqw',fontWeight:700,color:P.ink}},'KW '+w.kw)
          ]); })),
      dom.zoomed?h('div',{key:'sc',style:{fontSize:'1cqw',color:P.muted,marginTop:'1cqw',textAlign:'right'}},'Skala ab '+fmtNum(dom.lo,1)+'% (gespreizt) · exakte Werte am Balken'):null
    ])]);
  }
  function AgentCr(ctx, tk){ var P=pal(ctx.accent); var td=(ctx.deck.teams||{})[tk]||{}; var lbl=skillLabel(ctx,tk);
    var agents=(td.cr&&td.cr.agents)||[];
    var head=fondHead(P, lbl, 'Conversion Rate je Agent', agents.length?(agents.length+' Agenten · Ø 5 Wochen'):'');
    if(!agents.length) return emptyPanel(ctx,head,P,'Keine KPI-Daten je Agent.');
    var dom=zoomDomain(agents.map(function(a){return a.tot.cr;}).filter(function(v){return v!=null;}));
    var shown=agents.slice(0,16), twoCol=shown.length>7, half=Math.ceil(shown.length/2), groups=twoCol?[shown.slice(0,half),shown.slice(half)]:[shown];
    function rankRow(a,rank){ var v=a.tot.cr; var w=v==null?0:Math.max(6,frac(v,dom)*100);
      return h('div',{key:a.id,style:{display:'flex',alignItems:'center',gap:'1.2cqw'}},[
        h('span',{key:'r',style:{width:'2.2cqw',textAlign:'right',fontFamily:MONO,fontSize:'1.1cqw',fontWeight:700,color:P.muted}},rank+'.'),
        h('span',{key:'n',style:{width:twoCol?'12cqw':'20cqw',fontSize:'1.25cqw',fontWeight:600,color:P.ink,whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'}},a.name),
        h('div',{key:'b',style:{flex:1,height:'.85cqw',background:'#eef2f4',borderRadius:'.5cqw',overflow:'hidden'}}, h('div',{style:{width:w+'%',height:'100%',background:P.onLight,borderRadius:'.5cqw'}})),
        h('span',{key:'v',style:{width:'6cqw',textAlign:'right',fontFamily:MONO,fontWeight:700,fontSize:'1.25cqw',color:P.ink}}, v==null?'—':fmtNum(v,1)+'%')
      ]); }
    return Slide(ctx,[head, panel(P,[
      h('div',{key:'l',style:{flex:1,minHeight:0,display:'flex',gap:'4.5cqw',overflow:'hidden'}}, groups.map(function(g,ci){ return h('div',{key:ci,style:{flex:1,minWidth:0,display:'flex',flexDirection:'column',gap:'.7cqw',justifyContent:g.length<=6?'center':'flex-start'}}, g.map(function(a,ri){ return rankRow(a, ci*half+ri+1); })); })),
      h('div',{key:'note',style:{fontSize:'1cqw',color:P.muted,marginTop:'1cqw',textAlign:'right'}}, (dom.zoomed?('Balkenskala ab '+fmtNum(dom.lo,1)+'% · '):'')+'CR = (Offene+OSL)÷Calls, Ø über 5 Wochen')
    ])]);
  }
  function AgentCrTrend(ctx, tk, page){ var td=(ctx.deck.teams||{})[tk]||{}; var cr=td.cr||{};
    return AgentMultiples(ctx, tk, page, { agents:cr.agents, weeks:cr.weeks, title:'CR-Verlauf je Agent',
      value:function(a,w){ var c=a.byWeek&&a.byWeek[w.key]; return (c&&c.cr!=null)?c.cr:null; },
      fmtAvg:function(a){ return (a.tot&&a.tot.cr!=null)?(fmtNum(a.tot.cr,1)+'%'):'—'; }, foot:'Balken = CR je Woche',
      emptyTitle:'Keine KPI-Daten je Agent.', emptySub:'' });
  }
  function Mtd(ctx, tk){ var P=pal(ctx.accent); var td=(ctx.deck.teams||{})[tk]||{}; var lbl=skillLabel(ctx,tk);
    var mtd=(td.cr&&td.cr.mtd)||{}; var agents=mtd.agents||[]; var tm=mtd.team||{};
    var head=fondHead(P, lbl, 'Monat bis dato (MTD)', mtd.label||'');
    if(!agents.length) return emptyPanel(ctx,head,P,'Keine KPI-Daten im laufenden Monat.');
    var colName='26cqw'; var heads=['Mitarbeiter','Offene','OSL','Buchungen','Calls','CR'];
    var hdr=h('div',{key:'h',style:{display:'flex',alignItems:'flex-end',paddingBottom:'.7cqw',borderBottom:'1px solid #e6edef'}}, heads.map(function(t2,i){ return h('div',{key:i,style:{width:i===0?colName:'auto',flex:i===0?'none':1,textAlign:i===0?'left':'right',fontSize:'1.15cqw',fontWeight:700,color:P.muted,textTransform:'uppercase',paddingRight:'.6cqw'}},t2); }));
    function line(vals,bold,border){ return h('div',{style:{display:'flex',alignItems:'center',padding:'.45cqw 0',borderBottom:border?null:'1px solid #f1f5f9',borderTop:border||null,marginTop:border?'.2cqw':0,paddingTop:border?'.6cqw':'.45cqw',fontSize:'1.35cqw',fontWeight:bold?800:400,color:P.ink}},
      [h('div',{key:'n',style:{width:colName,fontWeight:bold?800:600,whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'}},vals[0])]
      .concat(vals.slice(1).map(function(v,i){ return h('div',{key:i,style:{flex:1,textAlign:'right',fontFamily:MONO,fontWeight:(i===2||i===4)?800:(bold?800:400),color:(i===4)?P.onLightTxt:P.ink,paddingRight:'.6cqw'}}, v); }))); }
    var body=agents.map(function(a){ return line([a.name,fmtNum(a.open),fmtNum(a.osl),fmtNum(a.open+a.osl),fmtNum(a.calls),a.cr==null?'—':fmtNum(a.cr,1)+'%'],false,null); });
    var totalRow=line(['Team gesamt',fmtNum(tm.open),fmtNum(tm.osl),fmtNum((tm.open||0)+(tm.osl||0)),fmtNum(tm.calls),tm.cr==null?'—':fmtNum(tm.cr,1)+'%'],true,'2px solid '+P.onLight);
    return Slide(ctx,[head, panel(P,[ h('div',{key:'tbl',style:{flex:1,minHeight:0,display:'flex',flexDirection:'column',overflow:'hidden'}}, [hdr].concat(body).concat([totalRow])), h('div',{key:'ft',style:{fontSize:'1.05cqw',color:P.muted,marginTop:'.8cqw'}}, 'MTD = Summe der Berichtsmonats-Wochen (KW '+((mtd.weekKws||[]).join(', '))+') · CR = (Offene+OSL)÷Calls') ])]);
  }

  // Fehlzeiten — Krankheitstage je Woche (System, aus Abwesenheiten) + Kommentar je Woche (manuell).
  //   deck.teams[tk].fehlzeiten = {weeks:[{kw,key}], krank:{key:num}, comment:{key:text}, _src}.
  function Fehlzeiten(ctx, tk){ var P=pal(ctx.accent); var td=(ctx.deck.teams||{})[tk]||{}; var lbl=skillLabel(ctx,tk);
    var fz=td.fehlzeiten||{}; var weeks=fz.weeks||[]; var krank=fz.krank||{}; var comment=fz.comment||{};
    var head=fondHead(P, lbl, 'Fehlzeiten', 'Krankheitstage je Woche');
    if(!weeks.length) return emptyPanel(ctx,head,P,'Keine Fehlzeiten-Daten.');
    var total=0; weeks.forEach(function(w){ total+=(krank[w.key]||0); });
    return Slide(ctx,[head, panel(P,[
      h('div',{key:'g',style:{flex:1,minHeight:0,display:'flex',gap:'2cqw',alignItems:'stretch'}}, weeks.map(function(w){ var k=krank[w.key]||0; var c=comment[w.key]||'';
        return h('div',{key:w.key,style:{flex:1,minWidth:0,display:'flex',flexDirection:'column',border:'1px solid #eef2f4',borderRadius:'1.2cqw',padding:'1.6cqw 1.4cqw'}},[
          h('div',{key:'kw',style:{fontFamily:MONO,fontSize:'1.3cqw',fontWeight:700,color:P.muted}},'KW '+w.kw),
          h('div',{key:'n',style:{fontSize:'4.6cqw',fontWeight:800,color:k>0?P.onLightTxt:P.muted,lineHeight:1.1,marginTop:'.4cqw'}}, fmtNum(k)),
          h('div',{key:'l',style:{fontSize:'1.1cqw',color:P.muted,fontWeight:700}}, k===1?'Krankheitstag':'Krankheitstage'),
          c?h('div',{key:'c',style:{marginTop:'1cqw',fontSize:'1.2cqw',color:P.ink,lineHeight:1.35}}, c):null
        ]);
      })),
      h('div',{key:'ft',style:{fontSize:'1.15cqw',color:P.muted,marginTop:'1.4cqw'}}, 'Summe '+fmtNum(total)+' Krankheitstage im Zeitraum · aus Abwesenheiten (Mo–Fr)')
    ])]);
  }

  // Folie 14 — Maßnahmen als FORTLAUFENDE Liste (Nachverfolgung). ctx.measures = [{id,text,status,comment,
  //   created_kw,created_year}] (Carry-over lädt hr.html). Mit ctx.onMeasure(action) INTERAKTIV (in-App, auch in
  //   der Darstellung pflegbar); ohne onMeasure read-only (öffentliche Seite/PDF, aus Snapshot). Fallback: Freitext.
  var MEAS_ST={open:{l:'Offen',c:'#dc2626',bg:'#fef2f2'},in_progress:{l:'In Arbeit',c:'#d97706',bg:'#fffbeb'},done:{l:'Erledigt',c:'#059669',bg:'#ecfdf5'}};
  function Massnahmen(ctx, tk){ return h(MassnahmenSlide,{ctx:ctx,tk:tk}); }
  function MassnahmenSlide(props){ var ctx=props.ctx, tk=props.tk; var P=pal(ctx.accent); var lbl=skillLabel(ctx,tk);
    // Maßnahmen je Skill getrennt (Sales = Verkauf, Support = Bearbeitung). measuresFor(tk) bevorzugt, sonst
    // Alt-Kontrakt ctx.measures. onMeasure trägt den Skill (_skill), damit Add/Status/Delete am richtigen Skill landet.
    var measures = ctx.measuresFor ? ctx.measuresFor(tk) : ctx.measures;
    var onMraw=ctx.onMeasure; var onM = onMraw ? function(a){ return onMraw(Object.assign({},a,{_skill:tk})); } : null;
    var nt=R.useState(''); var newText=nt[0], setNewText=nt[1];
    var head=fondHead(P, lbl, 'Maßnahmen', measures?'Nachverfolgung':'');
    if(measures==null){ var td=(ctx.deck.teams||{})[tk]||{}; var txt=(td.massnahmen||'').trim();
      if(!txt) return emptyPanel(ctx,head,P,'Keine Maßnahmen hinterlegt.');
      var paras=txt.split(/\n+/).filter(function(x){ return x.trim(); });
      return Slide(ctx,[head, panel(P, h('div',{style:{flex:1,minHeight:0,overflow:'hidden',display:'flex',flexDirection:'column',justifyContent:'center',gap:'1.6cqw'}},
        paras.map(function(p,i){ return h('div',{key:i,style:{display:'flex',gap:'1.4cqw',alignItems:'flex-start'}},[ h('div',{key:'d',style:{width:'1.2cqw',height:'1.2cqw',borderRadius:'50%',background:P.onLight,marginTop:'.7cqw',flexShrink:0}}), h('div',{key:'t',style:{fontSize:'2cqw',lineHeight:1.4,color:P.ink,fontWeight:500}}, p) ]); })
      ))]); }
    var pk=ctx.period||{}; var newThisWeek=measures.filter(function(m){ return m.created_kw===pk.no && m.created_year===pk.year; }).length;
    var canAdd=onM && newThisWeek<5;
    function dots(m){ return h('div',{style:{display:'flex',gap:'.5cqw'}}, ['open','in_progress','done'].map(function(k){ var s=MEAS_ST[k]; var on=m.status===k;
      return h('span',{key:k,onClick:function(){ onM({type:'status',id:m.id,status:k}); },title:s.l,style:{cursor:'pointer',width:'1.5cqw',height:'1.5cqw',borderRadius:'50%',background:on?s.c:'#fff',border:'.2cqw solid '+s.c,boxSizing:'border-box'}}); })); }
    var list=h('div',{key:'l',style:{flex:1,minHeight:0,overflowY:'auto',display:'flex',flexDirection:'column',gap:'.9cqw'}},
      measures.length? measures.map(function(m,i){ var s=MEAS_ST[m.status]||MEAS_ST.open;
        return h('div',{key:m.id||i,style:{display:'flex',gap:'1.2cqw',alignItems:'flex-start',padding:'1cqw 1.3cqw',borderRadius:'1cqw',background:s.bg,border:'1px solid '+rgba(s.c,.3)}},[
          h('div',{key:'st',style:{flexShrink:0,paddingTop:'.15cqw'}}, onM? dots(m) : h('span',{style:{display:'inline-block',width:'1.3cqw',height:'1.3cqw',borderRadius:'50%',background:s.c}})),
          h('div',{key:'b',style:{flex:1,minWidth:0}},[
            h('div',{key:'t',style:{fontSize:'1.7cqw',fontWeight:600,color:P.ink,lineHeight:1.3}}, m.text),
            onM? h('input',{key:'c'+(m.comment||''),defaultValue:m.comment||'',placeholder:'Kommentar…',onBlur:function(e){ if((e.target.value||'')!==(m.comment||'')) onM({type:'comment',id:m.id,comment:e.target.value}); },style:{marginTop:'.4cqw',width:'100%',boxSizing:'border-box',fontSize:'1.25cqw',padding:'.4cqw .6cqw',border:'1px solid '+rgba(s.c,.35),borderRadius:'.6cqw',background:'#fff',color:P.ink}})
              : (m.comment? h('div',{key:'c',style:{marginTop:'.3cqw',fontSize:'1.3cqw',color:P.muted}}, m.comment):null)
          ]),
          h('div',{key:'lb',style:{flexShrink:0,fontSize:'1.1cqw',fontWeight:800,color:s.c,alignSelf:'center'}}, s.l),
          onM? h('span',{key:'x',onClick:function(){ onM({type:'delete',id:m.id}); },title:'Entfernen',style:{cursor:'pointer',color:P.muted,fontSize:'1.5cqw',fontWeight:800,flexShrink:0,alignSelf:'center'}},'✕'):null
        ]);
      }) : [h('div',{key:'e',style:{color:P.muted,fontSize:'1.5cqw',textAlign:'center',padding:'2cqw'}}, onM?'Noch keine Maßnahmen — unten eintragen.':'Keine Maßnahmen hinterlegt.')]
    );
    var addRow = canAdd? h('div',{key:'a',style:{display:'flex',gap:'.8cqw',marginTop:'1cqw',flexShrink:0}},[
      h('input',{key:'i',value:newText,placeholder:'Neue Maßnahme (max. 5 je Woche)…',onChange:function(e){ setNewText(e.target.value); },onKeyDown:function(e){ if(e.key==='Enter'&&newText.trim()){ onM({type:'add',text:newText.trim()}); setNewText(''); } },style:{flex:1,fontSize:'1.4cqw',padding:'.6cqw .8cqw',border:'1px solid '+P.onLight,borderRadius:'.6cqw',background:'#fff',color:P.ink}}),
      h('span',{key:'b',onClick:function(){ if(newText.trim()){ onM({type:'add',text:newText.trim()}); setNewText(''); } },style:{cursor:'pointer',fontSize:'1.4cqw',fontWeight:800,color:'#fff',background:P.onLight,borderRadius:'.6cqw',padding:'.6cqw 1.2cqw',display:'flex',alignItems:'center'}},'+ Hinzufügen')
    ]) : (onM? h('div',{key:'cap',style:{marginTop:'.8cqw',fontSize:'1.1cqw',color:P.muted,flexShrink:0}},'Maximal 5 neue Maßnahmen je Woche erreicht.'):null);
    return Slide(ctx,[head, panel(P,[list, addRow])]);
  }
  // Folie 5 — Langzeit-Entwicklung, 12 Monate (voll manuell). deck.teams[tk].langzeit={year, rows:[{label, m:[12]}]}.
  function Langzeit(ctx, tk){ var P=pal(ctx.accent); var td=(ctx.deck.teams||{})[tk]||{}; var lbl=skillLabel(ctx,tk);
    var lz=td.langzeit||{}; var rows=lz.rows||[];
    var sm=((lz.startMonth||1)-1); var yr=lz.startYear||lz.year;
    var head=fondHead(P, lbl, 'Langzeit-Entwicklung', '12 Monate'+(yr?(' ab '+['Jan','Feb','Mär','Apr','Mai','Jun','Jul','Aug','Sep','Okt','Nov','Dez'][sm]+' '+yr):''));
    if(!rows.length) return emptyPanel(ctx,head,P,'Keine Langzeit-Daten hinterlegt.');
    var M0=['Jan','Feb','Mär','Apr','Mai','Jun','Jul','Aug','Sep','Okt','Nov','Dez']; var M=[]; for(var mi=0;mi<12;mi++) M.push(M0[(sm+mi)%12]); var colName='24cqw';
    var hdr=h('div',{key:'h',style:{display:'flex',alignItems:'flex-end',paddingBottom:'.5cqw',borderBottom:'1px solid #e6edef',fontSize:'1.05cqw',fontWeight:700,color:P.muted}},
      [h('div',{key:'n',style:{width:colName}},'')].concat(M.map(function(m,i){ return h('div',{key:i,style:{flex:1,textAlign:'center'}},m); })));
    function row(r,ri){ return h('div',{key:ri,style:{display:'flex',alignItems:'center',padding:'.3cqw 0',borderBottom:'1px solid #f6f8f9',fontSize:'1.15cqw',color:P.ink}},
      [h('div',{key:'n',style:{width:colName,fontWeight:600,whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'}},r.label||'')]
      .concat(M.map(function(m,i){ var v=(r.m||[])[i]; return h('div',{key:i,style:{flex:1,textAlign:'center',fontFamily:MONO,fontSize:'1.05cqw',color:(v===''||v==null)?'#cbd5e1':P.ink}}, (v===''||v==null)?'·':v); }))); }
    return Slide(ctx,[head, panel(P,[ h('div',{key:'t',style:{flex:1,minHeight:0,display:'flex',flexDirection:'column',overflow:'hidden'}}, [hdr].concat(rows.map(row))) ])]);
  }

  // Call-Reviews-Folie je Bericht schaltbar (ctx.callReviews). WICHTIG: deckSlides UND deckSlideKeys über
  // DENSELBEN Flag gaten → beide bleiben im Gleichschritt, die Keys der übrigen Folien verschieben sich nie.
  // Kommentar-Anker hängen am KEY (nicht an der Position); ein Kommentar auf einer ausgeblendeten Folie bleibt
  // in der DB und wird nur nicht angezeigt (kein Verlust, keine Fehlzuordnung).
  function deckShowCalls(ctx){ return ctx.callReviews!==false; }
  function hasCsat(ctx,k){ var td=(ctx.deck.teams||{})[k]||{}; return !!(td.csat&&td.csat.rows&&td.csat.rows.length); }
  function hasFte(ctx,k){ var td=(ctx.deck.teams||{})[k]||{}; return !!(td.fteList&&td.fteList.rows&&td.fteList.rows.length); }
  function hasStd(ctx,k){ var td=(ctx.deck.teams||{})[k]||{}; return (td.stunden||[]).some(function(r){ return r.kw!==''||r.plan!==''||r.geliefert!==''||r.rueck!==''; }); }
  function hasCr(ctx,k){ var td=(ctx.deck.teams||{})[k]||{}; return !!(td.cr&&td.cr.agents&&td.cr.agents.length); }
  function hasLangzeit(ctx,k){ var td=(ctx.deck.teams||{})[k]||{}; return !!(td.langzeit&&td.langzeit.rows&&td.langzeit.rows.length); }
  function hasCallsMtd(ctx,k){ var td=(ctx.deck.teams||{})[k]||{}; return !!(td.calls&&td.calls.monat&&Object.keys(td.calls.monat).length); }
  function hasMassnahmen(ctx,k){ var td=(ctx.deck.teams||{})[k]||{}; return !!((td.massnahmen||'').trim()) || !!(ctx.measures&&ctx.measures.length); }
  function hasFehlzeiten(ctx,k){ var td=(ctx.deck.teams||{})[k]||{}; return !!(td.fehlzeiten&&td.fehlzeiten.weeks&&td.fehlzeiten.weeks.length); }
  // Ein Skill kommt in den Bericht, wenn er IRGENDWELCHE Daten hat (verhindert leere Fremd-Skill-Folien, z. B.
  // "Support", wenn nur Sales gepflegt ist). Innerhalb eines aktiven Skills erscheinen ALLE 14 Kern-Folien in fester
  // Reihenfolge — fehlende Daten blenden eine Folie NICHT aus, sie zeigt einen ruhigen Hinweis. Skill kommt aus der
  // Schleife (skillLabel), nie handgetippt. Ist gar nichts gepflegt: erster Skill mit Hinweisen (leerer Rohbericht).
  function skillActive(ctx,k){ var td=(ctx.deck.teams||{})[k]||{};
    return hasFte(ctx,k)||hasStd(ctx,k)||hasCr(ctx,k)||hasCsat(ctx,k)||hasMassnahmen(ctx,k)||hasLangzeit(ctx,k)||hasFehlzeiten(ctx,k)||hasCallsMtd(ctx,k)||!!(td.calls&&td.calls.vorwoche&&Object.keys(td.calls.vorwoche).length); }
  function activeSkills(ctx){ var a=(ctx.skills||[]).filter(function(s){ return skillActive(ctx,s.key); }); return a.length?a:(ctx.skills||[]).slice(0,1); }
  // Agenten-Grafiken brechen bei zu vielen Personen automatisch auf Folgeseiten um (Folienzahl ergibt sich selbst,
  // nicht fest verdrahtet). Gleichmäßige Aufteilung: 17 Agenten → 2 Seiten à 9/8, nicht 15/2.
  var AGENT_PER_PAGE=10;
  function agentPages(list, cap){ list=list||[]; cap=cap||AGENT_PER_PAGE; var n=list.length; if(n<=cap) return [list]; var pages=Math.ceil(n/cap); var per=Math.ceil(n/pages); var out=[]; for(var i=0;i<n;i+=per) out.push(list.slice(i,i+per)); return out; }
  // Eligible-Call-Agenten (echte Answered-Zeile) — für Pagination-Count in skillPlan UND in CallsView identisch.
  function callsAgents(ctx, tk, period){ var td=(ctx.deck.teams||{})[tk]||{}; var cur=(td.calls&&td.calls[period])||{};
    var members=(ctx.membersOf(tk)||[]).filter(function(m){ return ((td.members||[]).length===0)||(td.members||[]).indexOf(m.id)>=0; });
    return members.filter(function(m){ var c=cur[m.id]; return c && c.answered!=null && String(c.answered).trim()!==''; }); }
  // Mini-Verlauf je Agent (kleine Vielfache) — geteilt von AHT (Support) und CR (Sales). value(a,w)=Balkenwert,
  // fmtAvg(a)=Ø-Text. head nur auf Seite 0 (Folgeseiten ohne Titel, wie in der Kundenvorlage).
  function AgentMultiples(ctx, tk, page, cfg){ page=page||0; var P=pal(ctx.accent); var lbl=skillLabel(ctx,tk);
    var agents=cfg.agents||[]; var weeks=cfg.weeks||[];
    if(!agents.length) return Slide(ctx,[ fondHead(P, lbl, cfg.title, cfg.eyebrow||''), pendingBody(ctx,P,cfg.emptyTitle||'Keine Daten',cfg.emptySub||'') ]);
    var pages=agentPages(agents); var pa=pages[page]||[];
    var all=[]; agents.forEach(function(a){ weeks.forEach(function(w){ var v=cfg.value(a,w); if(v!=null) all.push(v); }); });
    var dom=zoomDomain(all,0.4); var perRow=pa.length<=8?4:5;
    function mini(a){ return h('div',{key:a.id,style:{border:'1px solid #eef2f4',borderRadius:'1cqw',padding:'.9cqw 1cqw',display:'flex',flexDirection:'column',minWidth:0}},[
      h('div',{key:'n',style:{display:'flex',alignItems:'center',gap:'.4cqw',marginBottom:'.4cqw'}},[
        h('span',{key:'nm',style:{flex:1,fontSize:'1.1cqw',fontWeight:700,color:P.ink,whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'}},a.name),
        a.newbie?h('span',{key:'nb',style:{fontSize:'.72cqw',fontWeight:800,letterSpacing:'.06em',color:'#fff',background:P.onLight,borderRadius:'.4cqw',padding:'.05cqw .45cqw',flexShrink:0}},'NEU'):null
      ]),
      h('div',{key:'b',style:{display:'flex',alignItems:'flex-end',gap:'.4cqw',height:'6.5cqw'}}, weeks.map(function(w){ var v=cfg.value(a,w); var has=v!=null; var ht=has?Math.max(6,frac(v,dom)*100):0;
        return h('div',{key:w.key,style:{flex:1,display:'flex',flexDirection:'column',justifyContent:'flex-end',alignItems:'center',height:'100%'}},
          has? h('div',{style:{width:'100%',height:ht+'%',background:P.onLight,borderRadius:'.3cqw .3cqw 0 0'}})
             : h('div',{style:{width:'100%',height:'100%',display:'flex',alignItems:'center',justifyContent:'center'}}, h('div',{style:{width:'70%',borderTop:'2px dotted #cbd5e1'}}))); })),
      h('div',{key:'x',style:{display:'flex',gap:'.4cqw',marginTop:'.25cqw'}}, weeks.map(function(w){ return h('div',{key:w.key,style:{flex:1,textAlign:'center',fontFamily:MONO,fontSize:'.75cqw',color:P.muted}}, w.kw); })),
      h('div',{key:'avg',style:{marginTop:'.35cqw',fontFamily:MONO,fontSize:'1.05cqw',fontWeight:700,color:P.onLightTxt}}, 'Ø '+cfg.fmtAvg(a))
    ]); }
    var head=page===0?fondHead(P, lbl, cfg.title, (agents.length+' Agenten'+(pages.length>1?(' · '+pages.length+' Seiten'):''))):null;
    var body=[ h('div',{key:'g',style:{flex:1,minHeight:0,display:'grid',gridTemplateColumns:'repeat('+perRow+',1fr)',gap:'1.2cqw',overflow:'hidden',alignContent:'start'}}, pa.map(mini)),
      h('div',{key:'ft',style:{fontSize:'1cqw',color:P.muted,marginTop:'.8cqw'}}, cfg.foot+(pages.length>1?(' · Seite '+(page+1)+'/'+pages.length):'')+' · gepunktet = keine Daten') ];
    return Slide(ctx, [head, panel(P, body)].filter(Boolean));
  }
  function ahtMmss(s){ if(s==null) return '—'; s=Math.round(s); return Math.floor(s/60)+':'+(String(s%60).length<2?'0':'')+(s%60); }
  function CallAgentAht(ctx, tk, page){ var td=(ctx.deck.teams||{})[tk]||{}; var d=td.callaht||{};
    return AgentMultiples(ctx, tk, page, { agents:d.agents, weeks:d.weeks, title:'AHT je Agent · 5 Wochen',
      value:function(a,w){ var c=a.byWeek&&a.byWeek[w.key]; return (c&&c.aht!=null)?c.aht:null; },
      fmtAvg:function(a){ return ahtMmss(a.tot&&a.tot.aht); }, foot:'Balken = AHT je Woche (mm:ss)',
      emptyTitle:'AHT-Verlauf je Agent folgt', emptySub:'Wird mit „Aus Import übernehmen" (Calls) angebunden; bricht bei vielen Agenten automatisch um.' });
  }
  // ── Trennfolie je Bereich (z. B. „Support") + Abschluss „Thank you" ──
  function SectionDivider(ctx, label){ var P=pal(ctx.accent);
    return Slide(ctx, h('div',{style:{flex:1,display:'flex',flexDirection:'column',justifyContent:'center'}},[
      h('div',{key:'e',style:{fontFamily:MONO,fontSize:'1.6cqw',letterSpacing:'.24em',textTransform:'uppercase',color:rgba(P.fondText,.55),fontWeight:600}},'Bereich'),
      h('div',{key:'t',style:{fontSize:'8cqw',fontWeight:800,letterSpacing:'-.03em',color:P.fondText,lineHeight:1.02,marginTop:'1cqw'}},label),
      h('div',{key:'r',style:{width:'12cqw',height:'.5cqw',background:P.onLight,borderRadius:'.5cqw',marginTop:'2.4cqw'}})
    ]));
  }
  function ThankYou(ctx){ var P=pal(ctx.accent);
    return Slide(ctx, h('div',{style:{flex:1,display:'flex',flexDirection:'column',justifyContent:'center'}},[
      h('div',{key:'t',style:{fontSize:'8cqw',fontWeight:800,letterSpacing:'-.03em',color:P.fondText,lineHeight:1.02}},'Danke'),
      h('div',{key:'s',style:{fontSize:'2.2cqw',color:rgba(P.fondText,.72),marginTop:'2cqw',fontWeight:500}}, (ctx.projName||'')+' · KW '+ctx.period.no+' / '+ctx.period.year)
    ]));
  }
  // Ruhiger Platzhalter-Body (gleiche Optik wie die „keine Daten"-Folien) — für noch nicht angebundene Daten.
  function pendingBody(ctx, P, title, sub){ return panel(P, h('div',{style:{flex:1,display:'flex',alignItems:'center',justifyContent:'center',textAlign:'center'}}, h('div',{},[
    h('div',{key:'t',style:{fontSize:'2.4cqw',fontWeight:800,color:P.ink}},title),
    h('div',{key:'s',style:{fontSize:'1.5cqw',marginTop:'1cqw',color:P.muted,maxWidth:'56cqw',lineHeight:1.4}},sub)
  ]))); }
  // Mail-KPIs (Vorwoche/Monat) — Struktur steht, Daten folgen. Newbies (Start ≤ Grenze) werden hier markiert.
  function MailKpis(ctx, tk, mode){ var P=pal(ctx.accent); var lbl=skillLabel(ctx,tk);
    return Slide(ctx,[ fondHead(P, lbl+' · '+(mode==='monat'?'Monat (MTD)':'Vorwoche'), 'Mail-Kennzahlen'),
      pendingBody(ctx, P, 'Mail-Kennzahlen folgen', 'Die Mail-Daten werden noch angebunden. Neue Mitarbeiter (Start ≤ 8 Wochen) werden hier gekennzeichnet.') ]);
  }
  function MailAgentTrend(ctx, tk){ var P=pal(ctx.accent); var lbl=skillLabel(ctx,tk);
    return Slide(ctx,[ fondHead(P, lbl, 'Mail je Agent · 5 Wochen'),
      pendingBody(ctx, P, 'Mail-Verlauf je Agent folgt', 'Folgt mit den Mail-Daten; bricht bei vielen Agenten automatisch um.') ]);
  }
  // EINE Wahrheit für Folienreihenfolge + Anker-Keys je Skill. Sales-Set (mit CR) ≠ Support-Set (mit Mail).
  function skillPlan(ctx, k){ var L=skillLabel(ctx,k); var kind=(k==='sales')?'sales':'support'; var p=[]; var td=(ctx.deck.teams||{})[k]||{};
    function add(key,label,fn){ p.push({key:k+':'+key, label:L+' · '+label, fn:fn}); }
    // Paginierter Eintrag: n Seiten (≥1), Folgeseiten „(Forts.)" mit eigenem Key — Umbruch statt Abschneiden.
    function addPaged(baseKey,label,n,fn){ for(var pi=0;pi<Math.max(1,n);pi++){ (function(pi){ add(baseKey+(pi?':'+pi:''), label+(pi?' (Forts.)':''), function(){ return fn(pi); }); })(pi); } }
    addPaged('fte','FTE', ftePages(ctx,k), function(pi){ return Fte(ctx,k,pi); });
    add('stundentab','Stunden (Tabelle)',function(){return StundenTable(ctx,k);});
    add('stunden','Stunden',function(){return Stunden(ctx,k);});
    if(hasFehlzeiten(ctx,k)) add('fehlzeiten','Fehlzeiten',function(){return Fehlzeiten(ctx,k);});
    add('langzeit','Langzeit',function(){return Langzeit(ctx,k);});
    if(kind==='sales'){
      add('crtab','CR (Tabelle)',function(){return CrTable(ctx,k);});
      add('crchart','CR (Verlauf)',function(){return CrChart(ctx,k);});
      add('agentcr','CR je Agent',function(){return AgentCr(ctx,k);});
      addPaged('agentcrtrend','CR-Verlauf je Agent', agentPages((td.cr||{}).agents||[]).length, function(pi){ return AgentCrTrend(ctx,k,pi); });
      add('mtd','MTD',function(){return Mtd(ctx,k);});
      addPaged('calls','Calls (Vorwoche)', agentPages(callsAgents(ctx,k,'vorwoche'),14).length, function(pi){ return Calls(ctx,k,pi); });
      addPaged('callsmtd','Calls (Monat)', agentPages(callsAgents(ctx,k,'monat'),14).length, function(pi){ return CallsMtd(ctx,k,pi); });
    } else {
      addPaged('calls','Calls (Vorwoche)', agentPages(callsAgents(ctx,k,'vorwoche'),14).length, function(pi){ return Calls(ctx,k,pi); });
      addPaged('callsmtd','Calls (Monat)', agentPages(callsAgents(ctx,k,'monat'),14).length, function(pi){ return CallsMtd(ctx,k,pi); });
      addPaged('callaht','AHT je Agent', agentPages((td.callaht||{}).agents||[]).length, function(pi){ return CallAgentAht(ctx,k,pi); });
      add('mailvorwoche','Mail (Vorwoche)',function(){return MailKpis(ctx,k,'vorwoche');});
      add('mailmonat','Mail (Monat)',function(){return MailKpis(ctx,k,'monat');});
      add('mailagent','Mail je Agent',function(){return MailAgentTrend(ctx,k);});
    }
    if(deckShowCalls(ctx)) add('callscores','Call-Qualität',function(){return CallScores(ctx,k);});
    addPaged('csat','CSAT', agentPages((td.csat||{}).rows||[],11).length, function(pi){ return Csat(ctx,k,pi); });
    add('massnahmen','Maßnahmen',function(){return Massnahmen(ctx,k);});
    return p;
  }
  function deckSlides(ctx){ var out=[Title(ctx)]; activeSkills(ctx).forEach(function(s,i){ var k=s.key;
    if(i>0) out.push(SectionDivider(ctx, skillLabel(ctx,k)));
    skillPlan(ctx,k).forEach(function(it){ out.push(it.fn()); });
  }); out.push(ThankYou(ctx)); return out; }
  // Folien-Identität (für Kommentar-Anker) — dieselbe Reihenfolge/Quelle wie deckSlides.
  function deckSlideKeys(ctx){ var out=[{key:'title',label:'Titel'}]; activeSkills(ctx).forEach(function(s,i){ var k=s.key, L=skillLabel(ctx,k);
    if(i>0) out.push({key:'divider:'+k, label:L+' · Trenner'});
    skillPlan(ctx,k).forEach(function(it){ out.push({key:it.key, label:it.label}); });
  }); out.push({key:'thankyou', label:'Abschluss'}); return out; }

  window.PRES = { deckSlides:deckSlides, deckSlideKeys:deckSlideKeys, Title:Title, Fte:Fte, StundenTable:StundenTable, Stunden:Stunden, Fehlzeiten:Fehlzeiten, Langzeit:Langzeit, CrTable:CrTable, CrChart:CrChart, AgentCr:AgentCr, AgentCrTrend:AgentCrTrend, Mtd:Mtd, Calls:Calls, CallsMtd:CallsMtd, Massnahmen:Massnahmen, CallScores:CallScores, Csat:Csat, SectionDivider:SectionDivider, ThankYou:ThankYou, MailKpis:MailKpis, CallAgentAht:CallAgentAht, MailAgentTrend:MailAgentTrend, callCols:callCols, pal:pal,
    fmtNum:fmtNum, numOr:numOr, pctDiff:pctDiff, wavgTime:wavgTime, sumCol:sumCol, decToMmss:decToMmss, mmssToDec:mmssToDec };
})();
