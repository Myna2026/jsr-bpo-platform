// Sales-Akquise, Schnitt 0 (Compliance): öffentlicher Abmelde-Weg. Der Abmeldelink jeder Mail zeigt hierher
// (?token=<unsub_token>). Der Token gehört zu einem Lead → dessen Adresse wandert in die Unterdrückungsliste
// (nie wieder ansprechen), Lead-Status = suppressed, Ereignis protokolliert. Öffentlich, kein Login.
// Deploy: supabase functions deploy sales-unsubscribe --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function page(title: string, msg: string): Response {
  const html = `<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title></head>
<body style="font-family:system-ui,-apple-system,Arial,sans-serif;background:#f6f7f9;margin:0;display:flex;min-height:100vh;align-items:center;justify-content:center">
<div style="background:#fff;border:1px solid #e5e7eb;border-radius:16px;padding:32px 28px;max-width:440px;box-shadow:0 8px 30px rgba(0,0,0,.06);text-align:center">
<div style="font-size:22px;font-weight:800;color:#0f172a;margin-bottom:8px">${title}</div>
<div style="font-size:14px;color:#475569;line-height:1.6">${msg}</div>
</div></body></html>`;
  return new Response(html, { status: 200, headers: { "Content-Type": "text/html; charset=utf-8" } });
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const token = url.searchParams.get("token") || "";
  if (!token) return page("Abmeldung", "Kein gültiger Abmelde-Link.");
  const sb = createClient(SB_URL, SERVICE);
  const { data: lead } = await sb.from("sales_leads").select("id,contact_email").eq("unsub_token", token).maybeSingle();
  if (!lead || !lead.contact_email) return page("Abmeldung", "Dieser Link ist nicht mehr gültig. Falls Sie weiterhin Nachrichten erhalten, antworten Sie bitte kurz mit dem Wort Abmelden.");
  const email = String(lead.contact_email).trim().toLowerCase();
  await sb.from("sales_suppression").upsert({ email, reason: "unsubscribe", lead_id: lead.id }, { onConflict: "email", ignoreDuplicates: true });
  await sb.from("sales_leads").update({ status: "suppressed", last_activity_at: new Date().toISOString() }).eq("id", lead.id);
  await sb.from("sales_events").insert({ lead_id: lead.id, kind: "unsubscribe", detail: { email } });
  return page("Sie sind abgemeldet", "Wir haben Ihre Adresse aus dem Verteiler entfernt und werden Sie nicht erneut kontaktieren. Entschuldigen Sie die Störung.");
});
