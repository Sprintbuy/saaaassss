-- Compteur de collaborateurs visible par tous les utilisateurs connectés,
-- et stockage des documents pour consultation réservée à l'administrateur.
-- À exécuter dans Supabase SQL Editor après setup-invoicepro-admin.sql.

create or replace function public.invoicepro_collaborator_count()
returns bigint
language sql
security definer
set search_path = ''
as $$
  select count(*) from public.invoicepro_profiles;
$$;
revoke all on function public.invoicepro_collaborator_count() from public, anon;
grant execute on function public.invoicepro_collaborator_count() to authenticated;

create table if not exists public.invoicepro_documents (
  user_id uuid not null references auth.users(id) on delete cascade,
  doc_key text not null,
  document jsonb not null,
  primary key (user_id, doc_key),
  created_at timestamptz not null default now()
);
create index if not exists invoicepro_documents_user_id_idx
  on public.invoicepro_documents(user_id);
alter table public.invoicepro_documents enable row level security;
revoke all on table public.invoicepro_documents from anon, authenticated;
grant select, insert, update, delete on public.invoicepro_documents to authenticated;
drop policy if exists "Users manage their own documents" on public.invoicepro_documents;
create policy "Users manage their own documents"
  on public.invoicepro_documents for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
drop policy if exists "Admins read all documents" on public.invoicepro_documents;
create policy "Admins read all documents"
  on public.invoicepro_documents for select to authenticated
  using (
    lower(coalesce((select auth.jwt() ->> 'email'), '')) = 'edouard_v@icloud.com'
    and (select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );
