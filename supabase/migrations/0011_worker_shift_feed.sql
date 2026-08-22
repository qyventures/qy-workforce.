-- Least-privilege worker shift discovery feed.
-- Returns only operational fields a deployable worker needs to evaluate an eligible shift.
-- Client/site commercial fields remain protected by their existing RLS policies.

create or replace function public.get_available_shifts()
returns table (
  shift_id uuid,
  role_name text,
  client_name text,
  site_name text,
  starts_at timestamptz,
  ends_at timestamptz,
  worker_rate numeric,
  requirements jsonb,
  available_slots integer
)
language plpgsql
security definer
stable
set search_path=public
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if not exists (
    select 1 from public.worker_profiles wp
    where wp.user_id=auth.uid() and wp.status='deployable'
  ) then
    return;
  end if;

  return query
  select
    sh.id,
    r.name,
    c.name,
    s.name,
    sh.starts_at,
    sh.ends_at,
    sh.worker_rate,
    coalesce(sh.requirements, '{}'::jsonb),
    greatest(
      sh.headcount - (
        select count(*)::integer
        from public.shift_assignments a
        where a.shift_id=sh.id and a.cancelled_at is null
      ),
      0
    ) as available_slots
  from public.shifts sh
  join public.roles r on r.id=sh.role_id
  join public.sites s on s.id=sh.site_id
  join public.clients c on c.id=s.client_id
  where sh.status='open'
    and sh.starts_at > now()
    and exists (
      select 1 from public.worker_roles wr
      where wr.worker_id=auth.uid()
        and wr.role_id=sh.role_id
        and wr.approved=true
    )
    and not exists (
      select 1 from public.shift_assignments mine
      where mine.shift_id=sh.id
        and mine.worker_id=auth.uid()
        and mine.cancelled_at is null
    )
    and (
      select count(*)
      from public.shift_assignments active
      where active.shift_id=sh.id and active.cancelled_at is null
    ) < sh.headcount
  order by sh.starts_at asc
  limit 100;
end;
$$;

revoke all on function public.get_available_shifts() from public;
grant execute on function public.get_available_shifts() to authenticated;

comment on function public.get_available_shifts() is
'Authenticated deployable-worker feed containing only eligible, open and unfilled shifts. Commercial client/site data remains excluded.';
