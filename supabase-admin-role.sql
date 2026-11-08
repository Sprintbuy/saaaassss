-- Run this in Supabase Dashboard > SQL Editor > New query after the target account exists.
-- Do not automatically grant admin at signup: email confirmation may be disabled.
-- The role is stored in app_metadata, which users cannot edit from the browser.

drop trigger if exists invoicepro_assign_initial_admin on auth.users;
drop function if exists public.assign_initial_admin_role();

-- Make this the only current admin: remove any role claim from other users.
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) - 'role'
where lower(coalesce(email, '')) <> 'edouard_v@icloud.com'
  and coalesce(raw_app_meta_data, '{}'::jsonb) ? 'role';

-- Grant admin to this account if it already exists.
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
  || '{"role":"admin"}'::jsonb
where lower(email) = 'edouard_v@icloud.com';
