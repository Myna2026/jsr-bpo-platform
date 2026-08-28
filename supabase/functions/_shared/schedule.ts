// Kein-Wochenende-Regel (global, EINE Wahrheit für alle Dispatcher): Agenten-Erinnerungen nur Mo–Fr.
// Was Sa/So fällig wäre, kommt am Montag. Gilt für Mail und Slack. Die In-System-Einblendungen gaten
// separat im Frontend (AgentInsights prüft Wochentag 1–5). Manuelle Tests (force/dry) umgehen die Regel.
export function berlinNow(): Date {
  return new Date(new Date().toLocaleString("en-US", { timeZone: "Europe/Berlin" }));
}
export function berlinDow(d?: Date): number {
  return (d || berlinNow()).getDay();   // 0=So … 6=Sa
}
export function isWeekendBerlin(d?: Date): boolean {
  const w = berlinDow(d);
  return w === 0 || w === 6;
}

// ── Zentrale Zeitsteuerung (reminder_schedule) ──
// Eine Global-Zeile je Erinnerung + optionale Über­schreibung je Person. Die Function fragt hier, ob sie
// JETZT feuern soll (nach Stunde/Rhythmus/Wochentag/Monatstagen), statt feste Cron-Zeiten zu haben.
export async function getSchedule(sb: any, key: string): Promise<any> {
  const { data } = await sb.from("reminder_schedule").select("*").eq("reminder_key", key).is("user_id", null).maybeSingle();
  return data || null;
}
export async function personOverride(sb: any, key: string, userId: string): Promise<any> {
  if (!userId) return null;
  const { data } = await sb.from("reminder_schedule").select("*").eq("reminder_key", key).eq("user_id", userId).maybeSingle();
  return data || null;
}
// Ist diese Person für die Erinnerung aktiv? (Über­schreibung schlägt Global; Default an)
export async function personActive(sb: any, key: string, userId: string): Promise<boolean> {
  const o = await personOverride(sb, key, userId);
  if (o) return !!o.active;
  const g = await getSchedule(sb, key);
  return g ? !!g.active : true;
}

// Soll die Erinnerung JETZT (Berlin) laufen? active + Werktag + geplante Stunde + Rhythmus.
export function scheduleDue(sched: any, now?: Date): boolean {
  if (!sched || !sched.active) return false;
  const b = now || berlinNow();
  const dow = ((b.getDay() + 6) % 7) + 1;   // 1=Mo … 7=So
  if (dow >= 6) return false;                 // Sa(6)/So(7): Kein-Wochenende-Regel bleibt hart
  const hour = b.getHours();
  const hours: number[] = (sched.hours && sched.hours.length) ? sched.hours : [8];
  if (!hours.includes(hour)) return false;
  const dom = b.getDate();
  switch (sched.cadence) {
    case "weekly": return dow === (sched.weekday || 5);
    case "monthly":
    case "twice_monthly": return (sched.month_days || []).includes(dom);
    case "every_2_days":
    case "daily":
    default: return true;
  }
}
