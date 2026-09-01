-- QY Workforce: deterministic client SLA tracking and demand forecasting.
-- Decision support only. No automatic assignment, pricing, approval, messaging or client promise is made.

create table if not exists public.client_sla_policies (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete restrict,
  site_id uuid references public.sites(id) on delete restrict,
  target_fulfilment_pct numeric(5,2) not null default 85.00
    check (target_fulfilment_pct between 0 and 100),
  warning_lead_hours integer not null default 24 check (warning_lead_hours between 1 and 168),
  active boolean not null default true,
  notes text,
  created_by uuid not null references public.profiles(id),
  updated_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (notes is null or char_length(notes) <= 1000)
);

create unique index if not exists client_sla_policy_scope_uidx
  on public.client_sla_policies(client_id, coalesce(site_id, '00000000-0000-0000-0000-000000000000'::uuid));

alter table public.client_sla_policies enable row level security;
revoke insert, update, delete on public.client_sla_policies from anon, authenticated;

create policy "privileged read client sla policies"
  on public.client_sla_policies for select
  using (public.is_privileged());

create or replace function public.upsert_client_sla_policy(
  p_client_id uuid,
  p_site_id uuid default null,
  p_target_fulfilment_pct numeric default 85,
  p_warning_lead_hours integer default 24,
  p_notes text default null,
  p_active boolean default true
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_site_client uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_client_id is null or not exists(select 1 from public.clients where id=p_client_id) then
    raise exception 'client not found';
  end if;
  if p_target_fulfilment_pct is null or p_target_fulfilment_pct < 0 or p_target_fulfilment_pct > 100 then
    raise exception 'target fulfilment must be between 0 and 100';
  end if;
  if p_warning_lead_hours is null or p_warning_lead_hours < 1 or p_warning_lead_hours > 168 then
    raise exception 'warning lead hours must be between 1 and 168';
  end if;
  if p_notes is not null and char_length(trim(p_notes)) > 1000 then raise exception 'notes too long'; end if;

  if p_site_id is not null then
    select client_id into v_site_client from public.sites where id=p_site_id;
    if v_site_client is null then raise exception 'site not found'; end if;
    if v_site_client <> p_client_id then raise exception 'site does not belong to client'; end if;
  end if;

  insert into public.client_sla_policies(
    client_id,site_id,target_fulfilment_pct,warning_lead_hours,active,notes,created_by,updated_by
  ) values (
    p_client_id,p_site_id,round(p_target_fulfilment_pct,2),p_warning_lead_hours,p_active,
    nullif(trim(p_notes),''),auth.uid(),auth.uid()
  )
  on conflict (client_id, coalesce(site_id, '00000000-0000-0000-0000-000000000000'::uuid))
  do update set
    target_fulfilment_pct=excluded.target_fulfilment_pct,
    warning_lead_hours=excluded.warning_lead_hours,
    active=excluded.active,
    notes=excluded.notes,
    updated_by=auth.uid(),
    updated_at=now()
  returning id into v_id;

  insert into public.audit_events(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'client_sla_policy.upserted','client_sla_policy',v_id,
    jsonb_build_object('client_id',p_client_id,'site_id',p_site_id,
      'target_fulfilment_pct',round(p_target_fulfilment_pct,2),'warning_lead_hours',p_warning_lead_hours,'active',p_active));
  return v_id;
end;
$$;
revoke all on function public.upsert_client_sla_policy(uuid,uuid,numeric,integer,text,boolean) from public;
grant execute on function public.upsert_client_sla_policy(uuid,uuid,numeric,integer,text,boolean) to authenticated;

create or replace function public.get_client_sla_dashboard(
  p_days integer default 30,
  p_client_id uuid default null
) returns table(
  client_id uuid,
  client_name text,
  site_id uuid,
  site_name text,
  target_fulfilment_pct numeric,
  required_headcount bigint,
  filled_headcount bigint,
  fulfilment_pct numeric,
  cancellations bigint,
  no_shows bigint,
  shifts_count bigint,
  sla_status text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_days is null or p_days < 1 or p_days > 365 then raise exception 'days must be between 1 and 365'; end if;

  return query
  with base_shifts as (
    select sh.id, sh.site_id, sh.headcount
    from public.shifts sh
    where sh.starts_at >= now() - make_interval(days => p_days)
      and sh.starts_at < now()
      and sh.status not in ('draft','cancelled')
  ), assignment_stats as (
    select bs.id as shift_id,
      count(a.id) filter (where a.accepted_at is not null and a.cancelled_at is null) as filled,
      count(a.id) filter (where a.cancelled_at is not null) as cancelled
    from base_shifts bs
    left join public.shift_assignments a on a.shift_id=bs.id
    group by bs.id
  ), no_show_stats as (
    select a.shift_id, count(distinct re.id) as no_shows
    from public.worker_reliability_events re
    join public.shift_assignments a on a.id=re.source_id
    join base_shifts bs on bs.id=a.shift_id
    where re.event_type='no_show'
    group by a.shift_id
  ), rolled as (
    select c.id client_id, c.name client_name, s.id site_id, s.name site_name,
      sum(bs.headcount)::bigint required_headcount,
      sum(coalesce(ast.filled,0))::bigint filled_headcount,
      sum(coalesce(ast.cancelled,0))::bigint cancellations,
      sum(coalesce(ns.no_shows,0))::bigint no_shows,
      count(*)::bigint shifts_count
    from base_shifts bs
    join public.sites s on s.id=bs.site_id
    join public.clients c on c.id=s.client_id
    left join assignment_stats ast on ast.shift_id=bs.id
    left join no_show_stats ns on ns.shift_id=bs.id
    where p_client_id is null or c.id=p_client_id
    group by c.id,c.name,s.id,s.name
  )
  select r.client_id,r.client_name,r.site_id,r.site_name,
    coalesce(sp.target_fulfilment_pct,cp.target_fulfilment_pct,85.00)::numeric target_fulfilment_pct,
    r.required_headcount,r.filled_headcount,
    case when r.required_headcount=0 then 100.00 else round(100.0*r.filled_headcount/r.required_headcount,2) end::numeric fulfilment_pct,
    r.cancellations,r.no_shows,r.shifts_count,
    case
      when (case when r.required_headcount=0 then 100.00 else 100.0*r.filled_headcount/r.required_headcount end)
           >= coalesce(sp.target_fulfilment_pct,cp.target_fulfilment_pct,85.00) then 'meeting'
      when (case when r.required_headcount=0 then 100.00 else 100.0*r.filled_headcount/r.required_headcount end)
           >= coalesce(sp.target_fulfilment_pct,cp.target_fulfilment_pct,85.00)-5 then 'watch'
      else 'breach_risk'
    end::text sla_status
  from rolled r
  left join public.client_sla_policies sp on sp.client_id=r.client_id and sp.site_id=r.site_id and sp.active
  left join public.client_sla_policies cp on cp.client_id=r.client_id and cp.site_id is null and cp.active
  order by fulfilment_pct asc, r.client_name, r.site_name;
end;
$$;
revoke all on function public.get_client_sla_dashboard(integer,uuid) from public;
grant execute on function public.get_client_sla_dashboard(integer,uuid) to authenticated;

create or replace function public.get_ops_demand_forecast(
  p_forecast_days integer default 14,
  p_history_weeks integer default 8,
  p_client_id uuid default null
) returns table(
  forecast_date date,
  client_id uuid,
  client_name text,
  site_id uuid,
  site_name text,
  role_id uuid,
  role_name text,
  projected_headcount integer,
  historical_occurrences bigint,
  confidence text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_ops() then raise exception 'not authorised'; end if;
  if p_forecast_days is null or p_forecast_days < 1 or p_forecast_days > 90 then raise exception 'forecast days must be between 1 and 90'; end if;
  if p_history_weeks is null or p_history_weeks < 2 or p_history_weeks > 52 then raise exception 'history weeks must be between 2 and 52'; end if;

  return query
  with historical as (
    select s.client_id, sh.site_id, sh.role_id,
      extract(isodow from sh.starts_at)::integer as weekday,
      avg(sh.headcount)::numeric avg_headcount,
      count(*)::bigint occurrences
    from public.shifts sh
    join public.sites s on s.id=sh.site_id
    where sh.starts_at >= now() - make_interval(weeks => p_history_weeks)
      and sh.starts_at < now()
      and sh.status not in ('draft','cancelled')
      and (p_client_id is null or s.client_id=p_client_id)
    group by s.client_id,sh.site_id,sh.role_id,extract(isodow from sh.starts_at)
  ), future_days as (
    select gs::date forecast_date, extract(isodow from gs)::integer weekday
    from generate_series(current_date, current_date + (p_forecast_days-1), interval '1 day') gs
  )
  select fd.forecast_date,c.id,c.name,s.id,s.name,r.id,r.name,
    greatest(0,round(h.avg_headcount))::integer projected_headcount,
    h.occurrences,
    case when h.occurrences >= 6 then 'high' when h.occurrences >= 3 then 'medium' else 'low' end::text confidence
  from historical h
  join future_days fd on fd.weekday=h.weekday
  join public.clients c on c.id=h.client_id
  join public.sites s on s.id=h.site_id
  join public.roles r on r.id=h.role_id
  where c.active and s.active and r.active
  order by fd.forecast_date,c.name,s.name,r.name;
end;
$$;
revoke all on function public.get_ops_demand_forecast(integer,integer,uuid) from public;
grant execute on function public.get_ops_demand_forecast(integer,integer,uuid) to authenticated;
