-- 2026-07-28  MA-Import-Recht: Admin Test vorbelegen
--
-- Import + Vorlage in der Mitarbeiterliste sind pro user_id konfigurierbar (jsr_ma_import_v1,
-- Matrix „HR-Tab-Sperren" → Spalte „📥 Import", Standard AUS). team.ma_import wird beim Login
-- aus dieser app_config gelesen; der Import-Handler prüft zusätzlich selbst (nicht nur optisch).
--
-- Dieser Upsert schaltet den Test-Zugang „Admin Test" frei. Weitere Zugänge (z. B. der echte
-- Zugang, sobald er existiert) werden danach in der Matrix per Klick ergänzt — kein Code/SQL nötig.
-- jsonb-Merge (||) erhält evtl. schon gesetzte Zugänge. Idempotent.

insert into public.app_config (key, value, updated_at)
values ('jsr_ma_import_v1', '{"939dfd7c-f4ba-4a9e-aa2f-b3048544bffc": true}'::jsonb, now())
on conflict (key) do update
  set value = coalesce(public.app_config.value, '{}'::jsonb) || excluded.value,
      updated_at = now();
