// Edge Function: Bewerber-Import (Meta facebook_leads + Google-Sheet-Sync) — serverseitig, täglich.
// Läuft per Cron (~02:00 UTC, nach dem Windsor-Lauf um 01:00) ODER manuell aus dem Frontend.
// Übernahme-Logik liegt jetzt HIER (nicht mehr im Browser). Dubletten werden NICHT automatisch entschieden:
// Telefon-Kollisionen werden zurückgehalten (windsor_leads.status_review='dup') und landen im Dubletten-Bereich.
// Deploy: supabase functions deploy applicant-import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const isoUTC = (d: Date) => d.toISOString().slice(0, 10);

// ── Telefon-Normalisierung (1:1 aus hr.html) ─────────────────────────────────
const PHONE_CC = ["383", "355", "49", "43", "41"];
const PHONE_CC_NAT: Record<string, number[]> = { "383": [8, 8], "355": [8, 9], "49": [9, 11], "43": [9, 13], "41": [9, 9] };
const phoneDigits = (raw: string) => String(raw || "").replace(/^\s*\+/, "").replace(/\D/g, "");
const phoneDetectCC = (raw: string) => { const d = phoneDigits(raw); for (const cc of PHONE_CC) { if (d.startsWith(cc)) return cc; } return ""; };
function phoneClassify(raw: string): any {
  const s = String(raw || "").trim(); if (!s) return { cat: "missing" };
  const digits = phoneDigits(s);
  if (digits.length < 6 || /[a-zA-Z]/.test(s.replace(/^\s*\+/, ""))) return { cat: "unclear", reason: "unassignable" };
  if (!/^\s*\+/.test(s)) {
    const d0 = digits.replace(/^0/, "");
    if (d0.length === 8 && /^4[345689]/.test(d0)) return { cat: "ok", cc: "383", target: "+383" + d0 };
    if (d0.length === 9 && /^6[6789]/.test(d0)) return { cat: "ok", cc: "355", target: "+355" + d0 };
  }
  const cc = phoneDetectCC(s); if (!cc) return { cat: "unclear", reason: "no_cc" };
  const nat = digits.slice(cc.length); const [lo, hi] = PHONE_CC_NAT[cc] || [6, 14];
  if (nat.length < lo || nat.length > hi) return { cat: "unclear", reason: "implausible", cc };
  const target = "+" + cc + nat; return { cat: (s === target) ? "e164" : "ok", cc, target };
}
function metaCleanPhone(raw: string) {
  let s = String(raw || "").trim(); if (!s) return "";
  s = s.replace(/^\s*00/, "+"); const plus = /^\s*\+/.test(s) ? "+" : ""; const digits = s.replace(/[^\d]/g, "");
  return digits ? (plus + digits) : "";
}
const metaSplitName = (full: string) => { const p = String(full || "").trim().split(/\s+/).filter(Boolean); const f = p.shift() || ""; return { first_name: f, last_name: p.join(" ") }; };
const metaLevel = (g: string) => { const m = String(g || "").match(/\b([abc][12])\b/i); return m ? m[1].toUpperCase() : ""; };
function metaAvailable(raw: string, cvDate: string) {
  const s = String(raw || "").trim(); if (!s) return null;
  if (/^(sofort|ab sofort|jetzt|heute)\b/i.test(s)) return cvDate || isoUTC(new Date());
  let m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})(?!\d)/); if (m) return m[1] + "-" + m[2].padStart(2, "0") + "-" + m[3].padStart(2, "0");
  m = s.match(/^(\d{1,2})[.\/](\d{1,2})[.\/](\d{4}|\d{2})(?!\d)/);
  if (m) { let y = m[3]; if (y.length === 2) y = "20" + y; return y + "-" + m[2].padStart(2, "0") + "-" + m[1].padStart(2, "0"); }
  return null;
}
function cvDateIso(v: any) {
  if (!v) return null; const s = String(v).trim();
  if (/^\d{4}-\d{2}-\d{2}/.test(s)) return s.slice(0, 10);
  const m = s.match(/^(\d{1,2})[.\/](\d{1,2})[.\/](\d{4})/);
  return m ? m[3] + "-" + m[2].padStart(2, "0") + "-" + m[1].padStart(2, "0") : null;
}
function metaField(row: any, ...names: string[]) {
  for (const n of names) { const v = row && row[n]; if (v != null && String(v).trim() !== "") return v; }
  if (!row) return null;
  const norm = (s: string) => String(s || "").toLowerCase().replace(/ä/g, "a").replace(/ö/g, "o").replace(/ü/g, "u").replace(/ß/g, "ss").replace(/[^a-z0-9]/g, "");
  const want = names.map(norm);
  for (const k of Object.keys(row)) { if (want.indexOf(norm(k)) >= 0) { const v = row[k]; if (v != null && String(v).trim() !== "") return v; } }
  return null;
}
function metaLeadToPayload(lead: any) {
  const rawPhone = metaField(lead, "__telefonnummer__", "phone");
  const cleaned = metaCleanPhone(rawPhone); const pc = cleaned ? phoneClassify(cleaned) : { cat: "missing" };
  const phone = (pc.cat === "ok" || pc.cat === "e164") ? pc.target : null;
  const nm = metaSplitName(metaField(lead, "vor-_und_nachname", "full_name"));
  const emailRaw = metaField(lead, "email", "e_mail", "__email__", "e-mail-adresse", "e_mail_adresse");
  const email = (() => { const s = String(emailRaw == null ? "" : emailRaw).trim(); return (s && s.indexOf("@") > 0 && s.length <= 254) ? s : null; })();
  const german = metaField(lead, "__sprichst_du_deutsch__", "german"); const lvl = metaLevel(german);
  const created = metaField(lead, "created_time"); const cvDate = created ? String(created).slice(0, 10) : isoUTC(new Date());
  const availRaw = metaField(lead, "__wann_kannst_du_anfangen__", "available"); const av = metaAvailable(availRaw, cvDate);
  const cc = metaField(lead, "__hast_du_erfahrung_im_call_center__", "cc_experience");
  const work = metaField(lead, "__arbeitszeit_verfügbar__", "__arbeitszeit_verfuegbar__", "work_time");
  const interests = metaField(lead, "in_welchen_", "interests");
  const campaign = metaField(lead, "campaign"); const adName = metaField(lead, "ad_name"); const formId = metaField(lead, "form_id");
  const leadId = (lead && lead.id != null) ? String(lead.id) : null;
  const trim = (v: any) => { const s = (v == null ? "" : String(v)).trim(); return s || null; };
  const extra: any = {};
  if (trim(cc)) extra.cc_experience = trim(cc);
  if (trim(work)) extra.work_time = trim(work);
  if (trim(interests)) extra.interests = trim(interests);
  if (trim(german)) extra.german = trim(german);
  if (trim(availRaw) && !av) extra.available = trim(availRaw);
  if (trim(campaign)) extra.campaign = trim(campaign);
  if (trim(adName)) extra.ad_name = trim(adName);
  if (trim(formId)) extra.form_id = trim(formId);
  if (leadId) extra.lead_id = leadId;
  if (!phone && trim(rawPhone)) extra.phone_raw = trim(rawPhone);
  const payload = {
    first_name: trim(nm.first_name), last_name: trim(nm.last_name), email: email,
    phone: phone || null, city: null, project_id: null, target_role: "Agent", status: "cv_inbound",
    cv_date: cvDate, source: "meta", language_level: (lvl || null), available_from: av || null,
    work_history: null, notes: null, audios: [], videos: [], test_scores: {}, test_answers: {}, extra,
  };
  return { payload, phone };
}

