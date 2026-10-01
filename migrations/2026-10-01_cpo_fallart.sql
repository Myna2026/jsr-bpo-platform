-- Fallart beim Giganetz-Link: der Agent waehlt vor allem anderen, worum es geht.
-- Nur ein Kennzeichen zum Filtern, es aendert nichts an der Rechnung. Die Liste steht in
-- app_config und ist ohne Code erweiterbar; gespeichert wird der Schluessel, nicht die
-- Beschriftung, damit ein spaeteres Umbenennen die Historie nicht zerreisst.
alter table public.cpo_entries add column if not exists case_kind text;
comment on column public.cpo_entries.case_kind is
  'Art des Falls, Schluessel aus app_config jsr_cpo_options_v1 -> case_kinds. Nur Kennzeichen, keine Rechengroesse.';
create index if not exists cpo_entries_art on public.cpo_entries(project_id, work_date, case_kind);

update public.app_config
   set value = value || jsonb_build_object('case_kinds', jsonb_build_array(
         jsonb_build_object('key','vorvertrag',  'rank',1, 'label','Vorvertrag'),
         jsonb_build_object('key','kuendigung',  'rank',2, 'label','ordentliche Kündigung'),
         jsonb_build_object('key','sonstiges',   'rank',3, 'label','Sonstiges')))
 where key = 'jsr_cpo_options_v1'
   and not (value ? 'case_kinds');
