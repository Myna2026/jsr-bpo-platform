-- Datengetriebener Katalog der Teamleiter-Anstöße (Schnitt 5). Der User ergänzt Anstöße als ZEILEN,
-- ohne dass Code geändert wird. cond = welche belegte Lage gelten muss (leer = allgemeiner Anstoß,
-- immer erlaubt, behauptet nichts Falsches). template nutzt Platzhalter, die die Engine aus der
-- Situations-RPC füllt: {weak_names} {strong_names} {weak_kpi} {size} {present} {absent_reason}
-- {nofb_names} {new_names}. Höhere prio = wird bevorzugt, wenn die Lage sie hergibt.
create table if not exists public.leader_nudge_prompts (
  key       text primary key,
  cond      text not null default '',          -- '' | weak_strong | weak | absent_stable | no_feedback | new_joiner
  template  text not null,
  prio      int  not null default 1,
  active    boolean not null default true,
  created_at timestamptz default now()
);
alter table public.leader_nudge_prompts enable row level security;
drop policy if exists lnp_read on public.leader_nudge_prompts;
create policy lnp_read on public.leader_nudge_prompts for select using (public.is_management());
drop policy if exists lnp_write on public.leader_nudge_prompts;
create policy lnp_write on public.leader_nudge_prompts for all using (public.is_management()) with check (public.is_management());

insert into public.leader_nudge_prompts(key,cond,template,prio) values
  ('weak_strong','weak_strong','Bei dir sind {weak_names} bei den Kennzahlen gerade schwächer und {strong_names} stärker. Setz dich zu beiden und versteh, warum – die Starken zeigen oft, was den Schwächeren fehlt.',10),
  ('weak','weak','{weak_names} liegen diese Woche bei {weak_kpi} im kritischen Bereich. Nimm dir gezielt Zeit für sie, bevor sich das festsetzt.',8),
  ('absent_stable','absent_stable','Dein Team ist diese Woche zu {present} statt {size} da, {absent_reason}. Die Kennzahlen sind trotzdem stabil – sag deinen Leuten, dass dir das auffällt.',7),
  ('no_feedback','no_feedback','{nofb_names} sind länger im Team und hatten noch kein Feedbackgespräch. Plan diese Woche welche ein.',6),
  ('new_joiner','new_joiner','{new_names} sind neu in deinem Team. Schau, wie es läuft, und gib früh Rückmeldung – die ersten Wochen entscheiden.',5),
  ('g_zugehen','','Geh heute aktiv auf dein Team zu. Ein kurzes Gespräch sagt mehr als eine Kennzahl.',1),
  ('g_vieraugen','','Führ diese Woche ein Vier-Augen-Gespräch mit jemandem aus deinem Team.',1),
  ('g_qm','','Denk an die QM-Bewertungen für dein Team – sie sind die Grundlage für gutes Feedback.',1),
  ('g_stimmung','','Nimm dir heute einen Moment für die Stimmung im Team, nicht nur für die Zahlen.',1)
on conflict (key) do nothing;