// ── Google-Sheet-CSV (1:1 aus hr.html) ───────────────────────────────────────
function extractCsvUrl(sheetUrl: string) {
  if (!sheetUrl) return null; const s = sheetUrl.trim();
  if (/[?&]format=csv/.test(s) || /output=csv/.test(s) || /tqx=out:csv/.test(s)) return s;
  const m = s.match(/\/spreadsheets\/d\/([a-zA-Z0-9\-_]+)/); if (!m) return null;
  const g = s.match(/[#&?]gid=(\d+)/);
  return "https://docs.google.com/spreadsheets/d/" + m[1] + "/gviz/tq?tqx=out:csv&gid=" + (g ? g[1] : "0");
}
function parseCsv(text: string) {
  const rows: string[][] = []; let row: string[] = [], field = "", inQ = false;
  text = String(text).replace(/\r\n/g, "\n").replace(/\r/g, "\n");
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (inQ) { if (ch === '"') { if (text[i + 1] === '"') { field += '"'; i++; } else inQ = false; } else field += ch; }
    else { if (ch === '"') inQ = true; else if (ch === ",") { row.push(field); field = ""; } else if (ch === "\n") { row.push(field); rows.push(row); row = []; field = ""; } else field += ch; }
  }
  if (field.length || row.length) { row.push(field); rows.push(row); }
  if (!rows.length) return [];
  const header = rows[0].map((h) => (h || "").trim());
  return rows.slice(1).filter((r) => r.some((c) => (c || "").trim() !== "")).map((r) => { const o: any = {}; header.forEach((h, i) => { o[h] = (r[i] != null ? r[i] : "").trim(); }); return o; });
}

// ── Meta-Import ──────────────────────────────────────────────────────────────
async function importMeta(admin: any) {
  const { data: leads, error } = await admin.from("windsor_leads").select("*").eq("imported", false).is("status_review", null).order("created_time", { ascending: true });
  if (error) return { error: error.message };
  if (!leads || !leads.length) return { created: 0, held: 0, errors: 0, noPhone: 0, total: 0 };
  const byPhone = new Map<string, any>();
  const { data: cvs } = await admin.from("cvs").select("id,phone"); (cvs || []).forEach((c: any) => { if (c.phone) byPhone.set(String(c.phone).trim(), c.id); });
  let created = 0, held = 0, errors = 0, noPhone = 0;
  for (const lead of leads) {
    const { payload, phone } = metaLeadToPayload(lead);
    if (!phone) noPhone++;
    if (phone && byPhone.has(phone)) { await admin.from("windsor_leads").update({ status_review: "dup", imported_cv_id: byPhone.get(phone) }).eq("id", lead.id); held++; continue; }
    const { data: ins, error: e1 } = await admin.from("cvs").insert(payload).select("id").single();
    if (e1) { if (e1.code === "23505") { await admin.from("windsor_leads").update({ status_review: "dup" }).eq("id", lead.id); held++; } else errors++; continue; }
    await admin.from("windsor_leads").update({ imported: true, imported_cv_id: ins.id }).eq("id", lead.id);
    created++; if (phone) byPhone.set(phone, ins.id);
  }
  return { created, held, errors, noPhone, total: leads.length };
}

// ── Google-Sheet-Sync ────────────────────────────────────────────────────────
async function googleSync(admin: any) {
  const { data: cfgRow } = await admin.from("app_config").select("value").eq("key", "jsr_cv_sync_config_v1").maybeSingle();
  const cfg: any = (cfgRow && cfgRow.value) || {};
  const patchCfg = async (patch: any) => { try { await admin.from("app_config").upsert({ key: "jsr_cv_sync_config_v1", value: { ...cfg, ...patch, last_sync_at: new Date().toISOString() }, updated_at: new Date().toISOString() }); } catch (_e) { /* egal */ } };
  const csvUrl = cfg.csv_url || extractCsvUrl(cfg.sheet_url || "");
  if (!csvUrl) return { imported: 0, skipped: 0, error: "Keine gültige Sheet-URL." };
  let rows: any[] = [];
  try { const res = await fetch(csvUrl); if (!res.ok) throw new Error("HTTP " + res.status); rows = parseCsv(await res.text()); }
  catch (e) { await patchCfg({ last_error: "Abruf fehlgeschlagen: " + ((e as Error).message || e) }); return { imported: 0, skipped: 0, error: (e as Error).message || String(e) }; }
  const M = cfg.mapping || {};
  const cutoff = String(cfg.cutoff_date || "").slice(0, 10);
  const norm = (x: any) => String(x || "").trim().replace(/\s+/g, " ").toLowerCase();
  const pick = (r: any, h: string) => { const key = norm(h); const hit = Object.keys(r).find((k) => norm(k) === key); return hit != null ? String(r[hit] || "").trim() : ""; };
  const { data: existing } = await admin.from("cvs").select("phone"); const seen = new Set<string>();
  (existing || []).forEach((x: any) => { const pc = phoneClassify(x && x.phone); if (pc.cat === "ok" || pc.cat === "e164") seen.add(pc.target); });
  const ALLOWED = new Set(["355", "383"]);
  const nz = (v: any) => { const s = (v == null ? "" : String(v)).trim(); return s || null; };
  const payloads: any[] = []; const skip: Record<string, number> = {}; let preCutoff = 0;
  const bump = (k: string) => { skip[k] = (skip[k] || 0) + 1; };
  for (const r of rows) {
    const rowIso = cvDateIso(pick(r, M.date));
    if (!cutoff || !rowIso || rowIso < cutoff) { preCutoff++; continue; }
    const name = pick(r, M.name); const phoneRaw = pick(r, M.phone);
    if (!name) { bump("kein Name"); continue; }
    const pc = phoneClassify(phoneRaw);
    if (pc.cat === "missing") { bump("keine Telefonnummer"); continue; }
    if (pc.cat === "unclear") { bump("unklare Nummer"); continue; }
    if (!ALLOWED.has(pc.cc)) { bump("Fremdland"); continue; }
    if (seen.has(pc.target)) { bump("Dublette"); continue; }
    seen.add(pc.target);
    const sp = name.split(/\s+/).filter(Boolean); const first = sp.shift() || ""; const last = sp.join(" ");
    const german = pick(r, M.german); const lvl = (german.match(/\b([abc][12])\b/i) || [])[1];
    const extra: any = {}; const ccExp = pick(r, M.cc_experience), avail = pick(r, M.availability), wtime = pick(r, M.worktime);
    if (ccExp) extra.cc_experience = ccExp; if (avail) extra.availability = avail; if (wtime) extra.work_time = wtime;
    payloads.push({
      first_name: nz(first), last_name: nz(last), email: null, phone: pc.target, city: null, project_id: null,
      target_role: "Agent", status: "cv_inbound", cv_date: cvDateIso(pick(r, M.date)) || isoUTC(new Date()), source: "Google Sheet",
      language_level: (lvl ? lvl.toUpperCase() : nz(german)), work_history: nz(pick(r, M.experience)), notes: nz(pick(r, M.termin)),
      audios: [], videos: [], test_scores: {}, test_answers: {}, extra,
    });
  }
  let inserted = 0, dup = 0, errors = 0;
  for (const p of payloads) { const { error: e1 } = await admin.from("cvs").insert(p); if (!e1) inserted++; else if (e1.code === "23505") dup++; else errors++; }
  await patchCfg({ last_error: null, last_sync_count: inserted, last_sync_skipped: dup });
  return { imported: inserted, skipped: dup, preCutoff, total: rows.length, errors, skipByReason: skip };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST erwartet" }, 405);
  const auth = req.headers.get("Authorization") || "";
  const token = auth.replace(/^Bearer\s+/i, "").trim();
  // Berechtigt: Cron (Service-Role) ODER angemeldeter HR/Management-User (manueller Knopf).
  let ok = false;
  // 1) Exakter Service-Role-Match (falls Env == uebergebener Key).
  if (token === SERVICE) ok = true;
  // 2) Service-Role an der role-Claim des JWT erkennen. Das Gateway hat die Signatur bereits geprueft
  //    (verify_jwt aktiv) -> ein Token mit role=service_role ist echt und rotationssicher, egal welcher
  //    konkrete service_role-Key genutzt wird.
  if (!ok && token.split(".").length === 3) {
    try {
      const b64 = (token.split(".")[1] || "").replace(/-/g, "+").replace(/_/g, "/");
      const payload = JSON.parse(atob(b64 + "=".repeat((4 - b64.length % 4) % 4)));
      if (payload && payload.role === "service_role") ok = true;
    } catch (_e) { /* kein lesbarer JWT-Payload */ }
  }
  // 3) Angemeldeter HR/Management-User (manueller Knopf im Frontend).
  if (!ok && token) {
    try {
      const u = createClient(SB_URL, ANON, { global: { headers: { Authorization: auth } } });
      const { data } = await u.auth.getUser(); const uid = data?.user?.id;
      if (uid) { const { data: au } = await u.from("app_users").select("role_keys").eq("user_id", uid).single(); const roles: string[] = (au?.role_keys as string[]) || []; if (roles.includes("management") || roles.includes("hr")) ok = true; }
    } catch (_e) { /* ok bleibt false */ }
  }
  if (!ok) return json({ error: "Nicht berechtigt." }, 403);

  let body: any = {}; try { body = await req.json(); } catch { body = {}; }
  const which = body?.source; // 'meta' | 'google' | undefined(beide)
  const admin = createClient(SB_URL, SERVICE);
  const out: any = { ok: true, at: new Date().toISOString() };
  try {
    if (which !== "google") out.meta = await importMeta(admin);
    if (which !== "meta") out.google = await googleSync(admin);
  } catch (e) {
    return json({ error: "Import-Fehler: " + ((e as Error).message || e) }, 500);
  }
  return json(out);
});
