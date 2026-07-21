#!/usr/bin/env python3
# balcheck.py — Delimiter-/Script-Tag-Balance fuer frontend/hr.html
#
# ┌───────────────────────────────────────────────────────────────────────────┐
# │ BASELINE — ACHTUNG, DARF NICHT STILL VERALTEN:                             │
# │   ()=-23   {}=0   []=0   script 27/27                                       │
# │ Diese Werte sind ABSICHTLICH hart verdrahtet (BASE unten). Wenn eine       │
# │ BEWUSSTE Aenderung sie verschiebt (neuer <script>-Block, ein zusaetzliches │
# │ unbalanciertes Zeichen in String/Kommentar/Regex), dann ist der neue Stand │
# │ die neue Wahrheit → BASE hier VON HAND anpassen und im Commit begruenden.  │
# │ Nicht wegdruecken, nicht --force zur Gewohnheit machen: der Check ist das  │
# │ Netz gegen kaputte Deploys ins Live-System.                                │
# └───────────────────────────────────────────────────────────────────────────┘
import sys, subprocess, os

path = sys.argv[1] if len(sys.argv) > 1 else "frontend/hr.html"
try:
    root = subprocess.check_output(["git", "rev-parse", "--show-toplevel"]).decode().strip()
except Exception:
    root = "."
if not os.path.isabs(path):
    path = os.path.join(root, path)

s = open(path, encoding="utf-8").read()
def delta(o, c): return s.count(o) - s.count(c)

paren = delta("(", ")")
brace = delta("{", "}")
brack = delta("[", "]")
so, sc = s.count("<script"), s.count("</script>")

BASE = {"paren": -23, "brace": 0, "brack": 0, "script": (27, 27)}
ok = (paren == BASE["paren"] and brace == BASE["brace"] and brack == BASE["brack"]
      and (so, sc) == BASE["script"])

print(f"() = {paren:>4}   (baseline {BASE['paren']})   {'ok' if paren==BASE['paren'] else 'DRIFT'}")
print(f"{{}} = {brace:>4}   (baseline {BASE['brace']})   {'ok' if brace==BASE['brace'] else 'DRIFT'}")
print(f"[] = {brack:>4}   (baseline {BASE['brack']})   {'ok' if brack==BASE['brack'] else 'DRIFT'}")
print(f"script = {so}/{sc}   (baseline 27/27)   {'ok' if (so,sc)==BASE['script'] else 'DRIFT'}")
print("RESULT:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
