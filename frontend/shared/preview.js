/* ═══ Admin-Vorschau („Ansehen als“), geteilt von hr/mitarbeiter/client. Aktiv nur mit ?preview=<sitzung> in der URL.
   Der Admin bleibt angemeldet (eigene Anmeldung); jede Anfrage trägt die Kopfzeile x-preview, die Datenbank schaltet die
   Anfrage auf read-only und die Identität auf den Zielnutzer (preview_pre_request). Hier im Browser:
   1) eigener, leerer Zwischenspeicher für diesen Tab (nur die Anmeldung wird übernommen), damit sich Admin-Einstellungen
      nicht in die fremde Sicht mischen; 2) fetch-Wächter: Edge Functions nur aus der Leseliste, keine Datei-Downloads,
      Speichern-Fehler (25006) als Hinweis; 3) Realtime aus; 4) roter Balken mit „Beenden“.
   Muss VOR dem Anlegen des Supabase-Clients laufen: previewInit() → previewClientOptions() → sb.  ═══ */
(function(){
  var id = null;
  try { id = new URLSearchParams(location.search).get('preview') || null; } catch (e) {}
  if (id && !/^[0-9a-f-]{36}$/i.test(id)) id = null;
  var ALLOW_FN = ['partner-knowledge', 'coach-session'];   // Leseliste (User: Conny fragen, Coach-Probelauf)
  var state = { id: id, who: null, toastAt: 0 };
  window.PREVIEW = state;
  if (!id) return;

  // 1) Zwischenspeicher trennen: In-Memory-Ersatz für localStorage/sessionStorage. Die Anmeldung kommt NICHT aus dem echten
  //    Speicher (dessen Refresh-Token darf nur der Haupt-Tab nutzen, sonst fliegt der Admin überall raus), sondern als
  //    Zugriffstoken im URL-Fragment (#pt=…) vom HR-Tab; ohne Refresh, gilt bis zum Ablauf des Tokens (etwa eine Stunde).
  function shim() {
    var m = new Map();
    return { getItem: function(k){ return m.has(k) ? m.get(k) : null; }, setItem: function(k, v){ m.set(k, String(v)); }, removeItem: function(k){ m.delete(k); }, clear: function(){ m.clear(); }, key: function(i){ return Array.from(m.keys())[i] || null; }, get length(){ return m.size; } };
  }
  var pt = null;
  try { var hm = /(?:^#|&)pt=([^&]+)/.exec(location.hash || ''); if (hm) { pt = decodeURIComponent(hm[1]); history.replaceState(null, '', location.pathname + location.search); } } catch (e) {}
  try { var ls = shim(); Object.defineProperty(window, 'localStorage', { value: ls, configurable: true }); } catch (e) {}
  try { var ss = shim(); Object.defineProperty(window, 'sessionStorage', { value: ss, configurable: true }); } catch (e) {}
  if (pt) { try { var payload = JSON.parse(atob(pt.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))); var ref = (payload.iss || '').split('//')[1] ? (payload.iss || '').split('//')[1].split('.')[0] : (payload.ref || '');
      var sess = { access_token: pt, refresh_token: 'preview', token_type: 'bearer', expires_at: payload.exp, expires_in: Math.max(0, payload.exp - Math.floor(Date.now() / 1000)), user: { id: payload.sub, email: payload.email || '', aud: payload.aud || 'authenticated', role: payload.role || 'authenticated', app_metadata: payload.app_metadata || {}, user_metadata: payload.user_metadata || {}, created_at: '' } };
      window.localStorage.setItem('sb-' + ref + '-auth-token', JSON.stringify(sess)); state.token = pt; } catch (e) {} }

  // 2) fetch-Wächter
  var realFetch = window.fetch.bind(window);
  function toast(msg) { var now = Date.now(); if (now - state.toastAt < 1500) return; state.toastAt = now; var t = document.createElement('div'); t.textContent = msg; t.style.cssText = 'position:fixed;left:50%;bottom:24px;transform:translateX(-50%);z-index:2147483646;background:#b91c1c;color:#fff;padding:10px 16px;border-radius:10px;font:600 13.5px Inter,system-ui,sans-serif;box-shadow:0 8px 24px rgba(0,0,0,.25);max-width:92vw'; document.body.appendChild(t); setTimeout(function(){ t.remove(); }, 3200); }
  function blocked(msg) { toast(msg); return Promise.resolve(new Response(JSON.stringify({ error: msg, code: 'PREVIEW' }), { status: 403, headers: { 'Content-Type': 'application/json' } })); }
  window.fetch = function(input, init) {
    var url = typeof input === 'string' ? input : (input && input.url) || '';
    if (/\/functions\/v1\//.test(url)) { var fn = (url.split('/functions/v1/')[1] || '').split(/[/?]/)[0]; if (ALLOW_FN.indexOf(fn) < 0) return blocked('Vorschau: „' + fn + '“ ist hier nicht verfügbar (nur ansehen).'); }
    if (/\/storage\/v1\//.test(url) && !/\/storage\/v1\/object\/public\//.test(url)) return blocked('Vorschau: Dateien werden hier nicht geladen.');
    var isSb = /supabase\.co\//.test(url) && !/\/auth\/v1\//.test(url);
    if (isSb) { init = init || {}; var h = new Headers(init.headers || (typeof input !== 'string' && input.headers) || {}); h.set('x-preview', state.id); init.headers = h; }
    return realFetch(input, init).then(function(res) {
      if (isSb && res.status >= 400) { try { res.clone().json().then(function(j){ if (j && (j.code === '25006' || /read-only transaction/.test(j.message || ''))) toast('Vorschau: nichts gespeichert. Sie sehen nur an.'); }).catch(function(){}); } catch (e) {} }
      return res;
    });
  };
  window.previewClientOptions = function() { return { global: { headers: { 'x-preview': state.id }, fetch: window.fetch }, auth: { persistSession: true, autoRefreshToken: false, detectSessionInUrl: false } }; };
  // Zielnutzer aus Sicht der Datenbank (preview_whoami); null = Sitzung ungültig/abgelaufen
  window.previewWhoami = function(sb) { return sb.rpc('preview_whoami').then(function(r) { var w = r && r.data; if (!w || !w.preview_session) return null; state.who = w; return w; }).catch(function(){ return null; }); };
  // 3) Realtime stilllegen (Abos liefen mit Admin-Rechten)
  window.previewMuteRealtime = function(sb) { try { var stub = { on: function(){ return stub; }, subscribe: function(cb){ try{ cb && cb('CLOSED'); }catch(e){} return stub; }, unsubscribe: function(){ return Promise.resolve('ok'); }, send: function(){ return Promise.resolve('ok'); }, track: function(){ return Promise.resolve('ok'); } }; sb.channel = function(){ return stub; }; sb.removeChannel = function(){ return Promise.resolve('ok'); }; sb.removeAllChannels = function(){ return Promise.resolve([]); }; } catch (e) {} };
  // 4) Balken
  window.previewBanner = function(sb, who) {
    if (document.getElementById('previewBar')) return;
    var au = (who && who.app_user) || {}; var roles = (au.role_keys || []).join(', ');
    var bar = document.createElement('div'); bar.id = 'previewBar';
    bar.style.cssText = 'position:fixed;top:0;left:0;right:0;z-index:2147483645;background:#b91c1c;color:#fff;font:700 13px Inter,system-ui,sans-serif;padding:8px 14px;display:flex;align-items:center;gap:12px;box-shadow:0 4px 14px rgba(0,0,0,.25)';
    bar.innerHTML = '<span style="background:#fff;color:#b91c1c;border-radius:6px;padding:2px 8px;letter-spacing:.06em">VORSCHAU</span><span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">Sie sehen das Portal wie <b>' + esc(au.full_name || (who && who.email) || 'Nutzer') + '</b>' + (roles ? ' (' + esc(roles) + ')' : '') + '. Nur ansehen, nichts wird gespeichert.</span><button id="previewEnd" style="border:1.5px solid rgba(255,255,255,.7);background:transparent;color:#fff;border-radius:8px;padding:5px 12px;font:700 12.5px Inter,system-ui,sans-serif;cursor:pointer">Beenden</button>';
    document.body.appendChild(bar);
    var pad = function(){ document.documentElement.style.setProperty('--preview-bar', bar.offsetHeight + 'px'); document.body.style.paddingTop = bar.offsetHeight + 'px'; }; pad(); window.addEventListener('resize', pad);
    var st = document.createElement('style'); st.textContent = '.sidebar,[class*="sidebar"]{top:var(--preview-bar,0)!important} .topbar,.top-bar,.appbar{top:var(--preview-bar,0)!important}'; document.head.appendChild(st);
    document.getElementById('previewEnd').addEventListener('click', function(){ try { realFetch(sbUrl(sb) + '/rest/v1/rpc/preview_end', { method: 'POST', headers: { 'Content-Type': 'application/json', 'apikey': sbKey(sb), 'Authorization': 'Bearer ' + accessToken() }, body: JSON.stringify({ p_id: state.id }) }).catch(function(){}); } catch (e) {} setTimeout(function(){ window.close(); location.replace(location.pathname); }, 250); });
  };
  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"]/g, function(c){ return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }
  function sbUrl(sb){ return (sb && sb.supabaseUrl) || (sb && sb.rest && sb.rest.url && sb.rest.url.replace(/\/rest\/v1$/, '')) || ''; }
  function sbKey(sb){ return (sb && sb.supabaseKey) || ''; }
  function accessToken(){ return state.token || ''; }
  // Gate-Hilfe: session.user auf den Zielnutzer umbiegen (id + email), Rest der Anmeldung bleibt die des Admins
  window.previewSession = function(session, who) { if (!who) return session; var u = Object.assign({}, session.user, { id: who.user_id, email: who.email || session.user.email }); return Object.assign({}, session, { user: u }); };
})();
