-- Altbestand aus dem Wochenblatt loeschen.
-- Der Auftraggeber hat das Blatt "Planung + Rueckmeldung KW" fuer ungueltig erklaert (Antwort Edi,
-- 2026-09-29); gueltig ist allein das Tagesblatt. In report_forecast lagen aber noch 82 Wochenwerte
-- aus den Importen vom 04. und 11.09., die aus genau diesem Blatt stammen: KW 1 bis 53 des Jahres
-- 2026, darunter Support KW 1 bis 17 auf 0 und ein KW 44, das der Tagessumme widerspricht.
--
-- Erkennungsmerkmal: alles, was vor dem 2026-09-30 geschrieben wurde. Ab diesem Tag schreibt der
-- Import die Wochenwerte ausschliesslich als Summe der Tageswerte aus forecast_day; alle Zeilen aus
-- dem Re-Import tragen ein Datum von heute. Entscheidung des Users vom 2026-09-30: was fachlich
-- ungueltig ist, hat auch in der Praesentation nichts zu suchen.
--
-- report_forecast bleibt bestehen, aber nur noch als abgeleitete Wochenebene mit genau einem
-- Schreiber (dem Forecast-Import). Gelesen wird es von "Forecast vs. Ist", dem Kennzahlen-Register,
-- der Upload-Ampel, Edis Upload-Erinnerung und Pauls Wochen-Check.
delete from public.report_forecast
 where project_id = 'proj_hc_a1b2c3d4'
   and updated_at < timestamptz '2026-09-30 00:00:00+02';
