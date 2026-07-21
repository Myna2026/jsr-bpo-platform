#!/usr/bin/env node
// macheck.js — Syntax-Check fuer frontend/mitarbeiter.html (Vanilla-JS, KEIN Babel).
// Extrahiert die Inline-<script>-Bloecke (ohne src=) und kompiliert sie mit vm.Script:
// das wirft bei Syntaxfehlern, OHNE den Code auszufuehren (Browser-Globals wie
// document/window sind daher egal). Reiner Parse-Check.
//
// KEINE Zahlen-Baseline noetig und daher auch keine, die veralten koennte:
// geprueft wird ausschliesslich Syntax-Gueltigkeit. Ein FAIL hier heisst echtes
// invalides JS in mitarbeiter.html — nicht ein verschobener Sollwert.
const fs = require("fs"), vm = require("vm"), cp = require("child_process"), path = require("path");
let root = "."; try { root = cp.execSync("git rev-parse --show-toplevel").toString().trim(); } catch (e) {}
const file = process.argv[2] || path.join(root, "frontend/mitarbeiter.html");
const s = fs.readFileSync(file, "utf8");

const re = /<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g;
let m, i = 0, bad = 0;
while ((m = re.exec(s))) {
  i++;
  try {
    new vm.Script(m[1], { filename: `mitarbeiter.html#script${i}` });
  } catch (e) {
    bad++;
    console.log(`  Block ${i}: SYNTAXFEHLER — ${e.message}`);
  }
}
console.log(`Inline-Script-Bloecke: ${i}   Syntaxfehler: ${bad}`);
console.log("RESULT:", bad === 0 ? "PASS" : "FAIL");
process.exit(bad === 0 ? 0 : 1);
