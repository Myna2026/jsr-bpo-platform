-- CPO-Kalkulator Rabattstufen (Giganetz Retention) im Kundenportal + Management-Vorschau im Kundenportal.
-- Spec: CPO_Rabattstufen_Kalkulator_Spezifikation.md (16.09.2026). Rechenkern: frontend/shared/cpo-calc.js.
--
-- 1) Management darf ins Kundenportal (Vorschau "was der Kunde sieht" + interner Kalkulator).
--    Der Kunden-Scope (get_my_client_project_id) hängt am app_users.client_id, nicht an der Rolle.
--    Management wählt das Kundenkonto selbst im Kundenportal (client_preview_set), HR muss nichts pflegen.
-- 2) Kundenkonto Giganetz (bisher keins vorhanden), Tab 'calculator' an.
-- 3) Gespeicherte Kalkulation je Projekt+Skill: intern vollständig (nur Management),
--    Kunde liest ausschließlich die drei CPO-Felder über eine Definer-View (nie Volumen/Anteil/Delta).

-- ── 1) Management ins Kundenportal (vom User freigegeben 2026-09-16) ─────────────────────────
update public.roles_definitions
   set portals = array['mitarbeiter','hr','client']
 where role_key = 'management' and not ('client' = any(portals));

-- Management setzt sein Vorschau-Kundenkonto selbst (nur eigene Zeile, nur Management, Konto muss existieren).
create or replace function public.client_preview_set(p_client_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from app_users where user_id = auth.uid() and active and 'management' = any(role_keys)) then
    raise exception 'Nur Management kann ein Vorschau-Kundenkonto wählen.';
  end if;
  if p_client_id is not null and not exists (select 1 from client_accounts where id = p_client_id) then
    raise exception 'Kundenkonto unbekannt.';
  end if;
  update app_users set client_id = p_client_id where user_id = auth.uid();
end;
$$;
revoke all on function public.client_preview_set(text) from public;
grant execute on function public.client_preview_set(text) to authenticated;

-- ── 2) Kundenkonto Giganetz ───────────────────────────────────────────────────────────────────
insert into public.client_accounts (id, company_name, company_legal, project_name, project_id, billing_model, billing_currency, active, must_change_pw, visible_tabs, notes)
values ('client_giganetz', 'Deutsche GigaNetz', 'Deutsche GigaNetz GmbH', 'Giganetz', 'proj_gn_e5f6a7b8', 'monthly_flat', 'EUR', true, false,
        array['overview','employees','orgchart','shifts','calculator'],
        'Angelegt 2026-09-16 für den internen CPO-Kalkulator (Retention). Giganetz hat noch keinen Login.')
on conflict (id) do nothing;

-- ── 3) Gespeicherte Kalkulation ───────────────────────────────────────────────────────────────
create table if not exists public.cpo_calc_configs (
  project_id  text        not null,
  skill       text        not null,
  config      jsonb       not null default '{}'::jsonb,   -- kompletter Rechnerstand (rows, verschiebung, abstand)
  updated_by  uuid,
  updated_at  timestamptz not null default now(),
  primary key (project_id, skill)
);
alter table public.cpo_calc_configs enable row level security;

-- Intern: nur Management liest und schreibt (Preisverhandlung, kein HR-Thema).
drop policy if exists cpo_calc_mgmt_all on public.cpo_calc_configs;
create policy cpo_calc_mgmt_all on public.cpo_calc_configs
  for all to authenticated
  using  (exists (select 1 from app_users u where u.user_id = auth.uid() and u.active and 'management' = any(u.role_keys)))
  with check (exists (select 1 from app_users u where u.user_id = auth.uid() and u.active and 'management' = any(u.role_keys)));
grant select, insert, update on public.cpo_calc_configs to authenticated;

-- Kunde: nur die verhandelten CPOs des eigenen Projekts. Volumen, Anteile, Verschiebung, Abstand bleiben serverseitig verborgen.
create or replace view public.cpo_calc_customer_view
with (security_invoker = false, security_barrier = true) as
select c.project_id, c.skill, c.updated_at,
       (select coalesce(jsonb_agg(jsonb_build_object(
                 'key',        r->>'key',
                 'cpo_stufe2', r->'cpo_stufe2',
                 'cpo_stufe1', r->'cpo_stufe1')), '[]'::jsonb)
          from jsonb_array_elements(coalesce(c.config->'rows', '[]'::jsonb)) r) as rows
  from public.cpo_calc_configs c
 where c.project_id = public.get_my_client_project_id();
grant select on public.cpo_calc_customer_view to authenticated;
