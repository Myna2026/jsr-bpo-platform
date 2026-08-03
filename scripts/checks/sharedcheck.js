#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════════════
// sharedcheck.js — Prüfkette für frontend/shared/jsr-calc.js (im Deploy).
//   1. Datei parst/läuft (Syntaxfehler blocken den Deploy).
//   2. window.JSRCalc + erwartete Funktionen existieren.
//   3. Die Urlaubsformel liefert die bekannten Beispielwerte (Regel eingefroren).
// Damit ist die geteilte Datei NICHT außerhalb der Prüfkette.
// ════════════════════════════════════════════════════════════════════════════
const fs = require('fs');
const vm = require('vm');
const path = require('path');

const FILE = path.join(__dirname, '..', '..', 'frontend', 'shared', 'jsr-calc.js');

function fail(msg) { console.error('✗ sharedcheck: ' + msg); process.exit(1); }

let src;
try { src = fs.readFileSync(FILE, 'utf8'); } catch (e) { fail('jsr-calc.js nicht lesbar: ' + e.message); }

const sandbox = { window: {}, console: console };
vm.createContext(sandbox);
try { vm.runInContext(src, sandbox, { filename: 'jsr-calc.js' }); }
catch (e) { fail('Syntax-/Laufzeitfehler beim Laden: ' + e.message); }

const JSR = sandbox.window.JSRCalc;
if (!JSR) fail('window.JSRCalc nicht gesetzt.');
if (typeof JSR.vacationQuota !== 'function') fail('JSRCalc.vacationQuota fehlt.');
if (typeof JSR.holidayDates !== 'function') fail('JSRCalc.holidayDates fehlt.');

// Urlaubsformel gegen die abgestimmten Beispiele (Kalenderjahr 2026, Standard-Config).
const cfg = { year1_days: 18, year2_days: 20, seniority: [] };
const cases = [
  ['2025-11-04', 20], ['2025-02-18', 20], ['2026-02-16', 15],
  ['2026-03-01', 13.5], ['2026-07-20', 7.5], ['2026-12-15', 0],
];
let bad = 0;
for (const [d, exp] of cases) {
  const got = JSR.vacationQuota({ contract: { start: d } }, cfg, '2026-06', '').quota;
  if (got !== exp) { console.error('  Urlaubsformel falsch: Eintritt ' + d + ' → ' + got + ' (erwartet ' + exp + ')'); bad++; }
}
if (bad) fail(bad + ' Urlaubs-Beispiel(e) weichen ab — Regel gebrochen.');

// holidayDates: flacher Datums-Array aus gruppierter Config.
const hd = JSR.holidayDates({ 2026: [{ date: '2026-01-01' }, { date: '2026-12-25' }] });
if (!(Array.isArray(hd) && hd.length === 2 && hd[0] === '2026-01-01')) fail('holidayDates liefert nicht die erwartete flache Liste.');

console.log('sharedcheck: JSRCalc geladen, Urlaubsformel 6/6 korrekt, holidayDates ok. PASS');
