-- Glücksrad: Auszahlung = angezeigte Preisliste (Weg A). Der Normal-Dreh zieht künftig AUSSCHLIESSLICH aus
-- app_config.jsr_wheel_cfg.prizes (Betrag + Gewicht je Preis) — was HR pflegt und der Mitarbeiter sieht, ist
-- genau das, was gezahlt wird. Entfernt:
--   * die hartcodierte Betragstabelle [0,1,2,5,10,20,50] (hatte mit der angezeigten Liste nichts zu tun),
--   * den KPI-/Fairness-Boost im Normal-Pfad (versteckte Rechnung -> raus; Leistung honoriert man mit Bonus,
--     nicht mit einem manipulierten Glücksrad),
--   * die "Budget-Bremse" floor(v_rest), die bei knappem Topf heimlich einen krummen Ersatzbetrag auswarf.
-- Budget ist jetzt eine HARTE GRENZE (Variante 1): gezogen wird nur unter Preisen, die der Resttopf noch VOLL
-- deckt (amount<=rest) plus "leider nichts" (amount=0). Deckt der Topf keinen einzigen positiven Preis mehr,
-- liefert der Server den ehrlichen Zustand 'budget_exhausted' (amount 0) statt eines Fake-Verlusts.
-- Sonderaktionen (wheel_specials) bleiben UNVERÄNDERT; ihre Fairness/KPI-Gewichtung wandert nur in den
-- Spezial-Zweig, damit der Normal-Pfad nachweisbar keine versteckte Rechnung enthält (Verhalten identisch).
CREATE OR REPLACE FUNCTION public.spin_wheel()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_emp         uuid;
  v_today       date := current_date;
  v_month       text := to_char(current_date,'YYYY-MM');
  v_existing    wheel_spins%rowtype;
  v_special     wheel_specials%rowtype;
  v_has_special boolean := false;
  v_source      text := 'normal';
  v_special_id  uuid := null;
  v_amount      numeric := 0;
  v_budget      numeric := 0;
  v_spent       numeric := 0;
  v_rest        numeric := 0;
  v_last_win    date;
  v_weeks       int := 4;
  v_weight      numeric := 1.0;
  v_kpi_factor  numeric := 1.0;
  v_g           numeric;
  v_rand        numeric;
  v_tranche     numeric;
  v_awarded_cnt int;
  v_awarded_sum numeric;
  v_prizes      jsonb;
  v_has_pos     boolean;
  v_aff_pos     boolean;
  v_msg         text;
