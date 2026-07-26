#!/usr/bin/env node
// syntaxcheck.js — ECHTER Parse-Check fuer frontend/hr.html.
//
// Ergaenzt balcheck/jsxcheck (die NUR Klammern zaehlen und z.B. ein unescaptes
// Anfuehrungszeichen im JSX-Attribut NICHT fangen). Hier wird jeder
// <script type="text/babel">-Block mit @babel/parser (JSX) tatsaechlich geparst.
// Findet echte Syntaxfehler und meldet die Datei-globale Zeile/Spalte.
//
// Exit 0 = alle Bloecke parsen sauber. Exit 1 = Parse-Fehler ODER Parser fehlt.

const fs = require("fs"), cp = require("child_process"), path = require("path");

let root = "."; try { root = cp.execSync("git rev-parse --show-toplevel").toString().trim(); } catch (e) {}
const here = __dirname;

// Parser laden — bei Bedarf einmalig lokal nachinstallieren (self-healing, kein stiller Skip).
let parser;
function loadParser() { try { parser = require(path.join(here, "node_modules/@babel/parser")); return true; } catch (e) { return false; } }
if (!loadParser()) {
  process.stderr.write("  @babel/parser fehlt — installiere einmalig (npm install aus scripts/checks/package.json)…\n");
  // npm install (ohne Paketnamen) liest die package.json und installiert ALLE deklarierten
  // Dev-Tools gemeinsam — pruned die anderen Checks (eslint u.a.) NICHT weg.
  try { cp.execSync("npm install", { cwd: here, stdio: "ignore" }); } catch (e) {}
  if (!loadParser()) {
    console.log("RESULT: FAIL  (@babel/parser nicht verfuegbar — 'cd scripts/checks && npm install')");
    process.exit(1);
  }
}

const file = process.argv[2] || path.join(root, "frontend/hr.html");
const s = fs.readFileSync(file, "utf8");

// Zeile (1-basiert) an einem Zeichen-Offset.
const lineAt = (idx) => s.slice(0, idx).split("\n").length;

const openRe = /<script[^>]*type=["']text\/babel["'][^>]*>/g;
let blocks = 0, failed = 0, m;
while ((m = openRe.exec(s))) {
  const end = s.indexOf("</script>", m.index);
  if (end === -1) continue;
  blocks++;
  const bodyStart = m.index + m[0].length;
  const body = s.slice(bodyStart, end);
  const baseLine = lineAt(bodyStart); // Datei-Zeile, in der der Block-Body beginnt
  try {
    parser.parse(body, {
      sourceType: "unambiguous",
      errorRecovery: false,
      plugins: ["jsx", "optionalChaining", "nullishCoalescingOperator", "objectRestSpread"],
    });
  } catch (err) {
    failed++;
    const loc = err.loc || {};
    const fileLine = loc.line ? baseLine + loc.line - 1 : "?";
    console.log(`  ✗ Block #${blocks}: ${err.message.replace(/\s*\(\d+:\d+\)\s*$/, "")}`);
    console.log(`    -> ${path.relative(root, file)}:${fileLine}:${(loc.column ?? 0) + 1}`);
  }
}

const ok = failed === 0;
console.log(`geparste babel-Bloecke: ${blocks}   fehlerhaft: ${failed}   ${ok ? "ok" : "SYNTAXFEHLER"}`);
console.log("RESULT:", ok ? "PASS" : "FAIL");
process.exit(ok ? 0 : 1);
