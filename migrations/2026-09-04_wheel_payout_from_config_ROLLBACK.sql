-- ROLLBACK: stellt die spin_wheel-Fassung von vor 2026-09-04 wieder her (hartcodierte Beträge + KPI/Fairness + Budget-Bremse).
-- Nur benutzen, falls die Preislisten-Umstellung zurückgedreht werden muss.
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

  -- Fairness: Wochen seit letztem Gewinn (nie gewonnen -> Garantie-Niveau 4)
  select max(spin_date) into v_last_win from wheel_spins where emp_id = v_emp and amount > 0;
  if v_last_win is not null then
    v_weeks := greatest(0, floor((v_today - v_last_win)/7.0)::int);
  else
    v_weeks := 4;
  end if;

  -- KPI-Faktor: juengste bis 6 kpi_entries gegen kpi_config.thresholds bewerten,
  -- Tier-Guete (1=beste Stufe .. ~0=schlechteste) mitteln.
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

  v_rand := random();   -- einmal pro Dreh

  -- 2. Sonderaktion aktiv?
  select * into v_special from wheel_specials
    where start_date <= v_today and v_today <= end_date
    order by created_at desc limit 1;
  v_has_special := found;

  if v_has_special then
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
    -- 3. Monatsbudget + Restbudget (Budget minus Summe aller Gewinne des Monats)
    select coalesce(amount,0) into v_budget from wheel_budgets where month = v_month;
    v_budget := coalesce(v_budget,0);
    select coalesce(sum(amount),0) into v_spent from wheel_spins
      where spin_date >= date_trunc('month', v_today)::date
        and spin_date <  (date_trunc('month', v_today) + interval '1 month')::date;
    v_rest := v_budget - v_spent;
    if v_rest <= 0 then
      v_amount := 0;   -- Topf leer
    else
      -- Gewichtete Auswahl [0,1,2,5,10,20,50]; 0-Gewicht /v_weight -> hoehere Gewinnchance
      select v into v_amount from (
        select v, sum(w) over (order by ord) as cum, sum(w) over () as total
        from (values
          (0::numeric, (50.0 / v_weight), 1),
          (1, 25.0, 2),(2, 15.0, 3),(5, 8.0, 4),(10, 4.0, 5),(20, 2.0, 6),(50, 1.0, 7)
        ) as o(v, w, ord)
      ) q
      where q.cum >= v_rand * q.total
      order by q.cum asc limit 1;
      v_amount := coalesce(v_amount, 0);
      if v_amount > v_rest then v_amount := floor(v_rest); end if;   -- Budget-Bremse
      if v_amount < 0 then v_amount := 0; end if;
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

  if v_amount > 0 then
    v_msg := '🎉 Glückwunsch! Du hast ' || v_amount::text || ' € gewonnen!';
  else
    v_msg := 'Kein Gewinn — deine Chance steigt!';
  end if;

  return jsonb_build_object('amount', v_amount, 'source', v_source, 'message', v_msg);
end;
$function$
;
