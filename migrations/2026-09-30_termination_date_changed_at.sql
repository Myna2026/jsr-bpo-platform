-- Wann wurde das Austrittsdatum gesetzt oder geaendert?
-- Pauls Pruefung 7 warnte bisher anhand von employees.updated_at, das fuer den GANZEN Datensatz
-- gilt: jede Adressaenderung loeste die Warnung aus, und eine echte Aenderung am Austrittsdatum war
-- nicht davon zu unterscheiden. Dafuer jetzt ein eigenes Feld mit Trigger.
--
-- Namensabweichung zur Anforderung: die Spalte heisst nicht exit_date, sondern termination_date
-- (Master-Feldname, siehe docs/fachmodell/personen-und-datenmodell.md). Das neue Feld heisst
-- entsprechend termination_date_changed_at.
alter table public.employees add column if not exists termination_date_changed_at timestamptz;
comment on column public.employees.termination_date_changed_at is
  'Zeitpunkt, zu dem termination_date gesetzt oder geaendert wurde. Wird allein vom Trigger
   employees_termination_stamp gepflegt, nie von der Anwendung.';

create or replace function public.employees_termination_stamp()
returns trigger
language plpgsql
as $$
begin
  -- Nur bei echter Aenderung des Austrittsdatums stempeln. Wird es geleert, faellt auch der
  -- Stempel weg: ohne Austrittsdatum gibt es nichts zu pruefen.
  if tg_op = 'INSERT' then
    if new.termination_date is not null then new.termination_date_changed_at := now(); end if;
  elsif new.termination_date is distinct from old.termination_date then
    new.termination_date_changed_at := case when new.termination_date is null then null else now() end;
  else
    new.termination_date_changed_at := old.termination_date_changed_at;
  end if;
  return new;
end;
$$;

drop trigger if exists employees_termination_stamp on public.employees;
create trigger employees_termination_stamp
  before insert or update on public.employees
  for each row execute function public.employees_termination_stamp();

-- KEINE Befuellung des Bestands aus updated_at.
-- Geplant war, die 23 vorhandenen Austrittsdaten einmalig mit employees.updated_at zu stempeln.
-- Beim ersten Versuch hat der neue BEFORE-Trigger den Wert sofort wieder auf NULL zurueckgesetzt
-- (er haelt das Feld absichtlich gegen Schreibzugriffe dicht). Dieser eine fehlgeschlagene UPDATE
-- hat aber alle 23 Zeilen angefasst, und der bereits vorhandene Trigger update_employees_updated_at
-- hat dabei updated_at auf "jetzt" gesetzt. Die urspruenglichen Zeitstempel sind damit verloren.
--
-- Ein Stempel "heute" fuer alle 23 waere schlimmer als keiner: er wuerde in Pauls Pruefung 7 sieben
-- Tage lang bei jedem dieser Datensaetze eine Aenderungswarnung ausloesen, die es nie gab.
-- Deshalb bleibt das Feld fuer den Bestand leer. Leer heisst "unbekannt", und unbekannt warnt nicht.
-- Ab jetzt stempelt der Trigger jede echte Aenderung taggenau.
update public.employees set termination_date_changed_at = null where termination_date is not null;
