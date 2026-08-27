-- Live Ops shift control surface. The queue exposes demand and aggregate fill only;
-- worker identity and assignment records remain behind their existing RLS policies.

create or replace function public.get_ops_shift_queue(
  p_from timestamptz default now() - interval '1 day',
  p_to timestamptz default now() + interval '90 days'
)
returns table(
  shift_id uuid,
  site_id uuid,
  site_name text,
  client_name text,
  role_id uuid,
  role_name text,
  starts_at timestamptz,
  ends_at timestamptz,
  headcount integer,
  filled_count bigint,
  status public.shift_status,
  worker_rate numeric,
  client_rate numeric,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;
  if not public.is_ops() then
    raise exception 'not authorised';
  end if;
  if p_from is null or p_to is null or p_to <= p_from then
    raise exception 'invalid queue time range';
  end if;
  if p_to - p_from > interval '366 days' then
    raise exception 'queue time range exceeds 366 days';
  end if;

  return query
  select
    sh.id,
    si.id,
    si.name,
    c.name,
    r.id,
    r.name,
    sh.starts_at,
    sh.ends_at,
    sh.headcount,
    count(sa.id) filter (where sa.cancelled_at is null),
    sh.status,
    sh.worker_rate,
    sh.client_rate,
    sh.created_at
  from public.shifts sh
  join public.sites si on si.id = sh.site_id
  join public.clients c on c.id = si.client_id
  join public.roles r on r.id = sh.role_id
  left join public.shift_assignments sa on sa.shift_id = sh.id
  where sh.starts_at >= p_from and sh.starts_at < p_to
  group by sh.id, si.id, si.name, c.name, r.id, r.name
  order by sh.starts_at, sh.created_at;
end;
$$;

revoke all on function public.get_ops_shift_queue(timestamptz,timestamptz) from public;
grant execute on function public.get_ops_shift_queue(timestamptz,timestamptz) to authenticated;

comment on function public.get_ops_shift_queue(timestamptz,timestamptz) is
'Ops-only shift demand queue with aggregate active fill. Does not expose worker or attendance identity data.';
