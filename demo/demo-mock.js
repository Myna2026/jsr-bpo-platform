/* Vorführungs-Fassung SSF Balkan — ersetzt Supabase durch fest eingebaute Beispieldaten.
   Läuft per Doppelklick (file://), ohne Datenbank, ohne Anmeldung. Speichern ist wirkungslos.
   ALLE Namen/Kunden/Zahlen sind erfunden. */
(function(){
  "use strict";
  function iso(d){ var x=new Date(d); return x.getFullYear()+'-'+String(x.getMonth()+1).padStart(2,'0')+'-'+String(x.getDate()).padStart(2,'0'); }
  function isoWeek(d){ var t=new Date(Date.UTC(d.getFullYear(),d.getMonth(),d.getDate())); var dn=t.getUTCDay()||7; t.setUTCDate(t.getUTCDate()+4-dn); var ys=new Date(Date.UTC(t.getUTCFullYear(),0,1)); return {kw:Math.ceil((((t-ys)/86400000)+1)/7), year:t.getUTCFullYear()}; }
  var NOW=new Date(); var CW=isoWeek(NOW);
  function mondayOf(d){ var x=new Date(d); x.setDate(x.getDate()-((x.getDay()+6)%7)); return x; }
  function weekList(n){ var out=[]; var m=mondayOf(NOW); for(var i=n-1;i>=0;i--){ var dd=new Date(m); dd.setDate(m.getDate()-i*7); out.push(isoWeek(dd)); } return out; }
  var WEEKS=weekList(5);

  var FIRST=['Arben','Blerta','Driton','Fatlum','Gentiana','Ilir','Jeta','Kushtrim','Liridona','Mentor','Nora','Petrit','Qendrim','Rina','Shpend','Teuta','Uran','Valon','Xhevdet','Ylber','Ardit','Besa','Donika','Egzon','Flaka','Genti','Hana','Ismet','Jetmir','Kaltrina'];
  var LAST=['Krasniqi','Berisha','Gashi','Hoxha','Rexhaj','Shala','Kelmendi','Morina','Bytyqi','Zeqiri','Halimi','Dervishi','Ademi','Rama','Sopa','Kryeziu','Bajrami','Mustafa','Leci','Hasani'];

  var PROJECTS=[
    {id:'proj_nord',name:'Nordwind Telekom',client:'Nordwind AG',status:'active',location:'Prishtina',rate_training:16,rate_active:22,color:'#0E7C86',allow_global_bogen:false,skills:[{key:'sales',label:'Sales',rate:24},{key:'support',label:'Support',rate:22}]},
    {id:'proj_alpina',name:'Alpina Versicherung',client:'Alpina AG',status:'active',location:'Tirana',rate_training:18,rate_active:24,color:'#3B6FB0',allow_global_bogen:false,skills:[{key:'sales',label:'Sales',rate:26},{key:'support',label:'Support',rate:22},{key:'retention',label:'Retention',rate:24}]},
    {id:'proj_bergland',name:'Bergland Reisen',client:'Bergland GmbH',status:'active',location:'Prishtina',rate_training:16,rate_active:22,color:'#C0912E',allow_global_bogen:false,skills:[{key:'support',label:'Support',rate:22},{key:'retention',label:'Retention',rate:24}]}
  ];
  var LOCS=['Prishtina','Tirana'];
  // Positionen: pro Projekt 1 Projektleiter, 1 Teamleiter, dann QM/Trainer/Supervisor + Agenten.
  function posFor(i){ var m=i%10; if(m===0) return 'Teamleiter'; if(m===1) return 'Supervisor'; if(m===2) return 'Senior Agent'; if(m===3) return 'QM'; if(m===9) return 'Trainer'; return 'Agent'; }
  var SKILLS3=['sales','support','retention'];
  var EMP=[];
  for(var i=0;i<30;i++){
    var proj=PROJECTS[i%3]; var skl=proj.skills[i%proj.skills.length].key;
    var pos=(i%3===0 && i<3)?'Projektleiter':posFor(i);
    var startY=2024+(i%2), startM=(i*7%12)+1;
    var absences=[];
    if(i%5===0) absences.push({type:'vacation',from:iso(new Date(NOW.getFullYear(),NOW.getMonth(),3)),to:iso(new Date(NOW.getFullYear(),NOW.getMonth(),7)),days:5,paid:true,approved:true});
    if(i%7===0) absences.push({type:'sick',from:iso(new Date(NOW.getFullYear(),NOW.getMonth(),12)),to:iso(new Date(NOW.getFullYear(),NOW.getMonth(),13)),days:2,paid:true,approved:true});
    EMP.push({ id:'emp_'+i, first_name:FIRST[i], last_name:LAST[i%LAST.length], staff_number:'SSF-'+String(100+i),
      status: i%13===0?'training':(i%17===0?'inactive':'active'), position:pos, project_id:proj.id, project_skill:skl, primary_skill:skl,
      location:LOCS[i%2], work_model:'Vollzeit', work_hours:8, salary_type:'fixed', fixed_salary:600+(i%6)*40, salary_currency:'EUR', hourly_rate:'4.50', bank_currency:'EUR',
      hire_date:startY+'-'+String(startM).padStart(2,'0')+'-01', contract:{start:startY+'-'+String(startM).padStart(2,'0')+'-01',end:null,title:pos,project:proj.name,signed_at:startY+'-'+String(startM).padStart(2,'0')+'-01'},
      email:FIRST[i].toLowerCase()+'.'+LAST[i%LAST.length].toLowerCase()+'@ssf-balkan.example', phone:'+38344'+String(100000+i*137).slice(0,6),
      cv_skills:[skl,'kommunikation'], absences:absences, warnings:[], notes:'Beispiel-Datensatz', allowed_shifts:[], work_saturday:i%4===0, work_sunday:false, work_holidays:'no',
      project_assignments:[{project_id:proj.id,skill:skl,share_pct:100,start_date:startY+'-01-01',end_date:null}], vacation_days_quota:20 });
  }

  var KPI_CONFIG=[
    {id:'kpi_cr',name:'CR',skill:'sales',project_id:null,type:'percent',unit:'%',level:'agent',thresholds:[{op:'>=',v:45,color:'green'},{op:'>=',v:35,color:'amber'}]},
    {id:'kpi_aht',name:'AHT',skill:'support',project_id:null,type:'time',unit:'min',level:'agent',thresholds:[{op:'<=',v:6,color:'green'},{op:'<=',v:8,color:'amber'}]},
    {id:'kpi_csat',name:'CSAT',skill:'support',project_id:null,type:'grade',unit:'',level:'agent',thresholds:[{op:'>=',v:4.5,color:'green'},{op:'>=',v:4,color:'amber'}]},
    {id:'kpi_ret',name:'Retention-Quote',skill:'retention',project_id:null,type:'percent',unit:'%',level:'agent',thresholds:[{op:'>=',v:70,color:'green'},{op:'>=',v:55,color:'amber'}]}
  ];
  var KPI_ENTRIES=[]; EMP.forEach(function(e,ix){ if(e.status!=='active') return; WEEKS.forEach(function(w){ var kid=e.project_skill==='sales'?'kpi_cr':e.project_skill==='support'?'kpi_csat':'kpi_ret'; var base=e.project_skill==='sales'?42:e.project_skill==='support'?4.4:66; KPI_ENTRIES.push({emp_id:e.id,kpi_id:kid,value:Math.round((base+((ix+w.kw)%9-4)*(kid==='kpi_csat'?0.1:2))*100)/100,kw:w.kw,year:w.year,source:'import'}); }); });
  var KPI_PROJ=[]; PROJECTS.forEach(function(p){ WEEKS.forEach(function(w){ KPI_PROJ.push({project_id:p.id,skill:'sales',kpi_id:'kpi_cr',value:44+((w.kw)%6-3),kw:w.kw,year:w.year,source:'import'}); }); });

  var WEEKLY_HOURS=[], WEEKLY_CALLS=[], WEEKLY_GAUGES=[];
  EMP.forEach(function(e,ix){ if(e.status!=='active') return; WEEKS.forEach(function(w){
    WEEKLY_HOURS.push({project_id:e.project_id,employee_id:e.id,skill:e.project_skill,kw:w.kw,year:w.year,hours:36+((ix+w.kw)%5),sales_calls:e.project_skill==='sales'?(60+((ix*3+w.kw)%40)):0});
    WEEKLY_CALLS.push({project_id:e.project_id,employee_id:e.id,kw:w.kw,year:w.year,answered:70+((ix*7+w.kw)%50),outbound:10+(ix%20),no_answer:2+(ix%6),avg_handle_sec:300+((ix+w.kw)%120),avg_talk_sec:210,avg_hold_sec:30,avg_acw_sec:60});
    WEEKLY_GAUGES.push({employee_id:e.id,project_id:e.project_id,kw:w.kw,year:w.year,csat:Math.round((4.2+((ix+w.kw)%8)*0.08)*100)/100,anzahl:15+((ix+w.kw)%20),gesamt_pct:88,dauer_sec:240,nps:40});
  }); });

  var SHIFTS=[]; var mon=mondayOf(NOW);
  EMP.forEach(function(e,ix){ if(e.status==='inactive') return; for(var d=0;d<5;d++){ if((ix+d)%6===0) continue; var day=new Date(mon); day.setDate(mon.getDate()+d); SHIFTS.push({id:'sh_'+ix+'_'+d,project_id:e.project_id,employee_id:e.id,work_date:iso(day),shift:{value:'F',net:7.5},shift_value:'F',net_hours:7.5,skill:e.project_skill}); } });

  var CVS=[]; var CVST=['cv_inbound','cv_accepted','invited','interview','selection1','selection2','contract','rejected_by_us','parking','blacklist'];
  for(var c=0;c<12;c++){ CVS.push({id:'cv_'+c,name:FIRST[(c*3)%30]+' '+LAST[(c*5)%20],first_name:FIRST[(c*3)%30],last_name:LAST[(c*5)%20],status:CVST[c%CVST.length],source:c%3===0?'instagram':'cv',cv_date:iso(new Date(NOW.getFullYear(),NOW.getMonth(),1+c)),cv_received_at:iso(new Date(NOW.getFullYear(),NOW.getMonth(),1+c)),email:'bewerber'+c+'@example.com',phone:'+38344'+String(200000+c*311).slice(0,6),cv_skills:['support'],target_role:'Agent',project_id:PROJECTS[c%3].id,language_level:{level:'B2'}}); }

  var REPORT_FTE=EMP.filter(function(e){return e.project_skill;}).map(function(e){ return {project_id:e.project_id,employee_id:e.id,fte:e.status==='active'?1:0.5}; });
  var REPORT_MEAS=[
    {id:'rm1',project_id:'proj_nord',skill:'sales',text:'Nachschulung Einwandbehandlung',status:'in_progress',created_kw:CW.kw,created_year:CW.year,seq:0,created_by_name:'Demo Manager'},
    {id:'rm2',project_id:'proj_nord',skill:'support',text:'Zweite Telefonielinie ab nächster Woche',status:'open',created_kw:CW.kw,created_year:CW.year,seq:0,created_by_name:'Demo Manager'}
  ];
  var CALL_CRIT=[
    {id:'cc1',project_id:'proj_nord',skill:'sales',category:'Einstieg',order_index:10,prompt:'Begrüßung',type:'tristate',max_points:1,weight:1,allow_na:true,active:true,compliance_critical:false},
    {id:'cc2',project_id:'proj_nord',skill:'sales',category:'Einstieg',order_index:20,prompt:'Datenabgleich',type:'tristate',max_points:1,weight:1,allow_na:false,active:true,compliance_critical:true},
    {id:'cc3',project_id:'proj_nord',skill:'sales',category:'Abschluss',order_index:30,prompt:'Verabschiedung',type:'tristate',max_points:1,weight:1,allow_na:true,active:true,compliance_critical:false}
  ];
  var CALL_CFG=[{project_id:'proj_nord',skill:'sales',threshold_unit:'points',green_min:2,yellow_min:1}];
  var CALL_SAMPLES=[]; EMP.filter(function(e){return e.project_skill==='sales'&&e.status==='active';}).slice(0,6).forEach(function(e,k){ CALL_SAMPLES.push({id:'cs_'+k,employee_id:e.id,project_id:e.project_id,skill:'sales',sampled_date:iso(new Date(NOW.getFullYear(),NOW.getMonth(),5+k)),kw:CW.kw,year:CW.year,total_points:k%4,max_points:3,raw_points:k%4,total_pct:Math.round(k%4/3*100),compliance_failed:k===0,status:'done',conducted_by_name:'Demo QM'}); });

  var WINDSOR=[]; for(var d2=0;d2<20;d2++){ var day2=new Date(NOW.getFullYear(),NOW.getMonth(),1+d2); WINDSOR.push({date:iso(day2),datasource:d2%2?'facebook':'instagram',account_name:d2%2?'SSF Ads':'ssf_balkan',source:'demo',campaign:d2%2?'Recruiting KV':'',spend:d2%2?String(20+d2):'',impressions:d2%2?String(1000+d2*30):'',clicks:d2%2?String(30+d2):'0',reach:String(800+d2*20),followers_count:d2%2?'':String(3400+d2)}); }

  var DATA={
    app_users:[{user_id:'demo-mgmt',role_keys:['management'],full_name:'Demo Manager',active:true,email:'demo@ssf-balkan.example',employee_id:'emp_0',access:'all',locked:[]}],
    roles_definitions:[{role_key:'management',label:'Management',portals:['hr','client']},{role_key:'hr',label:'HR',portals:['hr']},{role_key:'teamlead',label:'Teamleiter',portals:['hr']}],
    employees:EMP, employees_masked:EMP, employees_team_view:EMP, projects:PROJECTS, project_skills:[],
    kpi_config:KPI_CONFIG, kpi_entries:KPI_ENTRIES, kpi_project_entries:KPI_PROJ,
    weekly_hours:WEEKLY_HOURS, weekly_calls:WEEKLY_CALLS, weekly_gauges:WEEKLY_GAUGES,
    shift_assignments:SHIFTS, shift_checkins:[], cvs:CVS, showcases:[],
    report_fte:REPORT_FTE, report_measures:REPORT_MEAS, report_forecast:[], report_longterm:[], report_fte_v1:[],
    call_criteria:CALL_CRIT, call_score_config:CALL_CFG, call_samples:CALL_SAMPLES, call_scores:[],
    windsor_marketing:WINDSOR, org_nodes:[], presentations:[], presentation_templates:[], presentation_comments:[],
    training_plans:[{id:'tp1',title:'Onboarding Nordwind',project_id:'proj_nord',status:'active',start_date:iso(NOW),note:'Beispiel'}],
    feedback_questions:[], feedback_sessions:[], feedback_answers:[], dm_threads:[], dm_messages:[], dm_participants:[],
    app_config:[], import_aliases:[], data_imports:[], activity_log:[], wheel_spins:[], wheel_specials:[],
    vacation_requests:[], jsr_countries_v1:[]
  };

  // ---- Query-Builder: chainbar + thenbar; ignoriert Filter, liefert die Tabelle. Schreiben = No-Op-Erfolg. ----
  var CHAIN=['select','eq','neq','in','gt','gte','lt','lte','or','is','ilike','like','contains','order','range','not','filter','match','overlaps','textSearch','csv'];
  function res(rows,head,cnt){ return {data:head?null:rows,error:null,count:(cnt==null?(rows?rows.length:0):cnt)}; }
  function builder(name){ var rows=(DATA[name]||[]).slice(); var head=false; var b={};
    CHAIN.forEach(function(m){ b[m]=function(a,opts){ if(m==='select'&&opts&&opts.head) head=true; return b; }; });
    b.limit=function(){return b;}; b.single=function(){return Promise.resolve({data:rows[0]||null,error:null});};
    b.maybeSingle=function(){return Promise.resolve({data:rows[0]||null,error:null});};
    b.then=function(r,j){ return Promise.resolve(res(rows,head)).then(r,j); };
    b.insert=function(p){ var arr=Array.isArray(p)?p:[p]; return okb(arr.map(function(x,i){ return Object.assign({id:(name+'_new_'+i)},x); })); };
    b.upsert=function(p){ var arr=Array.isArray(p)?p:[p]; return okb(arr); };
    b.update=function(){ return okb([]); }; b.delete=function(){ return okb([]); };
    return b;
  }
  function okb(rows){ var b={}; CHAIN.concat(['limit']).forEach(function(m){ b[m]=function(){return b;}; });
    b.single=function(){return Promise.resolve({data:rows[0]||{id:'demo'},error:null});};
    b.maybeSingle=function(){return Promise.resolve({data:rows[0]||null,error:null});};
    b.then=function(r,j){ return Promise.resolve({data:rows,error:null}).then(r,j); }; return b; }

  var SESSION={access_token:'demo-token',user:{id:'demo-mgmt',email:'demo@ssf-balkan.example'}};
  var MOCK={
    from:function(n){ return builder(n); },
    rpc:function(fn){ if(fn==='nlquery_exec') return Promise.resolve({data:[{hinweis:'Datenabfrage braucht die Live-Datenbank, in der Demo deaktiviert.'}],error:null}); return Promise.resolve({data:[],error:null}); },
    channel:function(){ var ch={on:function(){return ch;},subscribe:function(cb){ if(cb) try{cb('SUBSCRIBED');}catch(e){} return ch;},unsubscribe:function(){return ch;}}; return ch; },
    removeChannel:function(){}, getChannels:function(){return [];},
    auth:{ getSession:function(){return Promise.resolve({data:{session:SESSION},error:null});},
      getUser:function(){return Promise.resolve({data:{user:SESSION.user},error:null});},
      onAuthStateChange:function(cb){ if(cb) setTimeout(function(){ try{cb('SIGNED_IN',SESSION);}catch(e){} },0); return {data:{subscription:{unsubscribe:function(){}}}}; },
      signInWithPassword:function(){return Promise.resolve({data:{session:SESSION,user:SESSION.user},error:null});},
      signInWithOtp:function(){return Promise.resolve({data:{},error:null});}, verifyOtp:function(){return Promise.resolve({data:{session:SESSION},error:null});},
      signOut:function(){return Promise.resolve({error:null});}, setSession:function(){return Promise.resolve({data:{session:SESSION},error:null});} },
    storage:{ from:function(){ return { upload:function(){return Promise.resolve({data:{path:''},error:null});}, getPublicUrl:function(){return {data:{publicUrl:''}};}, download:function(){return Promise.resolve({data:null,error:null});}, list:function(){return Promise.resolve({data:[],error:null});}, remove:function(){return Promise.resolve({data:[],error:null});}, createSignedUrl:function(){return Promise.resolve({data:{signedUrl:''},error:null});} }; } }
  };
  window.supabase={ createClient:function(){ return MOCK; } };
  try{ window.__DEMO__=true; console.info('%cVorführungs-Fassung SSF Balkan — Beispieldaten, keine DB.','color:#0E7C86;font-weight:700'); }catch(e){}
})();
