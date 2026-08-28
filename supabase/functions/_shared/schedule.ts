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
