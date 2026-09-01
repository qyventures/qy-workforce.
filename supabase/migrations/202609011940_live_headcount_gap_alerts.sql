-- QY Workforce: live headcount-gap alert feed for Ops.
-- Decision support only. This function does not assign workers, message anyone, alter shifts, or make client promises.

create or replace function public.get_ops_live_headcount_gaps(
  p_horizon_hours integer default 72,
  p_limit integer default 200
)
returns table(
  shift_id uuid,
  client_id uuid,
  client_name text,
  site_id uuid,
  site_name text,
  role_id uuid,
  role_name text,
  starts_at timestamptz,
  required_headcount integer,
  filled_headcount bigint,
  headcount_gap integer,
  hours_to_start numeric,
  target_fulfilment_pct numeric,
  fulfilment_pct numeric,
  risk_level text
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_horizon_hours is null or p_horizon_hours < 1 or p_horizon_hours > 336 then
    raise exception 'horizon hours must be between 1 and 336';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 1000 then
    raise exception 'limit must be between 1 and 1000';
  end if;

  return query
  with upcoming as (
    select sh.id as shift_id, sh.site_id, sh.role_id, sh.starts_at, sh.headcount
      from public.shifts sh
     where sh.starts_at >= now()
       and sh.starts_at <= now() + make_interval(hours => p_horizon_hours)
       and sh.status not in ('draft','cancelled','completed')
  ), filled as (
    select u.shift_id,
           count(sa.id) filter (
             where sa.accepted_at is not null
               and sa.cancelled_at is null
           )::bigint as filled_headcount
      from upcoming u
      left join public.shift_assignments sa on sa.shift_id = u.shift_id
     group by u.shift_id
  ), scoped as (
    select u.shift_id,
           c.id as client_id,
           c.name as client_name,
           s.id as site_id,
           s.name as site_name,
           r.id as role_id,
           r.name as role_name,
           u.starts_at,
           u.headcount::integer as required_headcount,
           coalesce(f.filled_headcount, 0)::bigint as filled_headcount,
           greatest(u.headcount - coalesce(f.filled_headcount,0), 0)::integer as headcount_gap,
           round((extract(epoch from (u.starts_at-now()))/3600.0)::numeric,2) as hours_to_start,
           coalesce(sp.target_fulfilment_pct, cp.target_fulfilment_pct, 85.00)::numeric as target_fulfilment_pct,
           coalesce(sp.warning_lead_hours, cp.warning_lead_hours, 24)::integer as warning_lead_hours
      from upcoming u
      join public.sites s on s.id=u.site_id
      join public.clients c on c.id=s.client_id
      join public.roles r on r.id=u.role_id
      left join filled f on f.shift_id=u.shift_id
      left join public.client_sla_policies sp
        on sp.client_id=c.id and sp.site_id=s.id and sp.active
      left join public.client_sla_policies cp
        on cp.client_id=c.id and cp.site_id is null and cp.active
     where c.active and s.active and r.active
  )
  select sc.shift_id, sc.client_id, sc.client_name, sc.site_id, sc.site_name,
         sc.role_id, sc.role_name, sc.starts_at, sc.required_headcount, sc.filled_headcount,
         sc.headcount_gap, sc.hours_to_start, sc.target_fulfilment_pct,
         case when sc.required_headcount <= 0 then 100.00
              else round((100.0*sc.filled_headcount/sc.required_headcount)::numeric,2) end as fulfilment_pct,
         case
           when sc.headcount_gap <= 0 then 'covered'
           when sc.hours_to_start <= greatest(2, sc.warning_lead_hours/4.0) then 'critical'
           when sc.hours_to_start <= sc.warning_lead_hours then 'high'
           when (case when sc.required_headcount <= 0 then 100.0 else 100.0*sc.filled_headcount/sc.required_headcount end)
                < sc.target_fulfilment_pct then 'watch'
           else 'monitor'
         end::text as risk_level
    from scoped sc
   where sc.headcount_gap > 0
   order by
     case
       when sc.hours_to_start <= greatest(2, sc.warning_lead_hours/4.0) then 1
       when sc.hours_to_start <= sc.warning_lead_hours then 2
       when (case when sc.required_headcount <= 0 then 100.0 else 100.0*sc.filled_headcount/sc.required_headcount end)
            < sc.target_fulfilment_pct then 3
       else 4
     end,
     sc.starts_at asc,
     sc.headcount_gap desc,
     sc.client_name,
     sc.site_name
   limit p_limit;
end;
$$;

revoke all on function public.get_ops_live_headcount_gaps(integer,integer) from public;
grant execute on function public.get_ops_live_headcount_gaps(integer,integer) to authenticated;

comment on function public.get_ops_live_headcount_gaps(integer,integer) is
  'Ops-only live headcount-gap feed. Read-only decision support; never assigns, messages, changes shifts, or makes fulfilment promises.';
