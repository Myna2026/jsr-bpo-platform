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

  var CALL_COLS = {
    sales:   [{k:'no_answer',l:'No Answer',t:'count'},{k:'answered',l:'Answered',t:'count'},{k:'outbound',l:'Outbound',t:'count'},{k:'avg_talk',l:'Avg Talk',t:'time'},{k:'avg_acw',l:'Avg ACW',t:'time'},{k:'avg_handle',l:'Avg Handle',t:'time'},{k:'avg_hold',l:'Avg Hold',t:'time'}],
    support: [{k:'answered',l:'Answered',t:'count'},{k:'outbound',l:'Outbound',t:'count'},{k:'tel_hours',l:'Std. Telefonie',t:'num'},{k:'aht',l:'AHT',t:'time'},{k:'att',l:'ATT',t:'time'},{k:'hold',l:'HOLD',t:'time'},{k:'acw',l:'ACW',t:'time'}]
  };
  function callCols(t){ return CALL_COLS[t]||CALL_COLS.sales; }

  function Slide(ctx, label, children){
    var kids=[
      h('div',{key:'bar',style:{position:'absolute',top:0,left:0,width:6,height:'100%',background:ctx.accent}}),
      label?h('div',{key:'lbl',style:{position:'absolute',top:14,right:18,fontSize:11,fontWeight:700,letterSpacing:'.12em',textTransform:'uppercase',color:'#94a3b8'}},label):null,
      (ctx.customerLogo||ctx.ourLogo)?h('div',{key:'logos',style:{position:'absolute',bottom:14,right:18,display:'flex',gap:14,alignItems:'center',opacity:.92}},[
        ctx.customerLogo?h('img',{key:'c',src:ctx.customerLogo,alt:'',style:{height:26,maxWidth:130,objectFit:'contain'}}):null,
        ctx.ourLogo?h('img',{key:'o',src:ctx.ourLogo,alt:'',style:{height:20,maxWidth:110,objectFit:'contain'}}):null
      ]):null,
      h('div',{key:'body',style:{position:'absolute',inset:0,padding:'clamp(20px,4vw,52px)',display:'flex',flexDirection:'column'}},children),
      ctx.dummy?h('div',{key:'wm',style:{position:'absolute',inset:0,display:'flex',alignItems:'center',justifyContent:'center',pointerEvents:'none'}},h('span',{style:{transform:'rotate(-24deg)',fontSize:'clamp(44px,11vw,130px)',fontWeight:900,color:'rgba(220,38,38,.10)',letterSpacing:'.1em'}},'BEISPIEL')):null
    ];
    return h('div',{className:'pres-slide',style:{position:'relative',aspectRatio:'16 / 9',background:'#fff',border:'1px solid #e5e7eb',borderRadius:14,boxShadow:'0 6px 24px rgba(15,23,42,.08)',overflow:'hidden',marginBottom:20,fontFamily:ctx.font||'inherit'}}, kids);
  }

  function Title(ctx){ var t=(ctx.deck&&ctx.deck.titel)||{};
    return Slide(ctx, ctx.projName, h('div',{style:{flex:1,display:'flex',flexDirection:'column',justifyContent:'center'}},[
      h('div',{key:'a',style:{width:64,height:8,background:ctx.accent,borderRadius:4,marginBottom:'clamp(14px,3vh,34px)'}}),
      h('div',{key:'b',style:{fontSize:'clamp(28px,5.5vw,68px)',fontWeight:800,lineHeight:1.05,color:'#0f172a',letterSpacing:'-.02em'}},'Weekly Performance Review'),
      h('div',{key:'c',style:{fontSize:'clamp(16px,2.6vw,30px)',fontWeight:600,color:ctx.accent,marginTop:'clamp(6px,1.5vh,16px)'}}, ctx.projName+(t.untertitel?(' · '+t.untertitel):'')),
      h('div',{key:'d',style:{marginTop:'auto',display:'flex',gap:'clamp(18px,4vw,48px)',flexWrap:'wrap',fontSize:'clamp(11px,1.5vw,15px)',color:'#94a3b8',fontWeight:600}},[
        h('span',{key:'k'},'KW '+ctx.period.no+' / '+ctx.period.year),
        t.datum?h('span',{key:'dt'},t.datum):null,
        t.ansprech?h('span',{key:'ap'},t.ansprech):null
      ])
    ]));
  }

  function Stunden(ctx, tk){ var td=(ctx.deck.teams||{})[tk]||{}; var lbl=skillLabel(ctx,tk);
    var rows=(td.stunden||[]).filter(function(r){ return r.kw!==''||r.plan!==''||r.geliefert!==''; });
    var vals=[]; rows.forEach(function(r){ vals.push(numOr(r.plan,0),numOr(r.rueck,0),numOr(r.geliefert,0)); });
    var mx=Math.max.apply(null,[1].concat(vals)); var W=760,H=230,pad=30,bw=rows.length?(W-pad*2)/rows.length:0;
    var bar3=[{k:'plan',c:'#cbd5e1',l:'Plan'},{k:'rueck',c:ctx.accent+'99',l:'Rückm.'},{k:'geliefert',c:ctx.accent,l:'Geliefert'}];
    return Slide(ctx, lbl+' · Stunden', [
      h('div',{key:'t',style:{fontSize:'clamp(18px,3vw,34px)',fontWeight:800,color:'#0f172a'}},['Gelieferte Stunden ',h('span',{key:'s',style:{color:ctx.accent}},'· '+lbl)]),
      h('div',{key:'sub',style:{fontSize:'clamp(11px,1.4vw,14px)',color:'#94a3b8',marginBottom:'clamp(8px,2vh,18px)'}},'Plan / Rückmeldung / Geliefert über '+(rows.length||5)+' Wochen'),
      h('div',{key:'chart',style:{flex:1,minHeight:0}}, h('svg',{viewBox:'0 0 '+W+' '+(H+26),style:{width:'100%',height:'100%'},preserveAspectRatio:'xMidYMid meet'},
        rows.map(function(r,i){ var x0=pad+i*bw; return h('g',{key:i},[].concat(
          bar3.map(function(b,bi){ var v=numOr(r[b.k],0); var hh=Math.max(1,v/mx*H); var w=(bw-14)/3; var x=x0+7+bi*w; return h('rect',{key:bi,x:x,y:H-hh,width:w-3,height:hh,rx:'2',fill:b.c}); }),
          [h('text',{key:'l',x:x0+bw/2,y:H+16,textAnchor:'middle',fontSize:'12',fill:'#64748b'},'KW '+(r.kw||'—'))]
        )); })
      )),
      h('div',{key:'pc',style:{display:'flex',gap:'clamp(10px,2vw,26px)',flexWrap:'wrap',marginTop:'clamp(8px,2vh,16px)'}},
        rows.map(function(r,i){ var pc=pctDiff(r.geliefert,r.rueck); return h('div',{key:i,style:{fontSize:'clamp(10px,1.3vw,13px)'}},[
          h('span',{key:'k',style:{color:'#94a3b8',fontWeight:700}},'KW '+(r.kw||'—')+': '),
          h('b',{key:'v',style:{color:pc==null?'#64748b':pc<0?'#dc2626':'#059669'}}, pc==null?'—':((pc>0?'+':'')+fmtNum(pc,1)+' %')),
          r.erkl?h('span',{key:'e',style:{color:'#64748b'}},' · '+r.erkl):null
        ]); })
      ),
      h('div',{key:'leg',style:{display:'flex',gap:14,marginTop:10,fontSize:11,color:'#94a3b8'}}, bar3.map(function(b){ return h('span',{key:b.k,style:{display:'inline-flex',alignItems:'center',gap:5}},[h('span',{key:'d',style:{width:11,height:11,borderRadius:2,background:b.c}}),b.l]); }))
    ]);
  }

  function Calls(ctx, tk){ var td=(ctx.deck.teams||{})[tk]||{}; var lbl=skillLabel(ctx,tk); var cols=callCols(tk);
    var members=(ctx.membersOf(tk)||[]).filter(function(m){ return ((td.members||[]).length===0)||(td.members||[]).indexOf(m.id)>=0; });
    var cur=(td.calls&&td.calls.vorwoche)||{};
    var rows=members.map(function(m){ var c=cur[m.id]||{}; return Object.assign({},c,{answered:c.answered}); });
    var ans=members.map(function(m){ return {m:m,n:numOr((cur[m.id]||{}).answered,0)}; }).sort(function(a,b){ return b.n-a.n; });
    var mx=Math.max.apply(null,[1].concat(ans.map(function(a){return a.n;})));
    var htCol=cols.filter(function(c){ return /handle|aht/i.test(c.k); })[0]; var htKey=htCol?htCol.k:'avg_handle';
    return Slide(ctx, lbl+' · Calls', [
      h('div',{key:'t',style:{fontSize:'clamp(18px,3vw,34px)',fontWeight:800,color:'#0f172a'}},['Call-Kennzahlen ',h('span',{key:'s',style:{color:ctx.accent}},'· '+lbl),' ',h('span',{key:'w',style:{fontSize:'.5em',color:'#94a3b8',fontWeight:600}},'Vorwoche')]),
      h('div',{key:'big',style:{display:'flex',gap:'clamp(16px,4vw,48px)',margin:'clamp(8px,2vh,18px) 0 clamp(10px,2vh,20px)',flexWrap:'wrap'}},[
        h('div',{key:'a'},[h('div',{key:'n',style:{fontSize:'clamp(26px,5vw,56px)',fontWeight:800,color:ctx.accent,lineHeight:1}},fmtNum(sumCol(rows,'answered'))),h('div',{key:'l',style:{fontSize:11,color:'#94a3b8',fontWeight:700}},'Answered gesamt')]),
        h('div',{key:'b'},[h('div',{key:'n',style:{fontSize:'clamp(26px,5vw,56px)',fontWeight:800,color:'#0f172a',lineHeight:1}},wavgTime(rows,htKey,'answered')),h('div',{key:'l',style:{fontSize:11,color:'#94a3b8',fontWeight:700}},'Ø Handle (gew.)')])
      ]),
      h('div',{key:'bars',style:{flex:1,minHeight:0,overflow:'hidden',display:'flex',flexDirection:'column',gap:'clamp(4px,1vh,9px)'}},
        ans.slice(0,10).map(function(o){ return h('div',{key:o.m.id,style:{display:'flex',alignItems:'center',gap:10}},[
          h('span',{key:'n',style:{width:'clamp(90px,14vw,150px)',fontSize:'clamp(10px,1.3vw,13px)',fontWeight:600,whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'}},o.m.name),
          h('div',{key:'b',style:{flex:1,height:'clamp(12px,2vh,18px)',background:'#f1f5f9',borderRadius:4,overflow:'hidden'}}, h('div',{style:{width:(o.n/mx*100)+'%',height:'100%',background:ctx.accent,borderRadius:4}})),
          h('span',{key:'v',style:{width:44,textAlign:'right',fontFamily:'monospace',fontWeight:700,fontSize:'clamp(10px,1.3vw,13px)'}},fmtNum(o.n))
        ]); }).concat(ans.length===0?[h('div',{key:'e',style:{color:'#94a3b8'}},'Keine Mitarbeiter.')]:[]))
    ]);
  }

  function skillLabel(ctx, key){ var s=(ctx.skills||[]).filter(function(x){return x.key===key;})[0]; if(s) return s.label||s.key; return key==='sales'?'Sales':key==='support'?'Support':key; }

  function deckSlides(ctx){ var out=[Title(ctx)]; (ctx.skills||[]).forEach(function(s){ out.push(Stunden(ctx,s.key)); out.push(Calls(ctx,s.key)); }); return out; }
  // Folien-Identität (für Kommentar-Anker) — dieselbe Reihenfolge wie deckSlides.
  function deckSlideKeys(ctx){ var out=[{key:'title',label:'Titel'}]; (ctx.skills||[]).forEach(function(s){ out.push({key:s.key+':stunden',label:skillLabel(ctx,s.key)+' · Stunden'}); out.push({key:s.key+':calls',label:skillLabel(ctx,s.key)+' · Calls'}); }); return out; }

  window.PRES = { deckSlides:deckSlides, deckSlideKeys:deckSlideKeys, Title:Title, Stunden:Stunden, Calls:Calls, callCols:callCols,
    fmtNum:fmtNum, numOr:numOr, pctDiff:pctDiff, wavgTime:wavgTime, sumCol:sumCol, decToMmss:decToMmss, mmssToDec:mmssToDec };
})();
