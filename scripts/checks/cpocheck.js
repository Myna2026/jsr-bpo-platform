#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════════════
// cpocheck.js — Prüfkette für frontend/shared/cpo-calc.js (im Deploy).
//   1. Datei parst/läuft (Syntaxfehler blocken den Deploy).
//   2. window.CpoCalc + erwartete Funktionen existieren.
//   3. Die Testfälle aus der Spezifikation (§7, Stand 16.09.2026) werden exakt
//      auf 2 Nachkommastellen reproduziert (Regel eingefroren).
// ════════════════════════════════════════════════════════════════════════════
const fs = require('fs');
const vm = require('vm');
const path = require('path');

const FILE = path.join(__dirname, '..', '..', 'frontend', 'shared', 'cpo-calc.js');

function fail(msg) { console.error('✗ cpocheck: ' + msg); process.exit(1); }

let src;
try { src = fs.readFileSync(FILE, 'utf8'); } catch (e) { fail('cpo-calc.js nicht lesbar: ' + e.message); }

const sandbox = { window: {}, console: console };
vm.createContext(sandbox);
try { vm.runInContext(src, sandbox, { filename: 'cpo-calc.js' }); }
catch (e) { fail('Syntax-/Laufzeitfehler beim Laden: ' + e.message); }

const C = sandbox.window.CpoCalc;
if (!C) fail('window.CpoCalc nicht gesetzt.');
for (const fn of ['defaultsFor', 'initialState', 'calcRow', 'calcAll', 'breakEven', 'sensitivity', 'sensitivityRows', 'proposal', 'customerView', 'fmtEur', 'fmtPct']) {
  if (typeof C[fn] !== 'function') fail('CpoCalc.' + fn + ' fehlt.');
}

const PID = 'proj_gn_e5f6a7b8', SKILL = 'retention';
const defs = C.defaultsFor(PID, SKILL);
if (!defs) fail('Keine Defaults für ' + PID + '/' + SKILL + '.');

let bad = 0;
const r2 = v => Math.round(v * 100) / 100;
function expect(name, got, exp, digits) {
  const d = digits === undefined ? 2 : digits;
  const g = Number(got.toFixed(d)), e = Number(exp.toFixed(d));
  if (g !== e) { console.error('  ' + name + ': ' + got + ' (erwartet ' + exp + ')'); bad++; }
}

// §7.1 Kennzahlen der Defaults: Schnitt beim Plan-Mix + Break-even
const state = C.initialState(PID, SKILL);
state.rows.forEach(r => { r.volumen = { downgrade: 400, gleich: 400, upgrade: 200 }[r.key]; });
const plan = C.calcAll(defs, state);
const exp71 = { downgrade: [35.00, 0.800], gleich: [50.20, 0.714], upgrade: [80.10, 0.605] };
plan.rows.forEach(r => {
  expect('7.1 Schnitt ' + r.key, r.cpo_schnitt, exp71[r.key][0]);
  expect('7.1 Break-even ' + r.key, r.break_even, exp71[r.key][1], 3);
});

// §7.2 Umsatz mit Beispielvolumen 400/400/200, Umsatz alt gesamt 50.000
expect('7.2 Umsatz alt gesamt', plan.total.umsatz_alt, 50000);
const exp72 = { '-10': [51490, 1490, 0.0298], '0': [50100, 100, 0.0020], '10': [48710, -1290, -0.0258] };
C.sensitivity(defs, state, [-10, 0, 10]).forEach(s => {
  const e = exp72[String(s.punkte)];
  expect('7.2 Umsatz neu bei ' + s.punkte, s.umsatz_neu, e[0]);
  expect('7.2 Delta € bei ' + s.punkte, s.delta_eur, e[1]);
  expect('7.2 Delta % bei ' + s.punkte, s.delta_prozent, e[2], 4);
});

// §7.3 Sensitivität je Ergebnis (Delta % des Schnitts zur Referenz), auf 1 Nachkommastelle in %
const exp73 = {
  downgrade: [2.9, 1.4, 0.0, -1.4, -2.9],
  gleich:    [3.2, 1.8, 0.4, -1.0, -2.4],
  upgrade:   [2.8, 1.5, 0.1, -1.2, -2.6]
};
C.sensitivityRows(defs, state).forEach(row => {
  row.werte.forEach((w, i) => expect('7.3 ' + row.key + ' bei ' + w.punkte, w.delta_prozent * 100, exp73[row.key][i], 1));
});

