/* ════════════════════════════════════════════════════════════════════════════
 * TIVE 360° — CPO-KALKULATOR RABATTSTUFEN (Rechenkern)
 * ────────────────────────────────────────────────────────────────────────────
 * Spezifikation: CPO_Rabattstufen_Kalkulator_Spezifikation.md (Stand 16.09.2026),
 * Mandat Deutsche GigaNetz, Skill Retention. Reine Funktionen (Eingabe → Wert),
 * kein DOM/React/Supabase. Eingebunden per
 * <script src="shared/cpo-calc.js?v=__BUILD_ID__"> und genutzt über window.CpoCalc.
 *
 * Begriffe je Ergebnis (Spec §5):
 *   R = Referenz alter CPO (nur Vergleich, wird NIE abgerechnet)
 *   L = CPO Stufe 2 (hoher Endkunden-Rabatt → niedriger CPO)
 *   H = CPO Stufe 1 (geringer Endkunden-Rabatt → hoher CPO)
 *   s = tatsächlicher Anteil Stufe 2 (0..1) nach globaler Verschiebung + Begrenzung
 *   N = Volumen (Abschlüsse pro Monat)
 *
 * Prüfung: scripts/checks/cpocheck.js (im Deploy) rechnet die Testfälle aus
 * Spec §7 nach; Abweichungen blockieren den Deploy.
 * ════════════════════════════════════════════════════════════════════════════ */
