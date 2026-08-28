// Gemeinsame Grundlage für ALLE Agenten-Mails. Eine Verbesserung hier kommt allen zugute.
// Bausteine: gebrandeter Rahmen (Foto + Name + Farbe aus dem Register), Kennzahl-Kacheln,
// Balken-Diagramme (vertikal für Verläufe, horizontal für Vergleiche), Beobachtungs-Block mit
// Gesicht, Knopf ins System. Tabellen-Layout + @media -> auf dem Telefon eine Spalte.
// Der Aufbau je Mail darf abweichen (Inhalt bestimmt die Form) — die Sorgfalt bleibt gleich.

export const HR_BASE = "https://hr.tive360.de/";
export const PORTAL_URL = "https://hr.tive360.de/hr.html";

export type AgentBrand = { key: string; name: string; accent: string; photo: string; disclosure: string };

export async function agentBrand(sb: any, key: string, fallbackAccent = "#0F5661"): Promise<AgentBrand> {
  const { data } = await sb.from("ai_agents").select("key,name,accent,avatar_url,disclosure").eq("key", key).maybeSingle();
  const accent = (data && data.accent) || fallbackAccent;
  const photo = HR_BASE + ((data && data.avatar_url) || ("assets/agents/" + key + ".png"));
  return { key, name: (data && data.name) || key, accent, photo, disclosure: (data && data.disclosure) || "" };
}

const esc = (s: any) => String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

// Pfeil-Vergleich zur Vorperiode (neutral, kein Wertungswort).
export function delta(cur: number, prev: number): string {
  if (prev == null) return "";
  const d = cur - prev;
  if (d === 0) return "unverändert";
  return (d > 0 ? "▲ +" : "▼ ") + d + " vs. Vorwoche";
}

// Bis zu 4 Kennzahl-Kacheln, responsive (stapeln auf dem Telefon). sub = Vergleich/Zusatz.
export function tiles(items: { big: string | number; label: string; sub?: string }[]): string {
  const w = items.length >= 4 ? "25%" : items.length === 3 ? "33%" : items.length === 2 ? "50%" : "100%";
  const cells = items.map((it) =>
    '<td width="' + w + '" valign="top" class="atile" style="padding:0 5px 8px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f5f7f8;border:1px solid #e6ecee;border-radius:12px;"><tr><td style="padding:14px 6px;text-align:center;">'
    + '<div style="font-size:26px;font-weight:bold;color:#0f2830;line-height:1;">' + esc(it.big) + '</div>'
    + '<div style="font-size:11.5px;color:#5b6b70;margin-top:5px;line-height:1.3;">' + esc(it.label) + '</div>'
    + (it.sub ? '<div style="font-size:10.5px;color:#8a979c;margin-top:3px;">' + esc(it.sub) + '</div>' : '')
    + '</td></tr></table></td>').join("");
  return '<tr><td style="padding:18px 12px 2px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="table-layout:fixed;width:100%;"><tr>' + cells + '</tr></table></td></tr>';
}

// Vertikale Balken: Wert oben, Balken proportional, Label unten. Für Verläufe (z. B. je Wochentag).
export function barChart(title: string, bars: { label: string; value: number }[], accent: string): string {
  const max = Math.max(1, ...bars.map((b) => b.value));
  const H = 96;
  const cells = bars.map((b) => {
    const h = b.value > 0 ? Math.max(3, Math.round(H * b.value / max)) : 1;
    const col = b.value > 0 ? accent : "#e0e6e8";
    return '<td valign="bottom" align="center" style="padding:0 3px;">'
      + '<div style="font-size:10px;color:#5b6b70;margin-bottom:3px;">' + esc(b.value) + '</div>'
      + '<div style="height:' + h + 'px;background:' + col + ';border-radius:4px 4px 0 0;"></div>'
      + '<div style="font-size:10px;color:#8a979c;margin-top:4px;">' + esc(b.label) + '</div></td>';
  }).join("");
  return '<tr><td style="padding:14px 22px 2px;">'
    + (title ? '<div style="font-size:12px;color:#5b6b70;font-weight:bold;text-transform:uppercase;letter-spacing:.04em;margin-bottom:10px;">' + esc(title) + '</div>' : '')
    + '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="table-layout:fixed;width:100%;"><tr>' + cells + '</tr></table></td></tr>';
}

