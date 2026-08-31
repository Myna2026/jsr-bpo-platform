// Sales-Akquise, Schnitt 5: Öffnungs-Tracking. Ein 1x1-Pixel in der Mail zeigt hierher (?t=<unsub_token>). Beim
// Laden wird EINMAL ein 'opened'-Ereignis protokolliert und der Status von 'contacted' auf 'opened' gehoben.
// Bewusst minimal (ein Pixel), damit die Mail nicht nach Tracking-Schleuder aussieht. Öffentlich, kein Login.
// Deploy: supabase functions deploy sales-track --no-verify-jwt --use-api
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// 1x1 transparentes GIF
const PIXEL = Uint8Array.from(atob("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"), (c) => c.charCodeAt(0));

Deno.serve(async (req) => {
  const token = new URL(req.url).searchParams.get("t") || "";
  const pic = () => new Response(PIXEL, { status: 200, headers: { "Content-Type": "image/gif", "Cache-Control": "no-store, no-cache, must-revalidate", "Pragma": "no-cache" } });
  if (!token) return pic();
  try {
    const sb = createClient(SB_URL, SERVICE);
    const { data: lead } = await sb.from("sales_leads").select("id,status").eq("unsub_token", token).maybeSingle();
    if (lead) {
      // Nur EIN opened-Ereignis je Lead (Erstöffnung).
      const { data: seen } = await sb.from("sales_events").select("id").eq("lead_id", lead.id).eq("kind", "opened").limit(1);
      if (!seen || !seen.length) {
        await sb.from("sales_events").insert({ lead_id: lead.id, kind: "opened", detail: {} });
        if (lead.status === "contacted") await sb.from("sales_leads").update({ status: "opened", last_activity_at: new Date().toISOString() }).eq("id", lead.id);
      }
    }
  } catch (_e) { /* Tracking darf nie stören */ }
  return pic();
});
