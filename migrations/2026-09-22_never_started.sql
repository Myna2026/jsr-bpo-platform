-- Einmalige Datenkorrektur (User 2026-09-22, Weg 2): Dhurata Kastrati bleibt als gekuendigt bestehen,
-- bekommt aber den Merker never_started, damit die Kuendigungsstatistik sie getrennt zaehlt.
-- Dhurata Kastrati (Personalnummer 1075): Datensatz bleibt als gekuendigt bestehen (Weg 2 des Users),
-- mit dem Vermerk "nie angetreten" und dem festen Merker, damit die Kuendigungsstatistik sie getrennt zaehlt.
update public.employees
   set extra = coalesce(extra,'{}'::jsonb) || jsonb_build_object('never_started', true, 'termination_reason', 'nie angetreten'),
       updated_at = now()
 where id = '5e555d8c-9950-4e53-9dad-a3470ff2e5f7';
select id, first_name, last_name, status, termination_date,
       extra->>'never_started' as never_started, extra->>'termination_reason' as reason
  from public.employees where id = '5e555d8c-9950-4e53-9dad-a3470ff2e5f7';