// Horizontale Balken: Name links, Balken, Wert rechts. Für Vergleiche über viele Zeilen (z. B. Personen).
// opts.max: gemeinsame Skala über MEHRERE hBars-Aufrufe hinweg (sonst skaliert jeder Aufruf für sich, dann
//   sind Balken aus verschiedenen Gruppen NICHT vergleichbar). opts.compress: gestauchte (log-)Skala bei
//   großer Spannweite, damit ein kleiner Wert neben einem sehr großen noch sichtbar ist.
export function hBars(title: string, rows: { label: string; value: number; note?: string }[], accent: string,
                      opts?: { max?: number; compress?: boolean }): string {
  const max = Math.max(1, opts?.max != null ? opts.max : Math.max(1, ...rows.map((r) => r.value)));
  const compress = opts?.compress === true;
  const width = (v: number) => {
    if (v <= 0) return 0;
    const frac = compress ? Math.log(1 + v) / Math.log(1 + max) : v / max;
    return Math.max(2, Math.min(100, Math.round(100 * frac)));
  };
  const body = rows.map((r) => {
    const w = width(r.value);
    const rest = 100 - w;
    // Beide Zellen mit expliziter Breite (Summe 100), sonst verteilt table-layout:fixed eine 0%-Zelle falsch.
    const barCells = w > 0
      ? '<td width="' + w + '%" bgcolor="' + accent + '" style="height:14px;border-radius:7px;font-size:0;line-height:0;">&nbsp;</td><td width="' + rest + '%" style="font-size:0;line-height:0;">&nbsp;</td>'
      : '<td width="100%" style="font-size:0;line-height:0;">&nbsp;</td>';
    return '<tr><td style="padding:3px 8px 3px 0;font-size:12px;color:#1f2937;width:36%;">' + esc(r.label) + '</td>'
      + '<td style="padding:3px 0;"><table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="width:100%;table-layout:fixed;"><tr>'
      + barCells + '</tr></table></td>'
      + '<td style="padding:3px 0 3px 8px;font-size:11px;color:#5b6b70;text-align:right;white-space:nowrap;">' + esc(r.note != null ? r.note : r.value) + '</td></tr>';
  }).join("");
  return '<tr><td style="padding:14px 22px 2px;">'
    + (title ? '<div style="font-size:12px;color:#5b6b70;font-weight:bold;text-transform:uppercase;letter-spacing:.04em;margin-bottom:8px;">' + esc(title) + '</div>' : '')
    + '<table role="presentation" width="100%" cellpadding="0" cellspacing="0">' + body + '</table></td></tr>';
}

// Beobachtungs-Block: abgesetzt, Gesicht des Agenten links, Text in seiner Stimme.
export function observation(brand: AgentBrand, text: string): string {
  return '<tr><td style="padding:16px 22px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f2f6f7;border-left:4px solid ' + brand.accent + ';border-radius:10px;"><tr>'
    + '<td width="58" valign="top" style="padding:14px 0 14px 14px;"><img src="' + brand.photo + '" width="40" height="40" alt="' + esc(brand.name) + '" style="border-radius:20px;display:block;"></td>'
    + '<td style="padding:14px;font-size:15px;line-height:1.55;color:#1f2937;">' + esc(text).replace(/\n/g, "<br>") + '</td></tr></table></td></tr>';
}

