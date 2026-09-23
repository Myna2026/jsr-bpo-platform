// CPO-Tracking Giganetz Retention, öffentliche Erfassung (ohne Login). Zugang = Link-Token + Mitarbeiter-PIN
// (dieselbe PIN wie beim Schulungslink, geprüft über training_pin_check mit Brute-Force-Bremse).
//
// Der Agent sieht NIE einen CPO oder einen Umsatz: diese Funktion gibt die Felder schlicht nicht zurück.
// Geschrieben wird ausschließlich hier (service role), die Tabelle ist für anon/authenticated gesperrt.
//
// Aktionen: get {token} · login {token,pin} · list {session,date?} · add {session,entry} · cancel {session,id,reason}
// Deploy: supabase functions deploy cpo-track --use-api --no-verify-jwt
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
// Casenummer: CS oder IMS, gefolgt von Ziffern (User 2026-09-23). Fängt Zahlendreher und Tippfehler ab.
const CASE_RX = /^(CS|IMS)[0-9]{4,12}$/;
const OUTCOMES = [
  { key: "downgrade", label: "Downgrade, aber gehalten" },
  { key: "gleich", label: "Gleiche Tarifklasse" },
  { key: "upgrade", label: "Upgrade" },
];

// Tarife mit Rangfolge je Mandat. Aus den beiden Rängen leitet sich das Ergebnis ab, der Agent wählt es nie
// selbst: höherer Rang = Upgrade, niedrigerer = Downgrade, gleicher Rang = gleiche Tarifklasse.
async function tariffs(projectId: string, skill: string) {
  const { data } = await admin.from("app_config").select("value").eq("key", "jsr_cpo_tariffs_v1").maybeSingle();
  const all: any = (data && data.value) || {};
  const list = all[projectId + "/" + skill] || all[projectId] || [];
  return (Array.isArray(list) ? list : []).filter((t: any) => t && t.name).map((t: any) => ({ name: String(t.name), rank: Number(t.rank) }))
    .filter((t: any) => isFinite(t.rank)).sort((a: any, b: any) => a.rank - b.rank || a.name.localeCompare(b.name, "de"));
}
function outcomeOf(rankFrom: number, rankTo: number) {
  if (rankTo > rankFrom) return "upgrade";
  if (rankTo < rankFrom) return "downgrade";
  return "gleich";
}
async function options() {
  const { data } = await admin.from("app_config").select("value").eq("key", "jsr_cpo_options_v1").maybeSingle();
  const v: any = (data && data.value) || {};
  return {
    status: Array.isArray(v.status) ? v.status : [],
    action: Array.isArray(v.action) ? v.action : [],
    skill_label: v.skill_label || "Retention",
    close_action: v.close_action || "Angebot angenommen",
  };
}
// Ohne Token: wenn genau EIN Zugang aktiv ist, nimm den. Das erlaubt die kurze Adresse /retention ohne
// Token in der URL. Gibt es mehrere, muss der Link den Token tragen — sonst landet jemand im falschen Mandat.
// Der Token ist ohnehin kein Passwort; angemeldet wird mit der persönlichen PIN.
async function linkOf(token: string) {
  if (!token) {
    const { data } = await admin.from("cpo_links").select("token,project_id,skill,label,active").eq("active", true);
    return (data && data.length === 1) ? data[0] : null;
  }
  if (!/^[A-Za-z0-9_-]{6,64}$/.test(token)) return null;
  const { data } = await admin.from("cpo_links").select("token,project_id,skill,label,active").eq("token", token).maybeSingle();
  return (data && data.active) ? data : null;
}
async function sessionOf(id: string) {
  if (!id || !/^[0-9a-f-]{36}$/i.test(id)) return null;
  const { data } = await admin.from("cpo_sessions").select("id,token,employee_id,emp_name,expires_at").eq("id", id).maybeSingle();
  if (!data || new Date(data.expires_at).getTime() < Date.now()) return null;
  const link = await linkOf(data.token);
  return link ? { ...data, link } : null;
}
// Der abzurechnende CPO kommt aus dem gepflegten Kalkulator (cpo_calc_configs), nicht aus einer zweiten Liste.
// Fehlt die Konfiguration, fallen wir NICHT auf Vermutungen zurück, sondern lehnen den Abschluss ab.
async function cpoFor(projectId: string, skill: string, outcome: string, level: number) {
  const { data } = await admin.from("cpo_calc_configs").select("config,updated_at").eq("project_id", projectId).eq("skill", skill).maybeSingle();
  const rows: any[] = (data && data.config && Array.isArray(data.config.rows)) ? data.config.rows : [];
  const row = rows.find((r) => r && r.key === outcome);
  const amount = row ? Number(level === 2 ? row.cpo_stufe2 : row.cpo_stufe1) : NaN;
  if (!isFinite(amount) || amount <= 0) return null;
  return { amount: Math.round(amount * 100) / 100, basis: { outcome, level, config_updated_at: (data && data.updated_at) || null, cpo_stufe1: row.cpo_stufe1 ?? null, cpo_stufe2: row.cpo_stufe2 ?? null } };
}
// Was der Agent von einem Eintrag sehen darf: alles außer Geld.
const pub = (r: any) => ({ id: r.id, work_date: r.work_date, case_no: r.case_no, status: r.status, closed: r.closed, action: r.action,
  outcome: r.outcome, discount_level: r.discount_level, tariff_from: r.tariff_from, tariff_to: r.tariff_to,
  note: r.note, is_close: r.is_close, created_at: r.created_at,
  cancelled_at: r.cancelled_at, cancel_reason: r.cancel_reason });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: any = {}; try { body = await req.json(); } catch (_e) { return json({ error: "Ungültige Anfrage." }, 400); }
  const action = String(body.action || "");

  if (action === "get") {
    const link = await linkOf(String(body.token || ""));
    if (!link) return json({ error: "Dieser Link ist nicht (mehr) gültig." }, 404);
    const { data: proj } = await admin.from("projects").select("name").eq("id", link.project_id).maybeSingle();
    return json({ ok: true, token: link.token, project: (proj && proj.name) || link.project_id, skill: link.skill, label: link.label,
      options: await options(), outcomes: OUTCOMES, tariffs: await tariffs(link.project_id, link.skill) });
  }

  if (action === "login") {
    const link = await linkOf(String(body.token || ""));
    if (!link) return json({ error: "Dieser Link ist nicht (mehr) gültig." }, 404);
    const pin = String(body.pin || "").trim();
    if (!/^\d{3,8}$/.test(pin)) return json({ error: "Bitte deine PIN eingeben." }, 400);
    const { data: chk, error } = await admin.rpc("training_pin_check", { p_code: pin });
    if (error) return json({ error: "PIN-Prüfung fehlgeschlagen." }, 500);
    const c: any = chk || {};
    if (c.error === "locked") return json({ error: "Zu viele Versuche. Bitte kurz warten." }, 429);
    if (!c.ok || !c.employee_id) return json({ error: "Diese PIN kennen wir nicht." }, 401);
    const { data: ses, error: se } = await admin.from("cpo_sessions").insert({ token: link.token, employee_id: c.employee_id, emp_name: c.name || null }).select("id").single();
    if (se) return json({ error: "Anmeldung fehlgeschlagen." }, 500);
    return json({ ok: true, session: ses.id, name: c.name || "", sheet: c.name || "", options: await options(), outcomes: OUTCOMES,
      tariffs: await tariffs(link.project_id, link.skill), project: link.project_id });
  }

  const ses = await sessionOf(String(body.session || ""));
  if (!ses) return json({ error: "Deine Sitzung ist abgelaufen. Bitte PIN erneut eingeben.", expired: true }, 401);

  if (action === "list") {
    const date = /^\d{4}-\d{2}-\d{2}$/.test(String(body.date || "")) ? String(body.date) : null;
    let q = admin.from("cpo_entries").select("*").eq("employee_id", ses.employee_id).eq("project_id", ses.link.project_id).order("created_at", { ascending: true });
    if (date) q = q.eq("work_date", date);
    else q = q.gte("work_date", new Date(Date.now() - 13 * 864e5).toISOString().slice(0, 10));
    const { data } = await q;
    return json({ ok: true, name: ses.emp_name, entries: (data || []).map(pub) });
  }

  if (action === "add") {
    const e: any = body.entry || {};
    const opt = await options();
    const date = String(e.work_date || "").slice(0, 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return json({ error: "Bitte ein Datum wählen." }, 400);
    const caseNo = String(e.case_no || "").trim();
    if (!CASE_RX.test(caseNo.toUpperCase())) return json({ error: "Die Casenummer muss mit CS oder IMS beginnen, gefolgt von Ziffern (z. B. CS5006433)." }, 400);
    if (opt.status.length && !opt.status.includes(String(e.status || ""))) return json({ error: "Bitte einen Status wählen." }, 400);
    if (opt.action.length && !opt.action.includes(String(e.action || ""))) return json({ error: "Bitte auswählen, was gemacht wurde." }, 400);
    // „abgeschlossen = ja" gilt NUR bei „Angebot angenommen" (User 2026-09-23). Deshalb wird es aus der
    // Maßnahme abgeleitet und nicht vom Browser übernommen: sonst entstehen Zeilen wie „WVL, abgeschlossen ja".
    // Bewusst auch für „Case geschlossen" und „Kündigung in K7 erfasst": inhaltlich abgeschlossen, aber ohne
    // Verkauf, also kein Umsatz und Spalte E bleibt nein. Wenn Giganetz es anders will, hier ändern.
    const closed = String(e.action) === opt.close_action;
    const isClose = closed;
    const row: any = { project_id: ses.link.project_id, skill: ses.link.skill, employee_id: ses.employee_id, work_date: date,
      case_no: caseNo.toUpperCase(), status: String(e.status), closed, action: String(e.action), note: (String(e.note || "").trim() || null), created_via: "agent" };
    if (isClose) {
      // Der Agent wählt zwei Tarife, das Ergebnis rechnet der Server. Nie die Angabe des Browsers übernehmen.
      const tl = await tariffs(ses.link.project_id, ses.link.skill);
      const tFrom = tl.find((t: any) => t.name === String(e.tariff_from || ""));
      const tTo   = tl.find((t: any) => t.name === String(e.tariff_to || ""));
      if (!tFrom) return json({ error: "Bitte den bisherigen Tarif wählen." }, 400);
      if (!tTo)   return json({ error: "Bitte den neuen Tarif wählen." }, 400);
      const outcome = outcomeOf(tFrom.rank, tTo.rank);
      const level = Number(e.discount_level);
      if (level !== 1 && level !== 2) return json({ error: "Bitte die Rabattstufe wählen." }, 400);
      row.tariff_from = tFrom.name; row.tariff_to = tTo.name;
      const cpo = await cpoFor(ses.link.project_id, ses.link.skill, outcome, level);
      if (!cpo) return json({ error: "Für diese Tarifart ist noch kein CPO hinterlegt. Bitte der Teamleitung sagen." }, 409);
      row.outcome = outcome; row.discount_level = level; row.cpo_amount = cpo.amount;
      row.cpo_basis = { ...cpo.basis, tariff_from: tFrom.name, rank_from: tFrom.rank, tariff_to: tTo.name, rank_to: tTo.rank };
      // Ein abgerechneter Abschluss je Casenummer — Wiedervorlagen auf denselben Case bleiben erlaubt.
      const { data: dup } = await admin.from("cpo_entries").select("id,work_date,employee_id").eq("project_id", ses.link.project_id)
        .ilike("case_no", caseNo).eq("is_close", true).is("cancelled_at", null).limit(1);
      if (dup && dup.length) {
        let who = "einem Kollegen";
        const { data: emp } = await admin.from("employees").select("first_name,last_name").eq("id", dup[0].employee_id).maybeSingle();
        if (emp) who = ((emp.first_name || "") + " " + (emp.last_name || "")).trim();
        const d = String(dup[0].work_date).split("-").reverse().join(".");
        return json({ error: "Diese Casenummer ist am " + d + " schon als Abschluss erfasst (" + who + "). Ein Case zählt nur einmal." }, 409);
      }
    }
    const { data: ins, error: ie } = await admin.from("cpo_entries").insert(row).select("*").single();
    if (ie) {
      if (String(ie.code) === "23505") return json({ error: "Diese Casenummer ist schon als Abschluss erfasst. Ein Case zählt nur einmal." }, 409);
      return json({ error: "Speichern fehlgeschlagen: " + (ie.message || "") }, 500);
    }
    return json({ ok: true, entry: pub(ins) });
  }

  if (action === "cancel") {
    const id = String(body.id || "");
    if (!/^[0-9a-f-]{36}$/i.test(id)) return json({ error: "Eintrag nicht gefunden." }, 400);
    const reason = String(body.reason || "").trim().slice(0, 300) || "vom Mitarbeiter storniert";
    const { data, error } = await admin.from("cpo_entries").update({ cancelled_at: new Date().toISOString(), cancelled_by_name: ses.emp_name || null, cancel_reason: reason })
      .eq("id", id).eq("employee_id", ses.employee_id).is("cancelled_at", null).select("*");
    if (error) return json({ error: "Storno fehlgeschlagen." }, 500);
    if (!data || !data.length) return json({ error: "Dieser Eintrag lässt sich nicht mehr stornieren." }, 404);
    return json({ ok: true, entry: pub(data[0]) });
  }

  return json({ error: "Unbekannte Aktion." }, 400);
});
