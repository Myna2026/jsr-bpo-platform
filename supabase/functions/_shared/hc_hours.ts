// Gemeinsame Rechnung für HolidayCheck-Stunden: dieselbe Logik wie im Leitstand
// ("HC Stundenabgleich"), damit Mail, Wächter und Bildschirm nie auseinanderlaufen.
//
// Abgerechnet wird, was wir netto liefern: Schichtplan minus Urlaub/Krankheit/Pausen,
// je Person nur mit ihrem abrechenbaren Anteil (app_config.jsr_hc_billing_v1).
// Der Forecast ist das ZIEL, nicht die Obergrenze. Er liegt heute nur je Kalenderwoche
// vor; für Teilzeiträume wird er gleichmäßig auf die Tage verteilt. Sobald der
// Tages-Forecast eingelesen ist, ändert sich hier nur die Herkunft der Zahl, nicht der Aufbau.

export const HC_PROJECT = "proj_hc_a1b2c3d4";
export const HC_SKILLS = ["sales", "support"];
export const HC_BILLING_KEY = "jsr_hc_billing_v1";

export type HcCfg = { default_pct: number; entries: any[]; training_zero: string[] };

export function isoDay(d: Date) {
  return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
}
export function berlinNow() {
  return new Date(new Date().toLocaleString("en-US", { timeZone: "Europe/Berlin" }));
}
export function addDays(ds: string, n: number) {
  const d = new Date(ds + "T00:00:00"); d.setDate(d.getDate() + n); return isoDay(d);
}
export function daysBetween(from: string, to: string) {
  const out: string[] = []; let d = from;
  for (let i = 0; i < 400 && d <= to; i++) { out.push(d); d = addDays(d, 1); }
  return out;
}
// ISO-Kalenderwoche samt ISO-Jahr (am Jahreswechsel sind die beiden verschieden).
// Montag der ISO-Woche, in der dieser Tag liegt.
export function isoMonday(ds: string) {
  const dow = new Date(ds + "T00:00:00").getDay() || 7;   // So = 7
  return addDays(ds, 1 - dow);
}
export function isoWeek(ds: string) {
  const d = new Date(ds + "T00:00:00");
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() + 4 - (d.getDay() || 7));
  const yearStart = new Date(d.getFullYear(), 0, 1);
  return { kw: Math.ceil(((+d - +yearStart) / 86400000 + 1) / 7), year: d.getFullYear() };
}
export function eur(v: number) {
  return (Math.round((v || 0) * 100) / 100).toLocaleString("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + " €";
}
export function hrs(v: number) {
  return (Math.round((v || 0) * 10) / 10).toLocaleString("de-DE", { minimumFractionDigits: 1, maximumFractionDigits: 1 }) + " h";
}
export function dmy(ds: string) { const [y, m, d] = ds.split("-"); return Number(d) + "." + Number(m) + "." + y; }

// Abwesenheit kürzt den Plantag: ganztags auf null, halber Tag auf die Hälfte.
export function absFactor(emp: any, ds: string) {
  for (const a of (emp && emp.absences) || []) {
    const f = String(a.from || "").slice(0, 10); if (!f) continue;
    const t = String(a.to || f).slice(0, 10);
    if (ds >= f && ds <= t) {
      const d = Number(a.days);
      if (t === f && isFinite(d) && d > 0 && d < 1) return Math.max(0, 1 - d);
      return 0;
    }
  }
  return 1;
}
export function cfgNorm(v: any): HcCfg {
  const c = (v && typeof v === "object") ? v : {};
  return {
    default_pct: c.default_pct == null ? 100 : Number(c.default_pct),
    entries: Array.isArray(c.entries) ? c.entries : [],
    training_zero: Array.isArray(c.training_zero) ? c.training_zero : [],
  };
}
// Befristete Regel schlägt dauerhafte, bei gleicher Art gewinnt die zuletzt beginnende.
function entryFor(cfg: HcCfg, empId: string, ds: string) {
  let best: any = null;
  for (const e of cfg.entries || []) {
    if (!e || e.emp !== empId) continue;
    if (e.from && ds < e.from) continue;
    if (e.to && ds > e.to) continue;
    if (!best) { best = e; continue; }
    const a = (e.from || e.to) ? 1 : 0, b = (best.from || best.to) ? 1 : 0;
    if (a > b) { best = e; continue; }
    if (a === b && String(e.from || "") >= String(best.from || "")) best = e;
  }
  return best;
}
export function pctFor(cfg: HcCfg, empId: string, ds: string, trainDays: Record<string, boolean>) {
  if ((cfg.training_zero || []).indexOf(empId) >= 0 && trainDays[ds]) return 0;
  const e = entryFor(cfg, empId, ds);
  if (e) return Math.max(0, Math.min(100, Number(e.pct) || 0));
  return cfg.default_pct == null ? 100 : Number(cfg.default_pct);
}
// Anteil einer Schicht, der bis zur Uhrzeit (Minuten seit Mitternacht) gelaufen ist.
// nowMin = null heisst: der ganze geplante Tag zaehlt.
export function shiftShare(shiftValue: string, nowMin: number | null) {
  if (nowMin == null) return 1;
  const spans: { s: number; e: number }[] = [];
  String(shiftValue || "").split("|").forEach((p) => {
    const m = String(p).trim().match(/^(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})$/); if (!m) return;
    const a = Number(m[1].slice(0, 2)) * 60 + Number(m[1].slice(3));
    let b = Number(m[2].slice(0, 2)) * 60 + Number(m[2].slice(3));
    if (b <= a) b += 1440;
    spans.push({ s: a, e: b });
  });
  const gross = spans.reduce((a, x) => a + (x.e - x.s), 0);
  if (!gross) return nowMin >= 1020 ? 1 : Math.max(0, Math.min(1, (nowMin - 540) / 480));
  const done = spans.reduce((a, x) => a + Math.max(0, Math.min(nowMin, x.e) - x.s), 0);
  return Math.max(0, Math.min(1, done / gross));
}