// Metrik-Karte: Name + Notiz links, große farbige Zahl + Delta rechts. tone steuert die Farbe.
//   'bad' = rot (schlechter), 'good' = grün (besser), 'neutral' = dunkel. Für „wer ist schwach/stark".
export function metricCard(o: { name: string; value: string | number; unit?: string; deltaText?: string; tone?: string; note?: string }): string {
  const tone = o.tone || "neutral";
  const col = tone === "bad" ? "#dc2626" : tone === "good" ? "#16a34a" : "#0f2830";
  const bg = tone === "bad" ? "#fef2f2" : tone === "good" ? "#f0fdf4" : "#f5f7f8";
  const bd = tone === "bad" ? "#fecaca" : tone === "good" ? "#bbf7d0" : "#e6ecee";
  return '<tr><td style="padding:5px 22px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:' + bg + ";border:1px solid " + bd + ';border-radius:12px;"><tr>'
    + '<td style="padding:12px 14px;"><div style="font-size:15px;font-weight:700;color:#0f2830;">' + esc(o.name) + "</div>"
    + (o.note ? '<div style="font-size:12.5px;color:#5b6b70;margin-top:3px;line-height:1.4;">' + esc(o.note) + "</div>" : "")
    + '</td><td width="130" valign="top" style="padding:12px 14px;text-align:right;white-space:nowrap;">'
    + '<div style="font-size:24px;font-weight:800;color:' + col + ';line-height:1;">' + esc(o.value) + esc(o.unit || "") + "</div>"
    + (o.deltaText ? '<div style="font-size:11px;font-weight:700;color:' + col + ';margin-top:4px;">' + esc(o.deltaText) + "</div>" : "")
    + "</td></tr></table></td></tr>";
}

// Callout: abgesetzter, farbig umrandeter Block mit Titel — z. B. „Was hilft".
export function callout(title: string, text: string, accent: string): string {
  return '<tr><td style="padding:14px 22px 4px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:' + accent + '10;border-left:4px solid ' + accent + ';border-radius:10px;"><tr>'
    + '<td style="padding:12px 15px;"><div style="font-size:11px;font-weight:800;text-transform:uppercase;letter-spacing:.05em;color:' + accent + ';margin-bottom:5px;">' + esc(title) + "</div>"
    + '<div style="font-size:14px;line-height:1.55;color:#1f2937;">' + esc(text) + "</div></td></tr></table></td></tr>";
}

// Deep-Link an die Handlungsstelle im HR-Portal. Der Router in hr.html liest ?goto=… beim Laden und
// springt genau dorthin (statt nur "Zum System"). Ziele: fx · import(&project&source&kw&year) ·
// emp(&id&tab) · cvs(&filter) · <viewkey> generisch. So kommt man aus jeder Mail direkt zum Handeln.
export function linkGoto(goto: string, params?: Record<string, any>): string {
  const q = new URLSearchParams({ goto });
  if (params) for (const k of Object.keys(params)) { const v = params[k]; if (v != null && v !== "") q.set(k, String(v)); }
  return PORTAL_URL + "?" + q.toString();
}

