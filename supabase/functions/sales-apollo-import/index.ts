// Sales-Akquise, Schnitt 1: Leads aus Apollo importieren — mit EIGENEM 25HRS-Secret SALES_APOLLO_API_KEY
// (NICHT der Bestandsschlüssel aus einem anderen Vorhaben). Nur Freigabeliste. Unterdrückte Adressen werden
// übersprungen. Deploy: supabase functions deploy sales-apollo-import --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
function json(b: unknown, s = 200) { return new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } }); }

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: false, error: "POST" }, 405);
  const sb = createClient(SB_URL, SERVICE);
  const { data: u } = await sb.auth.getUser((req.headers.get("Authorization") || "").replace("Bearer ", ""));
  if (!u?.user) return json({ ok: false, error: "nicht angemeldet" }, 401);
  const { data: acc } = await sb.from("sales_access").select("user_id").eq("user_id", u.user.id).maybeSingle();
  if (!acc) return json({ ok: false, error: "kein Zugriff auf die Akquise" }, 403);

  const key = Deno.env.get("SALES_APOLLO_API_KEY") || "";
  if (!key) return json({ ok: false, error: "Secret SALES_APOLLO_API_KEY fehlt (eigener 25HRS-Apollo-Zugang)" }, 400);

  const b = await req.json().catch(() => ({}));
  const payload: Record<string, unknown> = { page: 1, per_page: Math.min(Number(b.per_page) || 25, 50) };
  if (Array.isArray(b.titles) && b.titles.length) payload.person_titles = b.titles;
  if (Array.isArray(b.locations) && b.locations.length) payload.organization_locations = b.locations;
  if (Array.isArray(b.industries) && b.industries.length) payload.organization_industries = b.industries;
  if (b.keywords) payload.q_keywords = String(b.keywords);

  let people: any[] = [];
  try {
    const r = await fetch("https://api.apollo.io/api/v1/mixed_people/api_search", {
      method: "POST", headers: { "Content-Type": "application/json", "X-Api-Key": key }, body: JSON.stringify(payload),
    });
    if (!r.ok) return json({ ok: false, error: "Apollo " + r.status + ": " + (await r.text()).slice(0, 160) }, 502);
    people = (await r.json()).people || [];
  } catch (e) { return json({ ok: false, error: "Apollo nicht erreichbar: " + ((e as Error).message || e) }, 502); }

  let imported = 0, skipped = 0;
  for (const p of people) {
    let email: string | null = p.email || null;
    if (!email) for (const ec of (p.email_statuses || [])) { if (ec.email && ec.deliverability !== "undeliverable") { email = ec.email; break; } }
    const org = p.organization || {};
    // Unterdrückte Adressen gar nicht erst aufnehmen.
    if (email) { const { data: can } = await sb.rpc("sales_can_send", { p_email: email }); if (can === false) { skipped++; continue; } }
    // Dubletten (gleiche E-Mail) überspringen.
    if (email) { const { data: dup } = await sb.from("sales_leads").select("id").ilike("contact_email", email).maybeSingle(); if (dup) { skipped++; continue; } }
    const { error } = await sb.from("sales_leads").insert({
      company: org.name || null, website: org.website_url || null, industry: org.industry || null,
      contact_name: [p.first_name, p.last_name || p.last_name_obfuscated].filter(Boolean).join(" ") || null,
      contact_email: email, contact_role: (p.title || "").slice(0, 255) || null,
      source: "apollo", created_by: u.user.id,
    });
    if (error) { skipped++; } else { imported++; }
  }
  return json({ ok: true, imported, skipped, found: people.length });
});
