-- Condor S2: die Schwellen-/Rückmeldungs-Config bekommt die Bogen-Art (intern|extern), damit Condors EXTERNER
-- Bogen eigene Ampel/Schwellen/Rückmeldungen hat, getrennt vom internen. call_criteria.rater_kind existiert
-- bereits (S1). Additiv; bestehende Config-Zeilen werden 'intern'.
alter table public.call_score_config add column if not exists rater_kind text not null default 'intern';
alter table public.call_score_config drop constraint if exists call_score_config_rater_kind_chk;
alter table public.call_score_config add  constraint call_score_config_rater_kind_chk check (rater_kind in ('intern','extern'));

-- Unique je (Projekt, Skill, Bogen-Art): intern und extern können eigene Schwellen haben.
drop index if exists public.uq_call_score_config;
create unique index uq_call_score_config on public.call_score_config
  (coalesce(project_id,''::text), coalesce(skill,''::text), rater_kind);
