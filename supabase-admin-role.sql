-- Run this once in Supabase Dashboard > SQL Editor > New query.
-- The role is stored in app_metadata, which users cannot edit from the browser.

create or replace function public.assign_initial_admin_role()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if lower(coalesce(new.email, '')) = 'edouarde801@gmail.com' then
    new.raw_app_meta_data := coalesce(new.raw_app_meta_data, '{}'::jsonb)
      || '{"role":"admin"}'::jsonb;
  end if;
  return new;
end;
$$;

drop trigger if exists invoicepro_assign_initial_admin on auth.users;
create trigger invoicepro_assign_initial_admin
  before insert on auth.users
  for each row execute function public.assign_initial_admin_role();

-- Make this the only current admin: remove any role claim from other users.
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) - 'role'
where lower(coalesce(email, '')) <> 'edouarde801@gmail.com'
  and coalesce(raw_app_meta_data, '{}'::jsonb) ? 'role';

-- Grant admin to this account if it already exists.
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
  || '{"role":"admin"}'::jsonb
where lower(email) = 'edouarde801@gmail.com';
