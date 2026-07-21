#!/bin/bash
# rollback.sh — stellt einen von deploy.sh gesicherten Live-Stand wieder her.
# Zeigt ZUERST an, welche Staende es gibt (Zeitstempel, Alter, Ordner) und
# verlangt eine ausdrueckliche Bestaetigung. Kein blindes Zuruecksetzen.
set -e

SERVER="root@178.104.147.208"
REMOTE_BASE="/var/www/tive360"

echo "=== TIVE 360° Rollback ==="
echo ""

# Alle Backups auf einmal abfragen: je Stand eine Zeile  name|mtime_epoch|groesse|ordner
LIST=$(ssh "$SERVER" "cd $REMOTE_BASE/_backups 2>/dev/null || exit 0; for d in \$(ls -1t 2>/dev/null); do [ -d \"\$d\" ] || continue; sz=\$(du -sh \"\$d\" 2>/dev/null | cut -f1); portals=\$(ls \"\$d\" 2>/dev/null | tr '\n' ' '); mt=\$(stat -c %Y \"\$d\" 2>/dev/null); echo \"\$d|\$mt|\$sz|\$portals\"; done")

if [ -z "$LIST" ]; then
  echo "Keine Backups gefunden unter $REMOTE_BASE/_backups/"
  echo "(Ein Backup entsteht automatisch beim naechsten ./deploy.sh.)"
  exit 1
fi

echo "Verfuegbare Staende (neueste zuerst):"
echo ""
NOW=$(date +%s)
i=0
while IFS='|' read -r name mt sz portals; do
  [ -z "$name" ] && continue
  i=$((i + 1))
  NAMES[$i]="$name"
  age="?"
  if [ -n "$mt" ]; then
    diff=$((NOW - mt))
    if   [ "$diff" -lt 3600 ];  then age="vor $((diff / 60)) min"
    elif [ "$diff" -lt 86400 ]; then age="vor $((diff / 3600)) h"
    else age="vor $((diff / 86400)) Tagen"; fi
  fi
  printf "  [%d]  %-22s  %-14s  %-6s  Ordner: %s\n" "$i" "$name" "$age" "$sz" "$portals"
done <<EOF
$LIST
EOF

echo ""
printf "Nummer zum Wiederherstellen (Enter = Abbruch): "
read -r choice || true
if [ -z "$choice" ]; then echo "Abgebrochen."; exit 0; fi
case "$choice" in
  *[!0-9]*) echo "Ungueltige Eingabe."; exit 1;;
esac
SEL="${NAMES[$choice]}"
if [ -z "$SEL" ]; then echo "Ungueltige Auswahl."; exit 1; fi

echo ""
echo "→ Ausgewaehlt: $SEL"
echo "  Das ueberschreibt die aktuellen Live-Dateien (hr/mitarbeiter/client/root)"
echo "  mit dem gesicherten Stand. Der JETZIGE Live-Stand wird dabei NICHT extra"
echo "  gesichert — erst der naechste ./deploy.sh legt wieder ein Backup an."
printf "Wirklich zuruecksetzen? Tippe 'ja': "
read -r ok || true
if [ "$ok" != "ja" ]; then echo "Abgebrochen."; exit 0; fi

echo ""
echo "→ Stelle wieder her…"
ssh "$SERVER" "bk=$REMOTE_BASE/_backups/$SEL; for d in hr mitarbeiter client root; do [ -d \"\$bk/\$d\" ] && cp -a \"\$bk/\$d/.\" \"$REMOTE_BASE/\$d/\"; done"
echo ""
echo "✓ Stand $SEL wiederhergestellt."
echo "  Im Browser pruefen (ggf. hart neu laden): https://hr.tive360.de"
