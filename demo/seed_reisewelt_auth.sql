-- Reisewelt-Demo: Logins. Setzt für Presenter + Agent ein bekanntes Passwort und legt den Kundenlogin an.
-- Passwort für ALLE drei: Reisewelt-Demo-2026!   NUR aufs Myna-Projekt einspielen.
-- Kein on_auth_user_created-Trigger in Myna → app_users wird hier explizit angelegt.

-- Bekanntes Passwort für die zwei bestehenden Demo-User setzen.
update auth.users set encrypted_password = extensions.crypt('Reisewelt-Demo-2026!', extensions.gen_salt('bf')), updated_at=now()
 where email in ('demo@reisewelt-demo.eu','arben.krasniqi@reisewelt-demo.eu');

-- Kundenlogin anlegen (idempotent).
delete from auth.identities where user_id='d0000000-0000-4000-8000-000000000001';
delete from app_users where user_id='d0000000-0000-4000-8000-000000000001';
delete from auth.users where id='d0000000-0000-4000-8000-000000000001';

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('d0000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
        'kunde@reisewelt-demo.eu', extensions.crypt('Reisewelt-Demo-2026!', extensions.gen_salt('bf')), now(),
        '{"provider":"email","providers":["email"]}','{}', now(), now());

insert into auth.identities (id, user_id, provider, provider_id, identity_data, last_sign_in_at, created_at, updated_at)
values (gen_random_uuid(),'d0000000-0000-4000-8000-000000000001','email','d0000000-0000-4000-8000-000000000001',
        '{"sub":"d0000000-0000-4000-8000-000000000001","email":"kunde@reisewelt-demo.eu","email_verified":true}', now(), now(), now());

-- GoTrue erwartet die Token-Spalten als '' (nicht NULL), sonst „Database error querying schema" beim Login.
update auth.users set confirmation_token='', recovery_token='', email_change_token_new='', email_change_token_current='',
  email_change='', phone_change='', phone_change_token='', reauthentication_token=''
 where id='d0000000-0000-4000-8000-000000000001';

insert into app_users (user_id, role_keys, full_name, active, must_change_pw, client_id)
values ('d0000000-0000-4000-8000-000000000001', ARRAY['kunde'], 'Reisewelt (Kunde)', true, false, 'client_rw_demo');

-- Kundenkonto-Mailadresse an die Demo-Domain angleichen.
update client_accounts set login_email='kunde@reisewelt-demo.eu', contact_email='kunde@reisewelt-demo.eu' where id='client_rw_demo';
