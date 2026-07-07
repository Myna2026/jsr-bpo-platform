#!/usr/bin/env bash
# =============================================================================
# scripts/verify_schema_coverage.sh
# =============================================================================
# Extrahiert Employee-Feldzugriffe aus frontend/hr.html und vergleicht sie
# gegen die aktuelle EMP_COLS-Whitelist (Feature 25a/25b saveEmployeeToDB).
#
# Reportet:
#   (a) Frontend-Felder NICHT in der Whitelist
#       -> wandern per saveEmployeeToDB ins `extra jsonb`
#       -> Kandidaten fuer Schema-Extension (25c...).
#   (b) Whitelist-Spalten NIE im Frontend genutzt
#       -> potenziell tote Schema-Spalten.
#
# Verwendung:
#   bash scripts/verify_schema_coverage.sh
#
# Kann von jedem Ort im Repo laufen (Root-Detection via git).
# =============================================================================

set -euo pipefail

# --- 0) Repo-Root finden ---
if ! REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "ERROR: nicht in einem git-Repository" >&2
  exit 2
fi
cd "$REPO_ROOT"

HR_HTML="frontend/hr.html"
if [ ! -f "$HR_HTML" ]; then
  echo "ERROR: $HR_HTML nicht gefunden" >&2
  exit 2
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# --- 1) Whitelist aus EMP_COLS in hr.html extrahieren ---
awk '/const EMP_COLS = new Set/{on=1}
     on{print}
     on && /^]\);$/{exit}' "$HR_HTML" \
  | grep -oE "'[a-z_]+'" \
  | tr -d "'" \
  | sort -u > "$TMPDIR/whitelist.txt"

WL_COUNT=$(wc -l < "$TMPDIR/whitelist.txt" | tr -d ' ')

# --- 2) Frontend-Feld-Zugriffe ---
#   Quellen: emp.XYZ, employee.XYZ, newEmp.XYZ, saved.XYZ (alle Employee-Kontext)
#   Filter: JS-Built-in-Methoden auf Arrays/Objekten raus
JS_BUILTINS='^(length|map|filter|find|forEach|some|every|includes|indexOf|push|pop|shift|unshift|splice|slice|reduce|sort|reverse|join|concat|toString|valueOf|hasOwnProperty|constructor|prototype|__proto__)$'

grep -oE "\b(emp|employee|newEmp|saved)\.[a-z_]+" "$HR_HTML" \
  | sed -E 's/^(emp|employee|newEmp|saved)\.//' \
  | grep -vE "$JS_BUILTINS" \
  | sort -u > "$TMPDIR/frontend.txt"

FE_COUNT=$(wc -l < "$TMPDIR/frontend.txt" | tr -d ' ')

# --- 3) Diff ---
comm -23 "$TMPDIR/frontend.txt" "$TMPDIR/whitelist.txt" > "$TMPDIR/missing.txt"
comm -13 "$TMPDIR/frontend.txt" "$TMPDIR/whitelist.txt" > "$TMPDIR/unused.txt"
MISS_COUNT=$(wc -l < "$TMPDIR/missing.txt" | tr -d ' ')
UNUSED_COUNT=$(wc -l < "$TMPDIR/unused.txt" | tr -d ' ')

# --- 4) Report ---
echo "==============================================="
echo "  Feature 25a/25b - Employees Schema Coverage"
echo "==============================================="
echo ""
echo "  Whitelist (EMP_COLS in hr.html): $WL_COUNT Spalten"
echo "  Frontend-Feld-Zugriffe:          $FE_COUNT unique Namen"
echo ""

echo "-----------------------------------------------"
echo "(a) Frontend nutzt, NICHT in Whitelist"
echo "    -> wandert per saveEmployeeToDB in extra"
echo "    -> Kandidat fuer 25c-Schema-Extension"
echo "-----------------------------------------------"
if [ "$MISS_COUNT" -eq 0 ]; then
  echo "  (keine - Frontend nutzt ausschliesslich Whitelist-Spalten)"
else
  echo "  $MISS_COUNT Felder:"
  sed 's/^/    /' "$TMPDIR/missing.txt"
fi
echo ""

echo "-----------------------------------------------"
echo "(b) Whitelist-Spalten NIE im Frontend genutzt"
echo "    -> potenziell tote Schema-Spalten"
echo "-----------------------------------------------"
if [ "$UNUSED_COUNT" -eq 0 ]; then
  echo "  (keine - alle Whitelist-Spalten werden verwendet)"
else
  echo "  $UNUSED_COUNT Felder:"
  sed 's/^/    /' "$TMPDIR/unused.txt"
fi
echo ""

echo "==============================================="
echo "  Fertig. Rein informativ - Exit-Code immer 0."
echo "==============================================="

exit 0
