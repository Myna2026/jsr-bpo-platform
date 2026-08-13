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
  function zoomDomain(vals,pad){ pad=(pad==null)?0.55:pad;
    var xs=(vals||[]).map(function(v){ return numOr(v,NaN); }).filter(function(v){ return !isNaN(v); });
    if(!xs.length) return {lo:0,hi:1,zoomed:false};
    var mn=Math.min.apply(null,xs), mx=Math.max.apply(null,xs), span=mx-mn;
    if(span<=0) return {lo:0,hi:mx||1,zoomed:false};
    return {lo:Math.max(0,mn-span*pad), hi:mx, zoomed:true};
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

  // Folie 2 — Besetzung & FTE. Daten in deck.teams[tk].fteList = {rows:[{id,name,fte}], total, _src}.
  function Fte(ctx, tk){ var P=pal(ctx.accent); var td=(ctx.deck.teams||{})[tk]||{}; var lbl=skillLabel(ctx,tk);
    var fl=td.fteList||{}; var rows=fl.rows||[]; var total=(fl.total!=null)?fl.total:numOr(td.fte,null);
    var head=fondHead(P, lbl, 'Besetzung & FTE', rows.length?(rows.length+' Mitarbeiter'):'');
    if(!rows.length){ return Slide(ctx,[head, panel(P, h('div',{style:{flex:1,display:'flex',alignItems:'center',justifyContent:'center',textAlign:'center'}}, h('div',{},[
      h('div',{key:'t',style:{fontSize:'2.4cqw',fontWeight:800,color:P.ink}},'Keine Besetzung übernommen'),
      h('div',{key:'s',style:{fontSize:'1.4cqw',marginTop:'1cqw',color:P.muted}},'FTE-Standard je Mitarbeiter pflegen und übernehmen.')
    ])))]); }
    var cols3=rows.length>8?3:(rows.length>4?2:1); var per=Math.ceil(rows.length/cols3); var groups=[]; for(var g=0;g<cols3;g++) groups.push(rows.slice(g*per,(g+1)*per));
    return Slide(ctx, [ head, panel(P, [
      h('div',{key:'top',style:{display:'flex',alignItems:'baseline',gap:'1.4cqw',marginBottom:'2cqw',flexShrink:0}},[
        h('span',{key:'n',style:{fontSize:'6cqw',fontWeight:800,color:P.onLightTxt,lineHeight:1,fontVariantNumeric:'tabular-nums'}}, total==null?'—':fmtNum(total,2)),
        h('span',{key:'l',style:{fontSize:'1.7cqw',fontWeight:700,color:P.muted}},'FTE gesamt')
      ]),
      h('div',{key:'grid',style:{flex:1,minHeight:0,display:'flex',gap:'3.5cqw',overflow:'hidden'}},
        groups.map(function(grp,gi){ return h('div',{key:gi,style:{flex:1,minWidth:0,display:'flex',flexDirection:'column',gap:'.5cqw'}},
          grp.map(function(r,ri){ return h('div',{key:r.id||ri,style:{display:'flex',alignItems:'center',justifyContent:'space-between',gap:'1cqw',padding:'.45cqw 0',borderBottom:'1px solid #f1f5f9'}},[
            h('span',{key:'n',style:{fontSize:'1.4cqw',fontWeight:600,color:P.ink,whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'}},r.name),
            h('span',{key:'f',style:{fontFamily:MONO,fontSize:'1.4cqw',fontWeight:700,color:P.onLightTxt,flexShrink:0}},fmtNum(r.fte,2))
          ]); })
        ); })
      )
    ]) ]);
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

  function Calls(ctx, tk){ var P=pal(ctx.accent); var td=(ctx.deck.teams||{})[tk]||{}; var lbl=skillLabel(ctx,tk); var cols=callCols(tk);
    var members=(ctx.membersOf(tk)||[]).filter(function(m){ return ((td.members||[]).length===0)||(td.members||[]).indexOf(m.id)>=0; });
    var cur=(td.calls&&td.calls.vorwoche)||{};
    var rows=members.map(function(m){ var c=cur[m.id]||{}; return Object.assign({},c,{answered:c.answered}); });
    var ans=members.map(function(m){ return {m:m,n:numOr((cur[m.id]||{}).answered,0)}; }).sort(function(a,b){ return b.n-a.n; });
    var dom=zoomDomain(ans.map(function(a){ return a.n; }));   // gespreizte Skala: nahe Werte sichtbar unterscheiden
    var htCol=cols.filter(function(c){ return /handle|aht/i.test(c.k); })[0]; var htKey=htCol?htCol.k:'avg_handle';
    return Slide(ctx, [
      fondHead(P, lbl+' · Vorwoche', 'Call-Kennzahlen'),
      panel(P, (function(){
        // Liste = Inhalt. Kopfzahlen KOMPAKT einzeilig (nicht zwei große Blöcke). Bei >7 MA zwei Spalten,
        // damit auch 15 Zeilen (Support) mit lesbarem Abstand passen — feste Zeilenhöhe, nicht flex-gestaucht.
        var shown=ans.slice(0,16), twoCol=shown.length>7, half=Math.ceil(shown.length/2);
        var colGroups=twoCol?[shown.slice(0,half),shown.slice(half)]:[shown];
        var nameW=twoCol?'12cqw':'20cqw';
        function stat(val,lbl,col){ return h('div',{style:{display:'flex',alignItems:'baseline',gap:'.9cqw'}},[
          h('span',{key:'n',style:{fontSize:'3.4cqw',fontWeight:800,color:col,lineHeight:1,fontVariantNumeric:'tabular-nums'}},val),
          h('span',{key:'l',style:{fontSize:'1.15cqw',color:P.muted,fontWeight:700}},lbl) ]); }
        function rankRow(o,rank){ var w=Math.max(6,frac(o.n,dom)*100);
          return h('div',{key:o.m.id,style:{display:'flex',alignItems:'center',gap:'1.2cqw'}},[
            h('span',{key:'r',style:{width:'2.2cqw',textAlign:'right',fontFamily:MONO,fontSize:'1.1cqw',fontWeight:700,color:P.muted,flexShrink:0}},rank+'.'),
            h('span',{key:'n',style:{width:nameW,fontSize:'1.25cqw',fontWeight:600,color:P.ink,whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis',flexShrink:0}},o.m.name),
            h('div',{key:'b',style:{flex:1,height:'0.85cqw',background:'#eef2f4',borderRadius:'.5cqw',overflow:'hidden'}}, h('div',{style:{width:w+'%',height:'100%',background:P.onLight,borderRadius:'.5cqw'}})),
            h('span',{key:'v',style:{width:'5cqw',textAlign:'right',fontFamily:MONO,fontWeight:700,fontSize:'1.25cqw',color:P.ink,flexShrink:0}},fmtNum(o.n))
          ]); }
        return [
          h('div',{key:'big',style:{display:'flex',gap:'4.5cqw',alignItems:'baseline',flexWrap:'wrap',marginBottom:'2cqw',flexShrink:0}},[
            stat(fmtNum(sumCol(rows,'answered')),'Answered gesamt',P.onLightTxt),
            stat(wavgTime(rows,htKey,'answered'),'Ø Handle (gew.)',P.ink)
          ]),
          h('div',{key:'list',style:{flex:1,minHeight:0,display:'flex',gap:'4.5cqw',overflow:'hidden'}},
            ans.length===0 ? [h('div',{key:'e',style:{color:P.muted,fontSize:'1.4cqw'}},'Keine Mitarbeiter.')]
            : colGroups.map(function(colRows,ci){ return h('div',{key:ci,style:{flex:1,minWidth:0,display:'flex',flexDirection:'column',gap:'.7cqw',justifyContent:colRows.length<=5?'center':'flex-start'}},
                colRows.map(function(o,ri){ return rankRow(o, ci*half+ri+1); })
              ); })
          ),
          dom.zoomed?h('div',{key:'scale',style:{fontFamily:MONO,fontSize:'1cqw',color:P.muted,opacity:.8,marginTop:'1cqw',textAlign:'right',flexShrink:0}},'Balkenskala ab '+fmtNum(dom.lo)+' (gespreizt) · exakte Werte am Balken'):null
        ];
      })())
    ]);
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
    var meta=count?((count)+' Stichprobe'+(count>1?'n':'')+avgTxt):'';
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
        h('span',{key:'n',style:{flex:1,minWidth:0,fontSize:'1.5cqw',fontWeight:600,color:P.ink,whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'}},e.name),
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
  function Csat(ctx, tk){ var P=pal(ctx.accent); var td=(ctx.deck.teams||{})[tk]||{}; var lbl=skillLabel(ctx,tk);
    var cs=td.csat||{}; var weeks=cs.weeks||[]; var rows=cs.rows||[];
    var rangeTxt=weeks.length?('KW '+weeks[0].kw+' – KW '+weeks[weeks.length-1].kw):'';
    var head=fondHead(P, lbl+' · CSAT', 'Kundenzufriedenheit', rangeTxt);
    if(!rows.length){ return Slide(ctx,[head, panel(P, h('div',{style:{flex:1,display:'flex',alignItems:'center',justifyContent:'center',textAlign:'center'}}, h('div',{},[
      h('div',{key:'t',style:{fontSize:'2.4cqw',fontWeight:800,color:P.ink}},'Keine CSAT-Daten in diesem Zeitraum'),
      h('div',{key:'s',style:{fontSize:'1.4cqw',marginTop:'1cqw',color:P.muted}},'Für '+lbl+' liegen keine Gauges-/CSAT-Werte vor.')
    ])))]); }
    function wavg(list){ var sv=0,sn=0; (list||[]).forEach(function(c){ if(c&&c.v!=null){ var n=(c.n||0)||1; sv+=c.v*n; sn+=n; } }); return sn?sv/sn:null; }
    var teamWeek={}; weeks.forEach(function(w){ teamWeek[w.key]=wavg(rows.map(function(r){ return r.cells[w.key]; })); });
    var teamAvg=wavg(rows.map(function(r){ return {v:r.avg,n:1}; }));
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
    var body=rows.map(function(r,i){ return h('div',{key:r.id||i,style:{display:'flex',alignItems:'center',gap:'1cqw',padding:'.4cqw 0',borderBottom:'1px solid #f1f5f9'}},
      [h('div',{key:'n',style:{width:colName,fontSize:'1.35cqw',fontWeight:600,color:P.ink,whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'}},r.name)]
      .concat(weeks.map(function(w){ return valCell(r.cells[w.key]); }))
      .concat([h('div',{key:'avg',style:{flex:1,textAlign:'center',fontFamily:MONO,fontSize:'1.6cqw',fontWeight:800,color:P.onLightTxt}}, r.avg==null?'—':fmtNum(r.avg,1))])); });
    var teamRow=h('div',{key:'team',style:{display:'flex',alignItems:'center',gap:'1cqw',paddingTop:'.7cqw',marginTop:'.2cqw',borderTop:'2px solid '+P.onLight}},
      [h('div',{key:'n',style:{width:colName,fontSize:'1.35cqw',fontWeight:800,color:P.ink}},'Team Ø')]
      .concat(weeks.map(function(w){ var v=teamWeek[w.key]; return h('div',{key:w.key,style:{flex:1,textAlign:'center',fontFamily:MONO,fontSize:'1.5cqw',fontWeight:800,color:P.ink}}, v==null?'—':fmtNum(v,1)); }))
      .concat([h('div',{key:'avg',style:{flex:1,textAlign:'center',fontFamily:MONO,fontSize:'1.7cqw',fontWeight:800,color:P.onLightTxt}}, teamAvg==null?'—':fmtNum(teamAvg,1))]));
    return Slide(ctx, [ head, panel(P, [
      h('div',{key:'tbl',style:{flex:1,minHeight:0,display:'flex',flexDirection:'column',overflow:'hidden'}}, [headerRow].concat(body).concat([teamRow])),
      h('div',{key:'ft',style:{fontSize:'1.1cqw',color:P.muted,marginTop:'1cqw'}},'CSAT je Mitarbeiter und Woche · n = Anzahl Bewertungen · Ø gewichtet nach n')
    ]) ]);
  }

  // Call-Reviews-Folie je Bericht schaltbar (ctx.callReviews). WICHTIG: deckSlides UND deckSlideKeys über
  // DENSELBEN Flag gaten → beide bleiben im Gleichschritt, die Keys der übrigen Folien verschieben sich nie.
  // Kommentar-Anker hängen am KEY (nicht an der Position); ein Kommentar auf einer ausgeblendeten Folie bleibt
  // in der DB und wird nur nicht angezeigt (kein Verlust, keine Fehlzuordnung).
  function deckShowCalls(ctx){ return ctx.callReviews!==false; }
  function hasCsat(ctx,k){ var td=(ctx.deck.teams||{})[k]||{}; return !!(td.csat&&td.csat.rows&&td.csat.rows.length); }
  function hasFte(ctx,k){ var td=(ctx.deck.teams||{})[k]||{}; return !!(td.fteList&&td.fteList.rows&&td.fteList.rows.length); }
  function hasStd(ctx,k){ var td=(ctx.deck.teams||{})[k]||{}; return (td.stunden||[]).some(function(r){ return r.kw!==''||r.plan!==''||r.geliefert!==''||r.rueck!==''; }); }
  function deckSlides(ctx){ var out=[Title(ctx)]; (ctx.skills||[]).forEach(function(s){ var k=s.key;
    if(hasFte(ctx,k)) out.push(Fte(ctx,k));
    if(hasStd(ctx,k)) out.push(StundenTable(ctx,k));
    out.push(Stunden(ctx,k)); out.push(Calls(ctx,k));
    if(deckShowCalls(ctx)) out.push(CallScores(ctx,k));
    if(hasCsat(ctx,k)) out.push(Csat(ctx,k));
  }); return out; }
  // Folien-Identität (für Kommentar-Anker) — dieselbe Reihenfolge wie deckSlides.
  function deckSlideKeys(ctx){ var out=[{key:'title',label:'Titel'}]; (ctx.skills||[]).forEach(function(s){ var k=s.key, L=skillLabel(ctx,k);
    if(hasFte(ctx,k)) out.push({key:k+':fte',label:L+' · FTE'});
    if(hasStd(ctx,k)) out.push({key:k+':stundentab',label:L+' · Stunden (Tabelle)'});
    out.push({key:k+':stunden',label:L+' · Stunden'}); out.push({key:k+':calls',label:L+' · Calls'});
    if(deckShowCalls(ctx)) out.push({key:k+':callscores',label:L+' · Call-Qualität'});
    if(hasCsat(ctx,k)) out.push({key:k+':csat',label:L+' · CSAT'});
  }); return out; }

  window.PRES = { deckSlides:deckSlides, deckSlideKeys:deckSlideKeys, Title:Title, Fte:Fte, StundenTable:StundenTable, Stunden:Stunden, Calls:Calls, CallScores:CallScores, Csat:Csat, callCols:callCols, pal:pal,
    fmtNum:fmtNum, numOr:numOr, pctDiff:pctDiff, wavgTime:wavgTime, sumCol:sumCol, decToMmss:decToMmss, mmssToDec:mmssToDec };
})();