// §7.4 Vorschlag mit Abstand 30 %: L_roh, L, H (gleich → 59,50 laut Formel, Default 60,00 hat Vorrang)
const exp74 = { downgrade: [33.02, 33.00, 43.00], gleich: [45.87, 46.00, 59.50], upgrade: [71.43, 71.50, 93.00] };
defs.ergebnisse.forEach(def => {
  const p = C.proposal(def, 0.30, 0.50);
  if (!p) { console.error('  7.4 Vorschlag ' + def.key + ' fehlt'); bad++; return; }
  expect('7.4 L_roh ' + def.key, p.L_roh, exp74[def.key][0]);
  expect('7.4 L ' + def.key, p.L, exp74[def.key][1]);
  expect('7.4 H ' + def.key, p.H, exp74[def.key][2]);
  if (p.schnitt < def.referenz_cpo - 1e-9) { console.error('  7.4 Schnitt unter Referenz bei ' + def.key); bad++; }
});

// §6.3 Ampel-Grenzen
if (C.ampel(0) !== 'green' || C.ampel(-0.02) !== 'yellow' || C.ampel(-0.0201) !== 'red' || C.ampel(null) !== 'none') { console.error('  Ampel-Grenzen falsch'); bad++; }

// §8 Grenzfälle: H ≤ L, negatives Volumen, Anteil außerhalb → als Fehler benannt, nicht gerechnet
const bad1 = C.calcRow(defs.ergebnisse[0], { volumen: 10, anteil_stufe2: 0.8, cpo_stufe2: 43, cpo_stufe1: 43 }, 0);
if (bad1.ok || bad1.errors.indexOf('h_le_l') < 0 || bad1.break_even !== null) { console.error('  H ≤ L nicht abgefangen'); bad++; }
const bad2 = C.calcRow(defs.ergebnisse[0], { volumen: -1, anteil_stufe2: 1.2, cpo_stufe2: 33, cpo_stufe1: 43 }, 0);
if (bad2.ok || bad2.errors.indexOf('volumen') < 0 || bad2.errors.indexOf('anteil') < 0) { console.error('  negatives Volumen / Anteil > 100 nicht abgefangen'); bad++; }
const bad3 = C.calcRow(defs.ergebnisse[0], { volumen: null, anteil_stufe2: 0.8, cpo_stufe2: 33, cpo_stufe1: 43 }, 0);
if (bad3.ok || bad3.errors.indexOf('volumen_leer') < 0) { console.error('  leeres Volumen nicht als Pflichtfeld erkannt'); bad++; }
// Verschiebung wird auf 0..1 begrenzt
const cl = C.calcRow(defs.ergebnisse[0], { volumen: 1, anteil_stufe2: 0.95, cpo_stufe2: 33, cpo_stufe1: 43 }, 20);
if (cl.anteil_eff !== 1) { console.error('  Verschiebung nicht auf 100 % begrenzt'); bad++; }

// Kundenansicht enthält keine internen Werte
const cv = C.customerView(defs, state);
const forbidden = ['break_even', 'umsatz_neu', 'umsatz_alt', 'delta_eur', 'delta_prozent', 'anteil_stufe2', 'plan_anteil_stufe2', 'volumen'];
cv.forEach(r => forbidden.forEach(k => { if (k in r) { console.error('  Kundenansicht enthält internen Wert ' + k); bad++; } }));

// Deutsches Format (Intl setzt ein geschütztes Leerzeichen vor €)
if (C.fmtEur(1234.5).replace(/ /g, ' ') !== '1.234,50 €') { console.error('  fmtEur: ' + C.fmtEur(1234.5)); bad++; }

if (bad) fail(bad + ' Abweichung(en) von der Spezifikation.');
console.log('✓ cpocheck: cpo-calc.js lädt, Testfälle §7.1–7.4 + Grenzfälle + Kundenansicht ok.');