export type HcSkill = {
  skill: string; label: string; rate: number | null; abrBis?: number;
  ziel: number; zielTeil: boolean;
  plan: number; abw: number; netto: number; abr: number; nichtAbr: number;
  eur: number | null; zielEur: number | null; luecke: number | null; lueckeEur: number | null;
  rows: any[];
};

// Eine Rechnung fuer einen Zeitraum. nowMin begrenzt den letzten Tag anteilig (Zwischenstand).
export async function hcCompute(admin: any, from: string, to: string, nowMin: number | null) {
  // Das Ziel liegt je WOCHE vor. Ein Tagesziel als Wochenziel geteilt durch sieben ist keine
  // Groesse: geliefert wird werktags, das Ziel verteilt sich aber auf sieben Kalendertage. Jeder
  // Werktag meldete deshalb ein Plus und jedes Wochenende ein grosses Minus, und ueber die Woche
  // kippte bei Sales sogar das Vorzeichen (Befund 2026-09-30). Verglichen wird jetzt "Woche bis
  // <Ende des Zeitraums>": das Wochenziel anteilig nach dem geplanten Volumen der bereits
  // vergangenen Tage. Dafuer werden die Schichten der GANZEN ISO-Wochen geladen.
  const wkFrom = isoMonday(from);
  const wkTo = addDays(isoMonday(to), 6);
  const years = [...new Set([Number(wkFrom.slice(0, 4)), Number(wkTo.slice(0, 4))])];
  const [shR, dhR, fcR, tpR, cfgR, skR] = await Promise.all([
    admin.from("shift_assignments").select("employee_id,skill,work_date,net_hours,shift_value")
      .eq("project_id", HC_PROJECT).gte("work_date", wkFrom).lte("work_date", wkTo),
    admin.from("daily_hours").select("employee_id,skill,work_date,hours")
      .eq("project_id", HC_PROJECT).gte("work_date", from).lte("work_date", to),
    admin.from("forecast_day").select("skill,work_date,fc_total").eq("project_id", HC_PROJECT)
      .gte("work_date", wkFrom).lte("work_date", wkTo),
    admin.from("training_plans").select("name,start_date,end_date,status").eq("project_id", HC_PROJECT),
    admin.from("app_config").select("value").eq("key", HC_BILLING_KEY).maybeSingle(),
    admin.from("project_skills").select("key,rate").eq("project_id", HC_PROJECT),
  ]);
  const sh = shR.data || [];
  const cfg = cfgNorm(cfgR.data && cfgR.data.value);
  const ids = [...new Set(sh.map((r: any) => r.employee_id).filter(Boolean))];
  const empR = ids.length
    ? await admin.from("employees").select("id,first_name,last_name,position,absences,termination_date").in("id", ids)
    : { data: [] as any[] };
  const empBy: Record<string, any> = {}; (empR.data || []).forEach((e: any) => { empBy[e.id] = e; });
  const rateBy: Record<string, number | null> = {};
  (skR.data || []).forEach((s: any) => { const v = Number(s.rate); rateBy[s.key] = isFinite(v) && v > 0 ? v : null; });

  const days = daysBetween(from, to);
  // Schulungstage ueber die GANZEN Wochen, nicht nur ueber den Zeitraum: das Wochenvolumen fuer das
  // anteilige Ziel rechnet auch Tage vor dem Zeitraum, und dort muss "0 % waehrend der Klasse" gelten.
  // trainNames meldet nur, was IM Zeitraum liegt, sonst stuende in der Mail eine laengst beendete Klasse.
  const trainDays: Record<string, boolean> = {}; const trainNames: Record<string, boolean> = {};
  (tpR.data || []).forEach((t: any) => {
    const a = String(t.start_date || "").slice(0, 10), b = String(t.end_date || "").slice(0, 10);
    if (!a || !b || b < a) return;
    const st = String(t.status || "");
    if (st === "done" || st === "cancelled") return;
    daysBetween(wkFrom, wkTo).forEach((ds) => { if (ds >= a && ds <= b) trainDays[ds] = true; });
    days.forEach((ds) => { if (ds >= a && ds <= b) trainNames[t.name || "Schulung"] = true; });
  });

  // Ziel JE TAG aus dem Tagesblatt des Auftraggebers (forecast_day). Bis zum 2026-09-30 wurde
  // stattdessen der Wochenwert aus report_forecast anteilig verteilt - eine Schaetzung, die je nach
  // Verteilung um zweistellige Stundenbetraege danebenlag und sogar das Vorzeichen drehen konnte
  // (Sales KW 40 bis Mittwoch: geschaetzt -7,7 h, tatsaechlich +10,6 h). Seit dem Umstieg auf das
  // Tagesblatt liegt das Ziel taggenau vor, also wird nichts mehr verteilt. Gegenprobe: die Summe
  // der Tageswerte trifft in 24 von 24 vollen Wochen den gespeicherten Wochenwert.
  // forecast_day ist seit dem 2026-09-30 die einzige Quelle des Forecasts, auch fuer die
  // Praesentation. report_forecast ist nur noch die abgeleitete Wochenebene mit genau einem
  // Schreiber (dem Import) und wird hier nicht gelesen: eine zweite Rechenstelle fuer dieselbe
  // Groesse ist genau das, was irgendwann auseinanderlaeuft.
  const fcDay: Record<string, number> = {};
  (fcR.data || []).forEach((r: any) => {
    const ds = String(r.work_date).slice(0, 10);
    const k = String(r.skill || "").toLowerCase() + "|" + ds;
    fcDay[k] = (fcDay[k] || 0) + (Number(r.fc_total) || 0);
  });
  const wkVol: Record<string, { bis: number; ganz: number }> = {};

  const istBy: Record<string, number> = {};
  (dhR.data || []).forEach((r: any) => { const k = r.employee_id + "|" + r.skill; istBy[k] = (istBy[k] || 0) + (Number(r.hours) || 0); });

  const per: Record<string, any> = {}; const daySeries: Record<string, any> = {};
  sh.forEach((r: any) => {
    const ds = String(r.work_date).slice(0, 10), sk = String(r.skill || "").toLowerCase();
    let net = Number(r.net_hours) || 0; if (net <= 0) return;
    // Letzter Tag nur anteilig, wenn ein Zwischenstand gerechnet wird.
    if (nowMin != null && ds === to) net = net * shiftShare(r.shift_value, nowMin);
    const emp = empBy[r.employee_id];
    // Nach dem Austritt gibt es nichts abzurechnen. Die Schichtzeile bleibt als Planungshistorie
    // stehen, sie erzeugt nur kein Geld mehr (Entscheidung 2026-09-30).
    const ende = emp && emp.termination_date ? String(emp.termination_date).slice(0, 10) : "";
    const raus = !!ende && ds > ende;
    const nach = raus ? 0 : net * absFactor(emp, ds);
    const pct = pctFor(cfg, r.employee_id, ds, trainDays);
    const abr = nach * (pct / 100);
    // Wochenvolumen fuer das anteilige Ziel: ueber die GANZE Woche, "bis" nur bis zum Zeitraum-Ende.
    const wkKey = sk + "|" + (() => { const w = isoWeek(ds); return w.year + "-" + w.kw; })();
    const wv = wkVol[wkKey] || (wkVol[wkKey] = { bis: 0, ganz: 0 });
    wv.ganz += abr; if (ds <= to) wv.bis += abr;
    if (ds < from || ds > to) return;              // nur der gewaehlte Zeitraum kommt in die Liste
    const k = r.employee_id + "|" + sk;
    const q = per[k] || (per[k] = {
      id: r.employee_id, skill: sk,
      name: ((emp && emp.first_name || "") + " " + (emp && emp.last_name || "")).trim() || "Unbekannt",
      position: (emp && emp.position) || "", plan: 0, abw: 0, netto: 0, abr: 0, pcts: [] as number[],
    });
    q.plan += net; q.abw += net - nach; q.netto += nach; q.abr += abr; q.pcts.push(pct);
    const dk = ds + "|" + sk;
    const dd = daySeries[dk] || (daySeries[dk] = { ds, skill: sk, plan: 0, netto: 0, abr: 0 });
    dd.plan += net; dd.netto += nach; dd.abr += abr;
  });
  const list = Object.keys(per).map((k) => {
    const q = per[k];
    q.pct = q.pcts.length ? Math.round(q.pcts.reduce((a: number, b: number) => a + b, 0) / q.pcts.length) : 100;
    q.ist = istBy[q.id + "|" + q.skill] || 0;
    return q;
  }).sort((a, b) => b.abr - a.abr);

  // Verglichen wird die Woche bis zum Ende des Zeitraums: Montag dieser Woche bis "to". Bei einem
  // Aufruf ueber eine ganze Woche ist das genau die Woche, bei einem Tagesaufruf der Wochenverlauf
  // bis zu diesem Tag. Ziel und Lieferung decken damit immer dieselben Tage ab.
  const bisVon = isoMonday(to);
  const zielOf = (skill: string) => {
    let ziel = 0, abrBis = 0, gefunden = false, luecken = 0;
    daysBetween(bisVon, to).forEach((ds) => {
      const v = fcDay[skill + "|" + ds];
      if (v == null) luecken++; else { gefunden = true; ziel += v; }
    });
    const wv = wkVol[skill + "|" + (() => { const w = isoWeek(to); return w.year + "-" + w.kw; })()] || { bis: 0, ganz: 0 };
    abrBis = wv.bis;
    return { h: gefunden ? ziel : 0, abrBis, teil: (to !== addDays(bisVon, 6)), luecken };
  };

  const skills: HcSkill[] = HC_SKILLS.map((sk) => {
    const rows = list.filter((r) => r.skill === sk);
    const rate = rateBy[sk] != null ? rateBy[sk] : null;
    const z = zielOf(sk);
    const sum = (f: string) => rows.reduce((a, r: any) => a + (Number(r[f]) || 0), 0);
    const abr = sum("abr"), netto = sum("netto");
    return {
      skill: sk, label: sk === "sales" ? "Sales" : "Support", rate,
      ziel: z.h, zielTeil: z.teil,
      plan: sum("plan"), abw: sum("abw"), netto, abr, nichtAbr: netto - abr,
      // abrBis = abrechenbar seit Wochenbeginn bis zum Ende des Zeitraums. NUR diese Zahl gehoert
      // gegen das Ziel: abr zaehlt den gewaehlten Zeitraum (oft ein Tag), das Ziel ist ein Wochenwert.
      abrBis: z.abrBis,
      eur: rate != null ? abr * rate : null,
      zielEur: rate != null && z.h > 0 ? z.h * rate : null,
      luecke: z.h > 0 ? z.abrBis - z.h : null,
      lueckeEur: rate != null && z.h > 0 ? (z.abrBis - z.h) * rate : null,
      rows,
    };
  });

  const total = {
    abrBis: skills.reduce((a, s) => a + (s as any).abrBis, 0),
    abr: skills.reduce((a, s) => a + s.abr, 0),
    netto: skills.reduce((a, s) => a + s.netto, 0),
    plan: skills.reduce((a, s) => a + s.plan, 0),
    abw: skills.reduce((a, s) => a + s.abw, 0),
    ziel: skills.reduce((a, s) => a + s.ziel, 0),
    eur: skills.reduce((a, s) => a + (s.eur || 0), 0),
    zielEur: skills.reduce((a, s) => a + (s.zielEur || 0), 0),
  };
  const ohneZiel = skills.filter((s) => s.ziel <= 0 && s.rows.length > 0).map((s) => s.label);
  const OVERHEAD = ["Teamleiter", "Trainer", "QM", "Projektleiter"];
  const offenOverhead = list.filter((r: any) =>
    OVERHEAD.indexOf(String(r.position || "").trim()) >= 0 &&
    !entryFor(cfg, r.id, to) && (cfg.training_zero || []).indexOf(r.id) < 0
  ).map((r: any) => r.name + " (" + r.position + ")");

  return {
    from, to, days, skills, list, total, cfg,
    daySeries: Object.keys(daySeries).map((k) => daySeries[k]).sort((a, b) => a.ds < b.ds ? -1 : 1),
    trainDays, trainNames: Object.keys(trainNames),
    ohneZiel, offenOverhead: [...new Set(offenOverhead)],
  };
}