// Leistungs-Zeile: Name (verlinkbar) + große farbige Zahl + Ampel-Zeichen, darunter ein Balken auf
// GEMEINSAMER Skala mit dem Team-Schnitt als Marke (▲). So sieht man ohne Lesen, wer wo steht.
//   tone: 'bad'(rot) | 'warn'(orange) | 'good'(grün) | 'neutral'.  badge: rohes HTML (farbiger Pfeil/Stern).
//   valuePct/avgPct: 0..100 auf der gemeinsamen Skala (der Aufrufer rechnet sie über alle Zeilen gleich).
export function perfRow(o: { name: string; href?: string; value: string | number; unit?: string; tone?: string; badge?: string; deltaText?: string; note?: string; valuePct?: number; avgPct?: number }): string {
  const tone = o.tone || "neutral";
  const col = tone === "bad" ? "#dc2626" : tone === "warn" ? "#d97706" : tone === "good" ? "#16a34a" : "#0f2830";
  const bg = tone === "bad" ? "#fef2f2" : tone === "warn" ? "#fffbeb" : tone === "good" ? "#f0fdf4" : "#f5f7f8";
  const bd = tone === "bad" ? "#fecaca" : tone === "warn" ? "#fde68a" : tone === "good" ? "#bbf7d0" : "#e6ecee";
  const vp = Math.max(3, Math.min(100, Math.round(o.valuePct || 0))), vr = 100 - vp;
  const ap = Math.max(0, Math.min(98, Math.round(o.avgPct || 0)));
  const nameHtml = o.href
    ? '<a href="' + esc(o.href) + '" style="color:#0f2830;text-decoration:none;border-bottom:1.5px solid ' + col + ';">' + esc(o.name) + "</a>"
    : '<span style="color:#0f2830;">' + esc(o.name) + "</span>";
  const badge = o.badge ? '<span style="font-size:15px;">' + o.badge + "</span> " : "";
  const bar = '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="table-layout:fixed;"><tr>'
    + '<td width="' + vp + '%" bgcolor="' + col + '" style="height:11px;border-radius:6px;font-size:0;line-height:0;">&nbsp;</td>'
    + '<td width="' + vr + '%" bgcolor="#e6ecee" style="font-size:0;line-height:0;">&nbsp;</td></tr></table>';
  const tick = '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="table-layout:fixed;"><tr>'
    + '<td width="' + ap + '%" style="font-size:0;line-height:0;">&nbsp;</td>'
    + '<td style="font-size:11px;color:#5b6b70;line-height:1;white-space:nowrap;">&#9650;</td></tr></table>';
  return '<tr><td style="padding:5px 22px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:' + bg + ";border:1px solid " + bd + ';border-radius:12px;"><tr>'
    + '<td style="padding:11px 14px;">'
    + '<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>'
    + '<td style="font-size:14.5px;font-weight:700;">' + badge + nameHtml + "</td>"
    + '<td style="text-align:right;white-space:nowrap;"><span style="font-size:22px;font-weight:800;color:' + col + ';">' + esc(o.value) + esc(o.unit || "") + "</span></td>"
    + "</tr></table>"
    + (o.deltaText ? '<div style="font-size:11.5px;color:#5b6b70;margin-top:2px;">' + esc(o.deltaText) + "</div>" : "")
    + '<div style="height:7px;font-size:0;line-height:0;">&nbsp;</div>' + bar + tick
    + (o.note ? '<div style="font-size:12px;color:#5b6b70;margin-top:3px;line-height:1.4;">' + esc(o.note) + "</div>" : "")
    + "</td></tr></table></td></tr>";
}

// Aufgaben-/Status-Karte: Titel + Status-Chip, Detailzeile, optionaler Aktions-Link (Deep-Link) direkt
// an die Handlungsstelle. Für Erinnerungen mit einer Liste offener Dinge (z. B. fehlende Uploads je Quelle).
export function taskCard(o: { title: string; state?: string; tone?: string; detail?: string; href?: string; cta?: string }): string {
  const tone = o.tone || "warn";
  const col = tone === "bad" ? "#dc2626" : tone === "warn" ? "#d97706" : tone === "good" ? "#16a34a" : "#0f2830";
  const bg = tone === "bad" ? "#fef2f2" : tone === "warn" ? "#fffbeb" : tone === "good" ? "#f0fdf4" : "#f5f7f8";
  const bd = tone === "bad" ? "#fecaca" : tone === "warn" ? "#fde68a" : tone === "good" ? "#bbf7d0" : "#e6ecee";
  return '<tr><td style="padding:5px 22px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:' + bg + ";border:1px solid " + bd + ';border-radius:12px;"><tr>'
    + '<td style="padding:12px 14px;">'
    + '<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>'
    + '<td style="font-size:14.5px;font-weight:700;color:#0f2830;">' + esc(o.title) + "</td>"
    + (o.state ? '<td style="text-align:right;white-space:nowrap;"><span style="font-size:10.5px;font-weight:800;text-transform:uppercase;letter-spacing:.04em;color:' + col + ";background:#ffffff;border:1px solid " + bd + ';border-radius:20px;padding:3px 9px;">' + esc(o.state) + "</span></td>" : "")
    + "</tr></table>"
    + (o.detail ? '<div style="font-size:12.5px;color:#5b6b70;margin-top:5px;line-height:1.45;">' + esc(o.detail) + "</div>" : "")
    + (o.href && o.cta ? '<div style="margin-top:9px;"><a href="' + esc(o.href) + '" style="display:inline-block;background:' + col + ';color:#ffffff;text-decoration:none;font-size:12.5px;font-weight:700;padding:8px 14px;border-radius:8px;">' + esc(o.cta) + "</a></div>" : "")
    + "</td></tr></table></td></tr>";
}

