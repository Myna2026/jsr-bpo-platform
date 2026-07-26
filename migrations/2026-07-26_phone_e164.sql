-- E.164-Telefon-Normalisierung — Umschreib-Lauf (konservativ)
-- =============================================================================
-- Nur Nummern mit SICHER erkannter Vorwahl (383 Kosovo, 355 Albanien, 49 DE,
-- 43 AT, 41 CH) und plausibler Nationalnummer-Laenge werden umgeschrieben auf
-- +CC+Nationalnummer OHNE Leerzeichen. Alles Unklare bleibt unangetastet.
-- KEIN Standort-Raten. Identische Logik wie der Report (hr.html phoneClassify).
--
-- Backup: Original wandert nach extra->>'phone_original' (umkehrbar, kein Deploy
-- noetig; extra-Sink round-trippt es verlustfrei). coalesce schuetzt vor
-- Doppellauf (bereits gesichertes Original wird nie ueberschrieben).
--
-- ZWEI TEILE, GETRENNT AUSFUEHRBAR: erst TEIL 1 (employees), dann TEIL 2 (cvs).
-- Voraussetzung: employees.extra und cvs.extra sind vom Typ jsonb.
-- =============================================================================


-- ── TEIL 1: employees ────────────────────────────────────────────────────────
with c as (
  select id, phone, regexp_replace(phone,'[^0-9]','','g') as d
  from employees
  where phone is not null and btrim(phone) <> ''
),
k as (
  select *, case when d like '383%' then '383'
                 when d like '355%' then '355'
                 when d like '49%'  then '49'
                 when d like '43%'  then '43'
                 when d like '41%'  then '41'
                 else '' end as cc
  from c
),
m as ( select *, substr(d, length(cc)+1) as nat, length(d)-length(cc) as natlen from k ),
ok as (
  select id, phone, '+'||cc||nat as target
  from m
  where phone !~ '[A-Za-z]'
    and length(d) >= 6
    and cc <> ''
    and case cc when '383' then natlen = 8
                when '355' then natlen between 8 and 9
                when '49'  then natlen between 9 and 11
                when '43'  then natlen between 9 and 13
                when '41'  then natlen = 9 end
    and btrim(phone) <> '+'||cc||nat        -- bereits E.164 -> nichts tun
)
update employees e
set extra = coalesce(e.extra,'{}'::jsonb)
            || jsonb_build_object('phone_original', coalesce(e.extra->>'phone_original', e.phone)),
    phone = ok.target
from ok
where ok.id = e.id;


-- ── TEIL 2: cvs (Bewerber) ───────────────────────────────────────────────────
-- ERST die cvs-Vorschau pruefen (siehe separate SELECT), dann diesen Block.
with c as (
  select id, phone, regexp_replace(phone,'[^0-9]','','g') as d
  from cvs
  where phone is not null and btrim(phone) <> ''
),
k as (
  select *, case when d like '383%' then '383'
                 when d like '355%' then '355'
                 when d like '49%'  then '49'
                 when d like '43%'  then '43'
                 when d like '41%'  then '41'
                 else '' end as cc
  from c
),
m as ( select *, substr(d, length(cc)+1) as nat, length(d)-length(cc) as natlen from k ),
ok as (
  select id, phone, '+'||cc||nat as target
  from m
  where phone !~ '[A-Za-z]'
    and length(d) >= 6
    and cc <> ''
    and case cc when '383' then natlen = 8
                when '355' then natlen between 8 and 9
                when '49'  then natlen between 9 and 11
                when '43'  then natlen between 9 and 13
                when '41'  then natlen = 9 end
    and btrim(phone) <> '+'||cc||nat
)
update cvs c2
set extra = coalesce(c2.extra,'{}'::jsonb)
            || jsonb_build_object('phone_original', coalesce(c2.extra->>'phone_original', c2.phone)),
    phone = ok.target
from ok
where ok.id = c2.id;


-- ── ROLLBACK (falls noetig) ──────────────────────────────────────────────────
-- update employees set phone = extra->>'phone_original' where extra ? 'phone_original';
-- update cvs       set phone = extra->>'phone_original' where extra ? 'phone_original';
-- ── CLEANUP nach Verifikation ────────────────────────────────────────────────
-- update employees set extra = extra - 'phone_original' where extra ? 'phone_original';
-- update cvs       set extra = extra - 'phone_original' where extra ? 'phone_original';
