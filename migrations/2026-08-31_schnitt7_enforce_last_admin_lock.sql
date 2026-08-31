-- Schnitt 7, Teil 4: enforce_last_admin härten. Der statement-level Trigger zählt nach der Änderung die aktiven
-- Admins; unter READ COMMITTED könnten ZWEI gleichzeitige Deaktivierungen verschiedener Admins beide „>=1" sehen
-- und beide committen (Write-Skew → 0 aktive Admins). Ein Transaktions-Advisory-Lock serialisiert die Prüfung:
-- die zweite Transaktion wartet, bis die erste committet, und sieht dann den aktualisierten Stand.

create or replace function public.enforce_last_admin()
 returns trigger language plpgsql security definer set search_path to 'public'
as $function$
begin
  perform pg_advisory_xact_lock(hashtext('app_users_last_admin'));   -- serialisiert konkurrierende Admin-Änderungen
  if (select count(*) from public.app_users
        where active = true
          and role_keys && array['management','hr']) = 0 then
    raise exception 'Mindestens ein aktiver Admin (management/hr) muss bestehen bleiben';
  end if;
  return null;
end;
$function$;

-- ── ROLLBACK: dieselbe Funktion ohne die pg_advisory_xact_lock-Zeile. ──