// Kleine Bezugsgröße (z. B. Team-Schnitt) als abgesetzte Zeile.
export function refLine(text: string): string {
  return '<tr><td style="padding:2px 22px 8px;"><span style="display:inline-block;background:#f0f3f4;border:1px solid #e0e6e8;border-radius:20px;padding:4px 12px;font-size:12px;color:#5b6b70;font-weight:600;">' + esc(text) + "</span></td></tr>";
}

export function button(href: string, label: string, accent: string): string {
  return '<tr><td align="center" style="padding:8px 22px 24px;"><a href="' + esc(href) + '" style="display:inline-block;background:' + accent + ';color:#ffffff;text-decoration:none;font-size:16px;font-weight:bold;padding:14px 30px;border-radius:10px;">' + esc(label) + '</a></td></tr>';
}

// Freitext-Absatz (z. B. Einleitung).
export function lead(html: string): string {
  return '<tr><td style="padding:16px 22px 2px;font-size:14px;line-height:1.6;color:#1f2937;">' + html + '</td></tr>';
}
// Beliebiger Inhalts-Abschnitt (rohes HTML, gepolstert).
export function block(html: string): string {
  return '<tr><td style="padding:6px 22px;">' + html + '</td></tr>';
}

// Rahmen: Kopf (Foto + Name + Untertitel in Agentenfarbe), Inhalt (aus den Bausteinen), Fuß.
export function shell(brand: AgentBrand, headline: string, subtitle: string, inner: string): string {
  const foot = brand.disclosure || ("Automatische Nachricht von " + brand.name + " · 25HRS.");
  return '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
    + '<style>@media only screen and (max-width:480px){.acard{width:100%!important;max-width:100%!important;}.atile{display:block!important;width:100%!important;padding:0 0 8px 0!important;}}</style></head>'
    + '<body style="margin:0;background:#eef2f3;">'
    + '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#eef2f3;padding:16px 0;"><tr><td align="center">'
    + '<table role="presentation" cellpadding="0" cellspacing="0" class="acard" style="max-width:600px;width:100%;background:#ffffff;border-radius:16px;overflow:hidden;font-family:Arial,Helvetica,sans-serif;">'
    + '<tr><td style="background:' + brand.accent + ';padding:20px 22px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>'
    + '<td width="60" valign="middle"><img src="' + brand.photo + '" width="48" height="48" alt="' + esc(brand.name) + '" style="border-radius:24px;display:block;border:2px solid #ffffff;"></td>'
    + '<td valign="middle" style="padding-left:12px;"><div style="font-size:19px;font-weight:bold;color:#ffffff;">' + esc(brand.name) + '</div>'
    + '<div style="font-size:12px;color:#ffffff;opacity:.85;">' + esc(subtitle) + '</div></td></tr></table></td></tr>'
    + (headline ? '<tr><td style="padding:18px 22px 0;"><div style="font-size:18px;font-weight:bold;color:#0f2830;">' + esc(headline) + '</div></td></tr>' : '')
    + inner
    + '<tr><td style="padding:2px 22px 22px;font-size:11px;color:#9ca3af;line-height:1.5;">' + esc(foot) + '</td></tr>'
    + '</table></td></tr></table></body></html>';
}
