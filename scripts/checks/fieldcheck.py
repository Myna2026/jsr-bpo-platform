#!/usr/bin/env python3
# fieldcheck.py — verifiziert, dass die 7 Verfuegbarkeits-/Planungsfelder sauber sind:
#   (1) in EMP_COLS  -> keine extra-Route, kein Verlust
#   (2) die 5 Flags in EMP_BOOL_COLS -> boolean-Coercion greift
#   (3) Migration legt alle 7 Spalten an
# Soll: 0 Verluste, keine der 7 wird noch gemeldet.
#
# ┌───────────────────────────────────────────────────────────────────────────┐
# │ BASELINE — ACHTUNG, DARF NICHT STILL VERALTEN:                             │
# │   FIELDS (7 Felder) + BOOLS (5 Flags) unten sind die erwartete Wahrheit.   │
# │ Kommt bewusst ein Verfuegbarkeitsfeld dazu/weg, sind FIELDS/BOOLS UND ggf. │
# │ die referenzierte Migration VON HAND anzupassen und im Commit zu           │
# │ begruenden — sonst blockiert der Check den Deploy zu Recht.                │
# └───────────────────────────────────────────────────────────────────────────┘
import re, sys, subprocess, os

root = subprocess.check_output(["git", "rev-parse", "--show-toplevel"]).decode().strip()
hr  = open(os.path.join(root, "frontend/hr.html"), encoding="utf-8").read()
mig = open(os.path.join(root, "migrations/2026-07-20_employees_availability.sql"), encoding="utf-8").read()

FIELDS = ["work_weekend", "work_holidays", "work_saturday", "work_sunday", "work_split", "work_notes", "training_id"]
BOOLS  = ["work_weekend", "work_holidays", "work_saturday", "work_sunday", "work_split"]

def setbody(name):
    m = re.search(r"const " + name + r" = new Set\(\[(.*?)\]\)", hr, re.S)
    return m.group(1) if m else ""
emp_cols = setbody("EMP_COLS")
emp_bool = setbody("EMP_BOOL_COLS")

losses = []
for f in FIELDS:
    in_cols = ("'" + f + "'") in emp_cols
    in_mig  = re.search(r"add column if not exists\s+" + f + r"\b", mig) is not None
    need_bool = f in BOOLS
    in_bool = ("'" + f + "'") in emp_bool
    ok = in_cols and in_mig and (in_bool if need_bool else True)
    flags = []
    if not in_cols: flags.append("NICHT in EMP_COLS -> extra/VERLUST")
    if not in_mig:  flags.append("keine Spalte in Migration")
    if need_bool and not in_bool: flags.append("nicht in EMP_BOOL_COLS")
    status = "ok" if ok else "  <-- " + ", ".join(flags)
    print(f"  {f:<15} cols={'Y' if in_cols else 'N'} mig={'Y' if in_mig else 'N'} bool={'Y' if in_bool else ('-' if not need_bool else 'N')}   {status}")
    if not in_cols: losses.append(f)

reported = [f for f in FIELDS if ("'" + f + "'") not in emp_cols]
print(f"Verluste (Feld ohne Spalte -> extra): {len(losses)}   (soll 0)")
print(f"Noch gemeldete der 7 Felder:          {len(reported)}   (soll 0)")
bad = len(losses) > 0 or len(reported) > 0
print("RESULT:", "FAIL" if bad else "PASS")
sys.exit(1 if bad else 0)
