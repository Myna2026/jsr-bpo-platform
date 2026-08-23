-- Float-Rauschen aus gespeicherten KPI-Werten entfernen (206.60000000000002, 13.216666..., mm:ss-Umrechnungen).
-- Ab jetzt runden die Schreibpfade beim Import/Manuell auf 4 Nachkommastellen (kpiRound in hr.html); dies saeubert
-- den Altbestand einmalig auf dieselbe Praezision. round(numeric,4) veraendert echte Werte nicht sichtbar.
update public.kpi_entries         set value = round(value, 4) where scale(value) > 4;
update public.kpi_project_entries set value = round(value, 4) where scale(value) > 4;
