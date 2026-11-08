-- Run in Supabase Dashboard > SQL Editor after supabase-admin-role.sql.
-- This table contains account email/creation date only. It never stores passwords.
create table if not exists public.invoicepro_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  created_at timestamptz not null default now()
);

alter table public.invoicepro_profiles enable row level security;
revoke all on public.invoicepro_profiles from anon;
grant select on public.invoicepro_profiles to authenticated;

drop policy if exists "Only admins can list accounts" on public.invoicepro_profiles;
create policy "Only admins can list accounts"
  on public.invoicepro_profiles
  for select
  to authenticated
  using (
    lower(coalesce((select auth.jwt() ->> 'email'), '')) = 'edouarde801@gmail.com'
    and (select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

create or replace function public.sync_invoicepro_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.invoicepro_profiles (id, email, created_at)
  values (new.id, new.email, coalesce(new.created_at, now()))
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

drop trigger if exists invoicepro_sync_profile on auth.users;
create trigger invoicepro_sync_profile
  after insert or update on auth.users
  for each row execute function public.sync_invoicepro_profile();

-- Backfill accounts that existed before this trigger was added.
insert into public.invoicepro_profiles (id, email, created_at)
select id, email, coalesce(created_at, now()) from auth.users
on conflict (id) do update set email = excluded.email;
