-- ============================================================================
-- Offboarding / Schnitt 2b Weg A — Einmal-Migration: extra.<feld> -> Spalte.
-- ERST NACH dem ALTER (employees_payroll_cols.sql) ausführen.
--
-- coalesce(spalte, extra->>...): überschreibt KEINE bereits gesetzten
-- Spaltenwerte (idempotent — mehrfach ausführbar). extra-Keys bleiben als
-- Sicherheitsnetz erhalten (NICHT gelöscht). Aufräumen später separat.
-- Casts: numeric/integer via nullif(...,'') (leere Strings → null statt
-- Cast-Fehler); boolean direkt (jsonb-Boolean → 'true'/'false' → ::boolean).
-- ============================================================================

update public.employees set
  fixed_salary     = coalesce(fixed_salary,     nullif(extra->>'fixed_salary','')::numeric),
  guaranteed_pct   = coalesce(guaranteed_pct,   nullif(extra->>'guaranteed_pct','')::numeric),
  deduct_missing   = coalesce(deduct_missing,   (extra->>'deduct_missing')::boolean),
  free_days_month  = coalesce(free_days_month,  nullif(extra->>'free_days_month','')::integer),
  monthly_bonus    = coalesce(monthly_bonus,    nullif(extra->>'monthly_bonus','')::numeric),
  overtime_allowed = coalesce(overtime_allowed, (extra->>'overtime_allowed')::boolean),
  productive_pct   = coalesce(productive_pct,   nullif(extra->>'productive_pct','')::numeric)
where extra ?| array['fixed_salary','guaranteed_pct','deduct_missing',
                     'free_days_month','monthly_bonus','overtime_allowed','productive_pct'];


-- ---- Verifikation (b): die migrierten Datensätze zeigen die Werte ----------
-- Erwartet: die 2 betroffenen Zeilen mit gefüllten Spalten (Werte = wie in extra).
select id, fixed_salary, guaranteed_pct, deduct_missing,
       free_days_month, monthly_bonus, overtime_allowed, productive_pct
  from public.employees
 where extra ?| array['fixed_salary','guaranteed_pct','deduct_missing',
                     'free_days_month','monthly_bonus','overtime_allowed','productive_pct']
 order by id;
