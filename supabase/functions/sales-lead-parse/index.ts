// Sales-Akquise, Schnitt 1: Lead aus einer weitergeleiteten Mail. Claude extrahiert Firma/Kontakt aus dem Text —
// nur was dasteht, KEINE erfundenen Fakten (unbekannt → null). Nur Freigabeliste. Später ruft mail-poll denselben
// Weg automatisch für die Ingest-Adresse. Deploy: supabase functions deploy sales-lead-parse --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC = Deno.env.get("ANTHROPIC_API_KEY") || "";
function json(b: unknown, s = 200) { return new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } }); }

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: false, error: "POST" }, 405);
  const sb = createClient(SB_URL, SERVICE);
  const { data: u } = await sb.auth.getUser((req.headers.get("Authorization") || "").replace("Bearer ", ""));
  if (!u?.user) return json({ ok: false, error: "nicht angemeldet" }, 401);
  const { data: acc } = await sb.from("sales_access").select("user_id").eq("user_id", u.user.id).maybeSingle();
  if (!acc) return json({ ok: false, error: "kein Zugriff auf die Akquise" }, 403);
  if (!ANTHROPIC) return json({ ok: false, error: "ANTHROPIC_API_KEY fehlt" }, 400);

  const text = String((await req.json().catch(() => ({}))).text || "").slice(0, 12000);
  if (!text.trim()) return json({ ok: false, error: "kein Text" }, 400);

  const sys = "Du extrahierst aus einer weitergeleiteten E-Mail die Firmen- und Kontaktdaten für einen Vertriebs-Lead. " +
    "Gib NUR belegte Angaben zurück, erfinde nichts. Unbekanntes Feld = null. Antworte ausschließlich als JSON mit den " +
    "Schlüsseln company, website, industry, contact_name, contact_email, contact_role.";
  let obj: any = {};
  try {
    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST", headers: { "x-api-key": ANTHROPIC, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model: "claude-sonnet-5", max_tokens: 400, system: sys, messages: [{ role: "user", content: text }] }),
    });
    if (!r.ok) return json({ ok: false, error: "Claude " + r.status + ": " + (await r.text()).slice(0, 160) }, 502);
    const raw = ((await r.json()).content || []).map((c: any) => c.text || "").join("");
    const m = raw.match(/\{[\s\S]*\}/); obj = m ? JSON.parse(m[0]) : {};
  } catch (e) { return json({ ok: false, error: "Extraktion fehlgeschlagen: " + ((e as Error).message || e) }, 502); }

  const email = obj.contact_email ? String(obj.contact_email).trim() : null;
  if (email) { const { data: dup } = await sb.from("sales_leads").select("id").ilike("contact_email", email).maybeSingle(); if (dup) return json({ ok: false, error: "Lead mit dieser Adresse existiert bereits" }, 409); }
  const { data: lead, error } = await sb.from("sales_leads").insert({
    company: obj.company || null, website: obj.website || null, industry: obj.industry || null,
    contact_name: obj.contact_name || null, contact_email: email, contact_role: obj.contact_role || null,
    source: "mail", created_by: u.user.id,
  }).select("*").maybeSingle();
  if (error) return json({ ok: false, error: error.message }, 500);
  return json({ ok: true, lead });
});