begin
  -- Aufrufer -> Mitarbeiter (serverseitig, kein Parameter)
  select employee_id into v_emp from app_users where user_id = auth.uid();
  if v_emp is null then
    return jsonb_build_object('amount',0,'source','none','message','Kein verknüpfter Mitarbeiter.');
  end if;

  -- 1. Tages-Check: schon heute gedreht?
  select * into v_existing from wheel_spins where emp_id = v_emp and spin_date = v_today;
  if found then
    return jsonb_build_object('amount', v_existing.amount, 'source', v_existing.source,
      'message','Heute schon gedreht — komm morgen wieder!', 'alreadySpun', true);
  end if;

  v_rand := random();   -- einmal pro Dreh

  -- 2. Sonderaktion aktiv?
  select * into v_special from wheel_specials
    where start_date <= v_today and v_today <= end_date
    order by created_at desc limit 1;
  v_has_special := found;

  if v_has_special then
    -- Fairness/KPI NUR für Sonderaktionen (unverändertes Verhalten; im Normal-Pfad bewusst nicht mehr genutzt).
    -- Fairness: Wochen seit letztem Gewinn (nie gewonnen -> Garantie-Niveau 4)
    select max(spin_date) into v_last_win from wheel_spins where emp_id = v_emp and amount > 0;
    if v_last_win is not null then
      v_weeks := greatest(0, floor((v_today - v_last_win)/7.0)::int);
    else
      v_weeks := 4;
    end if;
    -- KPI-Faktor: juengste bis 6 kpi_entries gegen kpi_config.thresholds bewerten, Tier-Guete mitteln.
    select avg(g) into v_g from (
      select (
        select (jsonb_array_length(kc.thresholds) - (t.ord - 1))::numeric
               / nullif(jsonb_array_length(kc.thresholds),0)
        from kpi_config kc
        cross join lateral (
          select ord
          from jsonb_array_elements(kc.thresholds) with ordinality as th(val, ord)
          where e.value >= (th.val->>'min')::numeric
            and e.value <= (th.val->>'max')::numeric
          order by ord limit 1
        ) t
        where kc.id = e.kpi_id
      ) as g
      from (
        select kpi_id, value from kpi_entries where emp_id = v_emp
        order by year desc nulls last, kw desc nulls last limit 6
      ) e
    ) sub;
    if v_g is not null then
      if v_g >= 0.66 then v_kpi_factor := 1.15;
      elsif v_g < 0.34 then v_kpi_factor := 0.85;
      else v_kpi_factor := 1.0; end if;
    end if;
    v_weight := (1.0 + 0.25 * v_weeks) * v_kpi_factor;
    if v_weeks >= 4 then v_weight := v_weight + 2.0; end if;   -- Garantie: deutlich erhoeht
    v_weight := greatest(0.1, v_weight);

    v_source := 'special';
    v_special_id := v_special.id;
    select count(*) filter (where amount > 0),
           coalesce(sum(amount) filter (where amount > 0),0)
      into v_awarded_cnt, v_awarded_sum
      from wheel_spins where special_id = v_special.id;
    v_rest    := coalesce(v_special.total_amount,0) - v_awarded_sum;
    v_tranche := coalesce(v_special.tranche_amount,0);
    if v_awarded_cnt >= coalesce(v_special.tranche_count,0) or v_tranche <= 0 or v_rest < v_tranche then
      v_amount := 0;   -- Tranchen/Topf ausgeschoepft
    else
      -- Fairness-Roll: 0 vs Tranche (hoeheres Gewicht -> kleineres 0-Gewicht)
      if v_rand * ((40.0 / v_weight) + 20.0) >= (40.0 / v_weight) then
        v_amount := v_tranche;
      else
        v_amount := 0;
      end if;
    end if;
  else
    -- 3. Normaler Glücksrad-Dreh: Beträge + Gewichte kommen AUSSCHLIESSLICH aus app_config.jsr_wheel_cfg.prizes.
    --    Keine versteckte Rechnung. Budget = harte Grenze (Variante 1).
    select coalesce(amount,0) into v_budget from wheel_budgets where month = v_month;
    v_budget := coalesce(v_budget,0);
    select coalesce(sum(amount),0) into v_spent from wheel_spins
      where spin_date >= date_trunc('month', v_today)::date
        and spin_date <  (date_trunc('month', v_today) + interval '1 month')::date;
    v_rest := v_budget - v_spent;

    v_prizes := coalesce((select value->'prizes' from app_config where key = 'jsr_wheel_cfg'), '[]'::jsonb);

    -- Gibt es überhaupt positive Preise? Und deckt der Resttopf mindestens einen davon voll?
    select exists(
        select 1 from jsonb_array_elements(v_prizes) p
        where coalesce((p->>'amount')::numeric,0) > 0
      ) into v_has_pos;
    select exists(
        select 1 from jsonb_array_elements(v_prizes) p
        where coalesce((p->>'amount')::numeric,0) > 0
          and coalesce((p->>'amount')::numeric,0) <= v_rest
      ) into v_aff_pos;

    if v_has_pos and not v_aff_pos then
      -- Monatstopf deckt keinen einzigen positiven Preis mehr -> ehrlich ausgeschoepft.
      v_amount := 0;
      v_source := 'budget_exhausted';
    else
      -- Gewichteter Zufall über die zulässigen Preise: alle "leider nichts" (amount=0) + alle Preise,
      -- die der Resttopf noch VOLL deckt (amount<=rest). Die in der Config gepflegten Gewichte SIND die Chancen.
      select amt into v_amount from (
        select (p->>'amount')::numeric as amt,
               sum(coalesce((p->>'weight')::numeric,1)) over (order by ord) as cum,
               sum(coalesce((p->>'weight')::numeric,1)) over () as total
        from jsonb_array_elements(v_prizes) with ordinality as t(p, ord)
        where coalesce((p->>'amount')::numeric,0) = 0
           or coalesce((p->>'amount')::numeric,0) <= v_rest
      ) q
      where q.cum >= v_rand * q.total
      order by q.cum asc limit 1;
      v_amount := coalesce(v_amount, 0);
    end if;
  end if;

  -- 4. Dreh speichern (auch 0 -> Wartestand); Race gegen unique(emp_id,spin_date) abfangen
  begin
    insert into wheel_spins (emp_id, spin_date, amount, source, special_id)
    values (v_emp, v_today, v_amount, v_source, v_special_id);
  exception when unique_violation then
    select * into v_existing from wheel_spins where emp_id = v_emp and spin_date = v_today;
    return jsonb_build_object('amount', v_existing.amount, 'source', v_existing.source,
      'message','Heute schon gedreht — komm morgen wieder!', 'alreadySpun', true);
  end;

  if v_source = 'budget_exhausted' then
    v_msg := 'Der Bonus-Topf für diesen Monat ist ausgeschöpft. Nächsten Monat geht es weiter!';
  elsif v_amount > 0 then
    v_msg := '🎉 Glückwunsch! Du hast ' || v_amount::text || ' € gewonnen!';
  else
    v_msg := 'Diesmal kein Gewinn. Morgen wieder!';
  end if;

  return jsonb_build_object('amount', v_amount, 'source', v_source, 'message', v_msg);
end;
$function$;
