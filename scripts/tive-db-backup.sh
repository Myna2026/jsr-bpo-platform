#!/usr/bin/env bash
# Naechtliche Sicherung der Supabase-Datenbank auf die Hetzner-VM.
#
# Warum es das gibt: das Projekt hat kein Point-in-Time-Recovery und keine abrufbaren Backups
# (supabase backups list meldet pitr_enabled:false und eine leere Liste). Am 2026-09-30 hat ein
# fehlgeschlagener Backfill die updated_at-Werte von 23 Mitarbeitern ueberschrieben; sie waren
# nicht wiederherstellbar. Ein taeglicher logischer Dump haette gereicht.
#
# Zugang: eigene Rolle tive_backup, nur lesend (pg_read_all_data + bypassrls, kein Schreibrecht,
# kein Superuser). Die Verbindungszeichenfolge liegt in /root/.tive_backup_url mit Rechten 600 und
# gehoert NICHT ins Repository.
#
# Ablage: /var/backups/tive360-db, also ausserhalb von /var/www. Die Deploy-Sicherungen liegen unter
# /var/www/tive360/_backups; dorthin gehoert ein Datenbank-Dump nicht, auch wenn Caddy das
# Verzeichnis heute nicht ausliefert. Ein Dump enthaelt das auth-Schema mit allen Zugaengen.
#
# Installiert als /usr/local/bin/tive-db-backup.sh, taeglich per Cron.
set -uo pipefail

ZIEL=/var/backups/tive360-db
LOG=/var/log/tive-db-backup.log
URLFILE=/root/.tive_backup_url
TAEGLICH=14          # so viele Tagessicherungen bleiben
MONATE=12            # dazu die erste Sicherung jedes Monats, so viele Monate zurueck
MINBYTES=1000000     # weniger heisst: da ist etwas schiefgelaufen

log(){ printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }

[ -r "$URLFILE" ] || { log "FEHLER: $URLFILE fehlt oder ist nicht lesbar"; exit 1; }
mkdir -p "$ZIEL"; chmod 700 "$ZIEL"

STAMP=$(date '+%F_%H%M')
TMP="$ZIEL/.unfertig_$STAMP.dump"
FERTIG="$ZIEL/tive360_$STAMP.dump"

if ! pg_dump "$(cat "$URLFILE")" -Fc --no-owner --no-privileges \
       -n public -n auth -n storage -f "$TMP" 2>>"$LOG"; then
  log "FEHLER: pg_dump abgebrochen, nichts uebernommen"; rm -f "$TMP"; exit 1
fi

GROESSE=$(stat -c %s "$TMP" 2>/dev/null || echo 0)
if [ "$GROESSE" -lt "$MINBYTES" ]; then
  log "FEHLER: Dump nur $GROESSE Bytes, das ist zu wenig. Nicht uebernommen."; rm -f "$TMP"; exit 1
fi
# Erst wenn die Datei auch lesbar ist, zaehlt sie als Sicherung. Ein halber Dump ist keiner.
if ! pg_restore -l "$TMP" >/dev/null 2>>"$LOG"; then
  log "FEHLER: Dump nicht lesbar, nicht uebernommen"; rm -f "$TMP"; exit 1
fi
TABELLEN=$(pg_restore -l "$TMP" 2>/dev/null | grep -c "TABLE DATA")
mv "$TMP" "$FERTIG"; chmod 600 "$FERTIG"
log "ok: $(basename "$FERTIG"), $((GROESSE/1024/1024)) MB, $TABELLEN Tabellen mit Daten"

# ── Aufbewahrung ────────────────────────────────────────────────────────────
# Die letzten TAEGLICH Sicherungen bleiben, dazu die jeweils erste eines Monats fuer MONATE Monate.
# So ist die letzte Woche tagesgenau da und aeltere Staende bleiben als Monatsmarken erhalten.
cd "$ZIEL" || exit 0
BEHALTEN=$(mktemp)
ls -1 tive360_*.dump 2>/dev/null | sort | tail -n "$TAEGLICH" >> "$BEHALTEN"
for M in $(ls -1 tive360_*.dump 2>/dev/null | sed 's/^tive360_\(....-..\).*/\1/' | sort -u | tail -n "$MONATE"); do
  ls -1 "tive360_$M"*.dump 2>/dev/null | sort | head -1 >> "$BEHALTEN"
done
sort -u "$BEHALTEN" -o "$BEHALTEN"
WEG=0
for F in $(ls -1 tive360_*.dump 2>/dev/null); do
  grep -qxF "$F" "$BEHALTEN" || { rm -f "$F" && WEG=$((WEG+1)); }
done
rm -f "$BEHALTEN"
[ "$WEG" -gt 0 ] && log "aufgeraeumt: $WEG alte Sicherungen geloescht"
log "Bestand: $(ls -1 tive360_*.dump 2>/dev/null | wc -l | tr -d ' ') Dateien, $(du -sh . 2>/dev/null | cut -f1)"
exit 0