(function (global) {
  'use strict';

  // ── Defaults je Mandat (Spec §2/§3). Schlüssel = project_id + '/' + skill. ──
  var MANDATES = {
    'proj_gn_e5f6a7b8/retention': {
      mandat: 'giganetz_retention',
      label: 'Deutsche GigaNetz · Retention',
      parameter: { abstand: 0.30, abstand_min: 0.25, abstand_max: 0.35, rundung: 0.50, waehrung: 'EUR', verschiebung_min: -20, verschiebung_max: 20 },
      ergebnisse: [
        { key: 'downgrade', label: 'Downgrade, aber gehalten', referenz_cpo: 35.00, plan_anteil_stufe2: 0.80, cpo_stufe2: 33.00, cpo_stufe1: 43.00 },
        { key: 'gleich',    label: 'Gleiche Tarifklasse',      referenz_cpo: 50.00, plan_anteil_stufe2: 0.70, cpo_stufe2: 46.00, cpo_stufe1: 60.00 },
        { key: 'upgrade',   label: 'Upgrade',                  referenz_cpo: 80.00, plan_anteil_stufe2: 0.60, cpo_stufe2: 71.50, cpo_stufe1: 93.00 }
      ]
    }
  };

  function num(v, d) { v = Number(v); return isFinite(v) ? v : d; }
  function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }
  function r2(v) { return Math.round(v * 100) / 100; }
  function clone(o) { return JSON.parse(JSON.stringify(o)); }

  function mandateKey(projectId, skill) { return (projectId || '') + '/' + ((skill || '') + '').toLowerCase(); }
  function defaultsFor(projectId, skill) { var m = MANDATES[mandateKey(projectId, skill)]; return m ? clone(m) : null; }

  // Leerer Rechnerstand aus den Defaults: Volumen leer (Pflichtfeld), Anteil = Plan-Anteil,
  // CPOs = verhandelte Defaults, Verschiebung 0, Abstand aus den Parametern.
  function initialState(projectId, skill) {
    var d = defaultsFor(projectId, skill);
    if (!d) return null;
    return {
      mandat: d.mandat,
      verschiebung: 0,                                   // Prozentpunkte, -20..+20
      abstand: d.parameter.abstand,                      // nur für "Vorschlag berechnen"
      rows: d.ergebnisse.map(function (e) {
        return { key: e.key, volumen: null, anteil_stufe2: e.plan_anteil_stufe2, cpo_stufe2: e.cpo_stufe2, cpo_stufe1: e.cpo_stufe1 };
      })
    };
  }

  // ── §5.2 Break-even: Anteil Stufe 2, bei dem Umsatz neu = Umsatz alt. Nur wenn H > L. ──
  function breakEven(R, L, H) {
    R = num(R, NaN); L = num(L, NaN); H = num(H, NaN);
    if (!(H > L) || !isFinite(R)) return null;
    return (H - R) / (H - L);
  }

  // ── §5.1 + §5.3 eine Zeile. anteil = Eingabe 0..1, verschiebung in Prozentpunkten. ──
  // Liefert Kennzahlen + Validierungsfehler (fehlende/ungültige Eingaben werden benannt, nicht erraten).
  function calcRow(def, row, verschiebung) {
    var R = num(def.referenz_cpo, NaN);
    var L = num(row.cpo_stufe2, NaN);
    var H = num(row.cpo_stufe1, NaN);
    var N = (row.volumen === null || row.volumen === undefined || row.volumen === '') ? null : num(row.volumen, NaN);
    var sIn = num(row.anteil_stufe2, NaN);
    var errors = [];
    if (!isFinite(L) || L < 0) errors.push('cpo_stufe2');
    if (!isFinite(H) || H < 0) errors.push('cpo_stufe1');
    if (isFinite(L) && isFinite(H) && !(H > L)) errors.push('h_le_l');          // Stufe 1 muss über Stufe 2 liegen
    if (N === null) errors.push('volumen_leer');
    else if (!isFinite(N) || N < 0 || Math.floor(N) !== N) errors.push('volumen');
    if (!isFinite(sIn) || sIn < 0 || sIn > 1) errors.push('anteil');

    var anteilEff = isFinite(sIn) ? clamp(sIn + num(verschiebung, 0) / 100, 0, 1) : NaN;
    var ok = errors.length === 0;
    var cpoSchnitt = (isFinite(L) && isFinite(H) && isFinite(anteilEff)) ? anteilEff * L + (1 - anteilEff) * H : NaN;
    var umsatzNeu = ok ? N * cpoSchnitt : NaN;
    var umsatzAlt = ok ? N * R : NaN;
    var deltaEur = ok ? umsatzNeu - umsatzAlt : NaN;
    var deltaPct = (ok && umsatzAlt > 0) ? (umsatzNeu / umsatzAlt) - 1 : null;
    // Delta % ist volumenunabhängig (Schnitt zur Referenz) → auch ohne Volumen zeigbar (Sensitivität).
    var deltaPctSchnitt = (isFinite(cpoSchnitt) && R > 0) ? cpoSchnitt / R - 1 : null;

    return {
      key: def.key, label: def.label,
      R: R, L: L, H: H, N: N,
      anteil_eingabe: sIn, anteil_eff: anteilEff,
      cpo_schnitt: cpoSchnitt,
      umsatz_neu: umsatzNeu, umsatz_alt: umsatzAlt,
      delta_eur: deltaEur, delta_prozent: deltaPct, delta_prozent_schnitt: deltaPctSchnitt,
      break_even: breakEven(R, L, H),
      abweichung_stufe2: (R > 0 && isFinite(L)) ? L / R - 1 : null,
      abweichung_stufe1: (R > 0 && isFinite(H)) ? H / R - 1 : null,
      abstand_ist: (L > 0 && isFinite(H)) ? H / L - 1 : null,
      ampel: ampel(deltaPct !== null ? deltaPct : deltaPctSchnitt),
      errors: errors, ok: ok
    };
  }

  // ── §6.3 Ampel: grün ≥ 0, gelb 0 bis −2 %, rot unter −2 %. ──
  function ampel(deltaPct) {
    if (deltaPct === null || deltaPct === undefined || !isFinite(deltaPct)) return 'none';
    if (deltaPct >= 0) return 'green';
    if (deltaPct >= -0.02) return 'yellow';
    return 'red';
  }

  // ── Alle Zeilen + Summen (§5.1 letzter Absatz). Summen nur über gültige Zeilen; ──
  // ist eine Zeile ungültig, wird das in `complete:false` sichtbar statt still summiert.
  function calcAll(defs, state) {
    var rows = defs.ergebnisse.map(function (def) {
      var row = (state.rows || []).filter(function (r) { return r.key === def.key; })[0] || {};
      return calcRow(def, row, state.verschiebung);
    });
    var neu = 0, alt = 0, complete = true;
    rows.forEach(function (r) { if (r.ok) { neu += r.umsatz_neu; alt += r.umsatz_alt; } else complete = false; });
    var any = rows.some(function (r) { return r.ok; });
    return {
      rows: rows,
      total: {
        umsatz_neu: any ? neu : NaN, umsatz_alt: any ? alt : NaN,
        delta_eur: any ? neu - alt : NaN,
        delta_prozent: (any && alt > 0) ? neu / alt - 1 : null,
        ampel: ampel((any && alt > 0) ? neu / alt - 1 : null),
        complete: complete
      }
    };
  }

  // ── §6.4 Sensitivität: Gesamtumsatz + Delta % bei zusätzlicher Verschiebung. ──
  // Die Punkte werden ZUSÄTZLICH zur eingestellten Verschiebung angewendet (0 = aktueller Stand).
  function sensitivity(defs, state, points) {
    points = points || [-10, -5, 0, 5, 10];
    return points.map(function (p) {
      var s = clone(state); s.verschiebung = num(state.verschiebung, 0) + p;
      var t = calcAll(defs, s).total;
      return { punkte: p, umsatz_neu: t.umsatz_neu, delta_eur: t.delta_eur, delta_prozent: t.delta_prozent, ampel: t.ampel };
    });
  }

  // ── §7.3 Sensitivität je Ergebnis: Delta % des Schnitts zur Referenz bei Anteil ± Punkte. ──
  function sensitivityRows(defs, state, points) {
    points = points || [-10, -5, 0, 5, 10];
    return defs.ergebnisse.map(function (def) {
      var row = (state.rows || []).filter(function (r) { return r.key === def.key; })[0] || {};
      return {
        key: def.key, label: def.label,
        werte: points.map(function (p) {
          var r = calcRow(def, row, num(state.verschiebung, 0) + p);
          return { punkte: p, anteil_eff: r.anteil_eff, delta_prozent: r.delta_prozent_schnitt };
        })
      };
    });
  }

  // ── §6.5 Kurve Delta % über Anteil Stufe 2 (0..1) je Ergebnis, für das Diagramm. ──
  function curve(def, row, steps) {
    steps = steps || 20;
    var R = num(def.referenz_cpo, NaN), L = num(row.cpo_stufe2, NaN), H = num(row.cpo_stufe1, NaN);
    var pts = [];
    for (var i = 0; i <= steps; i++) {
      var s = i / steps;
      var schnitt = s * L + (1 - s) * H;
      pts.push({ anteil: s, delta_prozent: R > 0 ? schnitt / R - 1 : null });
    }
    return pts;
  }

  // ── §5.4 Vorschlag: L auf nächste 0,50 gerundet, H AUFgerundet → Plan-Schnitt nie unter R. ──
  function roundNearest(v, step) { return Math.round(v / step) * step; }
  function roundUp(v, step) { return Math.ceil(v / step - 1e-9) * step; }   // 1e-9: 43.0000001 nicht auf 43.5 heben
  function proposal(def, abstand, rundung, planAnteil) {
    var R = num(def.referenz_cpo, NaN);
    var w = num(planAnteil !== undefined ? planAnteil : def.plan_anteil_stufe2, NaN);
    var a = num(abstand, 0.30);
    var step = num(rundung, 0.50);
    if (!isFinite(R) || !isFinite(w) || w <= 0 || w >= 1) return null;
    var Lroh = R / (w + (1 - w) * (1 + a));
    var L = r2(roundNearest(Lroh, step));
    var Hmin = (R - w * L) / (1 - w);
    var H = r2(roundUp(Hmin, step));
    var schnitt = w * L + (1 - w) * H;
    if (schnitt < R - 1e-9) H = r2(H + step);       // Sicherheitsnetz, darf nach roundUp nicht greifen
    return { key: def.key, L_roh: r2(Lroh), L: L, H_min: r2(Hmin), H: H, schnitt: r2(w * L + (1 - w) * H) };
  }

  function proposals(defs, state) {
    return defs.ergebnisse.map(function (def) {
      var row = (state.rows || []).filter(function (r) { return r.key === def.key; })[0] || {};
      return proposal(def, state.abstand, defs.parameter.rundung, row.anteil_stufe2);
    });
  }

  // ── Kundenansicht (§6.6): nur die beiden CPOs + Abweichung zur Referenz. Keine internen Werte. ──
  function customerView(defs, state) {
    return defs.ergebnisse.map(function (def) {
      var row = (state.rows || []).filter(function (r) { return r.key === def.key; })[0] || {};
      var R = num(def.referenz_cpo, NaN), L = num(row.cpo_stufe2, NaN), H = num(row.cpo_stufe1, NaN);
      return {
        key: def.key, label: def.label,
        referenz_cpo: R, cpo_stufe2: L, cpo_stufe1: H,
        abweichung_stufe2: R > 0 ? L / R - 1 : null,
        abweichung_stufe1: R > 0 ? H / R - 1 : null
      };
    });
  }

  // ── Formatierung (§8: deutsches Format 1.234,50 €). ──
  function fmtEur(v) {
    if (v === null || v === undefined || !isFinite(v)) return '–';
    return v.toLocaleString('de-DE', { style: 'currency', currency: 'EUR', minimumFractionDigits: 2, maximumFractionDigits: 2 });
  }
  function fmtPct(v, digits, signed) {
    if (v === null || v === undefined || !isFinite(v)) return '–';
    var d = digits === undefined ? 1 : digits;
    var s = (v * 100).toLocaleString('de-DE', { minimumFractionDigits: d, maximumFractionDigits: d });
    if (signed && v > 0) s = '+' + s;
    return s + ' %';
  }

  // Mandats-Schlüssel eines Projekts (für Projektleiter: nur das eigene Projekt). Leer, wenn kein Mandat.
  function mandatesForProject(projectId) {
    if (!projectId) return [];
    return Object.keys(MANDATES).filter(function (k) { return k.split('/')[0] === projectId; });
  }

  global.CpoCalc = {
    MANDATES: MANDATES,
    mandateKey: mandateKey, mandatesForProject: mandatesForProject, defaultsFor: defaultsFor, initialState: initialState,
    calcRow: calcRow, calcAll: calcAll, breakEven: breakEven, ampel: ampel,
    sensitivity: sensitivity, sensitivityRows: sensitivityRows, curve: curve,
    proposal: proposal, proposals: proposals, customerView: customerView,
    fmtEur: fmtEur, fmtPct: fmtPct, clamp: clamp
  };
})(typeof window !== 'undefined' ? window : this);
