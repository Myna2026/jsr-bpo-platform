#!/usr/bin/env node
// jsxcheck.js — Babel-Block-Integritaet fuer frontend/hr.html
//
// ┌───────────────────────────────────────────────────────────────────────────┐
// │ BASELINE — ACHTUNG, DARF NICHT STILL VERALTEN:  19/19                       │
// │   (jeder <script type="text/babel">-Block sauber geschlossen + brace-       │
// │   balanciert). Kommt EIN Babel-Block dazu oder faellt einer weg, ist die    │
// │   erwartete Zahl unten (=== 19) VON HAND anzupassen und im Commit zu        │
// │   begruenden. Der Check ist das Netz gegen kaputte Live-Deploys — nicht     │
// │   stillschweigend ueber --force umgehen.                                    │
// └───────────────────────────────────────────────────────────────────────────┘
const fs = require("fs"), cp = require("child_process"), path = require("path");
let root = "."; try { root = cp.execSync("git rev-parse --show-toplevel").toString().trim(); } catch (e) {}
const file = process.argv[2] || path.join(root, "frontend/hr.html");
const s = fs.readFileSync(file, "utf8");

const openRe = /<script[^>]*type=["']text\/babel["'][^>]*>/g;
let opened = 0, closedOk = 0, balanced = 0, m;
while ((m = openRe.exec(s))) {
  opened++;
  const end = s.indexOf("</script>", m.index);
  if (end === -1) continue;
  closedOk++;
  const body = s.slice(m.index + m[0].length, end);
  if ((body.split("{").length - body.split("}").length) === 0) balanced++;
}
const ok = opened === 19 && closedOk === 19 && balanced === 19;
console.log(`babel-Bloecke geoeffnet/geschlossen: ${closedOk}/${opened}   (baseline 19/19)   ${closedOk===opened&&opened===19?"ok":"DRIFT"}`);
console.log(`brace-balanciert:                    ${balanced}/${opened}                        ${balanced===opened?"ok":"DRIFT"}`);
console.log("RESULT:", ok ? "PASS" : "FAIL");
process.exit(ok ? 0 : 1);
