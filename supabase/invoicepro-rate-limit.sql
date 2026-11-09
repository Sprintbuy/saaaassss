-- Run once in Supabase SQL Editor before deploying invoicepro-gateway.
-- Only the trusted Edge Function uses the service_role RPC grant.
create table if not exists public.invoicepro_rate_limits (
  user_id uuid not null,
  window_start bigint not null,
  request_count integer not null default 0,
  primary key (user_id, window_start)
);

alter table public.invoicepro_rate_limits enable row level security;
revoke all on public.invoicepro_rate_limits from public, anon, authenticated;
grant select, insert, update, delete on public.invoicepro_rate_limits to service_role;

create or replace function public.invoicepro_consume_rate_limit(
  p_user_id uuid,
  p_limit integer default 60,
  p_window_seconds integer default 60
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_window bigint;
  v_count integer;
begin
  if p_user_id is null or p_limit < 1 or p_limit > 1000 or p_window_seconds < 1 or p_window_seconds > 3600 then
    return false;
  end if;

  v_window := floor(extract(epoch from clock_timestamp()) / p_window_seconds)::bigint;
  insert into public.invoicepro_rate_limits (user_id, window_start, request_count)
  values (p_user_id, v_window, 1)
  on conflict (user_id, window_start)
  do update set request_count = public.invoicepro_rate_limits.request_count + 1
  returning request_count into v_count;

  -- Opportunistic retention cleanup, scoped to this caller.
  delete from public.invoicepro_rate_limits
  where user_id = p_user_id and window_start < v_window - ceil(604800.0 / p_window_seconds)::bigint;

  return v_count <= p_limit;
end;
$$;

revoke all on function public.invoicepro_consume_rate_limit(uuid, integer, integer) from public, anon, authenticated;
grant execute on function public.invoicepro_consume_rate_limit(uuid, integer, integer) to service_role;
