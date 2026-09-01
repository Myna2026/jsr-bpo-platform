-- Kein aktiver, nutzbarer Zugang ohne Rolle. handle_new_user() (Trigger auf auth.users) legte neue app_users-Zeilen
-- bisher AKTIV an; role_keys bleibt per Default leer → aktiver, aber rollenloser (kaputter) Zugang, bis ein Admin
-- eine Rolle vergibt (Fälle Ardita, Abaz). Neue Zeilen starten jetzt INAKTIV: der Admin vergibt Rolle UND aktiviert
-- bewusst in der App-User-Verwaltung. Ergänzt die dortige Warnung über rollenlose Zugänge (Frontend).
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  insert into public.app_users (user_id, must_change_pw, active)
  values (new.id, true, false)
  on conflict (user_id) do nothing;
  return new;
end $$;
