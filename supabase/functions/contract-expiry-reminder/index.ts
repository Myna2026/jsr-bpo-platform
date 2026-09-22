// Lena: Vertragsübersicht 2×/Monat (~1. + 15.). Wer läuft in den nächsten 60 Tagen aus — MIT Folge:
// offen (Entscheidung steht aus: verlängern oder auslaufen lassen) oder schon entschieden (wird beendet).
// Gesamt an Shkurte, Rajner, Thorsten. Ylli nur sein Team (Giganetz), Edi nur seins (Holidaycheck).
// Von Lena (lena@). Kein Wochenende. Cron Tage 1–3 und 15–17; 7-Tage-Sperre -> einmal je Monatshälfte.
// Deploy: supabase functions deploy contract-expiry-reminder --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { agentBrand, shell, lead, taskCard, button, linkGoto } from "../_shared/agent_mail.ts";
import { smtpSend, slackDM, agentMailSender } from "../_shared/agent_send.ts";
import { scheduleDue, getSchedule } from "../_shared/schedule.ts";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const HORIZON = 60;   // Tage (Übersicht an Management/Leads)
// Deonita (HR): wöchentlich montags, nur die Verträge, die in 30 Tagen enden, nur wenn es welche gibt (User 2026-09-22).
const D_HORIZON = 30, D_UID = "35824fa3-cfe4-4c61-858a-ef1407a99ff7", D_MAIL = "hr@25hrs.net", D_CADENCE_MS = 6 * 864e5;
const CADENCE_MS = 7 * 864e5;   // höchstens einmal je Monatshälfte
const GESAMT_UIDS = ["54f067ab-b6f8-47a1-afa7-6dcb86b89b29", "14a5001c-9efb-4f76-b8f8-145e24b4be5f", "b7cbd0b3-961d-41e2-b358-cc13806b3fe3"]; // Shkurte, Rajner, Thorsten
const LEADS = [
  { uid: null, email: "edi.shaqiri@25hrs.net", project: "proj_hc_a1b2c3d4" },   // Edi · Holidaycheck
  { uid: "312020fc-5857-4591-9a1c-f963700053b1", email: null, project: "proj_gn_e5f6a7b8" }, // Ylli · Giganetz
];
const EMPLOYED = ["active", "training", "training_planned", "contract", "inactive", "freigestellt"];
const deDate = (d: string) => { const [y, m, da] = d.split("-"); return da + "." + m + "." + y; };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: any = {}; try { body = await req.json(); } catch (_e) { /* Cron */ }
  const previewTo = (typeof body.preview_to === "string" && body.preview_to.includes("@")) ? body.preview_to : null;
  const force = body.force === true || !!previewTo || body.test_deonita === true, dry = body.dry === true;
  const sched = await getSchedule(sb, "contract_expiry");
  const schedW = await getSchedule(sb, "contract_expiry_deonita");
  const dueMain = scheduleDue(sched), dueWeekly = scheduleDue(schedW);
  if (!force && !dueMain && !dueWeekly) return json({ ok: true, skipped: "not-scheduled" });

  if (!force && !dry && dueMain) { const { data: last } = await sb.from("agent_actions").select("at").eq("agent_key", "lena").eq("kind", "contract_expiry").order("at", { ascending: false }).limit(1);
    if (last && last[0] && (Date.now() - new Date(last[0].at).getTime()) < CADENCE_MS) return json({ ok: true, skipped: "cadence" }); }

  const weeklyOnly = body.weekly === true || body.test_deonita === true;   // Lauf für Deonita (30 Tage, montags)
  const today = new Date(new Date().toLocaleString("en-US", { timeZone: "Europe/Berlin" }));
  const iso = (dt: Date) => dt.toISOString().slice(0, 10);
  const from = iso(today), to = iso(new Date(today.getTime() + HORIZON * 864e5));

  const { data: emps } = await sb.from("employees").select("id,first_name,last_name,status,termination_date,contract,project_id").in("status", EMPLOYED);
  const projName: Record<string, string> = {}; { const { data: pr } = await sb.from("projects").select("id,name"); (pr || []).forEach((p: any) => projName[p.id] = p.name); }

  type Row = { id: string; name: string; end: string; project: string; project_id: string; decided: boolean; note: string };
  const rows: Row[] = [];
  (emps || []).forEach((e: any) => {
    const end = e.contract && e.contract.end; if (!end) return;
    if (end < from || end > to) return;
    const decided = !!e.termination_date || String(e.status).startsWith("terminated");
    const note = decided
      ? ("entschieden: wird beendet" + (e.termination_date ? " zum " + deDate(String(e.termination_date).slice(0, 10)) : ""))
      : "Entscheidung steht aus: verlängern oder auslaufen lassen";
    rows.push({ id: e.id, name: (e.first_name + " " + e.last_name).trim(), end, project: projName[e.project_id] || "ohne Projekt", project_id: e.project_id, decided, note });
  });
  rows.sort((a, b) => a.end.localeCompare(b.end));

  const brand = await agentBrand(sb, "lena", "#db2777");
  // Je Vertrag eine Karte mit Deep-Link direkt zum Mitarbeiter (je Name ein eigener Link).
  const renderList = (list: Row[]) => list.map((r) => taskCard({
    title: r.name + " · " + r.project,
    state: r.decided ? "entschieden" : "offen",
    tone: r.decided ? "neutral" : "warn",
    detail: "Vertrag endet " + deDate(r.end) + " · " + r.note,
    href: linkGoto("emp", { id: r.id }),
    cta: "Zum Profil",
  })).join("");

  async function buildMail(list: Row[], scope: string) {
    const openN = list.filter((r) => !r.decided).length;
    const leadTxt = list.length === 0
      ? "In den nächsten " + HORIZON + " Tagen läuft kein Vertrag aus."
      : list.length + (list.length === 1 ? " Vertrag läuft" : " Verträge laufen") + " in den nächsten " + HORIZON + " Tagen aus" + (openN ? ", davon " + openN + " noch ohne Entscheidung" : ", alle bereits entschieden") + ".";
    const inner = lead(leadTxt) + renderList(list) + button(linkGoto("employees"), "Zu den Mitarbeitern", brand.accent);
    return shell(brand, "Vertragsübersicht" + (scope ? " · " + scope : ""), "Nächste " + HORIZON + " Tage", inner);
  }
  const slackFor = (list: Row[]) => "*Lena · Vertragsübersicht*\n" + (list.length ? list.map((r) => "• " + r.name + " (" + r.project + "), endet " + deDate(r.end) + " — " + r.note).join("\n") : "Kein Vertrag läuft in den nächsten " + HORIZON + " Tagen aus.");

  // Empfänger-Mails auflösen
  let emailBy: Record<string, string> = {}; try { const { data: al } = await sb.auth.admin.listUsers({ perPage: 200 }); (al?.users || []).forEach((u: any) => { if (u.email) emailBy[u.id] = u.email; }); } catch (_e) {}
  const sender = await agentMailSender(sb, "lena");
  const results: any[] = [];
  async function send(to: string, list: Row[], scope: string) {
    if (!to) return; const html = await buildMail(list, scope);
    if (dry) { results.push({ to, scope, count: list.length, dry: true }); return; }
    const mr = sender ? await smtpSend(sender, to, "Vertragsübersicht" + (scope ? " · " + scope : "") + " (" + list.length + ")", html) : { ok: false, error: "kein Absender" };
    const sr = await slackDM(to, slackFor(list)); results.push({ to, scope, count: list.length, mail: mr.ok ? "sent" : mr.error, slack: sr });
  }

  // Vorschau: nur die Gesamt-Fassung an dich, keine echten Empfänger/kein Log
  if (previewTo) { const html = await buildMail(rows, "Gesamt");
    const mr = sender ? await smtpSend(sender, previewTo, "[Vorschau] Vertragsübersicht (" + rows.length + ")", html) : { ok: false, error: "kein Absender" };
    return json({ ok: true, preview: true, total: rows.length, mail: mr.ok ? "sent" : mr.error }); }

  // ── Deonita (HR): montags, Verträge der nächsten 30 Tage, nur wenn es welche gibt ──
  let dRows = rows.filter((r) => r.end <= iso(new Date(today.getTime() + D_HORIZON * 864e5)));
  // Testnachricht: wenn in 30 Tagen nichts endet, echte Daten aus dem größeren Fenster zeigen (sonst wäre die Probe leer)
  const testWide = body.test_deonita === true && !dRows.length && rows.length > 0;
  if (testWide) dRows = rows.slice();
  const runWeekly = body.test_deonita === true || dueWeekly || (force && weeklyOnly);
  let weekly: any = null;
  if (runWeekly) {
    let skip = "";
    if (!dry && body.test_deonita !== true && !force) { const { data: last } = await sb.from("agent_actions").select("at").eq("agent_key", "lena").eq("kind", "contract_expiry_30d").order("at", { ascending: false }).limit(1);
      if (last && last[0] && (Date.now() - new Date(last[0].at).getTime()) < D_CADENCE_MS) skip = "cadence"; }
    if (!skip && !dRows.length) skip = "nichts fällig";
    if (skip) { weekly = { skipped: skip, count: dRows.length }; }
    else {
      const to = emailBy[D_UID] || D_MAIL;
      const openN = dRows.filter((r) => !r.decided).length;
      const leadTxt = dRows.length + (dRows.length === 1 ? " befristeter Vertrag endet" : " befristete Verträge enden") + " in den nächsten " + D_HORIZON + " Tagen"
        + (openN ? ", davon " + openN + " noch ohne Entscheidung" : "") + ". Bitte entscheiden: verlängern oder auslaufen lassen.";
      const inner = lead(testWide ? (dRows.length + (dRows.length === 1 ? " befristeter Vertrag endet" : " befristete Verträge enden") + " in den nächsten " + HORIZON + " Tagen.") : leadTxt) + dRows.map((r) => taskCard({
        title: r.name + " · " + r.project,
        state: Math.max(0, Math.round((new Date(r.end).getTime() - today.getTime()) / 864e5)) + " Tage",
        tone: r.decided ? "neutral" : "warn",
        detail: "Vertragsende " + deDate(r.end) + " · " + r.note,
        href: linkGoto("emp", { id: r.id }), cta: "Zum Profil",
      })).join("") + button(linkGoto("employees"), "Zu den Mitarbeitern", brand.accent);
      const note = testWide ? lead("Testnachricht: In den nächsten " + D_HORIZON + " Tagen endet gerade kein Vertrag, deshalb zeigt diese Probe die nächsten " + HORIZON + " Tage. Die echte Nachricht kommt montags und nur, wenn wirklich etwas in " + D_HORIZON + " Tagen endet.") : "";
      const html = shell(brand, "Verträge, die bald enden", "Nächste " + (testWide ? HORIZON : D_HORIZON) + " Tage", note + inner);
      const subj = (body.test_deonita === true ? "[Testnachricht] " : "") + "Verträge, die in " + D_HORIZON + " Tagen enden (" + dRows.length + ")";
      const slackTxt = "*Lena · Verträge, die bald enden*\n" + dRows.map((r) => "• " + r.name + " (" + r.project + "), endet " + deDate(r.end) + " · noch " + Math.max(0, Math.round((new Date(r.end).getTime() - today.getTime()) / 864e5)) + " Tage — " + r.note).join("\n");
      if (dry) weekly = { to, count: dRows.length, dry: true, html };
      else { const mr = sender ? await smtpSend(sender, to, subj, html) : { ok: false, error: "kein Absender" };
        const sr = await slackDM(to, slackTxt);
        weekly = { to, count: dRows.length, mail: mr.ok ? "sent" : mr.error, slack: sr };
        if (body.test_deonita !== true) { try { await sb.from("agent_actions").insert({ agent_key: "lena", kind: "contract_expiry_30d", meta: { total: dRows.length, open: openN } }); } catch (_e) {} } }
    }
  }
  if (weeklyOnly) return json({ ok: true, weekly, total30: dRows.length });

  // Gesamt an Shkurte/Rajner/Thorsten (immer, auch wenn leer — es ist die Übersicht)
  if (dueMain || force) {
    for (const uid of GESAMT_UIDS) { if (emailBy[uid]) await send(emailBy[uid], rows, "Gesamt"); }
    // Leads: nur ihr Team, nur wenn dort etwas ausläuft
    for (const L of LEADS) { const teamRows = rows.filter((r) => r.project_id === L.project); if (!teamRows.length) continue;
      const to = L.email || (L.uid ? emailBy[L.uid] : ""); if (to) await send(to, teamRows, projName[L.project] || "Team"); }
    if (!dry) { try { await sb.from("agent_actions").insert({ agent_key: "lena", kind: "contract_expiry", meta: { total: rows.length, open: rows.filter((r) => !r.decided).length } }); } catch (_e) {} }
  }
  const previewHtml = dry ? await buildMail(rows, "Gesamt") : undefined;
  return json({ ok: true, total: rows.length, results, weekly, ...(dry ? { html: previewHtml } : {}) });
});
