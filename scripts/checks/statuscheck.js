#!/usr/bin/env node
// Deploy-Check: STATUS_FLOW (frontend/hr.html) vs. DB-Constraint cvs_status_valid.
//
// STATUS_FLOW und die CHECK-Constraint sind zweimal dieselbe Wahrheit. Laufen sie auseinander, wird ein im UI
// gesetzter Status vom DB-Update STILL abgelehnt (z.B. Kuendigung "kommt nicht an") — und faellt erst auf, wenn
// jemand nicht arbeiten kann. Dieser Check meldet das VOR dem Deploy.
//
// Blockt, wenn ein STATUS_FLOW-Status in der Constraint FEHLT (schaedliche Richtung: UI setzt, DB weist ab).
// Constraint-Werte, die nicht in STATUS_FLOW stehen (z.B. terminated_by_*), sind nur ein Hinweis.
// Ist die DB/CLI nicht erreichbar -> SKIP (kein Block, damit der Deploy nicht hart an der DB haengt).
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const HTML = path.join(ROOT, 'frontend', 'hr.html');

function statusFlowKeys() {
  const src = fs.readFileSync(HTML, 'utf8');
  const m = src.match(/const STATUS_FLOW\s*=\s*\[([\s\S]*?)\n\];/);
  if (!m) throw new Error('STATUS_FLOW-Array in frontend/hr.html nicht gefunden.');
  const keys = [...m[1].matchAll(/key:\s*'([a-z0-9_]+)'/g)].map(x => x[1]);
  if (!keys.length) throw new Error('Keine STATUS_FLOW-Keys geparst.');
  return [...new Set(keys)];
}

function constraintValues() {
  let out;
  try {
    out = execSync(
      'supabase db query --linked "select pg_get_constraintdef(oid) as def from pg_constraint where conname=\'cvs_status_valid\'"',
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 30000 }
    );
  } catch (e) {
    return null; // supabase-CLI/DB nicht verfuegbar
  }
  const vals = [...out.matchAll(/'([a-z0-9_]+)'::text/g)].map(x => x[1]);
  return vals.length ? [...new Set(vals)] : null;
}

const flow = statusFlowKeys();
const cons = constraintValues();

if (!cons) {
  console.log('SKIP: cvs_status_valid nicht abfragbar (supabase/DB nicht erreichbar) — Status-Abgleich uebersprungen.');
  process.exit(0);
}

const missingInDb = flow.filter(k => !cons.includes(k));
const extraInDb = cons.filter(k => !flow.includes(k));

if (extraInDb.length) {
  console.log('Hinweis: in cvs_status_valid, aber nicht in STATUS_FLOW (unkritisch): ' + extraInDb.join(', '));
}

if (missingInDb.length) {
  console.error('✗ STATUS_FLOW hat Status, die cvs_status_valid NICHT erlaubt — ein Setzen wird von der DB');
  console.error('  still abgelehnt (z.B. Kuendigung "kommt nicht an"). Fehlend in der Constraint:');
  console.error('    ' + missingInDb.join(', '));
  console.error('  Fix: Migration, die cvs_status_valid um diese Werte erweitert (Muster: migrations/*_cvs_status_*.sql),');
  console.error('  einspielen, dann erneut deployen.');
  process.exit(1);
}

console.log('RESULT: PASS (' + flow.length + ' STATUS_FLOW-Status alle in cvs_status_valid erlaubt)');
process.exit(0);
