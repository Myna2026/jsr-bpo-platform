-- Klartext-Passwort aus client_accounts entfernen.
-- login_password wurde im Klartext gespeichert, aber nie gelesen (client.html nutzt Supabase-Auth,
-- nicht dieses Feld) — reines Risiko ohne Nutzen. Das Frontend schreibt es seit Commit 2f89053 nicht
-- mehr (Feld/Template/CLIENT_COLS + Fake-Reset entfernt), daher ist der Drop gefahrlos.

alter table public.client_accounts drop column if exists login_password;
