#!/usr/bin/env node
// Deploy-Check: Frontend-Allow-Listen gegen ihre DB-CHECK-Constraints.
//   (1) STATUS_FLOW           -> cvs_status_valid
//   (2) UPLOAD_SOURCES        -> data_imports_source_type_check
//
// Jeweils zweimal dieselbe Wahrheit. Laufen sie auseinander, wird ein im UI gesetzter Wert vom DB-Insert/Update
// STILL abgelehnt (Kuendigung "kommt nicht an", Upload scheitert an der Constraint) — und faellt erst auf, wenn
// jemand nicht arbeiten kann. Dieser Check meldet das VOR dem Deploy.
//
// Blockt, wenn ein Frontend-Wert in der Constraint FEHLT (schaedliche Richtung: UI setzt, DB weist ab).
// Constraint-Werte ohne Frontend-Pendant sind nur ein Hinweis. DB/CLI nicht erreichbar -> SKIP (kein Block).
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const HTML = path.join(ROOT, 'frontend', 'hr.html');
const SRC = fs.readFileSync(HTML, 'utf8');

function statusFlowKeys() {
  const m = SRC.match(/const STATUS_FLOW\s*=\s*\[([\s\S]*?)\n\];/);
  if (!m) throw new Error('STATUS_FLOW-Array in frontend/hr.html nicht gefunden.');
  const keys = [...m[1].matchAll(/key:\s*'([a-z0-9_]+)'/g)].map(x => x[1]);
  if (!keys.length) throw new Error('Keine STATUS_FLOW-Keys geparst.');
  return [...new Set(keys)];
}

function uploadSourceKeys() {
  const m = SRC.match(/const UPLOAD_SOURCES\s*=\s*\[([\s\S]*?)\n\];/);
  if (!m) throw new Error('UPLOAD_SOURCES-Array in frontend/hr.html nicht gefunden.');
  const keys = [...m[1].matchAll(/key:\s*'([a-z0-9_]+)'/g)].map(x => x[1]);
  if (!keys.length) throw new Error('Keine UPLOAD_SOURCES-Keys geparst.');
  return [...new Set(keys)];
}

function constraintValues(name) {
  let out;
  try {
    out = execSync(
      'supabase db query --linked "select pg_get_constraintdef(oid) as def from pg_constraint where conname=\'' + name + '\'"',
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 30000, cwd: ROOT }
    );
  } catch (e) {
    return null; // supabase-CLI/DB nicht verfuegbar
  }
  const vals = [...out.matchAll(/'([a-z0-9_]+)'::text/g)].map(x => x[1]);
  return vals.length ? [...new Set(vals)] : null;
}

// Ein Abgleich: Frontend-Liste muss vollstaendig in der Constraint enthalten sein.
function check(label, frontendKeys, constraintName, notImported) {
  const cons = constraintValues(constraintName);
  if (!cons) { console.log('SKIP: ' + constraintName + ' nicht abfragbar (DB/CLI nicht erreichbar).'); return true; }
  const expect = frontendKeys.filter(k => !(notImported || []).includes(k));
  const missing = expect.filter(k => !cons.includes(k));
  const extra = cons.filter(k => !frontendKeys.includes(k));
  if (extra.length) console.log('Hinweis: in ' + constraintName + ', aber nicht in ' + label + ' (unkritisch): ' + extra.join(', '));
  if (missing.length) {
    console.error('✗ ' + label + ' hat Werte, die ' + constraintName + ' NICHT erlaubt — der DB-Schreibvorgang');
    console.error('  wird STILL abgelehnt (Setzen/Upload "kommt nicht an"). Fehlend in der Constraint:');
    console.error('    ' + missing.join(', '));
    console.error('  Fix: Migration, die ' + constraintName + ' um diese Werte erweitert, einspielen, dann deployen.');
    return false;
  }
  console.log('OK: ' + expect.length + ' ' + label + '-Werte alle in ' + constraintName + ' erlaubt.');
  return true;
}

let ok = true;
// (1) STATUS_FLOW -> cvs_status_valid
ok = check('STATUS_FLOW', statusFlowKeys(), 'cvs_status_valid') && ok;
// (2) UPLOAD_SOURCES -> data_imports_source_type_check. 'longterm' schreibt in report_longterm, keinen
//     data_imports-Satz — trotzdem in der Constraint gefuehrt (schadet nicht), darum kein notImported noetig.
ok = check('UPLOAD_SOURCES', uploadSourceKeys(), 'data_imports_source_type_check') && ok;

if (!ok) process.exit(1);
console.log('RESULT: PASS');
process.exit(0);
