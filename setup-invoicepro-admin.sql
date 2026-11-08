-- InvoicePro: role admin unique + liste privée des comptes.
-- À exécuter dans Supabase > SQL Editor, après avoir créé le compte
-- edouard_v@icloud.com et vérifié que c'est bien le compte qui t'appartient.
-- Ce script ne stocke et ne modifie aucun mot de passe.

-- Arrête l'exécution si le compte cible n'existe pas.
do $$
begin
  if not exists (
    select 1 from auth.users
    where lower(email) = 'edouard_v@icloud.com'
  ) then
    raise exception 'Compte edouard_v@icloud.com introuvable dans Authentication > Users. Crée ou mets à jour ce compte, puis relance ce script.';
  end if;
end;
$$;

-- Supprime l'ancien mécanisme d'attribution automatique à l'inscription.
-- Avec les confirmations d'e-mail désactivées, il ne faut jamais donner
-- des droits admin à une adresse simplement saisie dans un formulaire.
drop trigger if exists invoicepro_assign_initial_admin on auth.users;
drop function if exists public.assign_initial_admin_role();

-- Retire le rôle admin de tous les autres comptes existants.
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) - 'role'
where lower(coalesce(email, '')) <> 'edouard_v@icloud.com'
  and coalesce(raw_app_meta_data, '{}'::jsonb) ? 'role';

-- Attribue le rôle admin au compte existant.
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
  || '{"role":"admin"}'::jsonb
where lower(email) = 'edouard_v@icloud.com';

-- Table minimale pour afficher les comptes; aucun mot de passe n'y est copié.
create table if not exists public.invoicepro_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  created_at timestamptz not null default now()
);

alter table public.invoicepro_profiles enable row level security;
revoke all on table public.invoicepro_profiles from anon, authenticated;
grant usage on schema public to authenticated;
grant select on table public.invoicepro_profiles to authenticated;

drop policy if exists "Only admins can list accounts" on public.invoicepro_profiles;
create policy "Only admins can list accounts"
  on public.invoicepro_profiles
  for select
  to authenticated
  using (
    lower(coalesce((select auth.jwt() ->> 'email'), '')) = 'edouard_v@icloud.com'
    and (select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

-- Synchronise l'adresse et la date de création quand un compte est créé/modifié.
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

-- Ajoute les comptes déjà existants à la liste.
insert into public.invoicepro_profiles (id, email, created_at)
select id, email, coalesce(created_at, now())
from auth.users
on conflict (id) do update set email = excluded.email;
